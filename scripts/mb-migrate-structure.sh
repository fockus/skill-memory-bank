#!/usr/bin/env bash
# mb-migrate-structure.sh — one-shot v3.0 → v3.1 migrator for .memory-bank/.
#
# Usage: mb-migrate-structure.sh [--dry-run|--apply] [mb_path]
#
# Actions (only on --apply):
#   1. Back up plan.md, STATUS.md, BACKLOG.md, checklist.md → .pre-migrate/<timestamp>/
#   2. Upgrade plan.md singular `<!-- mb-active-plan -->` → plural; convert text-only
#      "## Active plan"/"**Active plan:**" to a plural block.
#   3. Ensure STATUS.md has `<!-- mb-active-plans -->` + `<!-- mb-recent-done -->` blocks.
#   4. Rewrite BACKLOG.md to skeleton with `## Ideas` + `## ADR` sections
#      (strip legacy "(none yet)" / "(empty)" placeholders; keep any real ideas).
#
# Idempotent: second run detects 0 actions.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MODE="dry-run"
MB_ARG=""
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
LEGACY_NONE_YET=$'\u043f\u043e\u043a\u0430 \u043d\u0435\u0442'

# ─── Detection ──────────────────────────────────────────────────────────────
actions=()

if [ -f "$PLAN" ]; then
  if ! grep -q '<!-- mb-active-plans -->' "$PLAN"; then
    actions+=("plan.md: add <!-- mb-active-plans --> block")
  fi
fi

if [ -f "$STATUS" ]; then
  grep -q '<!-- mb-active-plans -->' "$STATUS" \
    || actions+=("STATUS.md: add <!-- mb-active-plans --> block")
  grep -q '<!-- mb-recent-done -->' "$STATUS" \
    || actions+=("STATUS.md: add <!-- mb-recent-done --> block")
fi

if [ -f "$BACKLOG" ]; then
  if grep -qF "$LEGACY_NONE_YET" "$BACKLOG" \
     || grep -qE '\(empty\)' "$BACKLOG" \
     || ! grep -qE '^## ADR\s*$' "$BACKLOG"; then
    actions+=("BACKLOG.md: restructure to skeleton (## Ideas + ## ADR)")
  fi
fi

action_count=${#actions[@]}
echo "mode=$MODE"
echo "actions_pending=$action_count"
for a in "${actions[@]:-}"; do
  [ -n "$a" ] && echo "  - $a"
done

if [ "$MODE" != "apply" ] || [ "$action_count" -eq 0 ]; then
  exit 0
fi

# ─── Backup ─────────────────────────────────────────────────────────────────
timestamp=$(date +%Y%m%d_%H%M%S)
backup_dir="$MB_PATH/.pre-migrate/$timestamp"
mkdir -p "$backup_dir"
for f in plan.md STATUS.md BACKLOG.md checklist.md; do
  [ -f "$MB_PATH/$f" ] && cp "$MB_PATH/$f" "$backup_dir/"
done
echo "[apply] backup → .pre-migrate/$timestamp/"

# ─── plan.md: upgrade singular → plural + ensure block exists ──────────────
if [ -f "$PLAN" ] && ! grep -q '<!-- mb-active-plans -->' "$PLAN"; then
  python3 - "$PLAN" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()

# Collect plan reference lines (legacy "**Active plan:** `plans/...`" or HTML entries)
entry_re = re.compile(r'(?m)^\*\*Active plan:\*\*\s*`?(plans/[^\s`]+)`?\s*(?:—\s*(.*))?$')
entries = []
for m in entry_re.finditer(text):
    rel, desc = m.group(1), (m.group(2) or "").strip()
    basename = rel.split("/")[-1]
    date_m = re.match(r'(\d{4}-\d{2}-\d{2})_', basename)
    date = date_m.group(1) if date_m else ""
    title = desc or basename.replace(".md", "")
    entries.append(f"- [{date}] [{rel}]({rel}) — {title}")

# Upgrade singular HTML markers (if any)
text = text.replace("<!-- mb-active-plan -->", "<!-- mb-active-plans -->")
text = text.replace("<!-- /mb-active-plan -->", "<!-- /mb-active-plans -->")

# Replace heading: "## Active plan" → "## Active plans"
text = re.sub(r'(?m)^## Active plan\s*$', '## Active plans', text)

# Drop legacy inline **Active plan:** bullets (we'll rebuild them inside block)
text = entry_re.sub("", text)

# Ensure a block exists right after `## Active plans`.
if "<!-- mb-active-plans -->" not in text:
    block = "<!-- mb-active-plans -->\n" + \
            ("\n".join(entries) + "\n" if entries else "") + \
            "<!-- /mb-active-plans -->"
    if re.search(r'(?m)^## Active plans\s*$', text):
        text = re.sub(
            r'(?m)^(## Active plans\s*\n)',
            lambda m: m.group(1) + "\n" + block + "\n",
            text,
            count=1,
        )
    else:
        text = text.rstrip("\n") + "\n\n## Active plans\n\n" + block + "\n"
else:
    # Block exists but entries may be missing — inject them if non-empty and block is empty
    def inject(match):
        inner = match.group(1)
        if entries and not inner.strip():
            return "<!-- mb-active-plans -->\n" + "\n".join(entries) + "\n<!-- /mb-active-plans -->"
        return match.group(0)

    text = re.sub(
        r'<!-- mb-active-plans -->\n(.*?)<!-- /mb-active-plans -->',
        inject,
        text,
        count=1,
        flags=re.DOTALL,
    )

text = re.sub(r'\n{3,}', '\n\n', text)
open(path, "w", encoding="utf-8").write(text)
PY
  echo "[apply] plan.md migrated"
fi

# ─── STATUS.md: ensure mb-active-plans + mb-recent-done blocks ──────────────
if [ -f "$STATUS" ]; then
  python3 - "$STATUS" <<'PY'
import re
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
changed = False

if "<!-- mb-active-plans -->" not in text:
    block = (
        "\n## Active plans\n\n"
        "<!-- mb-active-plans -->\n"
        "<!-- /mb-active-plans -->\n"
    )
    text = text.rstrip("\n") + "\n" + block
    changed = True

if "<!-- mb-recent-done -->" not in text:
    block = (
        "\n## Recently done\n\n"
        "<!-- mb-recent-done -->\n"
        "<!-- /mb-recent-done -->\n"
    )
    text = text.rstrip("\n") + "\n" + block
    changed = True

if changed:
    text = re.sub(r'\n{3,}', '\n\n', text)
    open(path, "w", encoding="utf-8").write(text)
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

# Strip common placeholders
text = re.sub(r'(?m)^[\s]*\(\u043f\u043e\u043a\u0430 \u043d\u0435\u0442\)[\s]*$', '', text)
text = re.sub(r'(?m)^[\s]*\(empty\)[\s]*$', '', text)

if not re.search(r'(?m)^# ', text):
    text = "# Backlog\n\n" + text.lstrip("\n")

if not re.search(r'(?m)^## Ideas\s*$', text):
    text = text.rstrip("\n") + "\n\n## Ideas\n"

if not re.search(r'(?m)^## ADR\s*$', text):
    text = text.rstrip("\n") + "\n\n## ADR\n"

text = re.sub(r'\n{3,}', '\n\n', text).rstrip("\n") + "\n"
open(path, "w", encoding="utf-8").write(text)
PY
  echo "[apply] BACKLOG.md skeleton ensured"
fi

echo "[apply] v3.1 structural migration complete"
exit 0
