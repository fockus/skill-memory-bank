#!/usr/bin/env bash
# mb-compact.sh — status-based compaction decay.
#
# Usage: mb-compact.sh [--dry-run|--apply] [mb_path]
#
# Archival requires (age > threshold) AND (done-signal):
#   Plans: file in `plans/done/` (primary) OR mentioned in `checklist.md` as ✅
#          OR in `progress.md`/`STATUS.md` as "completed|done|closed|shipped".
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
CHECKLIST_AGE_DAYS="${MB_COMPACT_CHECKLIST_DAYS:-30}"

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

# File age in days (portable BSD/GNU `stat`).
mtime_days() {
  local f="$1" now mtime
  [ -e "$f" ] || { echo 0; return; }
  now=$(date +%s)
  mtime=$(stat -f%m "$f" 2>/dev/null || stat -c%Y "$f" 2>/dev/null || echo "$now")
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
  for f in "$MB_PATH/progress.md" "$MB_PATH/STATUS.md"; do
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
  for f in plan.md STATUS.md checklist.md RESEARCH.md BACKLOG.md; do
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
  local summary date_str backlog="$MB_PATH/BACKLOG.md" entry
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

# ─── v3.1: checklist.md section removal + legacy localized Deferred/Declined migration ───

# Print list of fully-done `## ` sections in checklist.md that are linked to
# a plan file in `plans/done/` older than CHECKLIST_AGE_DAYS.
collect_checklist_candidates() {
  local checklist="$MB_PATH/checklist.md"
  [ -f "$checklist" ] || return 0
  [ -d "$MB_PATH/plans/done" ] || return 0

  python3 - "$checklist" "$MB_PATH/plans/done" "$CHECKLIST_AGE_DAYS" <<'PY'
import os
import re
import sys
import time

checklist_path, done_dir, threshold_days = sys.argv[1], sys.argv[2], int(sys.argv[3])
text = open(checklist_path, encoding="utf-8").read()

sections = re.split(r'(?m)^(?=## )', text)
now = time.time()

done_plans = []
if os.path.isdir(done_dir):
    for name in os.listdir(done_dir):
        if name.endswith(".md"):
            full = os.path.join(done_dir, name)
            done_plans.append((full, open(full, encoding="utf-8").read()))


def linked_old_plan(heading: str) -> bool:
    needle = f"### {heading.strip()}"
    for path, content in done_plans:
        if needle in content:
            age_days = (now - os.path.getmtime(path)) / 86400
            if age_days > threshold_days:
                return True
    return False


for section in sections:
    first = section.splitlines()[0] if section.splitlines() else ""
    if not first.startswith("## "):
        continue
    heading = first[3:].strip()
    items = [line for line in section.splitlines() if re.match(r'^\s*-\s', line)]
    if not items:
        continue
    if any("⬜" in it or "[ ]" in it for it in items):
        continue
    if not all(("✅" in it) or ("[x]" in it.lower()) for it in items):
        continue
    if linked_old_plan(heading):
        print(heading)
PY
}

# Strip given `## <heading>` sections from checklist.md (in-place).
apply_checklist_removal() {
  local checklist="$MB_PATH/checklist.md" headings_file="$1"
  [ -f "$checklist" ] || return 0
  [ -s "$headings_file" ] || return 0
  python3 - "$checklist" "$headings_file" <<'PY'
import re
import sys

path, headings_file = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
targets = {
    line.strip() for line in open(headings_file, encoding="utf-8") if line.strip()
}

parts = re.split(r'(?m)^(?=## )', text)
kept = []
for p in parts:
    first = p.splitlines()[0] if p.splitlines() else ""
    if first.startswith("## "):
        heading = first[3:].strip()
        if heading in targets:
            continue
    kept.append(p)

new_text = "".join(kept)
# Collapse 3+ blank lines into max 2.
new_text = re.sub(r'\n{3,}', '\n\n', new_text)
open(path, "w", encoding="utf-8").write(new_text)
PY
}

# Emit bullets to migrate from plan.md's localized `Deferred` / `Declined`
# sections into DEFERRED / DECLINED. Format: <status>\t<text>
collect_plan_md_bullets() {
  local plan="$MB_PATH/plan.md"
  [ -f "$plan" ] || return 0
  python3 - "$plan" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
sections = re.split(r'(?m)^(?=## )', text)
DEFERRED = {"\u041e\u0442\u043b\u043e\u0436\u0435\u043d\u043e", "Deferred"}
DECLINED = {"\u041e\u0442\u043a\u043b\u043e\u043d\u0435\u043d\u043e", "Declined"}

for section in sections:
    lines = section.splitlines()
    if not lines or not lines[0].startswith("## "):
        continue
    heading = lines[0][3:].strip()
    if heading in DEFERRED:
        status = "DEFERRED"
    elif heading in DECLINED:
        status = "DECLINED"
    else:
        continue
    for line in lines[1:]:
        m = re.match(r'^\s*-\s+(.*\S)\s*$', line)
        if m:
            print(f"{status}\t{m.group(1)}")
PY
}

# Write DEFERRED/DECLINED ideas into BACKLOG.md and strip bullets from plan.md.
apply_plan_md_migration() {
  local plan="$MB_PATH/plan.md" backlog="$MB_PATH/BACKLOG.md"
  [ -f "$plan" ] && [ -f "$backlog" ] || return 0
  python3 - "$plan" "$backlog" <<'PY'
import re
import sys
import datetime

plan_path, backlog_path = sys.argv[1], sys.argv[2]
plan_text = open(plan_path, encoding="utf-8").read()
backlog_text = open(backlog_path, encoding="utf-8").read()

DEFERRED = {"\u041e\u0442\u043b\u043e\u0436\u0435\u043d\u043e", "Deferred"}
DECLINED = {"\u041e\u0442\u043a\u043b\u043e\u043d\u0435\u043d\u043e", "Declined"}

sections = re.split(r'(?m)^(?=## )', plan_text)
migrated = []
new_parts = []
for section in sections:
    lines = section.splitlines(keepends=True)
    if not lines or not lines[0].startswith("## "):
        new_parts.append(section)
        continue
    heading = lines[0][3:].strip()
    if heading in DEFERRED:
        status, prio = "DEFERRED", "MED"
    elif heading in DECLINED:
        status, prio = "DECLINED", "LOW"
    else:
        new_parts.append(section)
        continue
    kept_lines = [lines[0]]
    for line in lines[1:]:
        m = re.match(r'^\s*-\s+(.*\S)\s*$', line)
        if m:
            migrated.append((status, prio, m.group(1)))
        else:
            kept_lines.append(line)
    new_parts.append("".join(kept_lines))

new_plan = "".join(new_parts)
new_plan = re.sub(r'\n{3,}', '\n\n', new_plan)

if migrated:
    ids = [int(m.group(1)) for m in re.finditer(r'I-(\d{3})', backlog_text)]
    next_id = max(ids) + 1 if ids else 1
    today = datetime.date.today().isoformat()
    lines_out = []
    for status, prio, text in migrated:
        id_str = f"I-{next_id:03d}"
        next_id += 1
        lines_out.append(
            f"\n### {id_str} — {text} [{prio}, {status}, {today}]\n"
        )
    if re.search(r'(?m)^## Ideas\s*$', backlog_text):
        new_backlog = re.sub(
            r'(?m)^(## Ideas\s*\n)',
            lambda m: m.group(1) + "".join(lines_out),
            backlog_text,
            count=1,
        )
    else:
        new_backlog = backlog_text.rstrip("\n") + "\n\n## Ideas\n" + "".join(lines_out)
    open(backlog_path, "w", encoding="utf-8").write(new_backlog)

open(plan_path, "w", encoding="utf-8").write(new_plan)
PY
}

# ═══ Main ═══
plan_candidates=$(collect_plan_candidates)
note_candidates=$(collect_note_candidates)
active_warnings=$(collect_active_plan_warnings)
checklist_candidates=$(collect_checklist_candidates)
plan_md_bullets=$(collect_plan_md_bullets)

plan_count=0
note_count=0
checklist_count=0
plan_md_count=0
[ -n "$plan_candidates" ] && plan_count=$(echo "$plan_candidates" | grep -c .)
[ -n "$note_candidates" ] && note_count=$(echo "$note_candidates" | grep -c .)
[ -n "$checklist_candidates" ] && checklist_count=$(echo "$checklist_candidates" | grep -c .)
[ -n "$plan_md_bullets" ] && plan_md_count=$(echo "$plan_md_bullets" | grep -c .)

echo "mode=$MODE"
echo "plans_candidates=$plan_count"
echo "notes_candidates=$note_count"
echo "checklist_sections_to_remove=$checklist_count"
echo "plan_md_ideas_to_migrate=$plan_md_count"
echo "candidates=$((plan_count + note_count + checklist_count + plan_md_count))"

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
  if [ -n "$checklist_candidates" ]; then
    headings_tmp=$(mktemp)
    printf '%s\n' "$checklist_candidates" > "$headings_tmp"
    apply_checklist_removal "$headings_tmp"
    rm -f "$headings_tmp"
    echo "[apply] removed $checklist_count checklist section(s)"
  fi
  if [ -n "$plan_md_bullets" ]; then
    apply_plan_md_migration
    echo "[apply] migrated $plan_md_count plan.md idea(s) → BACKLOG.md"
  fi
  touch "$MB_PATH/.last-compact"
fi

exit 0
