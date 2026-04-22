#!/usr/bin/env bash
# mb-plan-done.sh — close an active plan.
#
# Usage:
#   mb-plan-done.sh <plan-file> [mb_path]
#
# v3.1 effects:
#   1. Remove plan's `## Stage N: <name>` sections from checklist.md (not tick).
#   2. Remove plan's entry from `<!-- mb-active-plans -->` blocks in roadmap.md + status.md.
#   3. Prepend entry to `<!-- mb-recent-done -->` in status.md.
#      Format: `- YYYY-MM-DD — [plans/done/<basename>](plans/done/<basename>) — <title>`
#      Trim block to MB_RECENT_DONE_LIMIT (default 10).
#   4. If backlog.md has an idea linked to this plan (`**Plan:** plans/<basename>`),
#      flip its status to DONE and add `**Outcome:**` placeholder.
#   5. Move plan-file → plans/done/<basename>.
#
# Requirement: plan-file must live under <mb_path>/plans/ (not already in done/).
# Exit codes: 0 OK, 1 usage/missing, 2 parse error, 3 wrong location.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

PLAN_FILE="${1:?Usage: mb-plan-done.sh <plan-file> [mb_path]}"
MB_PATH=$(mb_resolve_path "${2:-}")
LIMIT="${MB_RECENT_DONE_LIMIT:-10}"

if [ ! -f "$PLAN_FILE" ]; then
  echo "[error] Plan not found: $PLAN_FILE" >&2
  exit 1
fi

PLANS_DIR="$MB_PATH/plans"
DONE_DIR="$PLANS_DIR/done"

abs_plan=$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")
abs_plans=$(cd "$PLANS_DIR" 2>/dev/null && pwd || echo "")
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
PLAN_MD="$MB_PATH/roadmap.md"
STATUS_MD="$MB_PATH/status.md"
BACKLOG_MD="$MB_PATH/backlog.md"
BASENAME=$(basename "$PLAN_FILE")
TODAY=$(date +%Y-%m-%d)

[ -f "$CHECKLIST" ] || { echo "[error] checklist.md not found" >&2; exit 1; }
[ -f "$PLAN_MD" ]   || { echo "[error] roadmap.md not found" >&2; exit 1; }

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
# Stage parsing (needed to locate checklist sections to remove)
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
    END { if (use_markers == 0) exit 42 }
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
# Remove `## Stage N: <name>` sections from checklist.md
# Section = from heading line through the line before the next `## ` (or EOF).
# ═══════════════════════════════════════════════════════════════
remove_stage_section() {
  local checklist="$1" n="$2" name="$3"
  local heading="## Stage ${n}: ${name}"
  local tmp
  tmp=$(mktemp)

  awk -v h="$heading" '
    BEGIN { skip = 0 }
    /^## / {
      if ($0 == h) { skip = 1; next }
      skip = 0
      print
      next
    }
    !skip { print }
  ' "$checklist" > "$tmp"

  mv "$tmp" "$checklist"
}

removed_sections=0
while IFS=$'\t' read -r n name; do
  [ -n "$n" ] || continue
  remove_stage_section "$CHECKLIST" "$n" "$name"
  removed_sections=$((removed_sections + 1))
done <<< "$stages"

