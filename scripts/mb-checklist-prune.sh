#!/usr/bin/env bash
# mb-checklist-prune.sh — collapse completed sections in checklist.md to one-liners.
#
# Usage:
#   mb-checklist-prune.sh [--dry-run|--apply] [--mb <path>]
#
# Rules:
#   - Scans `### ` (level-3) sections in <mb>/checklist.md.
#   - A section is collapsable when:
#       (a) body contains a markdown link to `plans/done/...`
#       (b) body contains NO `⬜` and NO `[ ]` markers
#   - Collapse target form (single line, replaces multi-line section):
#       `### <heading> ✅ — Plan: [<basename>](<plans/done/...>)`
#   - Top-level `## ⏳ In flight` / `## ⏭ Next planned` content is never touched.
#   - On `--apply`: writes pre-mutation backup `<mb>/.checklist.md.bak.<unix-ts>`.
#   - After prune, warns to stderr if file is still > 120 lines (hard cap convention).
#   - Idempotent: rerun on already-collapsed file makes no further changes.
#
# Exit codes: 0 on success or no-op; non-zero on argument error.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

HARD_CAP_LINES=120

MODE="dry-run"
MB_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply)   MODE="apply"; shift ;;
    --mb)      MB_ARG="${2:-}"; shift 2 ;;
    --help|-h)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*)
      echo "[error] unknown flag: $1" >&2
      echo "Usage: mb-checklist-prune.sh [--dry-run|--apply] [--mb <path>]" >&2
      exit 1 ;;
    *)
      [ -z "$MB_ARG" ] && MB_ARG="$1"
      shift ;;
  esac
done

MB_PATH_RAW=$(mb_resolve_path "$MB_ARG")
if [ ! -d "$MB_PATH_RAW" ]; then
  echo "[error] .memory-bank not found at: $MB_PATH_RAW" >&2
  exit 1
fi
MB_PATH=$(cd "$MB_PATH_RAW" && pwd)
CHECKLIST="$MB_PATH/checklist.md"

if [ ! -f "$CHECKLIST" ]; then
  echo "[info] no checklist.md at $CHECKLIST — nothing to prune"
  exit 0
fi

# Heavy lifting in python — multi-line section parsing in pure bash is brittle.
PRUNE_OUTPUT=$(MB_CHECKLIST="$CHECKLIST" MB_MODE="$MODE" python3 - <<'PY'
import os
import re
import sys

path = os.environ["MB_CHECKLIST"]
mode = os.environ["MB_MODE"]
text = open(path, encoding="utf-8").read()
lines = text.splitlines(keepends=False)

# Locate ### section boundaries, but only outside the protected ## blocks.
# Protected = top-level sections whose heading text begins with the listed emojis/words.
PROTECTED_RE = re.compile(r"^##\s+(⏳\s*In\s*flight|⏭\s*Next\s*planned)", re.IGNORECASE)
H2_RE = re.compile(r"^##\s+")
H3_RE = re.compile(r"^###\s+(.+?)\s*$")
PLAN_DONE_RE = re.compile(r"\(([^)]*plans/done/[^)]+\.md)\)")
TODO_RE = re.compile(r"(⬜|\[\s\])")


def in_protected_block(idx: int) -> bool:
    # Walk upward to nearest H2; return True if it's a protected one.
    for j in range(idx - 1, -1, -1):
        if H2_RE.match(lines[j]):
            return bool(PROTECTED_RE.match(lines[j]))
    return False


# Build list of (start_idx, end_idx_exclusive, heading_text)
sections = []
i = 0
n = len(lines)
while i < n:
    m = H3_RE.match(lines[i])
    if not m:
        i += 1
        continue
    if in_protected_block(i):
        i += 1
        continue
    start = i
    heading = m.group(1)
    j = i + 1
    while j < n and not H3_RE.match(lines[j]) and not H2_RE.match(lines[j]):
        j += 1
    sections.append((start, j, heading))
    i = j

candidates = []
for start, end, heading in sections:
    body = "\n".join(lines[start + 1:end])
    plan_match = PLAN_DONE_RE.search(body)
    if not plan_match:
        continue
    if TODO_RE.search(body):
        continue
    # Skip already-collapsed (single-line, no body content beyond heading + maybe a blank).
    body_nonblank = [ln for ln in lines[start + 1:end] if ln.strip()]
    if len(body_nonblank) == 0:
        continue  # already a one-liner with trailing blank
    candidates.append((start, end, heading, plan_match.group(1)))

# Print plan to stdout (dry-run consumers parse this).
if candidates:
    print("# Plans to collapse:")
    for _start, _end, heading, plan_path in candidates:
        print(f"  collapse: {heading} → {plan_path}")
else:
    print("# No collapse candidates.")

if mode != "apply":
    sys.exit(0)

# Apply: rebuild file from non-replaced lines + replacement one-liners.
# We work top-down; build a list of (range, replacement_lines).
new_lines: list[str] = []
cursor = 0
for start, end, heading, plan_path in candidates:
    # copy lines [cursor:start]
    new_lines.extend(lines[cursor:start])
    base = os.path.basename(plan_path)
    # Single-line replacement with trailing blank to keep visual separation.
    new_lines.append(f"### {heading} — Plan: [{base}]({plan_path})")
    new_lines.append("")
    cursor = end
new_lines.extend(lines[cursor:])

# Drop accidental triple-blank runs introduced by collapse.
collapsed: list[str] = []
blank_streak = 0
for ln in new_lines:
    if ln.strip() == "":
        blank_streak += 1
        if blank_streak <= 2:
            collapsed.append(ln)
    else:
        blank_streak = 0
        collapsed.append(ln)

# Restore single trailing newline.
out = "\n".join(collapsed)
if not out.endswith("\n"):
    out += "\n"

# Print marker so bash side knows apply ran (and what content to write).
print("---APPLY-CONTENT-BEGIN---")
sys.stdout.write(out)
print("---APPLY-CONTENT-END---")
PY
)

# Split python output: everything before APPLY-CONTENT marker is the plan.
if [ "$MODE" = "apply" ] && printf '%s\n' "$PRUNE_OUTPUT" | grep -q '^---APPLY-CONTENT-BEGIN---$'; then
  PLAN_TEXT=$(printf '%s\n' "$PRUNE_OUTPUT" | awk '/^---APPLY-CONTENT-BEGIN---$/{exit} {print}')
  NEW_TEXT=$(printf '%s\n' "$PRUNE_OUTPUT" | awk 'flag {print} /^---APPLY-CONTENT-BEGIN---$/{flag=1}' | awk '/^---APPLY-CONTENT-END---$/{exit} {print}')
  printf '%s\n' "$PLAN_TEXT"

  TS=$(date +%s)
  cp "$CHECKLIST" "$MB_PATH/.checklist.md.bak.$TS"
  printf '%s\n' "$NEW_TEXT" > "$CHECKLIST"
  echo "[apply] wrote $CHECKLIST (backup: .checklist.md.bak.$TS)"
else
  printf '%s\n' "$PRUNE_OUTPUT"
fi

# Hard-cap warning (always evaluated against final file state).
LINE_COUNT=$(wc -l < "$CHECKLIST" | tr -d ' ')
if [ "$LINE_COUNT" -gt "$HARD_CAP_LINES" ]; then
  echo "[warn] checklist.md has $LINE_COUNT lines — exceeds hard cap of $HARD_CAP_LINES; manual trim or follow-up archival required" >&2
fi

exit 0
