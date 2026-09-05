"""Cost mining over Claude Code transcripts — the measurement half of `/mb cost`.

Reads a project's transcript store (``~/.claude/projects/<slug>/``: one
``<session>.jsonl`` per session plus ``<session>/subagents/*.jsonl`` per
dispatched subagent) and cuts it three ways for the mb-work-cost-diet gates:
per session, per subagent role, and per work item (the orchestrator segment
between ``mb-work-state.sh init`` and ``mb-work-checkbox.sh flip``).

Malformed JSON lines are skipped, never raised — transcripts are appended live,
so a truncated tail line is normal. Rendering and CLI live in
``scripts/mb-cost-report.py``.
"""

from __future__ import annotations

import json
import re
from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

# The FIRST match wins, so every entry is ordered by AGENT IDENTITY. Shared
# preamble markers must never decide a role: `mb-tooling-core` is prepended to
# reviewer/manager/research prompts too, and an implementer-first table using it
# made the `reviewer` bucket unreachable on real transcripts. Only the last entry
# falls back to the engineering-core preamble, after every identity has missed.
ROLE_MARKERS: tuple[tuple[str, str], ...] = (
    ("judge", r"mb-judge|MB Judge|Independent final quality gate|GO_WITH_BACKLOG"),
    ("verifier", r"plan-verifier|Plan execution auditor|Plan Verifier|mb-work verify"),
    ("reviewer", r"mb-reviewer|MB Reviewer|Code review agent|review payload|CHANGES_REQUESTED"),
    ("manager", r"mb-manager|MB Manager|Memory Bank manager"),
    ("research", r"mb-research|codebase-research"),
    (
        "implementer",
        r"mb-developer|mb-backend|mb-frontend|mb-qa|mb-devops|mb-architect|mb-analyst"
        r"|mb-ios|mb-android|MB Engineering Core|mb-engineering-core",
    ),
)

# The audit counted a test run as a Bash `tool_use` whose command matches this;
# the Sprint 2/3 gates cite those numbers, so the pattern is frozen.
TEST_CMD_RE = re.compile(r"pytest|bats|go test|ya make -t")

# A marker names the dispatched agent only in a structural position — a heading
# or the frontmatter `name:` — within the prompt's leading window. Everything
# else is prose, where a quoted finding says nothing about who is running.
_IDENTITY_WINDOW = 400
_IDENTITY_LINE_RE = re.compile(r"\s*(#|name:)")

ITEM_OPEN_RE = re.compile(r"mb-work-state\.sh init")
ITEM_CLOSE_RE = re.compile(r"mb-work-checkbox\.sh flip")

_USAGE_KEYS = ("cache_creation_input_tokens", "cache_read_input_tokens", "input_tokens")


def iter_records(path: Path) -> Iterator[dict[str, Any]]:
    """Yield JSON objects from a transcript, skipping unparseable/non-object lines."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except ValueError:
                continue
            if isinstance(obj, dict):
                yield obj


def _timestamp(record: dict[str, Any]) -> datetime | None:
    raw = record.get("timestamp")
    if not isinstance(raw, str):
        return None
    try:
        return datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def _tool_uses(record: dict[str, Any]) -> list[dict[str, Any]]:
    content = (record.get("message") or {}).get("content")
    if not isinstance(content, list):
        return []
    return [c for c in content if isinstance(c, dict) and c.get("type") == "tool_use"]


def _usage(record: dict[str, Any]) -> dict[str, int]:
    raw = (record.get("message") or {}).get("usage") or {}
    out = {k: int(raw.get(k) or 0) for k in _USAGE_KEYS}
    out["output_tokens"] = int(raw.get("output_tokens") or 0)
    return out


def _context_size(usage: dict[str, int]) -> int:
    return sum(usage[k] for k in _USAGE_KEYS)


def _bash_command(tool_use: dict[str, Any]) -> str:
    if tool_use.get("name") != "Bash":
        return ""
    return str((tool_use.get("input") or {}).get("command") or "")


def _minutes(start: datetime | None, end: datetime | None) -> float:
    if not start or not end:
        return 0.0
    return round((end - start).total_seconds() / 60, 4)


def _first_prompt(records: list[dict[str, Any]]) -> str:
    """Return the text of the first user message — a subagent's dispatch prompt."""
    for record in records:
        if record.get("type") != "user":
            continue
        content = (record.get("message") or {}).get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return "\n".join(
                str(c.get("text") or "")
                for c in content
                if isinstance(c, dict) and c.get("type") == "text"
            )
    return ""


def role_for_prompt(prompt: str) -> str:
    """Classify a subagent by its dispatch prompt; unmatched prompts are ``other``.

    Headings and the frontmatter `name:` in the leading window vote first; only
    a miss falls through to the whole prompt. A fix-cycle implementer quotes the
    judge's `mb-reviewer` / `CHANGES_REQUESTED` findings verbatim in its body,
    and that prose must not outrank the agent's own identity.
    """
    lead = prompt[:_IDENTITY_WINDOW].splitlines()
    identity = "\n".join(ln for ln in lead if _IDENTITY_LINE_RE.match(ln))
    for window in (identity, prompt[:8000]):
        for role, pattern in ROLE_MARKERS:
            if re.search(pattern, window, re.I):
                return role
    return "other"


