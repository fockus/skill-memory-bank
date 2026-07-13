"""Tests for the ``--sessions`` graph layer (Task 14, REQ-024..026 + Scenario 9).

The sessions layer bridges Group B (session memory in ``session/*.md``) into the
code graph: each session that touched graph modules becomes a ``session`` node
with ``worked_on`` edges to those modules, each edge carrying a one-line work
summary, and the summary is appended to the touched module nodes' ``doc`` field
so the embedding corpus matches work-history queries.

Discipline mirrored from ``--cochange`` (Task 5):
  * additive JSONL (``type":"node"`` kind=session / ``type":"edge"`` kind=worked_on)
    — unknown row types are ignored by every existing consumer;
  * the opt-in lives entirely inside ``--sessions``; base builds stay
    byte-identical (regression test);
  * pure functions tested mocklessly against on-disk fixtures.

REQ-026 (defense-in-depth redaction) is the load-bearing safety property: a
legacy session file may contain a secret, and ``graph.json`` is committable.
Scenario 9 asserts on the FILE BYTES that the raw token never reaches disk.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import codegraph_sessions as cgs  # noqa: E402

# A fake OpenRouter-style key — matches ``sk-[A-Za-z0-9_-]{20,}`` in redact.py.
FAKE_TOKEN = "sk-or-aaaaaaaaaaaaaaaaaaaaaaaa"


def _load_script():
    spec = importlib.util.spec_from_file_location(
        "mb_codegraph", REPO_ROOT / "scripts" / "mb-codegraph.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _write_session(
    mb: Path,
    sid: str,
    *,
    bullets: list[tuple[str, str, str]],
    started: str = "2026-06-11T02:00Z",
    what_changed: str | None = None,
    tail: str = " · ok · +5/-2",
) -> Path:
    """Write a session file in the real format.

    ``bullets`` = list of ``(time, request, files_csv)``; ``files_csv`` is the
    raw value after ``files:`` (use ``"(none)"`` for no files). ``tail`` is the
    modern Live-log outcome/diffstat suffix appended after the files field
    (``hooks/mb-session-turn.sh``); pass ``tail=""`` to emulate a legacy bullet.
    """
    sess_dir = mb / "session"
    sess_dir.mkdir(parents=True, exist_ok=True)
    lines = [
        "---",
        f"session_id: {sid}",
        "branch: main",
        f"started: {started}",
        "summarized: false",
        "---",
        "",
        "## Live log",
    ]
    for when, req, files_csv in bullets:
        lines.append(f'- {when} — User: "{req}" · tools: Bash,Edit · files: {files_csv}{tail}')
    if what_changed is not None:
        lines += ["", "## Summary", "", "### What changed", "", what_changed]
    path = sess_dir / f"{sid}.md"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


# ── pure: redact_secrets parity (REQ-026) ────────────────────────────


def test_redact_secrets_strips_openrouter_token():
    out = cgs.redact_secrets(f"touched the auth path with {FAKE_TOKEN} oops")
    assert FAKE_TOKEN not in out
    assert "[REDACTED]" in out


def test_strip_private_removes_private_spans():
    out = cgs.strip_private("public <private>secret-detail</private> tail")
    assert "secret-detail" not in out
    assert "public" in out and "tail" in out


def test_strip_private_removes_unterminated_span():
    out = cgs.strip_private("visible <private>dangling to end of string")
    assert "dangling" not in out
    assert "visible" in out


# ── pure: extract_session_layer ──────────────────────────────────────


def test_extract_session_layer_emits_worked_on_edges(tmp_path: Path):
    mb = tmp_path / "mb"
    abs_a = "/Users/x/proj/pkg/alpha.py"
    _write_session(
        mb,
        "2026-06-11_0200_aaaa",
        bullets=[("02:00", "fix the alpha bug", abs_a)],
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py", "pkg/beta.py"})
    edges = [e for e in layer.edges if e["kind"] == "worked_on"]
    assert len(edges) == 1
    e = edges[0]
    assert e["src"] == "session:2026-06-11_0200_aaaa"
    assert e["dst"] == "pkg/alpha.py"
    assert "alpha" in e["summary"]
    # one session node per session
    sess_nodes = [n for n in layer.nodes if n["kind"] == "session"]
    assert len(sess_nodes) == 1
    assert sess_nodes[0]["id"] == "session:2026-06-11_0200_aaaa"


def test_extract_session_layer_appends_doc(tmp_path: Path):
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_bbbb",
        bullets=[("02:00", "refactor the parser", "/Users/x/proj/pkg/alpha.py")],
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    assert "pkg/alpha.py" in layer.doc_appends
    appended = layer.doc_appends["pkg/alpha.py"]
    assert any("parser" in a for a in appended)


def test_extract_session_layer_session_without_files_skipped(tmp_path: Path):
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_cccc",
        bullets=[("02:00", "just a question", "(none)")],
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    assert layer.nodes == []
    assert layer.edges == []
    assert layer.doc_appends == {}


def test_extract_session_layer_unknown_files_skipped(tmp_path: Path):
    """A session touching only files outside the graph contributes nothing."""
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_dddd",
        bullets=[("02:00", "edit docs", "/Users/x/proj/README.md,/tmp/scratch.txt")],
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    assert layer.nodes == []
    assert layer.edges == []


def test_extract_session_layer_caps_doc_appends_per_module(tmp_path: Path):
    """Cap: at most 3 session summaries appended to any one module's doc."""
    mb = tmp_path / "mb"
    abs_a = "/Users/x/proj/pkg/alpha.py"
    for i in range(5):
        _write_session(
            mb,
            f"2026-06-11_020{i}_s{i}",
            bullets=[(f"02:0{i}", f"change number {i} here", abs_a)],
            started=f"2026-06-11T02:0{i}Z",
        )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    assert len(layer.doc_appends["pkg/alpha.py"]) == 3


