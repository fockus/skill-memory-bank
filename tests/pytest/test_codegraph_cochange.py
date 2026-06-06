"""Tests for memory_bank_skill/codegraph_cochange.py — git co-change file edges.

Pure functions (``parse_git_log``, ``count_pairs``, ``render_cochange_section``)
are tested mocklessly; ``co_change_edges`` is tested as integration against a
real ``git`` repo in ``tmp_path`` (git is the external boundary). Graceful
degradation (non-git dir / git binary absent) must yield ``[]`` — never raise.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import codegraph_cochange as cgco  # noqa: E402

NUL = "\x00"


def _load_script():
    spec = importlib.util.spec_from_file_location(
        "mb_codegraph", REPO_ROOT / "scripts" / "mb-codegraph.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _edge_kinds(graph_json: Path) -> list[str]:
    kinds = []
    for line in graph_json.read_text(encoding="utf-8").splitlines():
        rec = json.loads(line)
        if rec.get("type") == "edge":
            kinds.append(rec.get("kind"))
    return kinds


# ── pure: parse_git_log ──────────────────────────────────────────────

def test_parse_git_log_splits_commits_into_file_sets():
    raw = f"{NUL}\n\na.py\nb.py\n\n{NUL}\n\nb.py\nc.py\n"
    commits = cgco.parse_git_log(raw)
    assert commits == [{"a.py", "b.py"}, {"b.py", "c.py"}]


def test_parse_git_log_empty_input_returns_no_commits():
    assert cgco.parse_git_log("") == []


def test_parse_git_log_ignores_blank_records():
    raw = f"{NUL}\n\n{NUL}\n\na.py\n"
    assert cgco.parse_git_log(raw) == [{"a.py"}]


# ── pure: count_pairs ────────────────────────────────────────────────

def test_count_pairs_counts_pair_across_commits():
    commits = [{"a.py", "b.py"}, {"a.py", "b.py"}]
    pairs = cgco.count_pairs(commits, {"a.py", "b.py"})
    assert pairs == [("a.py", "b.py", 2)]


def test_count_pairs_drops_below_min_shared():
    commits = [{"a.py", "b.py"}]  # only 1 shared commit
    assert cgco.count_pairs(commits, {"a.py", "b.py"}, min_shared=2) == []


def test_count_pairs_skips_bulk_commits_over_threshold():
    bulk = {f"f{i}.py" for i in range(30)}
    commits = [bulk, bulk]  # huge commits — co-change is noise
    known = {f"f{i}.py" for i in range(30)}
    assert cgco.count_pairs(commits, known, max_files_per_commit=25) == []


def test_count_pairs_filters_to_known_files_only():
    commits = [{"a.py", "ghost.py"}, {"a.py", "ghost.py"}]
    # ghost.py is not a graph node → no pair survives
    assert cgco.count_pairs(commits, {"a.py"}) == []


def test_count_pairs_single_file_commits_produce_no_pairs():
    commits = [{"a.py"}, {"b.py"}]
    assert cgco.count_pairs(commits, {"a.py", "b.py"}) == []


def test_count_pairs_deterministic_order_and_cap():
    commits = [
        {"a.py", "b.py"}, {"a.py", "b.py"},          # weight 2
        {"c.py", "d.py"}, {"c.py", "d.py"}, {"c.py", "d.py"},  # weight 3
    ]
    known = {"a.py", "b.py", "c.py", "d.py"}
    pairs = cgco.count_pairs(commits, known, max_pairs=1)
    # highest weight first, then lexical → c/d (weight 3) wins the cap of 1
    assert pairs == [("c.py", "d.py", 3)]


# ── pure: render_cochange_section ────────────────────────────────────

def test_render_cochange_section_tabulates_edges():
    edges = [{"src": "a.py", "dst": "b.py", "kind": "co_change", "weight": 3}]
    md = cgco.render_cochange_section(edges)
    assert "## Co-changing file pairs" in md
    assert "`a.py`" in md and "`b.py`" in md
    assert "| 1 |" in md and "3" in md


def test_render_cochange_section_empty_is_graceful():
    md = cgco.render_cochange_section([])
    assert "## Co-changing file pairs" in md
    assert "No co-change" in md


# ── integration: co_change_edges (real git) ─────────────────────────

def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args],
                   check=True, capture_output=True, text=True)


def _commit(repo: Path, files: dict[str, str], msg: str) -> None:
    for name, content in files.items():
        p = repo / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        _git(repo, "add", name)
    _git(repo, "commit", "-q", "-m", msg)


@pytest.fixture
def git_repo(tmp_path: Path) -> Path:
    if shutil.which("git") is None:
        pytest.skip("git not available")
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "-q")
    _git(repo, "config", "user.email", "t@example.com")
    _git(repo, "config", "user.name", "Tester")
    _git(repo, "config", "commit.gpgsign", "false")
    return repo


def test_co_change_edges_links_files_changed_together(git_repo: Path):
    _commit(git_repo, {"a.py": "x = 1\n", "b.py": "y = 1\n"}, "feat")
    _commit(git_repo, {"a.py": "x = 2\n", "b.py": "y = 2\n"}, "fix")
    edges = cgco.co_change_edges(git_repo, {"a.py", "b.py"})
    assert edges == [{"src": "a.py", "dst": "b.py", "kind": "co_change", "weight": 2}]


def test_co_change_edges_reroots_to_src_root_subdir(git_repo: Path):
    _commit(git_repo, {"src/a.py": "x=1\n", "src/b.py": "y=1\n"}, "c1")
    _commit(git_repo, {"src/a.py": "x=2\n", "src/b.py": "y=2\n"}, "c2")
    # known_files are relative to src_root (the subdir), not the git toplevel
    edges = cgco.co_change_edges(git_repo / "src", {"a.py", "b.py"})
    assert edges == [{"src": "a.py", "dst": "b.py", "kind": "co_change", "weight": 2}]


def test_co_change_edges_non_git_dir_returns_empty(tmp_path: Path):
    plain = tmp_path / "plain"
    plain.mkdir()
    assert cgco.co_change_edges(plain, {"a.py"}) == []


def test_co_change_edges_git_missing_is_graceful(git_repo: Path, monkeypatch):
    def _boom(*a, **k):
        raise FileNotFoundError("git")
    monkeypatch.setattr(cgco.subprocess, "run", _boom)
    assert cgco.co_change_edges(git_repo, {"a.py", "b.py"}) == []


# ── wiring: scripts/mb-codegraph.py run(..., cochange=) ──────────────

@pytest.fixture
def py_git_repo(git_repo: Path) -> Path:
    """Git repo whose two .py files (graph nodes) change together twice."""
    _commit(git_repo, {"a.py": "import os\n", "b.py": "import sys\n"}, "c1")
    _commit(git_repo, {"a.py": "import os\nx=1\n", "b.py": "import sys\ny=1\n"}, "c2")
    return git_repo


def test_run_cochange_off_emits_no_co_change_edges(py_git_repo: Path, tmp_path: Path):
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(py_git_repo), mode="apply", cochange=False)
    assert "co_change" not in _edge_kinds(mb / "codebase" / "graph.json")


def test_run_cochange_on_adds_edges_and_section(py_git_repo: Path, tmp_path: Path):
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_script()
    summary = mod.run(mb_path=str(mb), src_root=str(py_git_repo), mode="apply", cochange=True)
    assert summary["cochange_edges"] >= 1
    assert "co_change" in _edge_kinds(mb / "codebase" / "graph.json")
    god = (mb / "codebase" / "god-nodes.md").read_text(encoding="utf-8")
    assert "## Co-changing file pairs" in god


def test_run_cochange_outside_git_is_graceful(tmp_path: Path):
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.py").write_text("x = 1\n", encoding="utf-8")
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_script()
    summary = mod.run(mb_path=str(mb), src_root=str(src), mode="apply", cochange=True)
    assert summary["cochange_edges"] == 0
    assert "co_change" not in _edge_kinds(mb / "codebase" / "graph.json")


def test_mb_command_doc_mentions_cochange_flag():
    mb_doc = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "--cochange" in mb_doc
