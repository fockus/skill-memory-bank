#!/usr/bin/env bash
# mb-compact.sh — status-based compaction decay.
#
# Usage: mb-compact.sh [--dry-run|--apply] [mb_path]
#
# Archival requires (age > threshold) AND (done-signal):
#   Plans: file in `plans/done/` (primary) OR mentioned in `checklist.md` as ✅
#          OR in `progress.md`/`status.md` as "completed|done|closed|shipped".
#          Active plans (not done) are NOT touched even if >180d → warning.
#   Notes: frontmatter `importance: low` + >90d + no references in core files.
#
# `--dry-run` (default): reasoning only, 0 changes. `--apply`: perform changes + touch `.last-compact`.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

PLAN_AGE_DAYS=60
NOTE_AGE_DAYS=90
ACTIVE_WARN_DAYS=180

MODE="dry-run"
MB_ARG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --*)
      echo "[error] unknown flag: $arg" >&2
      echo "Usage: mb-compact.sh [--dry-run|--apply] [mb_path]" >&2
      exit 1
      ;;
    *) MB_ARG="$arg" ;;
  esac
done

MB_PATH_RAW=$(mb_resolve_path "$MB_ARG")
if [ ! -d "$MB_PATH_RAW" ]; then
  echo "[error] .memory-bank not found at: $MB_PATH_RAW" >&2
  echo "[hint]  run /mb init first" >&2
  exit 1
fi
MB_PATH=$(cd "$MB_PATH_RAW" && pwd)

mtime_days() {
  local f="$1" now mtime
  [ -e "$f" ] || { echo 0; return; }
  now=$(date +%s)
  mtime=$(mb_mtime "$f")
  echo $(( (now - mtime) / 86400 ))
}