def test_extract_session_layer_redacts_secret_in_summary(tmp_path: Path):
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_eeee",
        bullets=[("02:00", f"leaked {FAKE_TOKEN} in the auth code", "/Users/x/proj/pkg/alpha.py")],
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    edge = next(e for e in layer.edges if e["kind"] == "worked_on")
    assert FAKE_TOKEN not in edge["summary"]
    assert "[REDACTED]" in edge["summary"]
    for appended in layer.doc_appends["pkg/alpha.py"]:
        assert FAKE_TOKEN not in appended


def test_extract_session_layer_strips_private_spans(tmp_path: Path):
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_ffff",
        bullets=[
            (
                "02:00",
                "work on <private>internal-codename</private> path",
                "/Users/x/proj/pkg/alpha.py",
            )
        ],
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    edge = next(e for e in layer.edges if e["kind"] == "worked_on")
    assert "internal-codename" not in edge["summary"]


def test_extract_session_layer_prefers_what_changed_summary(tmp_path: Path):
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_gggg",
        bullets=[("02:00", "the raw user request", "/Users/x/proj/pkg/alpha.py")],
        what_changed="rewrote the alpha tokenizer for speed",
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    edge = next(e for e in layer.edges if e["kind"] == "worked_on")
    assert "tokenizer" in edge["summary"]


def test_extract_session_layer_no_session_dir_is_graceful(tmp_path: Path):
    mb = tmp_path / "mb"
    mb.mkdir()
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    assert layer.nodes == []
    assert layer.edges == []
    assert layer.doc_appends == {}


