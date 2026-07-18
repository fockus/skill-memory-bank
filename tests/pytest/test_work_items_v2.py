"""Contract tests — tasks.md v2 fields in the shared work-item parser (Task 1).

Locks the C1/C2 contract for ``scripts/mb_work_items.py``:

* pre-v2 key projection (``source/topic/item_no/kind/heading/body/role/agent/
  status/covers/dod_lines``) stays **byte-identical** on the full legacy corpus
  (REQ-039 / REQ-005);
* the full JSON gains v2 keys ``stage``, ``blocked_by[]``, ``scope[]``,
  ``eval{cmd,red,exit,output_re,waiver}`` and ``budget`` with the C1 defaults;
* Blocked-by grammar (``<n>`` | ``<topic>#<n>`` | ``none``) and Scope grammar
  (repo-relative restricted glob) are enforced — malformed elements make the CLI
  exit ``2`` (R3-004), distinct from the mixed-marker ``exit 1``.

The RED anchor is ``test_v2_fields_parsed`` (design C1 / Eval T1).
"""

from __future__ import annotations

import hashlib
import json
import pathlib
import subprocess
import sys
import textwrap

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
# Make ``scripts`` importable regardless of how pytest is invoked — bare
# ``pytest tests/pytest/test_work_items_v2.py`` (the declared Eval command) must
# work, not only ``python -m pytest``. Repo convention: tests/pytest/test_cli.py:19-22.
sys.path.insert(0, str(REPO_ROOT))

from scripts.mb_work_items import parse_work_items  # noqa: E402

_CLI = REPO_ROOT / "scripts" / "mb_work_items.py"
_FIXTURES = REPO_ROOT / "tests" / "fixtures" / "work_items_v2"
_SNAPSHOT = _FIXTURES / "legacy_prev2_snapshot.json"
# Frozen copy of every specs/*/tasks.md at Task-1 time. The hashes in the
# snapshot were produced by the *original* parser (git HEAD) over these exact
# bytes — so the test proves NEW-parser projection == OLD-parser projection on
# a fixed corpus, immune to concurrent edits of the live specs (REQ-039).
_CORPUS = _FIXTURES / "corpus"

_PREV2_KEYS = [
    "source",
    "topic",
    "item_no",
    "kind",
    "heading",
    "body",
    "role",
    "agent",
    "status",
    "covers",
    "dod_lines",
]


# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────


def _spec_task(no: int, body: str) -> str:
    return f"<!-- mb-task:{no} -->\n## Task {no}: T\n\n{body}\n<!-- /mb-task:{no} -->\n"


def _write_tasks(tmp_path: pathlib.Path, *blocks: str, topic: str = "demo") -> pathlib.Path:
    d = tmp_path / topic
    d.mkdir(parents=True, exist_ok=True)
    p = d / "tasks.md"
    p.write_text("# Tasks\n\n" + "".join(blocks), encoding="utf-8")
    return p


def _run_cli(path: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(_CLI), str(path)],
        capture_output=True,
        text=True,
    )


def _single(path: pathlib.Path):
    items = parse_work_items(path)
    assert len(items) == 1
    return items[0]


# ──────────────────────────────────────────────────────────────────────────────
# RED anchor — full v2 block parses (design C1, Scenario 8)
# ──────────────────────────────────────────────────────────────────────────────


def test_v2_fields_parsed(tmp_path: pathlib.Path) -> None:
    body = textwrap.dedent(
        """\
        **Stage:** 2
        **Covers:** REQ-004
        **Role:** backend
        **Blocked-by:** 1, svp-interview-upgrade#3
        **Scope:** scripts/*.sh, tests/fixtures/**
        **Eval:** pytest tests/pytest/test_x.py — red: v2 fields are absent; exit: 1; output~: FAILED tests/pytest/test_x\\.py::test_v2_fields_parsed
        **Budget:** 100000
        """
    )
    item = _single(_write_tasks(tmp_path, _spec_task(1, body)))

    assert item.stage == 2
    assert list(item.blocked_by) == ["1", "svp-interview-upgrade#3"]
    assert list(item.scope) == ["scripts/*.sh", "tests/fixtures/**"]
    assert item.budget == 100000
    assert item.eval is not None
    assert item.eval["cmd"] == "pytest tests/pytest/test_x.py"
    assert item.eval["red"] == "v2 fields are absent"
    assert item.eval["exit"] == 1
    assert item.eval["output_re"] == r"FAILED tests/pytest/test_x\.py::test_v2_fields_parsed"


