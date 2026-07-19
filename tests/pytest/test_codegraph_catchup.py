"""I-133 — bounded inline catch-up for the code graph.

Contract (memory_bank_skill.codegraph_catchup.maybe_catchup):
  * trigger = `<codebase>/.graph-dirty` marker OR git-HEAD drift vs the meta row;
  * one consumer at a time (non-blocking flock on `<codebase>/.graph.lock`);
  * bounded by MB_GRAPH_CATCHUP_BUDGET (subprocess timeout — the I-132 rule:
    nothing may run unbounded); a timed-out/broken rebuild writes a cooldown
    marker so queries do not pay the budget again and again;
  * opt-in build flags (--docs et al.) are detected from the existing graph and
    preserved — a catch-up must never silently strip data layers;
  * kill-switch MB_GRAPH_AUTOUPDATE=off; never raises (fail-open like recall).
"""

from __future__ import annotations

import fcntl
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
QUERY_CLI = REPO_ROOT / "scripts" / "mb-graph-query.py"
BUILD_CLI = REPO_ROOT / "scripts" / "mb-codegraph.py"

sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill.codegraph_catchup import maybe_catchup  # noqa: E402


def _mk_project(tmp_path: Path) -> tuple[Path, Path]:
    """A minimal bank + src pair with one parsed module."""
    mb = tmp_path / ".memory-bank"
    src = tmp_path / "src"
    (mb / "codebase").mkdir(parents=True)
    src.mkdir()
    (src / "alpha.py").write_text("def alpha_one():\n    return 1\n")
    return mb, src


def _build(mb: Path, src: Path, *flags: str) -> Path:
    r = subprocess.run(
        [sys.executable, str(BUILD_CLI), "--apply", *flags, str(mb), str(src)],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert r.returncode == 0, r.stderr
    graph = mb / "codebase" / "graph.json"
    assert graph.is_file()
    return graph


def test_dirty_marker_triggers_rebuild_and_clears_marker(tmp_path, monkeypatch):
    monkeypatch.delenv("MB_GRAPH_AUTOUPDATE", raising=False)
    mb, src = _mk_project(tmp_path)
    graph = _build(mb, src)
    (src / "beta.py").write_text("def beta_new_symbol():\n    return 2\n")
    (mb / "codebase" / ".graph-dirty").write_text("src/beta.py\n")

    res = maybe_catchup(graph, src)

    assert res["result"] == "refreshed", res
    assert "beta_new_symbol" in graph.read_text()
    assert not (mb / "codebase" / ".graph-dirty").exists()


def test_clean_graph_without_git_is_a_noop(tmp_path):
    """No marker + no git repo (meta.commit null) → nothing to do, graph not
    rewritten (a rewrite would churn generated_at and dirty the working tree)."""
    mb, src = _mk_project(tmp_path)
    graph = _build(mb, src)
    before = graph.stat().st_mtime_ns

    res = maybe_catchup(graph, src)

    assert res["result"] == "clean", res
    assert graph.stat().st_mtime_ns == before


def test_busy_lock_skips_and_keeps_marker(tmp_path):
    mb, src = _mk_project(tmp_path)
    graph = _build(mb, src)
    (mb / "codebase" / ".graph-dirty").touch()
    lock = mb / "codebase" / ".graph.lock"
    with open(lock, "w") as fh:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        res = maybe_catchup(graph, src)
    assert res["result"] == "locked", res
    assert (mb / "codebase" / ".graph-dirty").exists()


def test_budget_timeout_writes_cooldown_and_keeps_marker(tmp_path, monkeypatch):
    """A hung parse (FIFO blocks read forever) must be killed at the budget,
    answer 'timed_out', and leave a cooldown so the NEXT query is instant."""
    mb, src = _mk_project(tmp_path)
    graph = _build(mb, src)
    os.mkfifo(src / "hang.py")
    (mb / "codebase" / ".graph-dirty").touch()
    monkeypatch.setenv("MB_GRAPH_CATCHUP_BUDGET", "0.5")

    res = maybe_catchup(graph, src)
    assert res["result"] == "timed_out", res
    assert (mb / "codebase" / ".graph-dirty").exists()

    res2 = maybe_catchup(graph, src)
    assert res2["result"] == "cooldown", res2


def test_head_drift_triggers_rebuild_without_marker(tmp_path):
    mb, src = _mk_project(tmp_path)
    env = {
        **os.environ,
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@t",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@t",
    }

    def _git(*args):
        subprocess.run(["git", "-C", str(src), *args], check=True, capture_output=True, env=env)

    _git("init", "-q")
    _git("add", "-A")
    _git("commit", "-qm", "one")
    graph = _build(mb, src)
    (src / "gamma.py").write_text("def gamma_after_commit():\n    return 3\n")
    _git("add", "-A")
    _git("commit", "-qm", "two")

    res = maybe_catchup(graph, src)
    assert res["result"] == "refreshed", res
    assert "gamma_after_commit" in graph.read_text()


def test_kill_switch_disables_catchup(tmp_path, monkeypatch):
    mb, src = _mk_project(tmp_path)
    graph = _build(mb, src)
    (mb / "codebase" / ".graph-dirty").touch()
    monkeypatch.setenv("MB_GRAPH_AUTOUPDATE", "off")

    res = maybe_catchup(graph, src)
    assert res["result"] == "disabled", res
    assert (mb / "codebase" / ".graph-dirty").exists()


def test_docs_layer_survives_catchup(tmp_path):
    """A graph built with --docs must be caught up WITH --docs — silently
    stripping doc/signature enrichment would be data loss."""
    mb, src = _mk_project(tmp_path)
    (src / "alpha.py").write_text('def alpha_one(x: int) -> int:\n    """Doc."""\n    return x\n')
    graph = _build(mb, src, "--docs")
    assert '"signature"' in graph.read_text()
    (src / "beta.py").write_text("def beta_new_symbol():\n    return 2\n")
    (mb / "codebase" / ".graph-dirty").touch()

    res = maybe_catchup(graph, src)
    assert res["result"] == "refreshed", res
    text = graph.read_text()
    assert "beta_new_symbol" in text
    assert '"signature"' in text  # docs layer preserved


def test_query_cli_catches_up_before_answering(tmp_path):
    """End-to-end: a query against a dirty graph transparently sees the new
    symbol — the vicious circle (stale graph → silence → never used) is cut."""
    mb, src = _mk_project(tmp_path)
    graph = _build(mb, src)
    (src / "beta.py").write_text(
        "from alpha import alpha_one\n\ndef beta_new_symbol():\n    return alpha_one()\n"
    )
    (mb / "codebase" / ".graph-dirty").touch()

    r = subprocess.run(
        [
            sys.executable,
            str(QUERY_CLI),
            "neighbors",
            "--graph",
            str(graph),
            "--symbol",
            "beta_new_symbol",
            "--json",
        ],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload.get("ok") is True, payload


def test_query_cli_catchup_subcommand(tmp_path):
    """`catchup` subcommand — the bounded SessionEnd entry point for hooks."""
    mb, src = _mk_project(tmp_path)
    graph = _build(mb, src)
    (src / "beta.py").write_text("def beta_new_symbol():\n    return 2\n")
    (mb / "codebase" / ".graph-dirty").touch()

    r = subprocess.run(
        [
            sys.executable,
            str(QUERY_CLI),
            "catchup",
            "--graph",
            str(graph),
            "--src-root",
            str(src),
            "--json",
        ],
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload.get("result") == "refreshed", payload
    assert "beta_new_symbol" in graph.read_text()