def session_stats(path: Path) -> dict[str, Any]:
    """Aggregate one orchestrator (or subagent) transcript into flat counters."""
    stats: dict[str, Any] = {
        "session": path.stem,
        "turns": 0,
        "tool_calls": 0,
        "tasks": 0,
        "test_runs": 0,
        "output_tokens": 0,
        "cache_creation_tokens": 0,
        "cache_read_tokens": 0,
        "input_tokens": 0,
        "peak_context": 0,
        "compactions": 0,
    }
    start = end = None
    for record in iter_records(path):
        moment = _timestamp(record)
        if moment:
            start = start or moment
            end = moment
        if record.get("type") == "summary":
            stats["compactions"] += 1
            continue
        if record.get("type") != "assistant":
            continue
        stats["turns"] += 1
        usage = _usage(record)
        stats["output_tokens"] += usage["output_tokens"]
        stats["cache_creation_tokens"] += usage["cache_creation_input_tokens"]
        stats["cache_read_tokens"] += usage["cache_read_input_tokens"]
        stats["input_tokens"] += usage["input_tokens"]
        stats["peak_context"] = max(stats["peak_context"], _context_size(usage))
        for tool_use in _tool_uses(record):
            stats["tool_calls"] += 1
            if tool_use.get("name") in ("Task", "Agent"):
                stats["tasks"] += 1
            elif TEST_CMD_RE.search(_bash_command(tool_use)):
                stats["test_runs"] += 1
    stats["started_at"] = start.isoformat() if start else None
    stats["ended_at"] = end.isoformat() if end else None
    stats["duration_min"] = _minutes(start, end)
    return stats


def subagent_stats(path: Path) -> dict[str, Any]:
    """Per-subagent counters plus the role inferred from its dispatch prompt."""
    stats = session_stats(path)
    stats["role"] = role_for_prompt(_first_prompt(list(iter_records(path))))
    return stats


def item_segments(path: Path) -> list[dict[str, Any]]:
    """Orchestrator cost between ``mb-work-state.sh init`` and ``…checkbox.sh flip``.

    Usage accrues from the turn *after* the opening one, whose tokens paid for
    choosing the item rather than doing it; an item never flipped is dropped.
    """
    segments: list[dict[str, Any]] = []
    current: dict[str, Any] | None = None
    for record in iter_records(path):
        if record.get("type") != "assistant":
            continue
        moment = _timestamp(record)
        if current is not None:
            usage = _usage(record)
            current["output_tokens"] += usage["output_tokens"]
            current["cache_creation_tokens"] += usage["cache_creation_input_tokens"]
            current["turns"] += 1
        for tool_use in _tool_uses(record):
            if tool_use.get("name") in ("Task", "Agent"):
                if current is not None:
                    current["dispatches"] += 1
                continue
            command = _bash_command(tool_use)
            if not command:
                continue
            if current is None and ITEM_OPEN_RE.search(command):
                current = {
                    "session": path.stem,
                    "started_at": moment.isoformat() if moment else None,
                    "_start": moment,
                    "output_tokens": 0,
                    "cache_creation_tokens": 0,
                    "turns": 0,
                    "dispatches": 0,
                    "bash_calls": 0,
                    "test_runs": 0,
                }
            if current is None:
                continue
            current["bash_calls"] += 1
            if TEST_CMD_RE.search(command):
                current["test_runs"] += 1
            if ITEM_CLOSE_RE.search(command):
                current["ended_at"] = moment.isoformat() if moment else None
                current["duration_min"] = _minutes(current.pop("_start"), moment)
                segments.append(current)
                current = None
    return segments


_ROLE_AVG_FIELDS = (
    "turns", "tool_calls", "test_runs", "output_tokens", "peak_context", "duration_min",
)


def _aggregate_roles(subagents: list[dict[str, Any]]) -> dict[str, dict[str, float]]:
    buckets: dict[str, list[dict[str, Any]]] = {}
    for sub in subagents:
        buckets.setdefault(sub["role"], []).append(sub)
    roles: dict[str, dict[str, float]] = {}
    for role, rows in sorted(buckets.items()):
        n = len(rows)
        summary: dict[str, float] = {"n": n}
        for key in _ROLE_AVG_FIELDS:
            summary[f"avg_{key}"] = round(sum(r[key] for r in rows) / n, 2)
        roles[role] = summary
    return roles


def _newest_moment(path: Path) -> datetime | None:
    latest = None
    for record in iter_records(path):
        moment = _timestamp(record)
        if moment and (latest is None or moment > latest):
            latest = moment
    return latest


def build_report(
    project_dir: Path,
    *,
    since_days: int | None = None,
    now: datetime | None = None,
) -> dict[str, Any]:
    """Scan a transcript store into the report consumed by `/mb cost` and the gates.

    ``since_days`` drops sessions whose newest record predates the cutoff; ``now``
    is injectable so that cutoff is testable against fixed fixtures.
    """
    project_dir = Path(project_dir)
    now = now or datetime.now(UTC)
    cutoff = now.timestamp() - since_days * 86400 if since_days else None

    sessions: list[dict[str, Any]] = []
    subagents: list[dict[str, Any]] = []
    items: list[dict[str, Any]] = []
    for main in sorted(project_dir.glob("*.jsonl")):
        if cutoff is not None:
            newest = _newest_moment(main)
            if newest is None or newest.timestamp() < cutoff:
                continue
        stats = session_stats(main)
        subs = sorted((project_dir / main.stem / "subagents").glob("*.jsonl"))
        stats["subagents"] = len(subs)
        sessions.append(stats)
        subagents.extend(subagent_stats(sub) for sub in subs)
        items.extend(item_segments(main))

    return {
        "generated_at": now.isoformat(),
        "project": str(project_dir),
        "since_days": since_days,
        "sessions": sessions,
        "roles": _aggregate_roles(subagents),
        "items": items,
    }
