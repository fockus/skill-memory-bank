"""End-to-end tests for the opt-in graph-intelligence layer.

Exercises the REAL CLI scripts (subprocess) over a REAL git repo, validating the
whole chain works together and produces consistent, uncorrupted artifacts:

    mb-codegraph.py --apply --cochange --questions   → graph.json + god-nodes.md
    mb-semantic-search.py                            → ranked hits over that graph
    mb-wiki.py plan / merge-edges / index            → dispatch plan + semantic edges

Default-path invariants are also asserted (no opt-in flags ⇒ no co_change/questions).
Skipped when `git` is unavailable.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = REPO_ROOT / "scripts"


def _run(*args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, *args],
        capture_output=True, text=True, cwd=str(cwd) if cwd else None, check=False,
    )


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True)


def _commit(repo: Path, files: dict[str, str], msg: str) -> None:
    for name, content in files.items():
        p = repo / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        _git(repo, "add", name)
    _git(repo, "commit", "-q", "-m", msg)


@pytest.fixture
def project(tmp_path: Path) -> tuple[Path, Path]:
    """A real git repo (src) + an empty memory-bank dir, with co-change history."""
    if shutil.which("git") is None:
        pytest.skip("git not available")
    repo = tmp_path / "proj"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "t@example.com")
    _git(repo, "config", "user.name", "Tester")
    _git(repo, "config", "commit.gpgsign", "false")

    auth = "def make_token():\n    return 1\n\n\ndef login_user():\n    return make_token()\n"
    session = "from auth import login_user\n\n\ndef start_session():\n    return login_user()\n"
    cart = "def cart_total():\n    return 0\n"
    # auth.py + session.py change together twice (co-change signal)
    _commit(repo, {"auth.py": auth, "session.py": session, "cart.py": cart}, "init")
    _commit(repo, {"auth.py": auth + "# tweak\n", "session.py": session + "# tweak\n"}, "tweak")

    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    return repo, mb


def test_e2e_full_intelligence_chain(project):
    repo, mb = project
    cg = str(SCRIPTS / "mb-codegraph.py")

    # 1) Build graph with co-change + questions
    r = _run(cg, "--apply", "--cochange", "--questions", str(mb), str(repo))
    assert r.returncode == 0, r.stderr
    graph_json = mb / "codebase" / "graph.json"
    god = mb / "codebase" / "god-nodes.md"
    assert graph_json.is_file() and god.is_file()

    # graph.json parses and carries a co_change edge (auth.py <-> session.py)
    records = [json.loads(ln) for ln in graph_json.read_text().splitlines() if ln.strip()]
    edge_kinds = {rec.get("kind") for rec in records if rec.get("type") == "edge"}
    assert "co_change" in edge_kinds
    cc = [rec for rec in records if rec.get("kind") == "co_change"]
    pair = {cc[0]["src"], cc[0]["dst"]}
    assert pair == {"auth.py", "session.py"}

    # god-nodes.md has both opt-in sections
    god_text = god.read_text(encoding="utf-8")
    assert "## Suggested questions" in god_text
    assert "## Co-changing file pairs" in god_text

    # 2) Semantic search over the produced graph (BM25, deterministic)
    ss = str(SCRIPTS / "mb-semantic-search.py")
    r2 = _run(ss, "login user", "--backend", "bm25", "--json", str(mb))
    assert r2.returncode == 0, r2.stderr
    payload = json.loads(r2.stdout)
    assert payload["ok"] is True and payload["backend"] == "bm25"
    hit_files = {h["file"] for h in payload["hits"]}
    assert "auth.py" in hit_files  # login_user / make_token live here

    # 3) Wiki dispatch plan (deterministic; communities may be 0 without networkx)
    wiki = str(SCRIPTS / "mb-wiki.py")
    r3 = _run(wiki, "plan", "--json", str(mb), str(repo))
    assert r3.returncode == 0, r3.stderr
    plan = json.loads(r3.stdout)
    assert "communities" in plan and "models" in plan
    assert plan["models"] == {"author": "haiku", "synthesizer": "sonnet"}

    # 4) Merge a surprising-connection edge, then prove the graph is still valid + searchable
    edges_file = mb / "edges.json"
    edges_file.write_text(
        json.dumps([{"src": "auth.py", "dst": "cart.py",
                     "confidence": 0.7, "rationale": "both touched at checkout"}]),
        encoding="utf-8")
    r4 = _run(wiki, "merge-edges", "--edges", str(edges_file), str(mb))
    assert r4.returncode == 0, r4.stderr
    assert "semantic_edges_added=1" in r4.stdout

    records2 = [json.loads(ln) for ln in graph_json.read_text().splitlines() if ln.strip()]
    assert any(rec.get("kind") == "semantic" for rec in records2)
    # idempotent: second merge adds nothing
    r5 = _run(wiki, "merge-edges", "--edges", str(edges_file), str(mb))
    assert "semantic_edges_added=0" in r5.stdout

    # graph still parses for search after the merge
    r6 = _run(ss, "checkout", "--backend", "bm25", "--json", str(mb))
    assert r6.returncode == 0 and json.loads(r6.stdout)["ok"] is True


def test_e2e_default_path_has_no_optin_artifacts(project):
    """No opt-in flags ⇒ graph has no co_change edges and god-nodes has no extra sections."""
    repo, mb = project
    cg = str(SCRIPTS / "mb-codegraph.py")
    r = _run(cg, "--apply", str(mb), str(repo))
    assert r.returncode == 0, r.stderr

    graph_json = mb / "codebase" / "graph.json"
    records = [json.loads(ln) for ln in graph_json.read_text().splitlines() if ln.strip()]
    edge_kinds = {rec.get("kind") for rec in records if rec.get("type") == "edge"}
    assert "co_change" not in edge_kinds
    assert "semantic" not in edge_kinds

    god_text = (mb / "codebase" / "god-nodes.md").read_text(encoding="utf-8")
    assert "## Suggested questions" not in god_text
    assert "## Co-changing file pairs" not in god_text


def test_e2e_semantic_search_missing_graph_exit_code(tmp_path: Path):
    """Semantic search against a bank with no graph exits 3, gracefully."""
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    r = _run(str(SCRIPTS / "mb-semantic-search.py"), "anything", "--json", str(mb))
    assert r.returncode == 3
    assert json.loads(r.stdout)["ok"] is False