def test_extract_session_layer_modern_bullet_tail_not_parsed_as_files(tmp_path: Path):
    """Regression: the modern Live-log tail ` · ok · +A/-B` must NOT be parsed into
    the files field, else the LAST file of every turn (and all files of single-file
    turns) silently lose their module mapping."""
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_tail",
        bullets=[
            (
                "02:00",
                "touch two modules",
                "/Users/x/proj/pkg/alpha.py,/Users/x/proj/pkg/beta.py",
            )
        ],
    )  # default tail = " · ok · +5/-2"
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py", "pkg/beta.py"})
    dsts = {e["dst"] for e in layer.edges if e["kind"] == "worked_on"}
    assert dsts == {"pkg/alpha.py", "pkg/beta.py"}  # neither dropped by the tail


def test_extract_session_layer_legacy_bullet_without_tail(tmp_path: Path):
    """Backward compat: a legacy bullet (no outcome/diffstat tail) still parses."""
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_legacy",
        bullets=[("02:00", "old format turn", "/Users/x/proj/pkg/alpha.py")],
        tail="",
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    dsts = {e["dst"] for e in layer.edges if e["kind"] == "worked_on"}
    assert dsts == {"pkg/alpha.py"}


def test_extract_session_layer_sanitizes_date_field(tmp_path: Path):
    """REQ-026 (defense-in-depth): a ``<private>`` span / secret in the frontmatter
    ``started:`` date must reach NEITHER the session node ``date`` NOR the doc label.
    The date is session-derived and graph.json is committable."""
    mb = tmp_path / "mb"
    _write_session(
        mb,
        "2026-06-11_0200_date",
        bullets=[("02:00", "work on alpha", "/Users/x/proj/pkg/alpha.py")],
        started=f"2026-06-11T02:00Z<private>{FAKE_TOKEN}</private>",
    )
    layer = cgs.extract_session_layer(mb, {"pkg/alpha.py"})
    node = next(n for n in layer.nodes if n["kind"] == "session")
    assert FAKE_TOKEN not in node.get("date", "")
    assert "<private>" not in node.get("date", "")
    for appended in layer.doc_appends["pkg/alpha.py"]:
        assert FAKE_TOKEN not in appended


# ── wiring: scripts/mb-codegraph.py under --sessions ─────────────────


def _records(graph_json: Path) -> list[dict]:
    return [json.loads(line) for line in graph_json.read_text(encoding="utf-8").splitlines()]


@pytest.fixture
def built_repo(tmp_path: Path) -> tuple[Path, Path]:
    """A src_root with one module + an mb with a session touching it."""
    src = tmp_path / "src"
    (src / "pkg").mkdir(parents=True)
    (src / "pkg" / "alpha.py").write_text("def run():\n    return 1\n", encoding="utf-8")
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    abs_alpha = str(src / "pkg" / "alpha.py")
    _write_session(
        mb,
        "2026-06-11_0200_wire",
        bullets=[("02:00", "patched the token redaction leak", abs_alpha)],
    )
    return src, mb


def test_run_sessions_emits_worked_on_edges(built_repo: tuple[Path, Path]):
    src, mb = built_repo
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(src), mode="apply", sessions=True)
    recs = _records(mb / "codebase" / "graph.json")
    worked = [r for r in recs if r.get("type") == "edge" and r.get("kind") == "worked_on"]
    assert worked, "expected worked_on edges under --sessions"
    assert worked[0]["dst"] == "pkg/alpha.py"
    sess = [r for r in recs if r.get("type") == "node" and r.get("kind") == "session"]
    assert sess


def test_run_sessions_off_emits_no_session_rows(built_repo: tuple[Path, Path]):
    src, mb = built_repo
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(src), mode="apply", sessions=False)
    recs = _records(mb / "codebase" / "graph.json")
    assert not [r for r in recs if r.get("kind") in ("session", "worked_on")]


