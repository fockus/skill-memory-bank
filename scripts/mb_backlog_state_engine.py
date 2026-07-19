#!/usr/bin/env python3
"""Backlog parser + state engine for the S4 backlog scripts (design.md C3).

Single authoritative implementation of the entry grammar and the
``NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX`` state
machine, extracted OUT of ``scripts/_lib.sh`` so the shared library keeps only a
thin lock/transition API (SRP + file-size gate). Stdlib-only, no third-party
imports, so every backlog writer can reuse it without a dependency.

Two callers, one file:
  * ``scripts/_lib.sh::mb_backlog_transition_locked`` →
        ``mb_backlog_state_engine.py transition-locked <backlog> <I-NNN> <STATE>
          [--reason T] [--plan R]``   (caller already holds the backlog lock)
  * ``scripts/mb-backlog-state.sh::run_engine`` →
        ``mb_backlog_state_engine.py getstate|list|annotate <backlog> ...``

Every command keeps stdout for machine output only; diagnostics go to stderr and
exit codes are: 0 success, 1 domain reject, 2 usage / not-found.
"""

import json
import re
import sys

import mb_fs_atomic
from mb_backlog_validate import validate_brief, validate_single_line

STATES = ["NEW", "NEEDS-INFO", "TRIAGED", "READY", "IN-PROGRESS", "DONE", "WONTFIX"]
EDGES = {
    "NEW": ["NEEDS-INFO"],
    "NEEDS-INFO": ["TRIAGED"],
    "TRIAGED": ["NEEDS-INFO", "READY"],
    "READY": ["IN-PROGRESS"],
    "IN-PROGRESS": ["DONE", "WONTFIX"],
    "DONE": [],
    "WONTFIX": [],
}
V2_META = ("**Type:**", "**Parent:**", "**Brief:**", "**Reason:**")

# `I-\d{3,}` not `I-\d+`: the documented grammar is I-NNN, and the lax form let
# a malformed `### I-1 —` header be parsed and MUTATED (R4-006). Three-or-more
# (rather than exactly three) keeps the id space open past I-999 instead of
# turning a future 4-digit backlog into a file full of unparsable entries.
HEADER_RE = re.compile(r"^### (I-\d{3,}) — (.*) \[([^,\]]+),\s*([^,\]]+),\s*([^\]]+)\]\s*$")
# Group 4 captures the line's own trailing whitespace so a CRLF line keeps its
# CR when only the state token is rewritten (R4-005).
HEADER_STATE_RE = re.compile(r"^(### I-\d+ — .*\[[^,\]]+,\s*)([A-Za-z][A-Za-z0-9_-]*)(.*\])(\s*)$")
SECTION_RE = re.compile(r"^## (.+?)\s*$")


def die(code, msg):
    if msg:
        sys.stderr.write(msg + "\n")
    sys.exit(code)


def json_str(s):
    return json.dumps(s if s is not None else "", ensure_ascii=False, separators=(",", ":"))


def read_text(path):
    """Read the backlog WITHOUT universal-newline translation (R4-005).

    A plain ``open()`` rewrites every CRLF to LF in memory, and since the file
    is re-joined with ``\\n`` on write, a single state transition silently
    rewrote the line ending of every hand-written line in the file. With
    ``newline=""`` each line keeps its own CR, ``split("\\n")`` leaves it at the
    end of the line, and ``"\\n".join`` puts the file back byte-for-byte apart
    from the token we meant to change.
    """
    try:
        with open(path, encoding="utf-8", newline="") as fh:
            return fh.read()
    except OSError:
        die(2, f"cannot read backlog: {path}")


def line_cr(lines):
    """The CR prefix new lines need to match the file's existing endings."""
    for ln in lines:
        if ln.endswith("\r"):
            return "\r"
    return ""


def write_atomic(path, text):
    """Publish the backlog through the ONE shared atomic primitive.

    The local copy this replaced did not carry the file mode across
    ``os.replace``, so mkstemp's private 0600 landed on the backlog and a shared
    bank silently became owner-only after a single transition (finding 5). The
    shared helper also fsyncs before the rename.
    """
    mb_fs_atomic.atomic_write(path, text)


def meta_value(body_lines, key):
    pat = re.compile(r"^\*\*" + re.escape(key) + r":\*\*\s*(.*)$")
    for ln in body_lines:
        m = pat.match(ln)
        if m:
            return m.group(1).strip()
    return None


