#!/usr/bin/env python3
"""Task rendering and task-state merging for the OpenSpec adapter.

``build_tasks`` renders an OpenSpec change's task groups as ``<!-- mb-task:N -->``
blocks; ``merge_task_state`` keeps `/mb work` check-state and the bank-only
``**Covers:**``/``**Role:**`` lines when a fresh render replaces a prior one.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    from mb_openspec_model import OSChange
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_model import OSChange


def merge_task_state(new_tasks_md: str, prior_tasks_md: str) -> tuple[str, list[str]]:
    """Preserve `/mb work` check-state and bank-only fields across re-import.

    Checkbox items are matched between ``prior_tasks_md`` (the previously
    written tasks.md, possibly hand-edited by ``/mb work``) and
    ``new_tasks_md`` (freshly regenerated from the current OpenSpec source)
    by their ``N.M`` task id when the text starts with one, else by
    *normalized task text* (trim + collapse whitespace) — never by position
    (D-06, AGR-105). Rewording a task that keeps its id keeps its state.

    - A matched prior task keeps its check-state.
    - A genuinely new task always arrives UNCHECKED, regardless of the
      OpenSpec side's own checkbox (D-05).
    - A prior task with no match is returned in ``orphaned_task_lines`` for
      the caller to append to ``backlog.md`` (REQ-017), never dropped.
    - ``**Covers:**``/``**Role:**`` are bank-only after the first import: a
      group that already has them keeps the prior lines (AGR-105).

    Returns ``(merged_tasks_md, orphaned_task_lines)``.
    """
    prior_checked: dict[str, bool] = {}
    prior_raw: dict[str, str] = {}
    prior_by_text: dict[str, str] = {}
    for line in prior_tasks_md.splitlines():
        m = _MB_CHECKBOX_RE.match(line)
        if not m:
            continue
        norm = _normalize_task_text(m.group("text"))
        tid = task_id(norm)
        key = f"id:{tid}" if tid else f"text:{norm}"
        prior_checked[key] = m.group("mark").lower() == "x"
        prior_raw[key] = line
        prior_by_text[norm] = key
    prior_fields = _bank_only_fields(prior_tasks_md)

    matched: set[str] = set()
    merged_lines: list[str] = []
    group: str | None = None
    for line in new_tasks_md.splitlines():
        gm = _GROUP_MARKER_RE.match(line)
        if gm:
            group = gm.group(1)
        fm = _BANK_ONLY_FIELD_RE.match(line)
        if fm and (group, fm.group(1)) in prior_fields:
            merged_lines.append(prior_fields[(group, fm.group(1))])
            continue
        m = _MB_CHECKBOX_RE.match(line)
        if not m:
            merged_lines.append(line)
            continue
        norm = _normalize_task_text(m.group("text"))
        tid = task_id(norm)
        hit = f"id:{tid}" if tid and f"id:{tid}" in prior_checked else prior_by_text.get(norm)
        if hit is not None:
            matched.add(hit)
            mark = "x" if prior_checked[hit] else " "
        else:
            mark = " "  # a genuinely new task always arrives unchecked (D-05)
        merged_lines.append(f"- [{mark}] {m.group('text')}")

    orphaned_task_lines = [prior_raw[key] for key in prior_checked if key not in matched]
    merged_md = "\n".join(merged_lines).rstrip() + "\n"
    return merged_md, orphaned_task_lines


_MB_CHECKBOX_RE = re.compile(r"^-\s\[(?P<mark>[ xX])\]\s+(?P<text>.+)$")
_TASK_ID_RE = re.compile(r"^(\d+(?:\.\d+)+)(?=\s|$)")
_GROUP_MARKER_RE = re.compile(r"^<!-- mb-task:(\S+) -->$")
_BANK_ONLY_FIELD_RE = re.compile(r"^\*\*(Covers|Role):\*\*")


def task_id(text: str) -> str | None:
    """The ``N.M`` id an OpenSpec task item starts with, else ``None``."""
    m = _TASK_ID_RE.match(text.strip())
    return m.group(1) if m else None


def _bank_only_fields(tasks_md: str) -> dict[tuple[str | None, str], str]:
    """``(group, "Covers"|"Role") -> line`` — the first of each per task group."""
    out: dict[tuple[str | None, str], str] = {}
    group: str | None = None
    for line in tasks_md.splitlines():
        gm = _GROUP_MARKER_RE.match(line)
        if gm:
            group = gm.group(1)
            continue
        fm = _BANK_ONLY_FIELD_RE.match(line)
        if fm and group is not None:
            out.setdefault((group, fm.group(1)), line)
    return out


def _normalize_task_text(text: str) -> str:
    return " ".join(text.split())


def build_tasks(ch: OSChange) -> str:
    lines = [
        f"# Tasks: {ch.change_id}",
        "",
        f"> Imported from OpenSpec change `{ch.change_id}` tasks.md.",
        "",
    ]
    if not ch.task_groups:
        lines.append("_(no tasks.md found in the source change)_")
        return "\n".join(lines).rstrip() + "\n"

    for group in ch.task_groups:
        lines.append(f"<!-- mb-task:{group.number} -->")
        lines.append(f"## Task {group.number}: {group.title}")
        lines.append("")
        lines.append("**Covers:** N/A")
        lines.append("**Role:** backend")
        lines.append("")
        for checked, item_text in group.items:
            if checked is None:
                lines.append(f"- {item_text}")
            else:
                mark = "x" if checked else " "
                lines.append(f"- [{mark}] {item_text}")
        lines.append("")

    return "\n".join(lines).rstrip() + "\n"
