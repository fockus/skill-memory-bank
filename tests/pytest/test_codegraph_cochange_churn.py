"""Tests for the git-churn ranking signal (Task 5, REQ-007).

Churn (``churn_30d`` per file) is derived from the SAME single ``git log`` pass
that mines co-change pairs — no extra subprocess. The opt-in lives entirely
inside ``--cochange``; base builds stay byte-identical.

Pure functions (``parse_git_log_with_dates``, ``count_churn``) are tested
mocklessly. ``co_change_and_churn`` is tested against a real ``git`` repo in
``tmp_path`` with controlled commit dates (``GIT_*_DATE`` env), and against the
orchestrator wiring. Graceful degradation (non-git / shallow / git absent) must
yield empty churn and never raise.
"""

from __future__ import annotations

import importlib.util
import json
import shutil
import subprocess
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import codegraph_cochange as cgco  # noqa: E402

NUL = "\x00"


def _load_script():
    spec = importlib.util.spec_from_file_location(
        "mb_codegraph", REPO_ROOT / "scripts" / "mb-codegraph.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ── pure: parse_git_log_with_dates ───────────────────────────────────


def test_parse_git_log_with_dates_extracts_timestamp_and_files():
    raw = f"{NUL}1700000000\na.py\nb.py\n{NUL}1700000100\nb.py\n"
    commits = cgco.parse_git_log_with_dates(raw)
    assert commits == [(1700000000, {"a.py", "b.py"}), (1700000100, {"b.py"})]


def test_parse_git_log_with_dates_empty_input_returns_no_commits():
    assert cgco.parse_git_log_with_dates("") == []


def test_parse_git_log_with_dates_commit_without_files_yields_empty_set():
    raw = f"{NUL}1700000000\n{NUL}1700000100\nc.py\n"
    commits = cgco.parse_git_log_with_dates(raw)
    assert commits == [(1700000000, set()), (1700000100, {"c.py"})]


def test_parse_git_log_with_dates_non_numeric_first_line_is_none():
    # Defensive: if git ever emits a non-timestamp first line, churn skips it.
    raw = f"{NUL}not-a-ts\na.py\n"
    commits = cgco.parse_git_log_with_dates(raw)
    assert commits == [(None, {"a.py"})]


# ── pure: count_churn ────────────────────────────────────────────────


def test_count_churn_counts_commits_in_window_per_file():
    now = 1_700_000_000
    day = 86_400
    commits = [
        (now - 1 * day, {"a.py", "b.py"}),
        (now - 5 * day, {"a.py"}),
        (now - 10 * day, {"a.py"}),
    ]
    churn = cgco.count_churn(commits, {"a.py", "b.py"}, now=now, window_days=30)
    assert churn == {"a.py": 3, "b.py": 1}


def test_count_churn_excludes_commits_older_than_window():
    now = 1_700_000_000
    day = 86_400
    commits = [
        (now - 5 * day, {"a.py"}),
        (now - 45 * day, {"a.py"}),  # outside 30d window → not counted
    ]
    churn = cgco.count_churn(commits, {"a.py"}, now=now, window_days=30)
    assert churn == {"a.py": 1}


def test_count_churn_restricts_to_known_files():
    now = 1_700_000_000
    commits = [(now, {"a.py", "ghost.py"})]
    churn = cgco.count_churn(commits, {"a.py"}, now=now, window_days=30)
    assert churn == {"a.py": 1}
    assert "ghost.py" not in churn


def test_count_churn_skips_commits_without_timestamp():
    now = 1_700_000_000
    commits = [(None, {"a.py"}), (now, {"a.py"})]
    churn = cgco.count_churn(commits, {"a.py"}, now=now, window_days=30)
    assert churn == {"a.py": 1}


def test_count_churn_empty_when_no_commits_in_window():
    now = 1_700_000_000
    commits = [(now - 100 * 86_400, {"a.py"})]
    assert cgco.count_churn(commits, {"a.py"}, now=now, window_days=30) == {}


# ── integration: co_change_and_churn (real git, controlled dates) ────


def _git(repo: Path, *args: str, env: dict[str, str] | None = None) -> None:
    full_env = None
    if env is not None:
        import os

        full_env = {**os.environ, **env}
    subprocess.run(
        ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True, env=full_env
    )


def _commit_at(repo: Path, files: dict[str, str], msg: str, when: datetime) -> None:
    for name, content in files.items():
        p = repo / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")
        _git(repo, "add", name)
    stamp = when.strftime("%Y-%m-%dT%H:%M:%S")
    _git(
        repo, "commit", "-q", "-m", msg, env={"GIT_AUTHOR_DATE": stamp, "GIT_COMMITTER_DATE": stamp}
    )


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


def test_co_change_and_churn_counts_recent_commits(git_repo: Path):
    now = datetime.now(UTC)
    # a.py committed 3× within the window; b.py once.
    _commit_at(git_repo, {"a.py": "x=1\n", "b.py": "y=1\n"}, "c1", now - timedelta(days=10))
    _commit_at(git_repo, {"a.py": "x=2\n"}, "c2", now - timedelta(days=5))
    _commit_at(git_repo, {"a.py": "x=3\n"}, "c3", now - timedelta(days=1))
    _, attrs = cgco.co_change_and_churn(git_repo, {"a.py", "b.py"})
    by_file = {a["file"]: a["churn_30d"] for a in attrs}
    assert by_file == {"a.py": 3, "b.py": 1}
    assert all(a["type"] == "node-attr" for a in attrs)


def test_co_change_and_churn_excludes_old_commits(git_repo: Path):
    now = datetime.now(UTC)
    _commit_at(git_repo, {"a.py": "x=1\n"}, "recent", now - timedelta(days=2))
    _commit_at(git_repo, {"a.py": "x=2\n"}, "old", now - timedelta(days=60))
    _, attrs = cgco.co_change_and_churn(git_repo, {"a.py"})
    by_file = {a["file"]: a["churn_30d"] for a in attrs}
    assert by_file == {"a.py": 1}  # the 60-day-old commit is outside the window


def test_co_change_and_churn_reroots_to_subdir(git_repo: Path):
    now = datetime.now(UTC)
    _commit_at(git_repo, {"src/a.py": "x=1\n"}, "c1", now - timedelta(days=3))
    _commit_at(git_repo, {"src/a.py": "x=2\n"}, "c2", now - timedelta(days=1))
    _, attrs = cgco.co_change_and_churn(git_repo / "src", {"a.py"})
    by_file = {a["file"]: a["churn_30d"] for a in attrs}
    assert by_file == {"a.py": 2}


def test_co_change_and_churn_non_git_dir_is_graceful(tmp_path: Path):
    plain = tmp_path / "plain"
    plain.mkdir()
    edges, attrs = cgco.co_change_and_churn(plain, {"a.py"})
    assert edges == []
    assert attrs == []


def test_co_change_and_churn_single_git_log_subprocess(git_repo: Path, monkeypatch):
    """DoD: churn adds NO extra subprocess. Exactly one ``git log`` call total."""
    now = datetime.now(UTC)
    _commit_at(git_repo, {"a.py": "x=1\n", "b.py": "y=1\n"}, "c1", now - timedelta(days=2))
    _commit_at(git_repo, {"a.py": "x=2\n", "b.py": "y=2\n"}, "c2", now - timedelta(days=1))

    real_run = subprocess.run
    log_calls = {"n": 0}

    def _counting_run(cmd, *a, **k):
        if isinstance(cmd, (list, tuple)) and "log" in cmd:
            log_calls["n"] += 1
        return real_run(cmd, *a, **k)

    monkeypatch.setattr(cgco.subprocess, "run", _counting_run)
    cgco.co_change_and_churn(git_repo, {"a.py", "b.py"})
    assert log_calls["n"] == 1


def test_co_change_and_churn_still_returns_cochange_edges(git_repo: Path):
    now = datetime.now(UTC)
    _commit_at(git_repo, {"a.py": "x=1\n", "b.py": "y=1\n"}, "c1", now - timedelta(days=3))
    _commit_at(git_repo, {"a.py": "x=2\n", "b.py": "y=2\n"}, "c2", now - timedelta(days=1))
    edges, _ = cgco.co_change_and_churn(git_repo, {"a.py", "b.py"})
    assert edges == [{"src": "a.py", "dst": "b.py", "kind": "co_change", "weight": 2}]


# ── wiring: scripts/mb-codegraph.py emits node-attr rows under --cochange ──


def _records(graph_json: Path) -> list[dict]:
    return [json.loads(line) for line in graph_json.read_text(encoding="utf-8").splitlines()]


@pytest.fixture
def py_git_repo(git_repo: Path) -> Path:
    now = datetime.now(UTC)
    _commit_at(
        git_repo, {"a.py": "import os\n", "b.py": "import sys\n"}, "c1", now - timedelta(days=4)
    )
    _commit_at(
        git_repo,
        {"a.py": "import os\nx=1\n", "b.py": "import sys\ny=1\n"},
        "c2",
        now - timedelta(days=1),
    )
    return git_repo


def test_run_cochange_emits_node_attr_rows(py_git_repo: Path, tmp_path: Path):
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(py_git_repo), mode="apply", cochange=True)
    recs = _records(mb / "codebase" / "graph.json")
    attrs = [r for r in recs if r.get("type") == "node-attr"]
    assert attrs, "expected node-attr churn rows under --cochange"
    by_file = {a["file"]: a["churn_30d"] for a in attrs}
    assert by_file.get("a.py", 0) >= 2
    assert by_file.get("b.py", 0) >= 2


