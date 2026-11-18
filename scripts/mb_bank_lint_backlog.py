#!/usr/bin/env python3
"""Backlog-side checks of mb-bank-lint.sh (design.md C5, C3, C4).

State alphabet vs legacy table, READY brief, WONTFIX reason and parent-chain
resolution. The grandfather rule: ``ready_without_brief`` and
``wontfix_without_reason`` apply only to entries carrying at least one v2 meta
line (``**Type:**``/``**Parent:**``/``**Brief:**``/``**Reason:**``). Read-only.
"""

import re

from mb_backlog_state_engine import STATES, parse_backlog
from mb_backlog_validate import validate_brief

LEGACY = {
    "OPEN": "TRIAGED", "PROPOSED": "TRIAGED", "DEFERRED": "TRIAGED",
    "PLANNED": "IN-PROGRESS", "RESOLVED": "DONE", "DECLINED": "WONTFIX",
}
# Any ``### I-NNN`` heading counts, even one the full header grammar rejects:
# a malformed twin still makes the id ambiguous.
ID_HEADING_RE = re.compile(r"^### (I-\d+)(?!\d)")


def _duplicate_ids(text, rel):
    """One ``duplicate_id`` error per id that heads more than one entry."""
    lines_by_id = {}
    for no, ln in enumerate(text.split("\n"), start=1):
        m = ID_HEADING_RE.match(ln)
        if m:
            lines_by_id.setdefault(m.group(1), []).append(no)
    return [("error", "duplicate_id", rel, nos[0],
             f"{iid} appears {len(nos)} times: lines {', '.join(map(str, nos))}")
            for iid, nos in lines_by_id.items() if len(nos) > 1]


def _meta_line(entry, key):
    prefix = f"**{key}:**"
    for i, ln in enumerate(entry["body_lines"]):
        if ln.startswith(prefix):
            return entry["header_idx"] + 2 + i
    return entry["header_idx"] + 1


def check_backlog(text, rel):
    """Findings for one backlog.md text; ``rel`` is the JSON-bound file label."""
    duplicates = _duplicate_ids(text, rel)
    if duplicates:
        # parse_backlog refuses an ambiguous index (exit 2), and every other
        # check resolves entries by id, so duplicates are the only findings.
        return duplicates
    _, entries = parse_backlog(text)
    by_id = {e["id"]: e for e in entries}
    findings = []
    for e in entries:
        line, label = e["header_idx"] + 1, f"{e['id']} — {e['title']}"
        token = e["state"]
        if token in LEGACY:
            findings.append(("warning", "legacy_state", rel, line,
                             f"{label}: legacy state {token}; run mb-backlog-migrate.sh (becomes {LEGACY[token]})"))
        elif token not in STATES:
            findings.append(("error", "invalid_state", rel, line, f"{label}: state {token!r} is outside the machine and the legacy table"))
        if e["has_v2"]:
            if token == "READY":
                ok, why = validate_brief(e["brief"])
                if not ok:
                    findings.append(("error", "ready_without_brief", rel, line, f"{label}: {why}"))
            if token == "WONTFIX" and not (e["reason"] or "").strip():
                findings.append(("error", "wontfix_without_reason", rel, line, f"{label}: WONTFIX needs a non-empty **Reason:**"))
        parent = e["parent"]
        if parent and parent != "none":
            path, node = [e["id"]], parent
            while node and node != "none" and node in by_id and node not in path:
                path.append(node)
                node = by_id[node]["parent"]
            if node and node != "none" and node not in by_id:
                findings.append(("error", "parent_cycle", rel, _meta_line(e, "Parent"), f"{label}: parent {node} does not exist"))
            elif node in path:
                findings.append(("error", "parent_cycle", rel, _meta_line(e, "Parent"),
                                 f"{label}: parent chain loops: {'->'.join(path[path.index(node):] + [node])}"))
    return findings