def parse_backlog(text):
    lines = text.split("\n")
    headers = []
    section = None
    for idx, ln in enumerate(lines):
        hm = HEADER_RE.match(ln)
        if hm:
            headers.append((idx, hm, section))
            continue
        sm = SECTION_RE.match(ln)
        if sm and not ln.startswith("### "):
            section = sm.group(1).strip()
    entries = []
    for i, (idx, hm, sect) in enumerate(headers):
        end = headers[i + 1][0] if i + 1 < len(headers) else len(lines)
        for j in range(idx + 1, end):
            if SECTION_RE.match(lines[j]) and not lines[j].startswith("### "):
                end = j
                break
        body_lines = lines[idx + 1 : end]
        state_field = hm.group(4).strip()
        state = state_field.split()[0] if state_field else ""
        body_join = "\n".join(body_lines)
        entries.append(
            {
                "id": hm.group(1),
                "num": int(hm.group(1)[2:]),
                "title": hm.group(2).strip(),
                "prio": hm.group(3).strip(),
                "state_field": state_field,
                "state": state,
                "date": hm.group(5).strip(),
                "section": sect,
                "header_idx": idx,
                "end_idx": end,
                "body_lines": body_lines,
                "parent": meta_value(body_lines, "Parent"),
                "brief": meta_value(body_lines, "Brief"),
                "reason": meta_value(body_lines, "Reason"),
                "type": meta_value(body_lines, "Type"),
                "spec": meta_value(body_lines, "Spec"),
                "group": meta_value(body_lines, "Group"),
                "has_v2": any(v in body_join for v in V2_META),
            }
        )
    assert_unique_ids(entries)
    return lines, entries


def assert_unique_ids(entries):
    """Reject a backlog that carries the same I-NNN more than once (exit 2).

    ``find_entry`` returns the FIRST match. With two ``I-001`` headers a
    transition reported success, rewrote only the first entry and left the
    second on its old state — an internally contradictory database that every
    later read would resolve differently depending on order (finding 8).

    The whole file is refused, not just the duplicated id: with an ambiguous
    index we cannot trust ANY lookup, and silently serving the other ids would
    let the inconsistency persist unnoticed. Detection lives in the single
    parse entry point so every subcommand inherits the gate.
    """
    seen = set()
    duplicates = []
    for e in entries:
        if e["id"] in seen and e["id"] not in duplicates:
            duplicates.append(e["id"])
        seen.add(e["id"])
    if duplicates:
        die(
            2,
            "code=duplicate_id ids="
            + ",".join(duplicates)
            + " detail=each I-NNN must appear exactly once in backlog.md",
        )


def find_entry(entries, entry_id):
    for e in entries:
        if e["id"] == entry_id:
            return e
    return None


def rewrite_state(header_line, new_state):
    m = HEADER_STATE_RE.match(header_line)
    if not m:
        return header_line
    # group(4) is the line's own trailing whitespace -- the CR of a CRLF line
    # lives there, and dropping it rewrote the ending of every touched header.
    return m.group(1) + new_state + m.group(3) + m.group(4)


def set_meta(seg, key, value, cr=""):
    # Lines carry their own CR (R4-005), so every line this function CREATES has
    # to carry it too or the segment ends up with mixed endings. `cr` comes from
    # the WHOLE file, not from `seg` -- an entry with an empty body has no line
    # to copy the ending from.
    line = f"**{key}:** {value}{cr}"
    blank = cr
    pat = re.compile(r"^\*\*" + re.escape(key) + r":\*\*")
    for i, bl in enumerate(seg):
        if pat.match(bl):
            seg[i] = line
            return seg
    body = list(seg)
    trailing = 0
    while body and body[-1].strip() == "":
        body.pop()
        trailing += 1
    if body:
        body.append(blank)
    body.append(line)
    body.append(blank)
    if trailing > 1:
        body.extend([blank] * (trailing - 1))
    return body


def del_meta(seg, key):
    pat = re.compile(r"^\*\*" + re.escape(key) + r":\*\*")
    return [bl for bl in seg if not pat.match(bl)]


def parent_chain_has_cycle(entries, child_id, new_parent):
    by_id = {e["id"]: e for e in entries}
    seen = set()
    node = new_parent
    while node is not None and node not in seen:
        if node == child_id:
            return True
        seen.add(node)
        pe = by_id.get(node)
        node = pe["parent"] if pe else None
    return False


