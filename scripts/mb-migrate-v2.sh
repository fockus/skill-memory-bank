#!/usr/bin/env bash
# mb-migrate-v2.sh — one-shot v1 → v2 migrator for .memory-bank/
#
# Renames STATUS/BACKLOG/RESEARCH/plan → lowercase status/backlog/research/roadmap,
# transforms plan.md → roadmap.md content structure, fixes references,
# creates a timestamped backup.
#
# Usage: mb-migrate-v2.sh [--dry-run|--apply] [mb_path]

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
      echo "Usage: mb-migrate-v2.sh [--dry-run|--apply] [mb_path]" >&2
      exit 1
      ;;
    *) MB_ARG="$arg" ;;
  esac
done

MB_PATH=$(mb_resolve_path "$MB_ARG")
[ -d "$MB_PATH" ] || { echo "[error] .memory-bank not found at: $MB_PATH" >&2; exit 1; }
MB_PATH=$(cd "$MB_PATH" && pwd)

# === Detection ===
# Using parallel arrays (bash 3.2 compatible — macOS default shell).
RENAMES_OLD=("STATUS.md" "BACKLOG.md" "RESEARCH.md" "plan.md")
RENAMES_NEW=("status.md" "backlog.md" "research.md" "roadmap.md")

# NOTE: plain -f tests are unreliable on macOS default APFS (case-insensitive):
# STATUS.md and status.md resolve to the same inode, so `[ -f status.md ]` would
# return true just because STATUS.md exists. Use case-sensitive `find -name` to
# check whether a distinct v2 file is already present.
planned_renames=()
for i in "${!RENAMES_OLD[@]}"; do
  old="${RENAMES_OLD[$i]}"
  new="${RENAMES_NEW[$i]}"
  old_hit=$(find "$MB_PATH" -maxdepth 1 -type f -name "$old" -print -quit 2>/dev/null || true)
  new_hit=$(find "$MB_PATH" -maxdepth 1 -type f -name "$new" -print -quit 2>/dev/null || true)
  if [ -n "$old_hit" ] && [ -z "$new_hit" ]; then
    planned_renames+=("$old → $new")
  fi
done

if [ "${#planned_renames[@]}" -eq 0 ]; then
  echo "[ok] no v1 files detected — nothing to migrate"
  exit 0
fi

echo "[detected] v1 layout — planned renames:"
for r in "${planned_renames[@]}"; do
  echo "  - $r"
done

if [ "$MODE" = "dry-run" ]; then
  echo "[dry-run] no files changed — run with --apply to execute"
  exit 0
fi

# === Backup ===
ts=$(date +%Y%m%d-%H%M%S)
backup_dir="$MB_PATH/.migration-backup-$ts"
mkdir -p "$backup_dir"
for i in "${!RENAMES_OLD[@]}"; do
  old="${RENAMES_OLD[$i]}"
  old_hit=$(find "$MB_PATH" -maxdepth 1 -type f -name "$old" -print -quit 2>/dev/null || true)
  if [ -n "$old_hit" ]; then
    cp "$old_hit" "$backup_dir/$old"
  fi
done
echo "[backup] saved to $backup_dir"

# === Rename ===
# Two-step rename via temporary name to handle case-insensitive FS (macOS APFS):
# `mv STATUS.md status.md` errors with "same file" on APFS because both names
# resolve to the same inode. Detour through .tmp-rename-N to force a distinct name.
for i in "${!RENAMES_OLD[@]}"; do
  old="${RENAMES_OLD[$i]}"
  new="${RENAMES_NEW[$i]}"
  old_hit=$(find "$MB_PATH" -maxdepth 1 -type f -name "$old" -print -quit 2>/dev/null || true)
  new_hit=$(find "$MB_PATH" -maxdepth 1 -type f -name "$new" -print -quit 2>/dev/null || true)
  if [ -n "$old_hit" ] && [ -z "$new_hit" ]; then
    tmp="$MB_PATH/.tmp-rename-$i"
    mv "$old_hit" "$tmp"
    mv "$tmp" "$MB_PATH/$new"
    echo "[renamed] $old → $new"
  fi
