"""Git-HEAD-aware freshness for the Memory Bank code graph.

Reads the always-on ``meta`` row (``codegraph_loader.read_meta``) and decides
staleness against two signals: wall-clock age of the stamp and how many commits
``src_root``'s HEAD is ahead of the graph's build commit. Git access is isolated
in ``_commits_behind`` (monkeypatchable; any git error fails open to age-only,
never raises). SRP: loader parses, this module owns freshness policy.
"""

from __future__ import annotations

import os
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from memory_bank_skill.codegraph_loader import read_meta

DEFAULT_STALE_HOURS = 24.0
DEFAULT_STALE_COMMITS = 50


def env_thresholds() -> tuple[float, int]:
    """Resolve ``(stale_hours, stale_commits)`` from ``MB_GRAPH_STALE_HOURS`` /
    ``MB_GRAPH_STALE_COMMITS``; a malformed value degrades to the default."""
    try:
        hours = float(os.environ.get("MB_GRAPH_STALE_HOURS", DEFAULT_STALE_HOURS))
    except (TypeError, ValueError):
        hours = DEFAULT_STALE_HOURS
    try:
        commits = int(os.environ.get("MB_GRAPH_STALE_COMMITS", DEFAULT_STALE_COMMITS))
    except (TypeError, ValueError):
        commits = DEFAULT_STALE_COMMITS
    return hours, commits


def _parse_iso(ts: str) -> datetime | None:
    try:
        return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=UTC)
    except (ValueError, TypeError):
        return None


def _commits_behind(src_root: Path, commit: str) -> int | None:
    """``git rev-list --count <commit>..HEAD`` → int, else ``None`` (fail-open on
    git missing / unknown commit / src outside a repo → caller falls back to age)."""
    try:
        result = subprocess.run(
            ["git", "-C", str(src_root), "rev-list", "--count", f"{commit}..HEAD"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (subprocess.SubprocessError, FileNotFoundError, OSError):
        return None
    if result.returncode != 0:
        return None
    try:
        return int(result.stdout.strip())
    except ValueError:
        return None


def graph_freshness(
    graph_path: str | Path,
    src_root: str | Path,
    *,
    stale_hours: float = DEFAULT_STALE_HOURS,
    stale_commits: int = DEFAULT_STALE_COMMITS,
) -> dict[str, Any]:
    """Return a freshness verdict for ``graph_path``. Never raises."""
    graph_path = Path(graph_path)
    src_root = Path(src_root)
    info: dict[str, Any] = {
        "exists": False,
        "generated_at": None,
        "commit": None,
        "nodes": None,
        "edges": None,
        "age_hours": None,
        "commits_behind": None,
        "stale": True,
        "reason": "absent",
    }
    if not graph_path.is_file():
        return info

    info["exists"] = True
    meta = read_meta(graph_path)
    generated_at = meta.get("generated_at") if meta else None
    commit = meta.get("commit") if meta else None
    info["generated_at"] = generated_at
    info["commit"] = commit
    if meta:
        info["nodes"] = meta.get("nodes")
        info["edges"] = meta.get("edges")

    parsed = _parse_iso(generated_at) if generated_at else None
    age_hours = None
    if parsed is not None:
        age_hours = (datetime.now(UTC) - parsed).total_seconds() / 3600.0
        info["age_hours"] = round(age_hours, 4)

    commits_behind = _commits_behind(src_root, commit) if commit else None
    info["commits_behind"] = commits_behind

    if age_hours is None and commits_behind is None:
        reason = "unknown"  # can't verify freshness → treat as stale
    elif commits_behind is not None and commits_behind > stale_commits:
        reason = "commits"
    elif age_hours is not None and age_hours > stale_hours:
        reason = "age"
    else:
        reason = "fresh"
    info["reason"] = reason
    info["stale"] = reason != "fresh"
    return info
