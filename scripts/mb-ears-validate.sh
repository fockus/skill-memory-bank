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

EARS_INPUT="$INPUT" python3 - <<'PY'
import os
import re
import sys

REQ_LINE = re.compile(r"^\s*-\s+\*\*REQ-(\d{3,})\*\*")
TRIGGER = re.compile(r"\b(The|When|While|Where|If)\b")
SHALL = re.compile(r"\bshall\b")

text = os.environ.get("EARS_INPUT", "")
bad = 0
for lineno, raw in enumerate(text.splitlines(), start=1):
    m = REQ_LINE.match(raw)
    if not m:
        continue
    req = f"REQ-{m.group(1)}"
    if not (TRIGGER.search(raw) and SHALL.search(raw)):
        sys.stderr.write(
            f"[ears] line {lineno}: {req} does not match any EARS pattern\n"
        )
        bad += 1

sys.exit(1 if bad else 0)
PY