def test_real_eval_line_strips_code_span_backticks() -> None:
    """A REAL Eval line from a live spec is authored byte-identical to design.md,
    which wraps the command and ERE in `` `code spans` `` (CPR-D). The parser must
    hand consumers an executable cmd and a compilable ERE — no backticks."""
    items = parse_work_items(_CORPUS / "svp-sdd-core" / "tasks.md")
    ev = {it.item_no: it.eval for it in items}
    t1 = ev[1]
    assert t1["cmd"] == "pytest tests/pytest/test_work_items_v2.py"
    assert t1["output_re"] == r"FAILED tests/pytest/test_work_items_v2\.py::test_v2_fields_parsed"
    # every real eval in the corpus is backtick-free after parsing
    import re as _re

    for it in items:
        e = it.eval
        if e and e["cmd"] != "none":
            assert "`" not in e["cmd"], f"task {it.item_no} cmd keeps backticks"
            if e["output_re"]:
                assert "`" not in e["output_re"], f"task {it.item_no} output_re keeps backticks"
                _re.compile(e["output_re"])  # must be a compilable ERE


# ──────────────────────────────────────────────────────────────────────────────
# Byte-identity of the pre-v2 projection on the whole legacy corpus (REQ-039)
# ──────────────────────────────────────────────────────────────────────────────


def test_prev2_projection_byte_identical_on_legacy_corpus() -> None:
    # Provenance (read-only, deterministic — re-runnable to regenerate):
    #   corpus  = `git show HEAD:.memory-bank/specs/<spec>/tasks.md` at Task-1 time
    #             (frozen under tests/fixtures/work_items_v2/corpus/, blob ee3f5e5),
    #   snapshot = the ORIGINAL parser (git HEAD `scripts/mb_work_items.py`) run over
    #             that frozen corpus, hashing only the 11 pre-v2 keys.
    # This is NOT a circular self-comparison: the hashes were produced by the
    # pre-v2 parser, so the test proves NEW projection == OLD projection.
    from scripts.mb_work_items import _work_item_to_dict

    snapshot = json.loads(_SNAPSHOT.read_text(encoding="utf-8"))
    assert snapshot, "frozen snapshot must not be empty"
    assert len(snapshot) == 29, f"expected 29 frozen specs, got {len(snapshot)}"
    corpus_names = {p.parent.name for p in _CORPUS.glob("*/tasks.md")}
    assert set(snapshot) == corpus_names, "snapshot spec set drifted from the frozen corpus"

    for spec_name, expected in snapshot.items():
        corpus_file = _CORPUS / spec_name / "tasks.md"
        assert corpus_file.exists(), f"frozen corpus missing {spec_name}"
        items = parse_work_items(corpus_file)
        assert len(items) == len(expected), f"item count drift in {spec_name}"
        for item, exp in zip(items, expected, strict=True):
            d = _work_item_to_dict(item)
            proj = {k: d[k] for k in _PREV2_KEYS}
            canon = json.dumps(proj, sort_keys=True, ensure_ascii=False)
            got = hashlib.sha256(canon.encode("utf-8")).hexdigest()
            assert got == exp["sha256"], (
                f"pre-v2 projection changed for {spec_name} item {exp['item_no']}"
            )


def test_cli_projection_keys_are_superset_of_prev2() -> None:
    # A legacy spec parses through the CLI and still carries every pre-v2 key.
    cp = _run_cli(REPO_ROOT / ".memory-bank/specs/adapter-parity/tasks.md")
    assert cp.returncode == 0, cp.stderr
    first = json.loads(cp.stdout.splitlines()[0])
    for k in _PREV2_KEYS:
        assert k in first
    for k in ("stage", "blocked_by", "scope", "eval", "budget"):
        assert k in first


