#!/usr/bin/env bash
# mb-status-rotate.sh — archive dated `## ` sections of status.md into progress.md.
#
# Usage:
#   mb-status-rotate.sh [--keep N] [--dry-run|--apply] [--mb <path>]
#
# Rules:
#   - A `## ` section is "dated" when its heading contains YYYY-MM-DD.
#   - The first N dated sections in file order (default 3) stay; every dated
#     section past them moves verbatim into progress.md as a block
#     `## [status archive] <heading text>` + the original body.
#   - Undated sections (`## Current phase`, `## Open backlog`, `## ⏭ …`) and the
#     preamble above the first `## ` never move; survivor order is unchanged.
#   - Appends go through mb-work-progress-append.sh (locked, atomic, append-only).
#     That helper is fail-safe — on lock timeout it warns and exits 0 WITHOUT
#     appending — so every block is verified present in progress.md before
#     status.md is touched. A missing block aborts with exit 1, status.md as is.
#   - `--apply` writes `<mb>/.status.md.bak.<unix-ts>` and replaces status.md
#     atomically (mktemp + mv); `--dry-run` (default) only prints the plan.
#   - Idempotent: a rerun finds nothing past --keep and no-ops.
#
# Exit codes: 0 success or no-op; 1 argument error or unverified append.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

MODE="dry-run"
KEEP=3
MB_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply)   MODE="apply"; shift ;;
    --keep)    KEEP="${2:-}"; shift 2 ;;
    --keep=*)  KEEP="${1#--keep=}"; shift ;;
    --mb)      MB_ARG="${2:-}"; shift 2 ;;
    --mb=*)    MB_ARG="${1#--mb=}"; shift ;;
    --help|-h)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*)
      echo "[error] unknown flag: $1" >&2
      echo "Usage: mb-status-rotate.sh [--keep N] [--dry-run|--apply] [--mb <path>]" >&2
      exit 1 ;;
    *)
      [ -z "$MB_ARG" ] && MB_ARG="$1"
      shift ;;
  esac
done

case "$KEEP" in
  ''|*[!0-9]*)
    echo "[error] --keep expects a non-negative integer, got: '$KEEP'" >&2
    exit 1 ;;
esac

MB_PATH_RAW=$(mb_resolve_path "$MB_ARG")
if [ ! -d "$MB_PATH_RAW" ]; then
  echo "[error] .memory-bank not found at: $MB_PATH_RAW" >&2
  exit 1
fi
MB_PATH=$(cd "$MB_PATH_RAW" && pwd)
STATUS="$MB_PATH/status.md"
PROGRESS="$MB_PATH/progress.md"

if [ ! -f "$STATUS" ]; then
  echo "[info] no status.md at $STATUS — nothing to rotate"
  exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Section parsing in bash is brittle; python owns it and hands back plain files.
MB_STATUS="$STATUS" MB_KEEP="$KEEP" MB_WORK="$WORK" python3 - <<'PY'
import os
import re

path = os.environ["MB_STATUS"]
keep = int(os.environ["MB_KEEP"])
work = os.environ["MB_WORK"]

lines = open(path, encoding="utf-8").read().splitlines(keepends=True)
H2_RE = re.compile(r"^##\s")
DATE_RE = re.compile(r"\d{4}-\d{2}-\d{2}")

starts = [i for i, ln in enumerate(lines) if H2_RE.match(ln)]
archive = []  # (start, end, heading)
seen_dated = 0
for k, start in enumerate(starts):
    end = starts[k + 1] if k + 1 < len(starts) else len(lines)
    heading = lines[start].rstrip("\n")[3:].strip()
    if not DATE_RE.search(heading):
        continue
    seen_dated += 1
    if seen_dated > keep:
        archive.append((start, end, heading))

with open(os.path.join(work, "count"), "w", encoding="utf-8") as fh:
    fh.write(f"{len(archive)}\n")

if not archive:
    print(f"# No dated section past --keep {keep} — nothing to archive.")
    raise SystemExit(0)

print(f"# Sections to archive ({len(archive)}, keeping the first {keep} dated):")
for n, (start, end, heading) in enumerate(archive, 1):
    print(f"  archive: {heading}")
    body = "".join(lines[start + 1:end]).rstrip("\n")
    with open(os.path.join(work, f"arch-{n:03d}.txt"), "w", encoding="utf-8") as fh:
        fh.write(f"## [status archive] {heading}\n{body}\n")

dropped = {i for start, end, _h in archive for i in range(start, end)}
out = "".join(ln for i, ln in enumerate(lines) if i not in dropped)
if not out.endswith("\n"):
    out += "\n"
with open(os.path.join(work, "status-new.txt"), "w", encoding="utf-8") as fh:
    fh.write(out)
PY

COUNT=$(cat "$WORK/count")
if [ "$COUNT" -eq 0 ]; then
  exit 0
fi

if [ "$MODE" != "apply" ]; then
  echo "[dry-run] nothing written — rerun with --apply to archive $COUNT section(s)"
  exit 0
fi

# Append first, verify each block landed, and only then touch status.md: the
# helper's fail-safe exit 0 would otherwise let a section vanish from status.md
# without ever reaching progress.md.
for block_file in "$WORK"/arch-*.txt; do
  heading=$(head -n 1 "$block_file")
  bash "$SCRIPT_DIR/mb-work-progress-append.sh" --text "$(cat "$block_file")" --mb "$MB_PATH"
  if ! grep -qxF -- "$heading" "$PROGRESS" 2>/dev/null; then
    echo "[error] append did not land in progress.md: $heading" >&2
    echo "[error] status.md left untouched — retry once the append lock is free" >&2
    exit 1
  fi
done

TS=$(date +%s)
cp "$STATUS" "$MB_PATH/.status.md.bak.$TS"
TMP=$(mktemp "$MB_PATH/.status.rotate.XXXXXX")
cp -p "$STATUS" "$TMP"
cat "$WORK/status-new.txt" > "$TMP"
mv -f "$TMP" "$STATUS"
echo "[apply] archived $COUNT section(s) to progress.md; wrote $STATUS (backup: .status.md.bak.$TS)"
