"""Tests for memory_bank_skill/codegraph_freshness.py — git-HEAD-aware staleness.

Contract:
    graph_freshness(graph_path, src_root, *, stale_hours, stale_commits) -> dict
    { exists, generated_at, commit, age_hours, commits_behind, stale, reason }
    reason ∈ absent | fresh | age | commits | unknown

Git access is isolated in the module-level ``_commits_behind`` helper so these
unit tests can monkeypatch it without a real repo.
"""

from __future__ import annotations

import json
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import codegraph_freshness as fresh  # noqa: E402


def _iso(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _write_graph(path: Path, generated_at: str, commit: str | None = "abc1234") -> Path:
    meta = {
        "type": "meta",
        "generated_at": generated_at,
        "commit": commit,
        "nodes": 2,
        "edges": 1,
    }
    lines = [
        json.dumps(meta),
        json.dumps({"type": "node", "name": "x", "file": "x.py"}),
        json.dumps({"type": "node", "name": "y", "file": "y.py"}),
        json.dumps({"type": "edge", "src": "x.py", "dst": "y", "kind": "import"}),
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def test_freshness_absent_graph_is_stale(tmp_path: Path):
    info = fresh.graph_freshness(tmp_path / "nope.json", tmp_path, stale_hours=24, stale_commits=50)
    assert info["exists"] is False
    assert info["stale"] is True
    assert info["reason"] == "absent"


def test_freshness_recent_within_thresholds_is_fresh(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(fresh, "_commits_behind", lambda src, commit: 0)
    g = _write_graph(tmp_path / "graph.json", _iso(datetime.now(UTC)))
    info = fresh.graph_freshness(g, tmp_path, stale_hours=24, stale_commits=50)
    assert info["exists"] is True
    assert info["stale"] is False
    assert info["reason"] == "fresh"
    assert info["commits_behind"] == 0


def test_freshness_old_age_marks_stale(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(fresh, "_commits_behind", lambda src, commit: 0)
    old = datetime.now(UTC) - timedelta(hours=48)
    g = _write_graph(tmp_path / "graph.json", _iso(old))
    info = fresh.graph_freshness(g, tmp_path, stale_hours=24, stale_commits=50)
    assert info["stale"] is True
    assert info["reason"] == "age"
    assert info["age_hours"] >= 47


def test_freshness_many_commits_behind_marks_stale(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(fresh, "_commits_behind", lambda src, commit: 120)
    g = _write_graph(tmp_path / "graph.json", _iso(datetime.now(UTC)))
    info = fresh.graph_freshness(g, tmp_path, stale_hours=24, stale_commits=50)
    assert info["stale"] is True
    assert info["reason"] == "commits"
    assert info["commits_behind"] == 120


def test_freshness_git_unavailable_falls_back_to_age(tmp_path: Path, monkeypatch):
    monkeypatch.setattr(fresh, "_commits_behind", lambda src, commit: None)
    g = _write_graph(tmp_path / "graph.json", _iso(datetime.now(UTC)))
    info = fresh.graph_freshness(g, tmp_path, stale_hours=24, stale_commits=50)
    assert info["commits_behind"] is None
    assert info["stale"] is False  # age is fresh; git absence never crashes
    assert info["reason"] == "fresh"