# ──────────────────────────────────────────────────────────────────────────────
# Defaults for absent v2 fields (C1)
# ──────────────────────────────────────────────────────────────────────────────


def test_defaults_for_absent_v2_fields(tmp_path: pathlib.Path) -> None:
    body = "**Covers:** REQ-001\n**Role:** developer\n"
    item = _single(_write_tasks(tmp_path, _spec_task(1, body)))
    assert item.stage == 1
    assert list(item.blocked_by) == []
    assert list(item.scope) == ["**"]
    assert item.eval is None
    assert item.budget == 120000


def test_blocked_by_default_is_previous_task(tmp_path: pathlib.Path) -> None:
    b1 = "**Covers:** REQ-001\n**Role:** developer\n"
    b2 = "**Covers:** REQ-002\n**Role:** developer\n"
    p = _write_tasks(tmp_path, _spec_task(1, b1), _spec_task(2, b2))
    items = parse_work_items(p)
    assert list(items[0].blocked_by) == []
    assert list(items[1].blocked_by) == ["1"]


def test_blocked_by_none_is_empty(tmp_path: pathlib.Path) -> None:
    body = "**Covers:** REQ-001\n**Role:** developer\n**Blocked-by:** none\n"
    item = _single(_write_tasks(tmp_path, _spec_task(1, body)))
    assert list(item.blocked_by) == []


# ──────────────────────────────────────────────────────────────────────────────
# Blocked-by grammar rejection (parser exits 2 on malformed)
# ──────────────────────────────────────────────────────────────────────────────


@pytest.mark.parametrize("value", ["abc", "1, oops", "topic#", "#3", "1;2"])
def test_invalid_blocked_by_rejected(tmp_path: pathlib.Path, value: str) -> None:
    body = f"**Covers:** REQ-001\n**Role:** developer\n**Blocked-by:** {value}\n"
    cp = _run_cli(_write_tasks(tmp_path, _spec_task(1, body)))
    assert cp.returncode == 2, (cp.returncode, cp.stdout, cp.stderr)


@pytest.mark.parametrize("field", ["Stage", "Blocked-by", "Scope", "Eval", "Budget"])
def test_empty_explicit_v2_field_is_malformed(tmp_path: pathlib.Path, field: str) -> None:
    # An EXPLICITLY empty field must be rejected (exit 2), never silently
    # collapse to the legacy default — a blank **Scope:** would erase all bounds.
    body = f"**Covers:** REQ-001\n**Role:** developer\n**{field}:** \n"
    cp = _run_cli(_write_tasks(tmp_path, _spec_task(1, body)))
    assert cp.returncode == 2, (field, cp.returncode, cp.stdout, cp.stderr)


# ──────────────────────────────────────────────────────────────────────────────
# Scope grammar — restricted glob (R3-004)
# ──────────────────────────────────────────────────────────────────────────────


def test_scope_valid_patterns_accepted(tmp_path: pathlib.Path) -> None:
    body = (
        "**Covers:** REQ-001\n**Role:** developer\n"
        "**Scope:** scripts/*.sh, dir/**, exact/path.py, agents/mb-*.md\n"
    )
    item = _single(_write_tasks(tmp_path, _spec_task(1, body)))
    assert list(item.scope) == ["scripts/*.sh", "dir/**", "exact/path.py", "agents/mb-*.md"]


@pytest.mark.parametrize(
    "pattern",
    ["src/?.py", "src/[ab].py", "src/{a,b}.py", "src/\\*.py", "src/a,b.py"],
)
def test_scope_malformed_rejected(tmp_path: pathlib.Path, pattern: str) -> None:
    body = f"**Covers:** REQ-001\n**Role:** developer\n**Scope:** {pattern}\n"
    cp = _run_cli(_write_tasks(tmp_path, _spec_task(1, body)))
    assert cp.returncode == 2, (pattern, cp.returncode, cp.stdout, cp.stderr)


