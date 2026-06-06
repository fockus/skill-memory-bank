#!/usr/bin/env python3
"""Parse plan stages and spec tasks into a unified WorkItem model.

Public API
----------
parse_work_items(path: pathlib.Path) -> list[WorkItem]
    Read a Markdown file that contains ``<!-- mb-stage:N -->`` or
    ``<!-- mb-task:N -->`` comment markers and return one :class:`WorkItem`
    per marker block.

CLI usage
---------
    python3 scripts/mb_work_items.py <path>

Emits one JSON object per line (JSON Lines) to stdout, one per WorkItem.
Keys are the dataclass field names; ``covers`` and ``dod_lines`` are lists.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from dataclasses import asdict, dataclass
from typing import Literal

# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

_STAGE_RE = re.compile(r"<!--\s*mb-stage:(\d+)\s*-->")
_TASK_RE = re.compile(r"<!--\s*mb-task:(\d+)\s*-->")
_DATE_PREFIX_RE = re.compile(r"^\d{4}-\d{2}-\d{2}_")

_COVERS_RE = re.compile(r"^\*\*covers:\*\*\s*(.+)$", re.IGNORECASE)
_ROLE_RE = re.compile(r"^\*\*Role:\*\*\s*(\S+)", re.IGNORECASE)
# Accept a qualifier after DoD (the global rules call for "DoD (SMART)"):
# `**DoD:**`, `**DoD (SMART)**`, `**DoD**` all open the section.
_DOD_HEADING_RE = re.compile(r"^\*\*DoD\b", re.IGNORECASE)
_CHECKBOX_RE = re.compile(r"^- \[[ xX]\] .+")
_CHECKED_RE = re.compile(r"^- \[[xX]\] ")

_QA_SIGNALS = re.compile(r"\bpytest\b|\bunittest\b")
_IOS_SIGNALS = re.compile(r"\bswift\b|\bxcode\b|\biostest\b|\bxctest\b", re.IGNORECASE)
_ANDROID_SIGNALS = re.compile(r"\bandroid\b|\bkotlin\b|\bcompose\b|\bespresso\b", re.IGNORECASE)
_FRONTEND_SIGNALS = re.compile(r"\breact\b|\bvue\b|\bangular\b|\bhtml\b|\bcss\b", re.IGNORECASE)
_BACKEND_SIGNALS = re.compile(r"\bdjango\b|\bfastapi\b|\bflask\b|\bspring\b|\bsql\b", re.IGNORECASE)
_DEVOPS_SIGNALS = re.compile(r"\bdocker\b|\bkubernetes\b|\bterraform\b|\bci/cd\b|\bdeploy\b", re.IGNORECASE)
_ARCHITECT_SIGNALS = re.compile(r"\badr\b|\barchitecture\b|\bdiagram\b|\berdoc\b", re.IGNORECASE)
_ANALYST_SIGNALS = re.compile(r"\bears\b|\brequirements?\b|\bspec\b|\btraceability\b", re.IGNORECASE)


@dataclass(frozen=True)
class WorkItem:
    """A single parsed work unit from a plan stage or spec task file."""

    source: Literal["plan", "spec"]
    topic: str
    item_no: int
    kind: Literal["stage", "task"]
    heading: str
    body: str
    role: str
    agent: str
    status: Literal["pending", "in-progress", "done"]
    covers: tuple[str, ...]
    dod_lines: tuple[str, ...]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _derive_topic(path: pathlib.Path, source: Literal["plan", "spec"]) -> str:
    """Return topic string for the given file path and source type."""
    if source == "plan":
        stem = path.stem
        return _DATE_PREFIX_RE.sub("", stem)
    else:
        return path.parent.name


def _parse_covers(body: str) -> tuple[str, ...]:
    """Extract REQ IDs from ``**Covers:** ...`` line(s) in body."""
    for line in body.splitlines():
        m = _COVERS_RE.match(line.strip())
        if m:
            raw = m.group(1)
            ids = [v.strip().upper() for v in raw.split(",") if v.strip()]
            return tuple(ids)
    return ()


def _parse_explicit_role(body: str) -> str | None:
    """Return explicit role from ``**Role:** <name>`` line, or None."""
    for line in body.splitlines():
        m = _ROLE_RE.match(line.strip())
        if m:
            return m.group(1).strip()
    return None


def _autodetect_role(body: str) -> str:
    """Heuristically detect role from keywords in body text."""
    if _QA_SIGNALS.search(body):
        return "qa"
    if _IOS_SIGNALS.search(body):
        return "ios"
    if _ANDROID_SIGNALS.search(body):
        return "android"
    if _FRONTEND_SIGNALS.search(body):
        return "frontend"
    if _BACKEND_SIGNALS.search(body):
        return "backend"
    if _DEVOPS_SIGNALS.search(body):
        return "devops"
    if _ARCHITECT_SIGNALS.search(body):
        return "architect"
    if _ANALYST_SIGNALS.search(body):
        return "analyst"
    return "developer"


def _parse_dod(body: str) -> tuple[tuple[str, ...], Literal["pending", "in-progress", "done"]]:
    """Parse DoD checkbox lines and return (dod_lines, status)."""
    lines = body.splitlines()
    in_dod = False
    checkbox_lines: list[str] = []

    for line in lines:
        if _DOD_HEADING_RE.match(line.strip()):
            in_dod = True
            continue
        if in_dod:
            stripped = line.strip()
            # Stop when we hit a new bold-heading section (** prefix) that isn't a checkbox
            if stripped.startswith("**") and not _CHECKBOX_RE.match(stripped):
                break
            if _CHECKBOX_RE.match(stripped):
                checkbox_lines.append(stripped)

    if not checkbox_lines:
        return (), "pending"

    checked_count = sum(1 for ln in checkbox_lines if _CHECKED_RE.match(ln))
    total = len(checkbox_lines)

    if checked_count == total:
        status: Literal["pending", "in-progress", "done"] = "done"
    elif checked_count > 0:
        status = "in-progress"
    else:
        status = "pending"

    return tuple(checkbox_lines), status


def _extract_heading(block_text: str) -> str:
    """Return the first non-empty line of the block (the heading line)."""
    for line in block_text.splitlines():
        stripped = line.strip()
        if stripped:
            # Strip leading '#' characters and whitespace for the heading value
            return stripped.lstrip("#").strip()
    return ""


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def parse_work_items(path: pathlib.Path) -> list[WorkItem]:
    """Parse a Markdown file and return one :class:`WorkItem` per marker block.

    Parameters
    ----------
    path:
        Absolute or relative path to a ``.md`` file. The file is read as
        UTF-8. An empty file or a file with no ``<!-- mb-stage:N -->`` /
        ``<!-- mb-task:N -->`` markers returns an empty list.

    Raises
    ------
    ValueError
        If the file contains both ``<!-- mb-stage:N -->`` and
        ``<!-- mb-task:N -->`` markers (mixed format).
    """
    text = path.read_text(encoding="utf-8")

    has_stage = bool(_STAGE_RE.search(text))
    has_task = bool(_TASK_RE.search(text))

    if has_stage and has_task:
        raise ValueError(
            f"mixed marker types in {path}: file contains both "
            "<!-- mb-stage:N --> and <!-- mb-task:N --> markers"
        )

    if not has_stage and not has_task:
        return []

    source: Literal["plan", "spec"]
    kind: Literal["stage", "task"]
    marker_re: re.Pattern[str]

    if has_stage:
        source = "plan"
        kind = "stage"
        marker_re = _STAGE_RE
    else:
        source = "spec"
        kind = "task"
        marker_re = _TASK_RE

    topic = _derive_topic(path, source)

    # Split on markers, keeping the marker text so we can capture item_no
    parts = marker_re.split(text)
    # parts = [pre-text, no1, block1, no2, block2, ...]
    # marker_re has one capture group → split interleaves numbers and blocks

    items: list[WorkItem] = []
    # parts[0] is preamble before first marker; skip it
    # parts[1::2] are the captured group (item numbers)
    # parts[2::2] are the content blocks following each marker
    pair_count = (len(parts) - 1) // 2
    for i in range(pair_count):
        item_no = int(parts[1 + i * 2])
        block = parts[2 + i * 2]

        heading = _extract_heading(block)
        body = block.strip()

        covers = _parse_covers(body)
        explicit_role = _parse_explicit_role(body)
        role = explicit_role if explicit_role is not None else _autodetect_role(body)
        agent = f"mb-{role}"
        dod_lines, status = _parse_dod(body)

        items.append(
            WorkItem(
                source=source,
                topic=topic,
                item_no=item_no,
                kind=kind,
                heading=heading,
                body=body,
                role=role,
                agent=agent,
                status=status,
                covers=covers,
                dod_lines=dod_lines,
            )
        )

    return items


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def _work_item_to_dict(item: WorkItem) -> dict:
    """Convert WorkItem to a JSON-serialisable dict (tuples → lists)."""
    d = asdict(item)
    d["covers"] = list(d["covers"])
    d["dod_lines"] = list(d["dod_lines"])
    return d


def main() -> None:
    """CLI: print one JSON object per line to stdout."""
    if len(sys.argv) != 2:
        print("Usage: mb_work_items.py <path>", file=sys.stderr)
        sys.exit(1)

    path = pathlib.Path(sys.argv[1])
    if not path.exists():
        print(f"Error: file not found: {path}", file=sys.stderr)
        sys.exit(1)

    try:
        items = parse_work_items(path)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)

    for item in items:
        print(json.dumps(_work_item_to_dict(item), ensure_ascii=False))


if __name__ == "__main__":
    main()