# ═══════════════════════════════════════════════════════════════
# Remove plan entry from mb-active-plans block in file
# ═══════════════════════════════════════════════════════════════
remove_active_plan_entry() {
  local file="$1" basename="$2"
  [ -f "$file" ] || return 0
  local tmp
  tmp=$(mktemp)

  awk -v bn="$basename" '
    BEGIN { inside=0 }
    /<!-- mb-active-plans -->/ { inside=1; print; next }
    /<!-- \/mb-active-plans -->/ { inside=0; print; next }
    {
      if (inside && index($0, bn) > 0) next
      print
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}

remove_active_plan_entry "$PLAN_MD" "$BASENAME"
remove_active_plan_entry "$STATUS_MD" "$BASENAME"

# ═══════════════════════════════════════════════════════════════
# Prepend entry to mb-recent-done block in status.md; trim to LIMIT
# ═══════════════════════════════════════════════════════════════
prepend_recent_done() {
  local file="$1" basename="$2" title="$3" today="$4" limit="$5"
  [ -f "$file" ] || return 0

  local entry="- ${today} — [plans/done/${basename}](plans/done/${basename}) — ${title}"

  # If block missing, inject it before EOF (best-effort legacy handling)
  if ! grep -q '<!-- mb-recent-done -->' "$file"; then
    {
      printf '\n## Recently done\n\n<!-- mb-recent-done -->\n%s\n<!-- /mb-recent-done -->\n' "$entry"
    } >> "$file"
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  awk -v entry="$entry" -v limit="$limit" '
    BEGIN { inside=0; printed=0; count=0 }
    /<!-- mb-recent-done -->/ {
      print
      print entry
      inside=1
      printed=1
      count=1
      next
    }
    /<!-- \/mb-recent-done -->/ {
      inside=0
      print
      next
    }
    {
      if (inside) {
        if (/^[[:space:]]*$/) { print; next }
        if (/^- /) {
          if (count < limit) { print; count++; next }
          else { next }
        }
        print
        next
      }
      print
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
}

prepend_recent_done "$STATUS_MD" "$BASENAME" "$plan_title" "$TODAY" "$LIMIT"

# ═══════════════════════════════════════════════════════════════
# Flip BACKLOG idea PLANNED → DONE (if linked to this plan)
# ═══════════════════════════════════════════════════════════════
flip_backlog_idea() {
  local file="$1" basename="$2"
  [ -f "$file" ] || return 0

  if ! grep -qE "\*\*Plan:\*\*.*plans/${basename}" "$file"; then
    return 0
  fi

  local tmp
  tmp=$(mktemp)
  python3 - "$file" "$basename" > "$tmp" <<'PY'
import re
import sys

path, basename = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()


def flip_status(block: str) -> str:
    bits = [b.strip() for b in block.split(",")]
    for i, b in enumerate(bits):
        if b.upper() in ("NEW", "TRIAGED", "PLANNED"):
            bits[i] = "DONE"
    return ", ".join(bits)


parts = re.split(r'(?m)^(?=### I-\d+\s+—\s+)', text)
out = []
for part in parts:
    if f"plans/{basename}" in part and "**Plan:**" in part:
        part = re.sub(
            r'^(### I-\d+\s+—\s+.*?\[)([^\]]*)(\])',
            lambda m: m.group(1) + flip_status(m.group(2)) + m.group(3),
            part,
            count=1,
            flags=re.MULTILINE,
        )
        if "**Outcome:**" not in part:
            part = part.rstrip("\n") + "\n\n**Outcome:** closed via plan.\n"
    out.append(part)

sys.stdout.write("".join(out))
PY

  mv "$tmp" "$file"
}

flip_backlog_idea "$BACKLOG_MD" "$BASENAME"

# ═══════════════════════════════════════════════════════════════
# Move plan file to plans/done/
# ═══════════════════════════════════════════════════════════════
mkdir -p "$DONE_DIR"
if [ -e "$DONE_DIR/$BASENAME" ]; then
  echo "[error] File already exists in done/: $DONE_DIR/$BASENAME" >&2
  exit 1
fi
mv "$PLAN_FILE" "$DONE_DIR/$BASENAME"

echo "[done] plan=$BASENAME removed_sections=$removed_sections → plans/done/"

# ═══════════════════════════════════════════════════════════════
# Chain: roadmap-sync + traceability-gen (best-effort — warn, don't fail)
# ═══════════════════════════════════════════════════════════════
SCRIPT_DIR=$(dirname "$0")
if [ -x "$SCRIPT_DIR/mb-roadmap-sync.sh" ]; then
  "$SCRIPT_DIR/mb-roadmap-sync.sh" "$MB_PATH" || echo "[warn] mb-roadmap-sync.sh failed (non-fatal)" >&2
fi
if [ -x "$SCRIPT_DIR/mb-traceability-gen.sh" ]; then
  "$SCRIPT_DIR/mb-traceability-gen.sh" "$MB_PATH" || echo "[warn] mb-traceability-gen.sh failed (non-fatal)" >&2
fi