def test_run_sessions_base_graph_byte_identical(built_repo: tuple[Path, Path], monkeypatch):
    """Regression: base build (no --sessions) is byte-identical with the flag off.

    Run twice — once with the flag absent, once explicitly False — and assert the
    graph.json bytes match (same pattern as --cochange byte-identity).

    ``SOURCE_DATE_EPOCH`` is pinned so the two builds' ``generated_at`` meta
    field can't legitimately differ across a real-clock second boundary — the
    test asserts the byte-identity invariant itself, not a race against the
    clock (see ``scripts/mb-codegraph.py::_generated_at_now``).
    """
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1700000000")
    src, mb = built_repo
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(src), mode="apply")
    baseline = (mb / "codebase" / "graph.json").read_bytes()

    mb2 = mb.parent / "mb2"
    (mb2 / "codebase").mkdir(parents=True)
    # mirror the session file so the only difference is the flag, not inputs
    (mb2 / "session").mkdir(parents=True)
    for f in (mb / "session").glob("*.md"):
        (mb2 / "session" / f.name).write_text(f.read_text(encoding="utf-8"), encoding="utf-8")
    mod.run(mb_path=str(mb2), src_root=str(src), mode="apply", sessions=False)
    assert (mb2 / "codebase" / "graph.json").read_bytes() == baseline


def test_run_sessions_god_nodes_md_unaffected_by_session_layer(
    built_repo: tuple[Path, Path], monkeypatch
):
    """Structural ranking guard: session/worked_on rows must not skew communities,
    betweenness or pagerank, so god-nodes.md is byte-identical with and without
    ``--sessions``. (graph.json differs — it carries the session rows — but the
    structural report does not.)

    ``SOURCE_DATE_EPOCH`` is pinned for the same reason as the graph.json
    byte-identity regression above: two builds must never be able to diverge
    on a real-clock second boundary.
    """
    monkeypatch.setenv("SOURCE_DATE_EPOCH", "1700000000")
    src, mb = built_repo
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(src), mode="apply", sessions=False)
    without = (mb / "codebase" / "god-nodes.md").read_bytes()
    mod.run(mb_path=str(mb), src_root=str(src), mode="apply", sessions=True)
    with_sessions = (mb / "codebase" / "god-nodes.md").read_bytes()
    assert with_sessions == without


def test_run_sessions_doc_feeds_embedding_corpus(built_repo: tuple[Path, Path]):
    """Doc appends must reach the embedding/BM25 corpus → work-history query finds the module."""
    from memory_bank_skill.semantic_search import run_search

    src, mb = built_repo
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(src), mode="apply", sessions=True, docs=True)
    result = run_search(query="token redaction leak", mb_path=str(mb), backend="bm25")
    files = {h["file"] for h in result["hits"]}
    assert "pkg/alpha.py" in files


# ── Scenario 9 (e2e): secret redacted before graph write (REQ-024..026) ──


# <!-- mb-scenario:9 -->
def test_scenario_9_sessions_layer_redacts_secret_before_graph_write(tmp_path: Path):
    """GIVEN a legacy session file with a raw token in its summary line,
    WHEN ``/mb graph --apply --sessions`` runs,
    THEN graph.json carries the worked_on edge with [REDACTED] and the raw
    token appears NOWHERE in the file bytes.
    """
    src = tmp_path / "src"
    (src / "pkg").mkdir(parents=True)
    (src / "pkg" / "auth.py").write_text("def login():\n    return True\n", encoding="utf-8")
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    abs_auth = str(src / "pkg" / "auth.py")
    _write_session(
        mb,
        "2026-06-11_0200_leak",
        bullets=[("02:00", f"debugged auth using {FAKE_TOKEN} in the header", abs_auth)],
    )

    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(src), mode="apply", sessions=True)

    graph_path = mb / "codebase" / "graph.json"
    raw_bytes = graph_path.read_bytes()
    assert FAKE_TOKEN.encode() not in raw_bytes, "raw token leaked into graph.json bytes"

    recs = _records(graph_path)
    worked = [r for r in recs if r.get("kind") == "worked_on"]
    assert worked, "expected a worked_on edge"
    assert worked[0]["dst"] == "pkg/auth.py"
    assert "[REDACTED]" in worked[0]["summary"]


# <!-- /mb-scenario:9 -->
