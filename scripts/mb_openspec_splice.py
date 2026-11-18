#!/usr/bin/env python3
"""Apply a sync plan to the bank triple unit by unit (AGR-105, Stage 9).

Only the spans of units the plan takes from OpenSpec are replaced, inserted or
deleted; every other line of the bank files — bank-added design sections, task
prose, Covers/Role, units the bank is ahead on — keeps its bytes. Pure: the
caller writes the returned texts.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
    from mb_openspec_spans import (
        COVERS_PREFIX,
        REQ_HEADING_PREFIX,
        Span,
        design_spans,
        req_id_of,
        requirement_spans,
        shared_scenarios,
        task_spans,
        trim_end,
    )
except ModuleNotFoundError:  # pragma: no cover - import-path fallback
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from mb_openspec_spans import (
        COVERS_PREFIX,
        REQ_HEADING_PREFIX,
        Span,
        design_spans,
        req_id_of,
        requirement_spans,
        shared_scenarios,
        task_spans,
        trim_end,
    )

Edit = tuple[int, int, list[str]]
_HEADING_NO_RE = re.compile(r"^### Requirement \d+: ")
_SCENARIO_RE = re.compile(r"^<!-- (/?)mb-scenario:\d+ -->$")
_MARK_RE = re.compile(r"^- \[[ xX]\] ")


def apply_edits(lines: list[str], edits: list[Edit]) -> list[str]:
    """Apply non-overlapping line edits; inserts at one position keep their order and
    land before a replace that starts there."""
    out, merged = list(lines), []
    inserts: dict[int, list[str]] = {}
    for start, end, new in edits:
        if start == end:
            inserts.setdefault(start, []).extend(new)
        else:
            merged.append((start, end, new))
    merged += [(pos, pos, block) for pos, block in inserts.items()]
    for start, end, new in sorted(merged, key=lambda e: (e[0], e[1]), reverse=True):
        out[start:end] = new
    return out


def _join(lines: list[str]) -> str:
    return "\n".join(lines).rstrip("\n") + "\n"


def _deletion(lines: list[str], start: int, end: int) -> Edit:
    while end < len(lines) and not lines[end].strip():
        end += 1
    return (start, end, [])


def _anchor_position(order: list[str], key: str, bank: dict[str, Span], gone: set[str]):
    """(index, after?) next to the closest rendered neighbour the bank still has."""
    at = order.index(key)
    for prev in reversed(order[:at]):
        if prev in bank and prev not in gone:
            return bank[prev].end, True
    for nxt in order[at + 1 :]:
        if nxt in bank and nxt not in gone:
            span = bank[nxt]
            return (span.head if span.head >= 0 else span.start), False
    return None, True


def _renumber(lines: list[str], headings: bool) -> list[str]:
    out, req_no, scenario_no = [], 0, 0
    for line in lines:
        if headings and _HEADING_NO_RE.match(line):
            req_no += 1
            line = _HEADING_NO_RE.sub(f"{REQ_HEADING_PREFIX}{req_no}: ", line)
        m = _SCENARIO_RE.match(line)
        if m:
            scenario_no += 0 if m.group(1) else 1
            line = f"<!-- {m.group(1)}mb-scenario:{scenario_no} -->"
        out.append(line)
    return out


def splice_requirements(bank_md: str, rendered_md: str, take: list[str], renamed_from: dict) -> str:
    keys = [k for k in take if k.startswith("req:")]
    if not keys:
        return bank_md
    lines, rl = bank_md.splitlines(), rendered_md.splitlines()
    bs, rs = requirement_spans(lines), requirement_spans(rl)
    gone = {k for k in keys if k in bs and k not in rs}
    in_place = {
        renamed_from[k]: k for k in keys if k in rs and k not in bs and renamed_from.get(k) in gone
    }
    owners: dict[int, int] = {}
    for span in bs.values():
        owners[span.head] = owners.get(span.head, 0) + 1
    edits: list[Edit] = []
    inserted = False
    for key in keys:
        if key in bs and key in rs:
            edits.append((bs[key].start, bs[key].end, rl[rs[key].start : rs[key].end]))
        elif key in in_place:
            span, new = bs[key], rs[in_place[key]]
            edits.append((span.start, span.end, rl[new.start : new.end]))
            if span.head >= 0 and owners[span.head] == 1 and new.head >= 0:
                edits.append((span.head, span.head + 1, [rl[new.head]]))
        elif key in gone:
            span = bs[key]
            owned = span.head >= 0 and owners[span.head] == 1
            edits.append(_deletion(lines, span.head if owned else span.start, span.end))
        elif key in rs and key not in in_place.values():
            new = rs[key]
            block = ([rl[new.head], ""] if new.head >= 0 else []) + rl[new.start : new.end]
            pos, after = _anchor_position(list(rs), key, bs, gone)
            pos = len(lines) if pos is None else pos
            edits.append((pos, pos, ["", *block] if after else [*block, ""]))
            inserted = True
    taken_ids = {rid for k in keys if k in bs and (rid := req_id_of(bs[k]))}
    edits += _release_shared(lines, shared_scenarios(lines, bs), taken_ids)
    structural = bool(gone or inserted or in_place)
    return _join(_renumber(apply_edits(lines, edits), headings=structural))


def _release_shared(lines: list[str], shared, taken_ids: set[str]) -> list[Edit]:
    """A requirement taken from OpenSpec brings its scenarios inline: drop its REQ-ID
    from shared blocks, and drop a block that then covers nothing."""
    edits: list[Edit] = []
    for start, end, covers in shared:
        if not taken_ids & set(covers):
            continue
        left = [rid for rid in covers if rid not in taken_ids]
        if not left:
            edits.append(_deletion(lines, start, end))
            continue
        at = next(i for i in range(start, end) if lines[i].startswith(COVERS_PREFIX))
        edits.append((at, at + 1, [f"{COVERS_PREFIX} {', '.join(left)}"]))
    return edits


def splice_design(bank_md: str, rendered_md: str, take: list[str]) -> str:
    keys = [k for k in take if k.startswith(("proposal:", "removed:")) or k == "design"]
    if not keys:
        return bank_md
    lines, rl = bank_md.splitlines(), rendered_md.splitlines()
    bs, rs = design_spans(lines), design_spans(rl)
    edits: list[Edit] = []
    for key in keys:
        section = not key.startswith("removed:")
        if key in bs and key in rs:
            new = rl[rs[key].start : rs[key].end]
            start = bs[key].head + 1 if section else bs[key].start
            edits.append((start, bs[key].end, ["", *new] if section else new))
        elif key in bs:
            span = bs[key]
            edits.append(_deletion(lines, span.head if section else span.start, span.end))
        elif key in rs:
            add = rs[key]
            body = rl[add.start : add.end]
            block = [rl[add.head], "", *body] if section else body
            edits.append(_design_insert(lines, bs, key, block, section))
    return _join(apply_edits(lines, edits))


def _design_insert(
    lines: list[str], bs: dict[str, Span], key: str, block: list[str], section: bool
) -> Edit:
    removed_head = next((i for i, ln in enumerate(lines) if ln.strip() == "## Removed scope"), -1)
    if section:
        pos = removed_head if removed_head >= 0 else len(lines)
        return (pos, pos, [*block, ""] if removed_head >= 0 else ["", *block])
    if removed_head < 0:
        return (len(lines), len(lines), ["", "## Removed scope", "", *block])
    entries = [s.end for k, s in bs.items() if k.startswith("removed:")]
    pos = max(entries) if entries else trim_end(lines, removed_head, removed_head + 1)
    return (pos, pos, ["", *block])


def splice_tasks(
    bank_md: str, rendered_md: str, take: list[str], checks: dict[str, bool]
) -> tuple[str, list[str]]:
    """Returns ``(tasks_md, orphan_lines)``; a task or group OpenSpec dropped is an orphan."""
    lines, rl = bank_md.splitlines(), rendered_md.splitlines()
    bs, rs = task_spans(lines), task_spans(rl)
    edits: list[Edit] = []
    orphans: list[str] = []
    dropped = {k[6:] for k in take if k.startswith("group:") and k in bs and k not in rs}
    for key in [k for k in take if k.startswith("group:")]:
        if key in bs and key in rs:
            edits.append((bs[key].head, bs[key].head + 1, [rl[rs[key].head]]))
        elif key in bs:
            span = bs[key]
            orphans += [ln for ln in lines[span.head : span.end] if ln.strip()]
            edits.append(_deletion(lines, span.start, span.end))
        elif key in rs:
            groups = [s.end for k, s in bs.items() if k.startswith("group:")]
            pos = max(groups) if groups else len(lines)
            edits.append((pos, pos, ["", *rl[rs[key].start : rs[key].end]]))
    for key in sorted(set(checks) | {k for k in take if k.startswith("task:")}):
        item = bs.get(key)
        if item is not None and item.group in dropped:
            continue
        if item is not None and key in rs and key in take:
            edits.append(
                (item.start, item.end, [_item_line(rs[key], checks.get(key, item.checked))])
            )
        elif item is not None and key in take:
            orphans.append(lines[item.start])
            edits.append((item.start, item.end, []))
        elif item is not None:
            edits.append(
                (item.start, item.end, [_MARK_RE.sub(_mark(checks[key]), lines[item.start])])
            )
        elif key in rs and f"group:{rs[key].group}" in bs:
            group = rs[key].group
            items = [s.end for s in bs.values() if s.group == group]
            pos = max(items) if items else bs[f"group:{group}"].end
            edits.append((pos, pos, [rl[rs[key].start]]))
    return _join(apply_edits(lines, edits)), orphans


def _mark(checked: bool | None) -> str:
    return "- [x] " if checked else "- [ ] "


def _item_line(rendered: Span, checked: bool | None) -> str:
    if rendered.checked is None:
        return f"- {rendered.body[0]}"
    return f"{_mark(rendered.checked if checked is None else checked)}{rendered.body[0]}"