done

# === Content transform: roadmap.md ===
# Transforms v1 plan.md content into v2 roadmap format. Preserves the legacy
# <!-- mb-active-plan --> block by relocating it into the new ## Now section.
if [ -f "$MB_PATH/roadmap.md" ]; then
  python3 - "$MB_PATH/roadmap.md" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")

# Idempotency guard — if the file already has the v2 shape, leave it alone.
if "## Now (in progress)" in text and "## Next" in text:
    sys.exit(0)

# Extract legacy active-plan block (if any).
m = re.search(r"<!-- mb-active-plan -->.*?<!-- /mb-active-plan -->", text, re.DOTALL)
active_plan_block = m.group(0) if m else ""

# Strip old top heading and active-plan block from source body.
body = re.sub(r"^\s*#\s+Plan\s*\n+", "", text, count=1)
body = re.sub(
    r"<!-- mb-active-plan -->.*?<!-- /mb-active-plan -->\n*",
    "",
    body,
    flags=re.DOTALL,
)

# Build new roadmap.
now_section = "## Now (in progress)\n\n"
if active_plan_block:
    now_section += active_plan_block + "\n"
else:
    now_section += "_No active plan. Run /mb plan <type> <topic> to start._\n"

new_roadmap = f"""# Roadmap

_Last updated: auto-synced by mb-roadmap-sync.sh_

{now_section}
## Next (strict order — depends)

_Queued plans appear here. See plans/*.md frontmatter: depends_on._

## Parallel-safe (can run now)

_Independent plans. See plans/*.md frontmatter: parallel_safe: true._

## Paused / Archived

_Plans in paused/cancelled state._

## Linked Specs (active)

_Active specs/<topic>/ directories._

## See also
- traceability.md — REQ coverage matrix
- backlog.md — future ideas & ADR
- checklist.md — current in-flight tasks

---

### Legacy content (from v1 plan.md — review and integrate above)

{body.strip()}
"""

path.write_text(new_roadmap, encoding="utf-8")
print(f"[transformed] {path}")
PY
fi

# === Reference fixup inside .memory-bank/ .md files ===
# Rewrites cross-references in all .md files under $MB_PATH (excluding the
# backup directory). STATUS.md / BACKLOG.md / RESEARCH.md → lowercase.
# plan.md → roadmap.md ONLY when used as a file reference (word-boundary
# preceded by a non-identifier char), not when "plan" appears in prose.
python3 - "$MB_PATH" <<'PY'
import re
import sys
from pathlib import Path

mb = Path(sys.argv[1])
replacements = [
    (re.compile(r"\bSTATUS\.md\b"), "status.md"),
    (re.compile(r"\bBACKLOG\.md\b"), "backlog.md"),
    (re.compile(r"\bRESEARCH\.md\b"), "research.md"),
    # plan.md → roadmap.md: only when preceded by path separator or start of
    # word (non-identifier char) to avoid mangling prose. Matches:
    #   "see plan.md"       → yes   (space before)
    #   "plans/plan.md"     → yes   (slash before)
    #   "the plan.md file"  → yes   (space before)
    # Does not match:
    #   "explanation.md"    → no    ("a" before "plan", identifier char)
    (re.compile(r"(?<![A-Za-z0-9_\-])plan\.md\b"), "roadmap.md"),
]

# Exclude any .migration-backup-* directory under $MB_PATH.
skip_prefixes = tuple(str(p.resolve()) for p in mb.glob(".migration-backup-*"))

updated = 0
for md in mb.rglob("*.md"):
    resolved = str(md.resolve())
    if any(resolved.startswith(p) for p in skip_prefixes):
        continue
    original = md.read_text(encoding="utf-8")
    new_text = original
    for pat, repl in replacements:
        new_text = pat.sub(repl, new_text)
    if new_text != original:
        md.write_text(new_text, encoding="utf-8")
        rel = md.relative_to(mb)
        print(f"[refs] updated {rel}")
        updated += 1

print(f"[refs] {updated} file(s) updated")
PY

echo "[ok] migration complete — backup at $backup_dir"
