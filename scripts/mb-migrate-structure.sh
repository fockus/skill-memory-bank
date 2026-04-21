#!/usr/bin/env bash
# mb-migrate-structure.sh — one-shot v3.0 → v3.1 migrator for .memory-bank/.
#
# Usage: mb-migrate-structure.sh [--dry-run|--apply] [mb_path]

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MODE="dry-run"
MB_ARG=""
CHECKLIST_AGE_DAYS="${MB_COMPACT_CHECKLIST_DAYS:-30}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --*)
      echo "[error] unknown flag: $arg" >&2
      echo "Usage: mb-migrate-structure.sh [--dry-run|--apply] [mb_path]" >&2
      exit 1
      ;;
    *) MB_ARG="$arg" ;;
  esac
done

MB_PATH=$(mb_resolve_path "$MB_ARG")
[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }
MB_PATH=$(cd "$MB_PATH" && pwd)

PLAN="$MB_PATH/plan.md"
STATUS="$MB_PATH/STATUS.md"
BACKLOG="$MB_PATH/BACKLOG.md"
LEGACY_NONE_YET=$'пока нет'

mtime_days() {
  local file="$1" now mtime
  [ -e "$file" ] || { printf '%s\n' 0; return 0; }
  now=$(date +%s)
  mtime=$(mb_mtime "$file")
  printf '%s\n' $(( (now - mtime) / 86400 ))
}

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
for name in os.listdir(done_dir):
    if not name.endswith(".md"):
        continue
    full = os.path.join(done_dir, name)
    done_plans.append((full, open(full, encoding="utf-8").read()))


def linked_old_plan(heading: str) -> bool:
    needle = f"### {heading.strip()}"
    for path, content in done_plans:
        if needle not in content:
            continue
        age_days = (now - os.path.getmtime(path)) / 86400
        if age_days > threshold_days:
            return True
    return False


for section in sections:
    lines = section.splitlines()
    if not lines or not lines[0].startswith("## "):
        continue
    heading = lines[0][3:].strip()
    items = [line for line in lines[1:] if re.match(r'^\s*-\s', line)]
    if not items:
        continue
    if any("⬜" in item or "[ ]" in item for item in items):
        continue
    if not all(("✅" in item) or ("[x]" in item.lower()) for item in items):
        continue
    if linked_old_plan(heading):
        print(heading)
PY
}

apply_checklist_removal() {
  local checklist="$MB_PATH/checklist.md" headings_file="$1"
  [ -f "$checklist" ] || return 0
  [ -s "$headings_file" ] || return 0
  python3 - "$checklist" "$headings_file" <<'PY'
import re
import sys

path, headings_file = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
targets = {line.strip() for line in open(headings_file, encoding="utf-8") if line.strip()}

parts = re.split(r'(?m)^(?=## )', text)
kept = []
for part in parts:
    lines = part.splitlines()
    if lines and lines[0].startswith("## ") and lines[0][3:].strip() in targets:
        continue
    kept.append(part)

new_text = re.sub(r'\n{3,}', '\n\n', ''.join(kept))
open(path, 'w', encoding='utf-8').write(new_text)
PY
}

collect_plan_md_bullets() {
  [ -f "$PLAN" ] || return 0
  python3 - "$PLAN" <<'PY'
import re
import sys

text = open(sys.argv[1], encoding="utf-8").read()
sections = re.split(r'(?m)^(?=## )', text)
deferred = {"Отложено", "Deferred"}
declined = {"Отклонено", "Declined"}

for section in sections:
    lines = section.splitlines()
    if not lines or not lines[0].startswith("## "):
        continue
    heading = lines[0][3:].strip()
    if heading in deferred:
        status = "DEFERRED"
    elif heading in declined:
        status = "DECLINED"
    else:
        continue
    for line in lines[1:]:
        match = re.match(r'^\s*-\s+(.*\S)\s*$', line)
        if match:
            print(f"{status}\t{match.group(1)}")
PY
}