def test_run_cochange_off_emits_no_node_attr_rows(py_git_repo: Path, tmp_path: Path):
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_script()
    mod.run(mb_path=str(mb), src_root=str(py_git_repo), mode="apply", cochange=False)
    recs = _records(mb / "codebase" / "graph.json")
    assert not [r for r in recs if r.get("type") == "node-attr"]


def test_run_cochange_outside_git_emits_no_node_attr(tmp_path: Path):
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.py").write_text("x = 1\n", encoding="utf-8")
    mb = tmp_path / "mb"
    (mb / "codebase").mkdir(parents=True)
    mod = _load_script()
    summary = mod.run(mb_path=str(mb), src_root=str(src), mode="apply", cochange=True)
    assert summary["cochange_edges"] == 0
    recs = _records(mb / "codebase" / "graph.json")
    assert not [r for r in recs if r.get("type") == "node-attr"]


# ── regression: node-attr rows do not break the graph query loader ────


def test_node_attr_rows_ignored_by_graph_loader(tmp_path: Path):
    """node-attr is a NEW row type; the canonical loader must tolerate it."""
    from memory_bank_skill.codegraph_loader import load_graph

    graph = tmp_path / "graph.json"
    graph.write_text(
        "\n".join(
            [
                json.dumps({"type": "node", "kind": "function", "name": "f", "file": "a.py"}),
                json.dumps({"type": "node-attr", "file": "a.py", "churn_30d": 5}),
                json.dumps({"type": "edge", "kind": "call", "src": "a.py:f", "dst": "b"}),
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    nodes, edges = load_graph(graph)
    assert len(nodes) == 1
    assert len(edges) == 1  # node-attr row neither counted as node nor edge


def test_node_attr_rows_ignored_by_graph_query_core(tmp_path: Path):
    """mb_graph_query_core must not crash on node-attr rows (neighbors query)."""
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    import mb_graph_query_core as core

    graph = tmp_path / "graph.json"
    graph.write_text(
        "\n".join(
            [
                json.dumps({"type": "node", "kind": "function", "name": "f", "file": "a.py"}),
                json.dumps({"type": "node-attr", "file": "a.py", "churn_30d": 5}),
                json.dumps({"type": "edge", "kind": "call", "src": "a.py:f", "dst": "g"}),
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    nodes, edges = core.load_graph(graph)
    payload = core.neighbors_payload(nodes, edges, symbol="f", file_name=None)
    assert payload["ok"] is True
