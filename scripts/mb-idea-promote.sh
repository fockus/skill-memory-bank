#!/usr/bin/env bash
# mb-idea-promote.sh — promote an idea (I-NNN) into an active plan.
#
# Usage:
#   mb-idea-promote.sh <I-NNN> <type> [mb_path]
#     type ∈ feature|fix|refactor|experiment
#
# Effects:
#   1. Find idea in BACKLOG.md → extract title.
#   2. Create plan via mb-plan.sh (type + sanitized title as topic).
#   3. Flip idea status NEW|TRIAGED → PLANNED; add/replace `**Plan:** [plans/...](plans/...)`.
#   4. Run mb-plan-sync.sh so the plan appears in active-plans blocks.
#
# Exit codes: 0 OK, 1 missing files / idea not found, 2 already planned/done/declined,
#             3 invalid type.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

ID="${1:?Usage: mb-idea-promote.sh <I-NNN> <type> [mb_path]}"
TYPE="${2:?Usage: mb-idea-promote.sh <I-NNN> <type> [mb_path]}"
MB_PATH=$(mb_resolve_path "${3:-}")

case "$TYPE" in
  feature|fix|refactor|experiment) ;;
  *) echo "[error] Invalid type: $TYPE (feature|fix|refactor|experiment)" >&2; exit 3 ;;
esac

BACKLOG="$MB_PATH/BACKLOG.md"
[ -f "$BACKLOG" ] || { echo "[error] BACKLOG.md not found: $BACKLOG" >&2; exit 1; }

if ! [[ "$ID" =~ ^I-[0-9]{3}$ ]]; then
  echo "[error] Invalid ID format: $ID (expected I-NNN)" >&2
  exit 1
fi

# Extract idea header line
idea_line=$(grep -E "^### ${ID} — " "$BACKLOG" | head -1 || true)
if [ -z "$idea_line" ]; then
  echo "[error] Idea $ID not found in BACKLOG.md" >&2
  exit 1
fi

# Parse title + status via python (portable regex + unicode).
title=$(python3 - "$idea_line" "$ID" <<'PY'
import re, sys
line, idea_id = sys.argv[1], sys.argv[2]
m = re.match(
    rf"^### {re.escape(idea_id)} — (?P<title>.*?) \[(?P<prio>[^,]+),\s*(?P<status>[^,]+),\s*(?P<date>[^\]]+)\]$",
    line,
)
print(m.group("title") if m else "")
PY
)
status=$(python3 - "$idea_line" "$ID" <<'PY'
import re, sys
line, idea_id = sys.argv[1], sys.argv[2]
m = re.match(
    rf"^### {re.escape(idea_id)} — (?P<title>.*?) \[(?P<prio>[^,]+),\s*(?P<status>[^,]+),\s*(?P<date>[^\]]+)\]$",
    line,
)
print(m.group("status").strip().upper() if m else "")
PY
)

status_upper=$(printf '%s' "$status" | tr '[:lower:]' '[:upper:]')
case "$status_upper" in
  NEW|TRIAGED) ;;
  PLANNED)  echo "[error] Idea $ID is already PLANNED" >&2; exit 2 ;;
  DONE)     echo "[error] Idea $ID is already DONE" >&2; exit 2 ;;
  DECLINED) echo "[error] Idea $ID is DECLINED — cannot promote" >&2; exit 2 ;;
  DEFERRED) echo "[error] Idea $ID is DEFERRED — un-defer first" >&2; exit 2 ;;
  *)        echo "[error] Unknown idea status: $status" >&2; exit 1 ;;
esac

if [ -z "$title" ]; then
  echo "[error] Failed to parse title from idea line: $idea_line" >&2
  exit 1
fi

# Create the plan via mb-plan.sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
plan_path=$("$SCRIPT_DIR/mb-plan.sh" "$TYPE" "$title" "$MB_PATH")
plan_basename=$(basename "$plan_path")

# Flip status + add Plan link using python for safe block editing
python3 - "$BACKLOG" "$ID" "$plan_basename" <<'PY'
import re
import sys

path, idea_id, basename = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding="utf-8").read()

pattern = re.compile(
    rf'^(### {re.escape(idea_id)} — )(.*?)(\[)([^\]]*)(\])',
    re.MULTILINE,
)


def flip(m):
    bits = [b.strip() for b in m.group(4).split(",")]
    for i, b in enumerate(bits):
        if b.upper() in ("NEW", "TRIAGED"):
            bits[i] = "PLANNED"
    return m.group(1) + m.group(2) + m.group(3) + ", ".join(bits) + m.group(5)


text_new = pattern.sub(flip, text, count=1)

# Locate idea block to inject/replace Plan link.
blocks = re.split(r'(?m)^(?=### I-\d+\s+—\s+)', text_new)
for i, block in enumerate(blocks):
    if block.lstrip().startswith(f"### {idea_id} —"):
        link = f"**Plan:** [plans/{basename}](plans/{basename})"
        if re.search(r'^\*\*Plan:\*\*', block, re.MULTILINE):
            block = re.sub(
                r'^\*\*Plan:\*\*.*$',
                link,
                block,
                count=1,
                flags=re.MULTILINE,
            )
        else:
            block = block.rstrip("\n") + f"\n\n{link}\n"
        blocks[i] = block
        break

open(path, "w", encoding="utf-8").write("".join(blocks))
PY

# Run sync so the new plan appears in active-plans blocks
"$SCRIPT_DIR/mb-plan-sync.sh" "$plan_path" "$MB_PATH" >/dev/null

echo "[promote] $ID → $plan_basename"
printf '%s\n' "$plan_path"
