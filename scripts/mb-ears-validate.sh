#!/usr/bin/env bash
# mb-ears-validate.sh — validate REQ bullets against the 5 EARS patterns.
#
# Easy Approach to Requirements Syntax (EARS):
#   Ubiquitous:        The <system> shall <response>
#   Event-driven:      When <trigger>, the <system> shall <response>
#   State-driven:      While <state>, the <system> shall <response>
#   Optional feature:  Where <feature>, the <system> shall <response>
#   Unwanted:          If <trigger>, then the <system> shall <response>
#
# Validation rule: every line of the form
#   `- **REQ-NNN** ...`
# must contain BOTH one of the trigger keywords (The|When|While|Where|If) AND
# the verb `shall`, as standalone words. Other lines are ignored.
#
# Usage:
#   mb-ears-validate.sh <file>
#   mb-ears-validate.sh -            # read from stdin
#
# Exit codes:
#   0 — all REQ lines are valid (or no REQ lines at all)
#   1 — one or more REQ lines violate the format (details on stderr)
#   2 — usage error / file does not exist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ARG="${1:-}"

if [ -z "$ARG" ]; then
  echo "Usage: mb-ears-validate.sh <file>|-" >&2
  exit 2
fi

if [ "$ARG" = "-" ]; then
  INPUT=$(cat)
elif [ -f "$ARG" ]; then
  INPUT=$(cat "$ARG")
else
  echo "[error] file not found: $ARG" >&2
  exit 2
fi

EARS_INPUT="$INPUT" MB_SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import os
import re
import sys

sys.path.insert(0, os.environ["MB_SCRIPT_DIR"])
import mb_req_id as rq  # shared REQ-ID grammar (supports REQ-RS-NNN schemes)

REQ_LINE = rq.EARS_REQ_LINE_RE  # bold-bullet REQ line; group(1) = scheme
TRIGGER = re.compile(r"\b(The|When|While|Where|If)\b", re.IGNORECASE)
SHALL = re.compile(r"\bshall\b", re.IGNORECASE)

text = os.environ.get("EARS_INPUT", "")
lines = text.splitlines()
n = len(lines)
bad = 0
i = 0
while i < n:
    m = REQ_LINE.match(lines[i])
    if not m:
        i += 1
        continue
    req = "REQ-" + m.group(1)
    start = i
    # A requirement may wrap across physical lines; gather its continuation
    # lines (indented, non-empty) so `shall` on a wrapped line still counts.
    # Stop at a blank line, the next REQ bullet, or a new top-level
    # bullet/heading — so one requirement's verb never leaks into another's.
    chunk = [lines[i]]
    j = i + 1
    while j < n:
        nxt = lines[j]
        if not nxt.strip():
            break
        if REQ_LINE.match(nxt):
            break
        if nxt.lstrip()[:1] in "-*+#":  # any list item (incl. nested) or heading
            break
        chunk.append(nxt)
        j += 1
    joined = " ".join(chunk)
    # EARS puts the trigger keyword (The/When/While/Where/If) on the requirement
    # line itself; only the `shall` clause may wrap onto a continuation line.
    # Requiring the trigger on the first line stops a title-only requirement from
    # being excused by trigger+shall text that merely appears in wrapped notes.
    if not (TRIGGER.search(chunk[0]) and SHALL.search(joined)):
        sys.stderr.write(
            f"[ears] line {start + 1}: {req} does not match any EARS pattern\n"
        )
        bad += 1
    i = j

sys.exit(1 if bad else 0)
PY