# ── transition-locked (design.md C3 primitive; caller already holds the lock) ──
def transition_main(argv):
    if len(argv) < 3:
        die(2, "usage: <backlog> <I-NNN> <NEW_STATE> [--reason T] [--plan R]")
    backlog, entry_id, new_state = argv[0], argv[1], argv[2]
    reason = None
    plan = None
    rest = argv[3:]
    i = 0
    while i < len(rest):
        if rest[i] == "--reason" and i + 1 < len(rest):
            reason = rest[i + 1]
            i += 2
        elif rest[i] == "--plan" and i + 1 < len(rest):
            plan = rest[i + 1]
            i += 2
        else:
            die(2, f"usage: unexpected argument {rest[i]}")
    if new_state not in STATES:
        die(2, f"usage: unknown target state {new_state}")
    # Reject injectable values BEFORE reading or touching the backlog.
    for field, value in (("reason", reason), ("plan", plan)):
        ok, why = validate_single_line(value, field)
        if not ok:
            die(2, why)
    lines, entries = parse_backlog(read_text(backlog))
    e = find_entry(entries, entry_id)
    if e is None:
        die(2, f"not found: {entry_id}")
    old = e["state"]
    if old not in STATES:
        die(
            1,
            f"cannot transition {entry_id} from legacy/unknown state {old}; "
            "run mb-backlog-migrate.sh",
        )
    if new_state not in EDGES.get(old, []):
        allowed = ", ".join(EDGES.get(old, [])) or "(none)"
        die(
            1,
            f"invalid transition {old} -> {new_state} for {entry_id}; "
            f"allowed from {old}: {allowed}",
        )
    if new_state == "READY":
        ok, why = validate_brief(e["brief"])
        if not ok:
            die(1, f"READY refused for {entry_id}: {why}")
    if new_state == "WONTFIX" and not (reason and reason.strip()):
        die(1, f"WONTFIX requires a non-empty --reason for {entry_id}")
    lines[e["header_idx"]] = rewrite_state(lines[e["header_idx"]], new_state)
    cr = line_cr(lines)
    seg = lines[e["header_idx"] + 1 : e["end_idx"]]
    if reason is not None and reason.strip():
        seg = set_meta(seg, "Reason", reason.strip(), cr)
    if plan is not None:
        seg = set_meta(seg, "Plan", plan, cr)
    lines[e["header_idx"] + 1 : e["end_idx"]] = seg
    write_atomic(backlog, "\n".join(lines))
    sys.exit(0)


# ── getstate / list / annotate (mb-backlog-state.sh embedded engine) ──────────
def state_main(argv):
    action = argv[0] if argv else ""
    if action == "getstate":
        backlog, entry_id = argv[1], argv[2]
        _, entries = parse_backlog(read_text(backlog))
        e = find_entry(entries, entry_id)
        if e is None:
            sys.exit(2)
        print(e["state"])
        return
    if action == "list":
        backlog = argv[1]
        _, entries = parse_backlog(read_text(backlog))
        listed = [e for e in entries if e["section"] != "Out of scope"]
        for e in sorted(listed, key=lambda x: x["num"]):
            print(
                f"item={e['id']} state={e['state']} "
                f"parent={e['parent'] or 'none'} depth=0 title={json_str(e['title'])}"
            )
        return
    if action == "annotate":
        backlog, entry_id = argv[1], argv[2]
        brief = None
        parent = None
        parent_set = False
        rest = argv[3:]
        i = 0
        while i < len(rest):
            if rest[i] == "--brief" and i + 1 < len(rest):
                brief = rest[i + 1]
                i += 2
            elif rest[i] == "--parent" and i + 1 < len(rest):
                parent = rest[i + 1]
                parent_set = True
                i += 2
            else:
                die(2, f"usage: unexpected argument {rest[i]}")
        if brief is None:
            die(2, "usage: annotate requires --brief")
        # Injectable values are rejected BEFORE anything is read or written.
        for field, value in (("brief", brief), ("parent", parent)):
            ok, why = validate_single_line(value, field)
            if not ok:
                die(2, why)
        ok, why = validate_brief(brief)
        if not ok:
            die(1, f"invalid brief: {why}")
        lines, entries = parse_backlog(read_text(backlog))
        e = find_entry(entries, entry_id)
        if e is None:
            die(2, f"not found: {entry_id}")
        if parent_set and parent != "none":
            if not re.match(r"^I-\d+$", parent):
                die(2, f"usage: invalid parent {parent}")
            if find_entry(entries, parent) is None:
                die(1, f"code=missing_parent item={entry_id} parent={parent}")
            if parent == entry_id or parent_chain_has_cycle(entries, entry_id, parent):
                die(1, f"code=parent_cycle path={entry_id}->{parent}->{entry_id}")
        cr = line_cr(lines)
        seg = lines[e["header_idx"] + 1 : e["end_idx"]]
        seg = set_meta(seg, "Brief", brief, cr)
        if parent_set:
            seg = (
                del_meta(seg, "Parent") if parent == "none" else set_meta(seg, "Parent", parent, cr)
            )
        lines[e["header_idx"] + 1 : e["end_idx"]] = seg
        write_atomic(backlog, "\n".join(lines))
        return
    die(2, f"usage: unknown action {action}")


def main(argv):
    if not argv:
        die(2, "usage: <command> ...")
    if argv[0] == "transition-locked":
        transition_main(argv[1:])
    else:
        state_main(argv)


if __name__ == "__main__":
    main(sys.argv[1:])