apply_plan_md_migration() {
  [ -f "$PLAN" ] && [ -f "$BACKLOG" ] || return 0
  python3 - "$PLAN" "$BACKLOG" <<'PY'
import datetime
import re
import sys

plan_path, backlog_path = sys.argv[1], sys.argv[2]
plan_text = open(plan_path, encoding="utf-8").read()
backlog_text = open(backlog_path, encoding="utf-8").read()

deferred = {"Отложено", "Deferred"}
declined = {"Отклонено", "Declined"}

sections = re.split(r'(?m)^(?=## )', plan_text)
migrated = []
new_parts = []
for section in sections:
    lines = section.splitlines(keepends=True)
    if not lines or not lines[0].startswith("## "):
        new_parts.append(section)
        continue

    heading = lines[0][3:].strip()
    if heading in deferred:
        status, prio = "DEFERRED", "MED"
    elif heading in declined:
        status, prio = "DECLINED", "LOW"
    else:
        new_parts.append(section)
        continue

    kept_lines = [lines[0]]
    for line in lines[1:]:
        match = re.match(r'^\s*-\s+(.*\S)\s*$', line)
        if match:
            migrated.append((status, prio, match.group(1)))
        else:
            kept_lines.append(line)
    new_parts.append(''.join(kept_lines))

new_plan = re.sub(r'\n{3,}', '\n\n', ''.join(new_parts))

if migrated:
    ids = [int(match.group(1)) for match in re.finditer(r'I-(\d{3})', backlog_text)]
    next_id = max(ids) + 1 if ids else 1
    today = datetime.date.today().isoformat()
    new_entries = []
    for status, prio, text in migrated:
        new_entries.append(f"\n### I-{next_id:03d} — {text} [{prio}, {status}, {today}]\n")
        next_id += 1

    if re.search(r'(?m)^## Ideas\s*$', backlog_text):
        backlog_text = re.sub(
            r'(?m)^(## Ideas\s*\n)',
            lambda match: match.group(1) + ''.join(new_entries),
            backlog_text,
            count=1,
        )
    else:
        backlog_text = backlog_text.rstrip('\n') + '\n\n## Ideas\n' + ''.join(new_entries)

open(backlog_path, 'w', encoding='utf-8').write(backlog_text)
open(plan_path, 'w', encoding='utf-8').write(new_plan)
PY
}

# ─── Detection ──────────────────────────────────────────────────────────────
checklist_candidates=$(collect_checklist_candidates)
plan_md_bullets=$(collect_plan_md_bullets)

checklist_count=0
plan_md_count=0
[ -n "$checklist_candidates" ] && checklist_count=$(echo "$checklist_candidates" | grep -c .)
[ -n "$plan_md_bullets" ] && plan_md_count=$(echo "$plan_md_bullets" | grep -c .)

actions=()

if [ -f "$PLAN" ] && ! grep -q '<!-- mb-active-plans -->' "$PLAN"; then
  actions+=("plan.md: add <!-- mb-active-plans --> block")
fi

if [ -f "$STATUS" ]; then
  grep -q '<!-- mb-active-plans -->' "$STATUS" || actions+=("STATUS.md: add <!-- mb-active-plans --> block")
  grep -q '<!-- mb-recent-done -->' "$STATUS" || actions+=("STATUS.md: add <!-- mb-recent-done --> block")
fi

if [ -f "$BACKLOG" ]; then
  if grep -qF "$LEGACY_NONE_YET" "$BACKLOG" || grep -qE '\(empty\)' "$BACKLOG" || ! grep -qE '^## ADR\s*$' "$BACKLOG"; then
    actions+=("BACKLOG.md: restructure to skeleton (## Ideas + ## ADR)")
  fi
fi

[ "$checklist_count" -gt 0 ] && actions+=("checklist.md: remove $checklist_count completed section(s)")
[ "$plan_md_count" -gt 0 ] && actions+=("plan.md: migrate $plan_md_count deferred/declined idea(s) to BACKLOG.md")

