#!/usr/bin/env bash
# mb-plan-sync.sh — synchronize a plan with `checklist.md` + `plan.md`.
#
# Usage:
#   mb-plan-sync.sh <plan-file> [mb_path]
#
# Effects:
#   - Extract `(N, name)` pairs from the plan via `<!-- mb-stage:N -->` markers
#     (fallback: regex `### Stage N: <name>`).
#   - For each pair, if `checklist.md` does not have `## Stage N: <name>`,
#     append the section to the end together with one item `- ⬜ <name>`.
#     Existing sections are not modified → idempotent.
#   - In `plan.md`, replace the block between `<!-- mb-active-plan -->` and
#     `<!-- /mb-active-plan -->` with a single line
#     `**Active plan:** \`plans/<basename>\` — <title>`.
#     If markers do not exist, add them after `## Active plan`
#     or at the end of the file.
#
# Exit codes: 0 OK, 1 usage/missing file, 2 parse error.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

PLAN_FILE="${1:?Usage: mb-plan-sync.sh <plan-file> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")

if [ ! -f "$PLAN_FILE" ]; then
  echo "[error] Plan not found: $PLAN_FILE" >&2
  exit 1
fi

CHECKLIST="$MB_PATH/checklist.md"
PLAN_MD="$MB_PATH/plan.md"

[ -f "$CHECKLIST" ] || {
  echo "[error] checklist.md not found: $CHECKLIST" >&2
  exit 1
}
[ -f "$PLAN_MD" ] || {
  echo "[error] plan.md not found: $PLAN_MD" >&2
  exit 1
}

BASENAME=$(basename "$PLAN_FILE")

# ═══ Extract plan title (first H1 after optional prefix) ═══
plan_title=$(awk '
  /^# /{
    sub(/^# [^:：]+[:：][[:space:]]*/, "")
    sub(/^# /, "")
    print
    exit
  }
' "$PLAN_FILE")
[ -n "$plan_title" ] || plan_title="$BASENAME"

# ═══ Stage parsing ═══
# Primary: `<!-- mb-stage:N -->` markers → next line `### Stage N: <name>`.
# Fallback: if markers are missing — parse `### Stage N: <name>` directly.
# Output: tab-separated (`N<TAB>name`), one line per stage.
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
    END {
      if (use_markers == 0) exit 42
    }
  ' "$PLAN_FILE"
}

stages=$(parse_stages) || rc=$?
rc=${rc:-0}

if [ "$rc" -eq 42 ] || [ -z "$stages" ]; then
  # Fallback — no markers, parse `###` headings directly
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

# ═══ Append missing sections to checklist ═══
append_missing_stages() {
  local checklist="$1" stages="$2"
  local tmp
  tmp=$(mktemp)
  cp "$checklist" "$tmp"

  local added=0
  while IFS=$'\t' read -r n name; do
    [ -n "$n" ] || continue
    # Check whether `## Stage N:` already exists (ignoring title/emoji)
    if grep -qE "^## [^0-9]*${n}:" "$tmp"; then
      continue
    fi
    # Append to the end
    {
      printf '\n## Stage %s: %s\n' "$n" "$name"
      printf -- '- ⬜ %s\n' "$name"
    } >> "$tmp"
    added=$((added + 1))
  done <<< "$stages"

  mv "$tmp" "$checklist"
  printf '%s\n' "$added"
}

added_count=$(append_missing_stages "$CHECKLIST" "$stages")

# ═══ Update active-plan block in plan.md ═══
update_active_plan_block() {
  local plan_md="$1" basename="$2" title="$3"
  local tmp
  tmp=$(mktemp)

  local new_line="**Active plan:** \`plans/$basename\` — $title"

  if grep -q '<!-- mb-active-plan -->' "$plan_md"; then
    # Markers exist — replace the content between them
    awk -v newline="$new_line" '
      BEGIN { inside = 0 }
      /<!-- mb-active-plan -->/ {
        print
        print newline
        inside = 1
        next
      }
      /<!-- \/mb-active-plan -->/ {
        inside = 0
        print
        next
      }
      !inside { print }
    ' "$plan_md" > "$tmp"
  else
    # Markers do not exist — insert after `## Active plan` or append to the end
    if grep -qE '^## Active plan[[:space:]]*$' "$plan_md"; then
      awk -v newline="$new_line" '
        /^## Active plan[[:space:]]*$/ {
          print
          print ""
          print "<!-- mb-active-plan -->"
          print newline
          print "<!-- /mb-active-plan -->"
          inserted = 1
          next
        }
        { print }
      ' "$plan_md" > "$tmp"
    else
      cp "$plan_md" "$tmp"
      {
        printf '\n## Active plan\n\n'
        printf '<!-- mb-active-plan -->\n'
        printf '%s\n' "$new_line"
        printf '<!-- /mb-active-plan -->\n'
      } >> "$tmp"
    fi
  fi

  mv "$tmp" "$plan_md"
}

update_active_plan_block "$PLAN_MD" "$BASENAME" "$plan_title"

# ═══ Report ═══
stage_count=$(printf '%s\n' "$stages" | grep -c . || true)
echo "[sync] plan=$BASENAME stages=$stage_count added=$added_count"
