#!/usr/bin/env python3
"""Candidate inspection for mb-brief.sh — steps 4 and 5 of contract C6.

    mb_brief_candidate.py <candidate> <auto:0|1> [<input-path>...]

Step 4 checks the --auto agreement: `--auto` skips the light-question gate, so
the brief MUST record what it assumed instead, and a brief NOT generated under
--auto must not claim to have assumed anything. Step 5 checks the C2 invariant
— the frontmatter `inputs:` list, the Attachments links and the argv basenames
must describe one and the same set of files.

Both are enforced in code rather than trusted to the prompt layer.

stdout: one `error=` line per violation, empty when the candidate agrees.
exit:   0 agreed - 1 violation.
"""

import os
import re
import sys
from urllib.parse import quote, unquote

candidate = sys.argv[1]
auto = sys.argv[2] == "1"
argv_names = [os.path.basename(p) for p in sys.argv[3:]]

with open(candidate, encoding="utf-8") as fh:
    lines = fh.read().split("\n")


def frontmatter(src):
    if not src or src[0] != "---":
        return {}, []
    for i in range(1, len(src)):
        if src[i] == "---":
            break
    else:
        return {}, []
    scalars, items, key = {}, [], None
    for line in src[1:i]:
        if not line.strip():
            continue
        if line[:1] in (" ", "\t"):
            stripped = line.strip()
            if key == "inputs" and stripped.startswith("- "):
                items.append(stripped[2:].strip())
            continue
        mo = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):(.*)$", line)
        if not mo:
            continue
        key, value = mo.group(1), mo.group(2).strip()
        scalars.setdefault(key, value)
        if key == "inputs" and value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            items = [p.strip() for p in inner.split(",")] if inner else []
    return scalars, items


scalars, fm_items = frontmatter(lines)

# ── step 4 — the --auto agreement is checked in code, never trusted to the
# prompt layer: `--auto` skips the question gate, so the brief MUST say what it
# assumed, and a brief that was NOT generated under --auto must not claim to.
note = scalars.get("assumptions_note")
if auto and not (note or "").strip():
    sys.stdout.write("error=assumptions_note_missing\n")
    sys.exit(1)
if not auto and note is not None:
    sys.stdout.write("error=assumptions_note_unexpected\n")
    sys.exit(1)


# ── step 5 — the C2 invariant.
def attachments_body(src):
    out, fence, seen = [], False, False
    for line in src:
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if not fence and line.startswith("## "):
            if seen:
                break
            seen = line[3:].rstrip() == "Attachments"
            continue
        if seen and not fence:
            out.append(line)
    return out


LINK_RE = re.compile(r"^- \[(.+)\]\(inputs/(.+)\)$")
problems = []
att_names = []
body = [ln for ln in attachments_body(lines)
        if ln.strip() and not ln.strip().startswith("<!--")]

if body == ["- None"]:
    att_names = []
elif any(ln.strip() == "- None" for ln in body):
    problems.append(("", "attachments"))
else:
    for line in body:
        mo = LINK_RE.match(line.rstrip())
        if not mo:
            problems.append(("", "attachments"))
            continue
        label, target = mo.group(1), mo.group(2)
        decoded = unquote(target)
        # The encoding must be CANONICAL, not merely decodable: an unencoded
        # `inputs/a b.md` decodes fine yet is not the grammar C2 fixes, and two
        # spellings of one path would let the invariant compare unequal sets.
        if quote(decoded, safe="") != target or decoded != label:
            problems.append((decoded, "attachments"))
            continue
        if decoded in att_names:
            problems.append((decoded, "attachments"))
            continue
        att_names.append(decoded)

fm_names = [p[len("inputs/"):] for p in fm_items if p.startswith("inputs/")]

everything = set(fm_names) | set(att_names) | set(argv_names)
for name in everything:
    if name not in fm_names:
        problems.append((name, "frontmatter"))
    if name not in att_names:
        problems.append((name, "attachments"))
    if name not in argv_names:
        problems.append((name, "argv"))

if problems:
    # `path=` carries the percent-encoded form so the line stays parseable even
    # when the basename contains a space.
    out = sorted({
        "error=inputs_mismatch path=inputs/%s where=%s" % (quote(n, safe=""), w)
        for n, w in problems
    })
    sys.stdout.write("\n".join(out) + "\n")
    sys.exit(1)
