#!/usr/bin/env bash
# mb-plan-done.sh — close a plan.
#
# Usage:
#   mb-plan-done.sh <plan-file> [mb_path]
#
# Effects:
#   1. For each `(N, name)` pair from the plan: in the `checklist.md` section
#      `## Stage N: <name>`, all `- ⬜ ...` are converted to `- ✅ ...`.
#   2. The plan file is moved to `<mb_path>/plans/done/<basename>`.
#   3. The contents of the `<!-- mb-active-plan --> … <!-- /mb-active-plan -->`
#      block in `plan.md` are cleared (markers remain).
#
# Requirement: the plan file must live inside `<mb_path>/plans/` (not in `done/`).
# Exit codes: 0 OK, 1 usage/missing file, 2 parse error, 3 wrong location.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

PLAN_FILE="${1:?Usage: mb-plan-done.sh <plan-file> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")

if [ ! -f "$PLAN_FILE" ]; then
  echo "[error] Plan not found: $PLAN_FILE" >&2
  exit 1
fi

PLANS_DIR="$MB_PATH/plans"
DONE_DIR="$PLANS_DIR/done"

# Validation: file must be inside `plans/` (and not already in `done/`)
abs_plan=$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")
abs_plans=$(cd "$PLANS_DIR" && pwd 2>/dev/null || echo "")
abs_done=$(cd "$DONE_DIR" 2>/dev/null && pwd || echo "")

if [ -z "$abs_plans" ] || [[ "$abs_plan" != "$abs_plans"/* ]]; then
  echo "[error] Plan file must live under $PLANS_DIR/" >&2
  exit 3
fi
if [ -n "$abs_done" ] && [[ "$abs_plan" == "$abs_done"/* ]]; then
  echo "[error] Plan file is already in done/: $PLAN_FILE" >&2
  exit 3
fi

CHECKLIST="$MB_PATH/checklist.md"
PLAN_MD="$MB_PATH/plan.md"
BASENAME=$(basename "$PLAN_FILE")

[ -f "$CHECKLIST" ] || { echo "[error] checklist.md not found" >&2; exit 1; }
[ -f "$PLAN_MD" ]   || { echo "[error] plan.md not found" >&2; exit 1; }

# ═══ Stage parsing (same as sync) ═══
parse_stages() {
  awk '
    BEGIN { use_markers = 0 }
    /<!-- mb-stage:[0-9]+ -->/ {
      use_markers = 1
      match($0, /[0-9]+/)
      pending = substr($0, RSTART, RLENGTH)
      next
    }
    pending != "" && /^### [^0-9]+[0-9]+:/ {
      sub(/^### [^0-9]+[0-9]+:[[:space:]]*/, "")
      printf "%s\t%s\n", pending, $0
      pending = ""
      next
    }
    END { if (use_markers == 0) exit 42 }
  ' "$PLAN_FILE"
}

stages=$(parse_stages) || rc=$?
rc=${rc:-0}

if [ "$rc" -eq 42 ] || [ -z "$stages" ]; then
  stages=$(awk '
    /^### [^0-9]+[0-9]+:/ {
      line = $0
      match(line, /[0-9]+/)
      n = substr(line, RSTART, RLENGTH)
      sub(/^### [^0-9]+[0-9]+:[[:space:]]*/, "", line)
      printf "%s\t%s\n", n, line
    }
  ' "$PLAN_FILE")
fi

if [ -z "$stages" ]; then
  echo "[error] Failed to extract stages from $PLAN_FILE" >&2
  exit 2
fi

# ═══ Close ⬜ → ✅ inside plan sections in checklist ═══
# Algorithm: for each stage, find the range (from `## Stage N:` to the next `## `)
# and replace `- ⬜` → `- ✅` inside that range.
close_stage_items() {
  local checklist="$1" n="$2"
  local tmp
  tmp=$(mktemp)

  awk -v n="$n" '
    BEGIN { inside = 0 }
    /^## / {
      # Check: is this `## Stage N:`?
      if ($0 ~ "^## [^0-9]*" n ":") {
        inside = 1
      } else {
        inside = 0
      }
      print
      next
    }
    {
      if (inside && /^- ⬜ /) {
        sub(/^- ⬜ /, "- ✅ ")
      }
      print
    }
  ' "$checklist" > "$tmp"

  mv "$tmp" "$checklist"
}

closed=0
while IFS=$'\t' read -r n _name; do
  [ -n "$n" ] || continue
  close_stage_items "$CHECKLIST" "$n"
  closed=$((closed + 1))
done <<< "$stages"

# ═══ Clear active-plan block in plan.md ═══
clear_active_plan_block() {
  local plan_md="$1"
  local tmp
  tmp=$(mktemp)

  if grep -q '<!-- mb-active-plan -->' "$plan_md"; then
    awk '
      BEGIN { inside = 0 }
      /<!-- mb-active-plan -->/ { print; inside = 1; next }
      /<!-- \/mb-active-plan -->/ { inside = 0; print; next }
      !inside { print }
    ' "$plan_md" > "$tmp"
    mv "$tmp" "$plan_md"
  else
    rm -f "$tmp"
  fi
}

clear_active_plan_block "$PLAN_MD"

# ═══ Move the plan file ═══
mkdir -p "$DONE_DIR"
if [ -e "$DONE_DIR/$BASENAME" ]; then
  echo "[error] File already exists in done/: $DONE_DIR/$BASENAME" >&2
  exit 1
fi
mv "$PLAN_FILE" "$DONE_DIR/$BASENAME"

echo "[done] plan=$BASENAME closed_stages=$closed → plans/done/"
