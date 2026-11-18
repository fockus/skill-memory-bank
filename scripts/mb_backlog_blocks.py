#!/usr/bin/env python3
"""Move whole backlog entry blocks between ``##`` sections (design.md C3/C4).

Shared by ``mb_backlog_state_engine.py`` (WONTFIX → ``## Out of scope``) and
``mb_backlog_migrate.py`` (DECLINED → WONTFIX). Operates on a list of lines
(each keeps its own CR) and on parsed entries; imports nothing from the engine so
the engine can import it without a cycle.
"""

import re

SECTION_RE = re.compile(r"^## (.+?)\s*$")
OUT = "Out of scope"


def section_bounds(lines, name):
    """(start, end) line indexes of ``## <name>``; (None, None) when absent."""
    start = None
    for i, ln in enumerate(lines):
        sm = SECTION_RE.match(ln)
        if sm and not ln.startswith("### "):
            if start is not None:
                return start, i
            if sm.group(1).strip() == name:
                start = i
    return (start, len(lines)) if start is not None else (None, None)


def move_to_out_of_scope(lines, entries, ids, cr=""):
    """Cut the blocks of ``ids`` and append them, in numeric order, to ``## Out of scope``.

    The section is created after ``## Ideas`` (or at EOF) when missing. Returns the
    ids moved. Block bytes are preserved; only separating blank lines are managed.
    """
    blocks = []
    for e in sorted(entries, key=lambda x: x["header_idx"], reverse=True):
        if e["id"] in ids:
            blocks.append((e["num"], lines[e["header_idx"] : e["end_idx"]], e["id"]))
            del lines[e["header_idx"] : e["end_idx"]]
    blocks.sort(key=lambda b: b[0])
    flat = []
    for _, blk, _entry_id in blocks:
        while blk and blk[-1].strip() == "":
            blk.pop()
        flat.extend(([cr] if flat else []) + blk)
    if not flat:
        return []
    start, end = section_bounds(lines, OUT)
    if start is not None:
        at, prefix = end, [cr]
    else:
        ideas_start, ideas_end = section_bounds(lines, "Ideas")
        at = ideas_end if ideas_start is not None else len(lines)
        prefix = [cr, f"## {OUT}{cr}", cr]
    while at > 0 and lines[at - 1].strip() == "":
        at -= 1
    lines[at:at] = prefix + flat
    return [b[2] for b in blocks]