# Importance from frontmatter (first 20 lines).
note_importance() {
  [ -f "$1" ] || { echo ""; return; }
  awk '
    NR == 1 && $0 !~ /^---/ { exit }
    /^---/ && NR > 1 { exit }
    /^importance:/ {
      sub(/^importance:[[:space:]]*/, "")
      gsub(/["'\'' ]/, "")
      print; exit
    }
  ' "$1"
}

# Basic frontmatter validity check.
note_frontmatter_ok() {
  local f="$1" body_start
  head -1 "$f" | grep -q '^---$' || return 1
  body_start=$(awk '/^---$/ && NR > 1 { print NR; exit }' "$f")
  [ -n "$body_start" ] || return 1
  head -"$body_start" "$f" | grep -qE '\[\[\[|\{\{\{' && return 1
  return 0
}

# Done-signal for a plan. Echoes reason to stdout. 0 if done, 1 if active.
plan_done_signal() {
  local plan="$1" rel abs_plan basename
  abs_plan=$(cd "$(dirname "$plan")" 2>/dev/null && pwd)/$(basename "$plan")
  rel="${abs_plan#"$MB_PATH"/}"
  basename=$(basename "$plan")

  if [[ "$rel" == plans/done/* ]]; then
    echo "in_done_dir"; return 0
  fi
  if [ -f "$MB_PATH/checklist.md" ] \
     && grep -E '(✅|\[x\])' "$MB_PATH/checklist.md" 2>/dev/null | grep -qF "$basename"; then
    echo "checklist_done"; return 0
  fi
  local f
  for f in "$MB_PATH/progress.md" "$MB_PATH/status.md"; do
    [ -f "$f" ] || continue
    if grep -E 'completed|done|closed|shipped' "$f" 2>/dev/null \
       | grep -qF "$basename"; then
      echo "progress_done"; return 0
    fi
  done
  if [ -f "$MB_PATH/checklist.md" ] \
     && grep -E '(⬜|\[ \])' "$MB_PATH/checklist.md" 2>/dev/null | grep -qF "$basename"; then
    echo "checklist_todo"; return 1
  fi
  return 1
}

# References to a note in active files.
note_referenced() {
  local rel="$1" base f
  base=$(basename "$rel")
  for f in roadmap.md status.md checklist.md research.md backlog.md; do
    [ -f "$MB_PATH/$f" ] || continue
    grep -qF "$base" "$MB_PATH/$f" 2>/dev/null && return 0
  done
  return 1
}

# Title + outcome → 1-line summary.
plan_oneline_summary() {
  local f="$1" title outcome
  title=$(grep -m1 '^# ' "$f" 2>/dev/null | sed 's/^# *//' || true)
  outcome=$(grep -m1 -iE '^(Outcome|Result|Summary):' "$f" 2>/dev/null \
            | sed 's/^[^:]*: *//' || true)
  [ -z "$title" ] && title=$(basename "$f" .md)
  [ -z "$outcome" ] && outcome="archived"
  echo "${title} → ${outcome}"
}

# Body compressed to 3 non-empty lines (without frontmatter).
note_compress_body() {
  awk '
    BEGIN { fm = 0; found_open = 0; n = 0 }
    /^---$/ {
      if (found_open == 0) { found_open = 1; fm = 1; next }
      if (fm == 1) { fm = 0; next }
    }
    fm == 1 { next }
    found_open == 0 { next }
    /^[[:space:]]*$/ { next }
    { print; n++; if (n >= 3) exit }
  ' "$1"
}

collect_plan_candidates() {
  if [ -d "$MB_PATH/plans/done" ]; then
    while IFS= read -r -d '' f; do
      local age rel
      age=$(mtime_days "$f")
      rel="${f#"$MB_PATH"/}"
      [ "$age" -gt "$PLAN_AGE_DAYS" ] && printf '%s\tin_done_dir\t%s\n' "$rel" "$age"
    done < <(find "$MB_PATH/plans/done" -type f -name '*.md' -print0 2>/dev/null)
  fi
  if [ -d "$MB_PATH/plans" ]; then
    while IFS= read -r -d '' f; do
      local age rel reason
      age=$(mtime_days "$f")
      rel="${f#"$MB_PATH"/}"
      [[ "$rel" == plans/done/* ]] && continue
      if [ "$age" -gt "$PLAN_AGE_DAYS" ]; then
        reason=$(plan_done_signal "$f" || true)
        if [ "$reason" = "checklist_done" ] || [ "$reason" = "progress_done" ]; then
          printf '%s\t%s\t%s\n' "$rel" "$reason" "$age"
        fi
      fi
    done < <(find "$MB_PATH/plans" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)
  fi
}

collect_active_plan_warnings() {
  [ -d "$MB_PATH/plans" ] || return 0
  while IFS= read -r -d '' f; do
    local age rel signal
    age=$(mtime_days "$f")
    rel="${f#"$MB_PATH"/}"
    [[ "$rel" == plans/done/* ]] && continue
    [ "$age" -gt "$ACTIVE_WARN_DAYS" ] || continue
    signal=$(plan_done_signal "$f" || true)
    if [ "$signal" != "checklist_done" ] && [ "$signal" != "progress_done" ] \
       && [ "$signal" != "in_done_dir" ]; then
      printf '%s\t%s\n' "$rel" "$age"
    fi
  done < <(find "$MB_PATH/plans" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null)
}

collect_note_candidates() {
  [ -d "$MB_PATH/notes" ] || return 0
  while IFS= read -r -d '' f; do
    local rel age imp
    rel="${f#"$MB_PATH"/}"
    [[ "$rel" == notes/archive/* ]] && continue
    if ! note_frontmatter_ok "$f"; then
      echo "[warn] broken frontmatter skip: $rel" >&2; continue
    fi
    age=$(mtime_days "$f")
    [ "$age" -gt "$NOTE_AGE_DAYS" ] || continue
    imp=$(note_importance "$f")
    [ "$imp" = "low" ] || continue
    note_referenced "$rel" && continue
    printf '%s\tlow_age_unref\t%s\n' "$rel" "$age"
  done < <(find "$MB_PATH/notes" -type f -name '*.md' -print0 2>/dev/null)
}

apply_plan_archive() {
  local rel="$1" reason="$2" f="$MB_PATH/$1"
  [ -f "$f" ] || return 0
  local summary date_str backlog="$MB_PATH/backlog.md" entry
  summary=$(plan_oneline_summary "$f")
  date_str=$(date +%Y-%m-%d)
  if ! grep -q '^## Archived plans' "$backlog" 2>/dev/null; then
    printf '\n## Archived plans\n\n' >> "$backlog"
  fi
  entry="- ${date_str}: ${summary} (was: ${rel})"
  grep -qF "was: ${rel}" "$backlog" 2>/dev/null || echo "$entry" >> "$backlog"
  rm -f "$f"
  echo "[apply] archived plan: $rel (reason=$reason)"
}

apply_note_archive() {
  local rel="$1" f="$MB_PATH/$1" archive_dir="$MB_PATH/notes/archive" base dest
  [ -f "$f" ] || return 0
  mkdir -p "$archive_dir"
  base=$(basename "$rel")
  dest="$archive_dir/$base"
  if [ -e "$dest" ]; then
    echo "[warn] archive target exists, skip: $dest" >&2; return 0
  fi
  local frontmatter compressed
  frontmatter=$(awk 'BEGIN{n=0} /^---$/{n++; print; if(n>=2) exit; next} n==1 {print}' "$f")
  compressed=$(note_compress_body "$f")
  {
    echo "$frontmatter"
    echo ""
    echo "<!-- archived on $(date +%Y-%m-%d) — compressed summary below -->"
    echo "$compressed"
  } > "$dest"
  rm -f "$f"
  echo "[apply] archived note: $rel → notes/archive/"
}

# ═══ Main ═══
plan_candidates=$(collect_plan_candidates)
note_candidates=$(collect_note_candidates)
active_warnings=$(collect_active_plan_warnings)

plan_count=0
note_count=0
[ -n "$plan_candidates" ] && plan_count=$(echo "$plan_candidates" | grep -c .)
[ -n "$note_candidates" ] && note_count=$(echo "$note_candidates" | grep -c .)

echo "mode=$MODE"
echo "plans_candidates=$plan_count"
echo "notes_candidates=$note_count"
echo "candidates=$((plan_count + note_count))"

if [ "$plan_count" -gt 0 ]; then
  echo ""
  echo "# Plans to archive:"
  while IFS=$'\t' read -r rel reason age; do
    [ -z "$rel" ] && continue
    echo "  archive: $rel (reason=$reason, age=${age}d)"
  done <<< "$plan_candidates"
fi

if [ "$note_count" -gt 0 ]; then
  echo ""
  echo "# Notes to archive:"
  while IFS=$'\t' read -r rel reason age; do
    [ -z "$rel" ] && continue
    echo "  archive: $rel (reason=$reason, age=${age}d)"
  done <<< "$note_candidates"
fi

if [ -n "$active_warnings" ]; then
  echo ""
  echo "# Warnings — active plans older than ${ACTIVE_WARN_DAYS}d (not done, not archived):"
  while IFS=$'\t' read -r rel age; do
    [ -z "$rel" ] && continue
    echo "  warning: $rel is ${age}d old but not done — check whether it is still relevant"
  done <<< "$active_warnings"
fi

if [ "$MODE" = "apply" ]; then
  if [ -n "$plan_candidates" ]; then
    while IFS=$'\t' read -r rel reason _age; do
      [ -z "$rel" ] && continue
      apply_plan_archive "$rel" "$reason"
    done <<< "$plan_candidates"
  fi
  if [ -n "$note_candidates" ]; then
    while IFS=$'\t' read -r rel _reason _age; do
      [ -z "$rel" ] && continue
      apply_note_archive "$rel"
    done <<< "$note_candidates"
  fi
  touch "$MB_PATH/.last-compact"
fi

exit 0