action_count=${#actions[@]}
echo "mode=$MODE"
echo "actions_pending=$action_count"
echo "checklist_sections_to_remove=$checklist_count"
echo "plan_md_ideas_to_migrate=$plan_md_count"
for action in "${actions[@]:-}"; do
  [ -n "$action" ] && echo "  - $action"
done

if [ "$MODE" != "apply" ] || [ "$action_count" -eq 0 ]; then
  exit 0
fi

# ─── Backup ─────────────────────────────────────────────────────────────────
timestamp=$(date +%Y%m%d_%H%M%S)
backup_dir="$MB_PATH/.pre-migrate/$timestamp"
mkdir -p "$backup_dir"
for file in plan.md STATUS.md BACKLOG.md checklist.md; do
  [ -f "$MB_PATH/$file" ] && cp "$MB_PATH/$file" "$backup_dir/"
done
echo "[apply] backup → .pre-migrate/$timestamp/"

# ─── plan.md: upgrade singular → plural + ensure block exists ──────────────
if [ -f "$PLAN" ] && ! grep -q '<!-- mb-active-plans -->' "$PLAN"; then
  python3 - "$PLAN" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
entry_re = re.compile(r'(?m)^\*\*Active plan:\*\*\s*`?(plans/[^\s`]+)`?\s*(?:—\s*(.*))?$')
entries = []
for match in entry_re.finditer(text):
    rel, desc = match.group(1), (match.group(2) or "").strip()
    basename = rel.split("/")[-1]
    date_match = re.match(r'(\d{4}-\d{2}-\d{2})_', basename)
    date = date_match.group(1) if date_match else ""
    title = desc or basename.replace('.md', '')
    entries.append(f"- [{date}] [{rel}]({rel}) — {title}")

text = text.replace("<!-- mb-active-plan -->", "<!-- mb-active-plans -->")
text = text.replace("<!-- /mb-active-plan -->", "<!-- /mb-active-plans -->")
text = re.sub(r'(?m)^## Active plan\s*$', '## Active plans', text)
text = entry_re.sub('', text)

if "<!-- mb-active-plans -->" not in text:
    block = "<!-- mb-active-plans -->\n"
    if entries:
        block += "\n".join(entries) + "\n"
    block += "<!-- /mb-active-plans -->"
    if re.search(r'(?m)^## Active plans\s*$', text):
        text = re.sub(r'(?m)^(## Active plans\s*\n)', lambda m: m.group(1) + "\n" + block + "\n", text, count=1)
    else:
        text = text.rstrip("\n") + "\n\n## Active plans\n\n" + block + "\n"

text = re.sub(r'\n{3,}', '\n\n', text)
open(path, 'w', encoding='utf-8').write(text)
PY
  echo "[apply] plan.md migrated"
fi

# ─── STATUS.md: ensure blocks ───────────────────────────────────────────────
if [ -f "$STATUS" ]; then
  python3 - "$STATUS" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
changed = False

if "<!-- mb-active-plans -->" not in text:
    text = text.rstrip("\n") + "\n\n## Active plans\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n"
    changed = True

if "<!-- mb-recent-done -->" not in text:
    text = text.rstrip("\n") + "\n\n## Recently done\n\n<!-- mb-recent-done -->\n<!-- /mb-recent-done -->\n"
    changed = True

if changed:
    text = re.sub(r'\n{3,}', '\n\n', text)
    open(path, 'w', encoding='utf-8').write(text)
PY
  echo "[apply] STATUS.md blocks ensured"
fi

# ─── BACKLOG.md: ensure skeleton + strip placeholders ───────────────────────
if [ -f "$BACKLOG" ]; then
  python3 - "$BACKLOG" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

text = re.sub(r'(?m)^[\s]*\(пока нет\)[\s]*$', '', text)
text = re.sub(r'(?m)^[\s]*\(empty\)[\s]*$', '', text)

if not re.search(r'(?m)^# ', text):
    text = '# Backlog\n\n' + text.lstrip('\n')

if not re.search(r'(?m)^## Ideas\s*$', text):
    text = text.rstrip('\n') + '\n\n## Ideas\n'

if not re.search(r'(?m)^## ADR\s*$', text):
    text = text.rstrip('\n') + '\n\n## ADR\n'

text = re.sub(r'\n{3,}', '\n\n', text).rstrip('\n') + '\n'
open(path, 'w', encoding='utf-8').write(text)
PY
  echo "[apply] BACKLOG.md skeleton ensured"
fi

if [ "$checklist_count" -gt 0 ]; then
  headings_tmp=$(mktemp)
  printf '%s\n' "$checklist_candidates" > "$headings_tmp"
  apply_checklist_removal "$headings_tmp"
  rm -f "$headings_tmp"
  echo "[apply] removed $checklist_count checklist section(s)"
fi

if [ "$plan_md_count" -gt 0 ]; then
  apply_plan_md_migration
  echo "[apply] migrated $plan_md_count plan.md idea(s) → BACKLOG.md"
fi

echo "[apply] v3.1 structural migration complete"
