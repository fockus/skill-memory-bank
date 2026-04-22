#!/usr/bin/env bash
# mb-plan-sync.sh — synchronize a plan with checklist.md + roadmap.md + status.md.
#
# Usage:
#   mb-plan-sync.sh <plan-file> [mb_path]
#
# Effects (v3.1 — multi-active):
#   - Parse `(N, name)` pairs from the plan (`<!-- mb-stage:N -->` markers or
#     fallback to `### Stage N: <name>`).
#   - For each `(N, name)` absent from checklist.md, append section
#     `## Stage N: <name>` + item `- ⬜ <name>`. Idempotent by full section title.
#   - Upsert an entry for this plan into the `<!-- mb-active-plans --> ... -->`
#     block in BOTH roadmap.md and status.md:
#        `- [YYYY-MM-DD] [plans/<basename>](plans/<basename>) — <title>`
#     Match key = basename. Re-sync replaces the line; different plan appends.
#   - Legacy singular `<!-- mb-active-plan -->` marker auto-upgrades to plural.
#   - status.md is optional — if present, it gets the same upsert.
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
PLAN_MD="$MB_PATH/roadmap.md"
STATUS_MD="$MB_PATH/status.md"

[ -f "$CHECKLIST" ] || { echo "[error] checklist.md not found: $CHECKLIST" >&2; exit 1; }
[ -f "$PLAN_MD" ]   || { echo "[error] roadmap.md not found: $PLAN_MD" >&2; exit 1; }

BASENAME=$(basename "$PLAN_FILE")

# Date from basename prefix YYYY-MM-DD_, fallback to today's date.
if [[ "$BASENAME" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}) ]]; then
  PLAN_DATE="${BASH_REMATCH[1]}"
else
  PLAN_DATE=$(date +%Y-%m-%d)
fi

# Plan title = first H1 minus optional `# <kind>:` prefix.
plan_title=$(awk '
  /^# /{
    sub(/^# [^:：]+[:：][[:space:]]*/, "")
    sub(/^# /, "")
    print
    exit
  }
' "$PLAN_FILE")
[ -n "$plan_title" ] || plan_title="$BASENAME"

# ═══════════════════════════════════════════════════════════════
# Stage parsing
# ═══════════════════════════════════════════════════════════════
parse_stages() {
  awk '
    BEGIN { use_markers = 0 }
    /<!-- mb-stage:[0-9]+ -->/ {
      use_markers = 1
      match($0, /[0-9]+/)
      pending = substr($0, RSTART, RLENGTH)
      next
    }
    pending != "" && /^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:/ {
      sub(/^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:[[:space:]]*/, "")
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
  stages=$(awk '
    /^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:/ {
      line = $0
      match(line, /[0-9]+/)
      n = substr(line, RSTART, RLENGTH)
      sub(/^#{2,4} (Task|Stage|Phase|Sprint) [0-9]+:[[:space:]]*/, "", line)
      printf "%s\t%s\n", n, line
    }
  ' "$PLAN_FILE")
fi

if [ -z "$stages" ]; then
  echo "[error] Failed to extract stages from $PLAN_FILE" >&2
  exit 2
fi

# ═══════════════════════════════════════════════════════════════
# Append missing stages into checklist.md (idempotent by full title)
# ═══════════════════════════════════════════════════════════════
append_missing_stages() {
  local checklist="$1" stages="$2"
  local tmp
  tmp=$(mktemp)
  cp "$checklist" "$tmp"

  local added=0
  while IFS=$'\t' read -r n name; do
    [ -n "$n" ] || continue
    local heading="## Stage ${n}: ${name}"
    # Match exact heading line to distinguish multiple active plans sharing N
    if awk -v h="$heading" 'BEGIN{found=0} $0==h{found=1; exit} END{exit !found}' "$tmp"; then
      continue
    fi
    {
      printf '\n%s\n' "$heading"
      printf -- '- ⬜ %s\n' "$name"
    } >> "$tmp"
    added=$((added + 1))
  done <<< "$stages"

  mv "$tmp" "$checklist"
  printf '%s\n' "$added"
}

added_count=$(append_missing_stages "$CHECKLIST" "$stages")

# ═══════════════════════════════════════════════════════════════
# Upsert entry into <!-- mb-active-plans --> block of a file
# ═══════════════════════════════════════════════════════════════
# Args: <file> <basename> <date> <title>
# If the file does not contain plural markers, try to upgrade singular ones
# or insert a new block after `## Active plan(s)` / at EOF.
upsert_active_plan_entry() {
  local file="$1" basename="$2" plan_date="$3" title="$4"
  local entry tmp
  entry="- [${plan_date}] [plans/${basename}](plans/${basename}) — ${title}"
  tmp=$(mktemp)

  if grep -q '<!-- mb-active-plans -->' "$file"; then
    awk -v entry="$entry" -v bn="$basename" '
      BEGIN { inside=0; replaced=0 }
      /<!-- mb-active-plans -->/ { inside=1; print; next }
      /<!-- \/mb-active-plans -->/ {
        if (inside && replaced==0) { print entry; replaced=1 }
        inside=0
        print
        next
      }
      {
        if (inside) {
          if (index($0, bn) > 0) {
            if (replaced==0) { print entry; replaced=1 }
            next
          }
          print
        } else {
          print
        }
      }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
    return 0
  fi

  # Legacy singular markers → upgrade to plural + insert entry
  if grep -q '<!-- mb-active-plan -->' "$file"; then
    awk -v entry="$entry" '
      BEGIN { inside=0; inserted=0 }
      /<!-- mb-active-plan -->/ {
        print "<!-- mb-active-plans -->"
        if (inserted==0) { print entry; inserted=1 }
        inside=1
        next
      }
      /<!-- \/mb-active-plan -->/ {
        print "<!-- /mb-active-plans -->"
        inside=0
        next
      }
      !inside { print }
    ' "$file" > "$tmp"

    # Upgrade heading `## Active plan` → `## Active plans` if present
    sed -i.bak -E 's/^## Active plan[[:space:]]*$/## Active plans/' "$tmp" 2>/dev/null || true
    rm -f "$tmp.bak"

    mv "$tmp" "$file"
    return 0
  fi

  # No markers at all — add block after `## Active plans` heading or EOF
  if grep -qE '^## Active plans[[:space:]]*$' "$file"; then
    awk -v entry="$entry" '
      /^## Active plans[[:space:]]*$/ && !done {
        print
        print ""
        print "<!-- mb-active-plans -->"
        print entry
        print "<!-- /mb-active-plans -->"
        done=1
        next
      }
      { print }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
    return 0
  fi

  {
    cat "$file"
    printf '\n## Active plans\n\n'
    printf '<!-- mb-active-plans -->\n'
    printf '%s\n' "$entry"
    printf '<!-- /mb-active-plans -->\n'
  } > "$tmp"
  mv "$tmp" "$file"
}

upsert_active_plan_entry "$PLAN_MD"   "$BASENAME" "$PLAN_DATE" "$plan_title"
if [ -f "$STATUS_MD" ]; then
  upsert_active_plan_entry "$STATUS_MD" "$BASENAME" "$PLAN_DATE" "$plan_title"
fi

# ═══════════════════════════════════════════════════════════════
# Report
# ═══════════════════════════════════════════════════════════════
stage_count=$(printf '%s\n' "$stages" | grep -c . || true)
echo "[sync] plan=$BASENAME stages=$stage_count added=$added_count"