@pytest.mark.parametrize("pattern", ["/abs/path.py", "../escape.py", "!negate.py", "a//b.py"])
def test_scope_structural_violations_rejected(tmp_path: pathlib.Path, pattern: str) -> None:
    body = f"**Covers:** REQ-001\n**Role:** developer\n**Scope:** {pattern}\n"
    cp = _run_cli(_write_tasks(tmp_path, _spec_task(1, body)))
    assert cp.returncode == 2, (pattern, cp.returncode, cp.stdout, cp.stderr)


def test_scope_with_spaces_in_path_accepted(tmp_path: pathlib.Path) -> None:
    # Paths with spaces are legal restricted-glob elements (no forbidden metachar).
    body = "**Covers:** REQ-001\n**Role:** developer\n**Scope:** my dir/*.sh, other.sh\n"
    item = _single(_write_tasks(tmp_path, _spec_task(1, body)))
    assert list(item.scope) == ["my dir/*.sh", "other.sh"]


# ──────────────────────────────────────────────────────────────────────────────
# Eval grammar and red anchors (C1)
# ──────────────────────────────────────────────────────────────────────────────


def test_eval_without_anchors(tmp_path: pathlib.Path) -> None:
    body = (
        "**Covers:** REQ-001\n**Role:** developer\n"
        "**Eval:** bats tests/x.bats — red: the contract assertion fails\n"
    )
    item = _single(_write_tasks(tmp_path, _spec_task(1, body)))
    assert item.eval["cmd"] == "bats tests/x.bats"
    assert item.eval["red"] == "the contract assertion fails"
    assert item.eval["exit"] is None
    assert item.eval["output_re"] is None
    assert item.eval["waiver"] is None


def test_eval_waiver(tmp_path: pathlib.Path) -> None:
    body = (
        "**Covers:** REQ-001\n**Role:** developer\n"
        "**Eval:** none — waiver: pure prose doc, no runtime surface\n"
    )
    item = _single(_write_tasks(tmp_path, _spec_task(1, body)))
    assert item.eval["cmd"] == "none"
    assert item.eval["waiver"] == "pure prose doc, no runtime surface"
    assert item.eval["red"] is None


def test_eval_bare_none(tmp_path: pathlib.Path) -> None:
    body = "**Covers:** REQ-001\n**Role:** developer\n**Eval:** none\n"
    item = _single(_write_tasks(tmp_path, _spec_task(1, body)))
    assert item.eval["cmd"] == "none"
    assert item.eval["waiver"] is None


# ──────────────────────────────────────────────────────────────────────────────
# Frontmatter is ignored by the projection (C3 schema preamble)
# ──────────────────────────────────────────────────────────────────────────────


def test_frontmatter_ignored_projection(tmp_path: pathlib.Path) -> None:
    d = tmp_path / "fm"
    d.mkdir()
    p = d / "tasks.md"
    p.write_text(
        '---\nestimated_tokens:\n  total: 100000\n  stages:\n    "1": 100000\n---\n\n'
        "# Tasks\n\n"
        + _spec_task(1, "**Covers:** REQ-001\n**Role:** backend\n**Budget:** 100000\n"),
        encoding="utf-8",
    )
    item = _single(p)
    assert item.topic == "fm"
    assert item.role == "backend"
    assert item.budget == 100000
    # frontmatter preamble is discarded — heading is the task heading, not YAML
    assert item.heading == "Task 1: T"


# ──────────────────────────────────────────────────────────────────────────────
# Regression: mixed markers keep exit 1 (not the new malformed exit 2)
# ──────────────────────────────────────────────────────────────────────────────


def test_mixed_markers_still_exit_1(tmp_path: pathlib.Path) -> None:
    p = tmp_path / "mixed.md"
    p.write_text(
        "<!-- mb-stage:1 -->\n## Stage 1\n\nbody\n<!-- mb-task:1 -->\n## Task 1\n\nbody\n",
        encoding="utf-8",
    )
    cp = _run_cli(p)
    assert cp.returncode == 1, (cp.returncode, cp.stderr)
