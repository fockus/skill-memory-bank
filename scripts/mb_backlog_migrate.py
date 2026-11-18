#!/usr/bin/env python3
"""Backlog migrator engine for mb-backlog-migrate.sh (design.md C4).

Usage: mb_backlog_migrate.py <backlog.md> <dry-run|apply> [--backup-dir DIR]

Plans (and, in ``apply``, performs) the legacy → machine migration:
  * status token table: TRIAGED|OPEN|PROPOSED|DEFERRED → TRIAGED, PLANNED →
    IN-PROGRESS, RESOLVED → DONE, DECLINED → WONTFIX (the block moves under
    ``## Out of scope``; no retroactive ``**Reason:**``). NEW and DONE stay. Only
    the token is rewritten — dates, hashes and other detail stay byte-identical.
  * ``[SPEC:<group>] <child-topic>`` titles → typed entries (Type/Group/Parent/
    Spec meta lines, prefix stripped).
  * Historical entries NEVER receive ``**Type:** IDEA`` (the grandfather rule).
A token outside the table and the C3 alphabet only warns (``unknown_legacy_state``).
The caller (the shell wrapper) holds the backlog lock; the write is atomic.
"""

import os
import re
import shutil
import sys

from mb_backlog_blocks import OUT, move_to_out_of_scope
from mb_backlog_state_engine import (
    STATES,
    line_cr,
    parse_backlog,
    read_text,
    rewrite_state,
    write_atomic,
)

TABLE = {
    "TRIAGED": "TRIAGED",
    "OPEN": "TRIAGED",
    "PROPOSED": "TRIAGED",
    "DEFERRED": "TRIAGED",
    "PLANNED": "IN-PROGRESS",
    "RESOLVED": "DONE",
    "DECLINED": "WONTFIX",
}
SPEC_RE = re.compile(r"^\[SPEC:([a-z0-9][a-z0-9-]*)\] ([a-z0-9][a-z0-9-]*)$")


def _header_title_swap(header, old_title, new_title):
    return header.replace(" — " + old_title + " [", " — " + new_title + " [", 1)


LOOSE_HEADING_RE = re.compile(r"^### I-\d")
# Last `[PRIO, <state field>…]` on a heading the strict grammar rejected (no created
# date, or text after the bracket). Group 2 is the first comma-free field.
LOOSE_RE = re.compile(r"^(### I-\d{3,} — .*\[(?:HIGH|MED|LOW),\s*)([^,\]]*)(.*)$")


def loose_pass(lines, strict_idx, actions, warnings):
    """Token rewrite for headings outside the strict grammar; never guesses a state.

    A state-less heading or a heading with no bracket is only reported. Rewrites
    keep every other byte; a loose DECLINED is not moved (its block extent is
    unknown), only reported in the action text.
    """
    missing, unparsed = [], []
    for i, ln in enumerate(lines):
        if i in strict_idx or not LOOSE_HEADING_RE.match(ln):
            continue
        entry_id = re.match(r"^### (I-\d+)", ln).group(1)
        m = LOOSE_RE.match(ln)
        if not m:
            unparsed.append(entry_id)
            continue
        field = m.group(2)
        token = field.split()[0] if field.split() else ""
        if not token or not token[0].isalpha():
            missing.append(entry_id)
            continue
        target = TABLE.get(token)
        if target is None and token not in STATES:
            warnings.append(f"unknown_legacy_state={token} item={entry_id}")
        elif target is not None and target != token:
            lines[i] = m.group(1) + field.replace(token, target, 1) + m.group(3)
            note = " (not moved: heading outside the strict grammar)" if target == "WONTFIX" else ""
            actions.append(f"{entry_id}: state {token} → {target}{note}")
    warnings.extend(f"missing_state ids={i}" for i in missing)
    warnings.extend(f"unparsed_heading ids={i}" for i in unparsed)


def merge_id_warnings(warnings):
    """Fold per-id `<code> ids=I-x` warnings into one `<code> ids=I-a,I-b` line each."""
    merged, out = {}, []
    for w in warnings:
        code, sep, ids = w.partition(" ids=")
        if sep:
            merged.setdefault(code, []).append(ids)
        else:
            out.append(w)
    return out + [f"{code} ids={','.join(sorted(v))}" for code, v in sorted(merged.items())]


def plan_edits(lines, entries, actions, warnings):
    """Edit tokens/titles/meta in place (reverse order keeps indices valid)."""
    cr = line_cr(lines)
    to_move = []
    for e in reversed(entries):
        h = e["header_idx"]
        token = e["state"]
        target = TABLE.get(token)
        if target is not None and target != token:
            lines[h] = rewrite_state(lines[h], target)
            actions.append(f"{e['id']}: state {token} → {target}")
            if target == "WONTFIX" and e["section"] != OUT:
                to_move.append(e["id"])
        elif target is None and token not in STATES:
            if token[:1].isalpha():
                warnings.append(f"unknown_legacy_state={token} item={e['id']}")
            else:
                warnings.append(f"missing_state ids={e['id']}")
        m = SPEC_RE.match(e["title"])
        if m and e["type"] is None:
            lines[h] = _header_title_swap(lines[h], e["title"], m.group(2))
            lines[h + 1 : h + 1] = [
                f"**Type:** SPEC{cr}",
                f"**Group:** {m.group(1)}{cr}",
                f"**Parent:** none{cr}",
                f"**Spec:** {m.group(2)}{cr}",
            ]
            actions.append(f"{e['id']}: [SPEC:{m.group(1)}] prefix → typed SPEC entry")
    return to_move


def move_declined(lines, ids, actions):
    _, entries = parse_backlog("\n".join(lines))
    for entry_id in move_to_out_of_scope(lines, entries, ids, line_cr(lines)):
        actions.append(f"{entry_id}: moved to ## {OUT}")


def migrate(text):
    lines, entries = parse_backlog(text)
    actions, warnings = [], []
    loose_pass(lines, {e["header_idx"] for e in entries}, actions, warnings)
    ids = plan_edits(lines, entries, actions, warnings)
    if ids:
        move_declined(lines, set(ids), actions)
    return "\n".join(lines), actions, merge_id_warnings(warnings)


def main(argv):
    if len(argv) < 2 or argv[1] not in ("dry-run", "apply"):
        sys.stderr.write("usage: mb_backlog_migrate.py <backlog.md> <dry-run|apply> [--backup-dir DIR]\n")
        return 2
    path, mode = argv[0], argv[1]
    backup_dir = argv[3] if len(argv) >= 4 and argv[2] == "--backup-dir" else None
    text = read_text(path)
    new_text, actions, warnings = migrate(text)
    print(f"mode={mode}")
    print(f"actions_pending={len(actions)}")
    for a in sorted(actions):
        print(f"  - {a}")
    for w in warnings:
        sys.stderr.write(f"[warn] {w}\n")
    if mode == "apply" and actions:
        if backup_dir:
            os.makedirs(backup_dir, exist_ok=True)
            shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))
            print(f"[apply] backup → {backup_dir}")
        write_atomic(path, new_text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
