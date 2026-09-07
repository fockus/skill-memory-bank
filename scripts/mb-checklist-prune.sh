#!/usr/bin/env bash
# mb-checklist-prune.sh — checklist.md compactor + v1→v2 migrator.
#
# Usage:
#   mb-checklist-prune.sh [--dry-run|--apply] [--mb <path>]
#
# Rules (v2 format, AGR-043 — information is never deleted):
#   - Per-stage `<!-- mb-plan:<file> -->` + `## Stage N: …` blocks of one plan
#     collapse into a single v2 block `## <title> — k/n` with one line per stage.
#   - A block whose plan now lives in `plans/done/`, and any fully-done `### `
#     section linking `plans/done/…`, moves VERBATIM into progress.md under
#     `## [checklist archive] <date> — <label>`; the checklist is only rewritten
#     once that append is confirmed on disk.
#   - Open `⬜` lines are never moved. `## ⏳ In flight` / `## ⏭ Next planned`
#     are never touched.
#   - Line cap: MB_CHECKLIST_MAX_LINES -> `<mb>/.mb-config` `checklist_max_lines=`
#     -> 100. Still over cap after compaction → exit 3 with a per-plan diagnostic
#     (a signal to pause or close plans — live work is never cut to fit).
#   - On `--apply`: writes `<mb>/.checklist.md.bak.<unix-ts>` when content changes.
#
# Exit codes: 0 success/no-op, 1 argument or bank error, 3 still over cap.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECKLIST_V2="$SCRIPT_DIR/mb-checklist-v2.py"
APPEND_SH="$SCRIPT_DIR/mb-work-progress-append.sh"

MODE="dry-run"
MB_ARG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) MODE="dry-run"; shift ;;
    --apply)   MODE="apply"; shift ;;
    --mb)      MB_ARG="${2:-}"; shift 2 ;;
    --help|-h)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    --*)
      echo "[error] unknown flag: $1" >&2
      echo "Usage: mb-checklist-prune.sh [--dry-run|--apply] [--mb <path>]" >&2
      exit 1 ;;
    *)
      [ -z "$MB_ARG" ] && MB_ARG="$1"
      shift ;;
  esac
done

MB_PATH_RAW=$(mb_resolve_path "$MB_ARG")
if [ ! -d "$MB_PATH_RAW" ]; then
  echo "[error] .memory-bank not found at: $MB_PATH_RAW" >&2
  exit 1
fi
MB_PATH=$(cd "$MB_PATH_RAW" && pwd)
CHECKLIST="$MB_PATH/checklist.md"

if [ ! -f "$CHECKLIST" ]; then
  echo "[info] no checklist.md at $CHECKLIST — nothing to prune"
  exit 0
fi

# Cap: env -> `<mb>/.mb-config` -> default. A non-numeric value falls back.
CAP_DEFAULT=100
_resolve_cap() {
  local raw=""
  if [ -n "${MB_CHECKLIST_MAX_LINES:-}" ]; then
    raw="$MB_CHECKLIST_MAX_LINES"
  elif [ -f "$MB_PATH/.mb-config" ] && [ ! -L "$MB_PATH/.mb-config" ]; then
    raw=$(grep -E '^checklist_max_lines=' "$MB_PATH/.mb-config" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  fi
  case "$raw" in ''|*[!0-9]*) raw="$CAP_DEFAULT" ;; esac
  printf '%s\n' "$raw"
}
CAP=$(_resolve_cap)
PLANS_DIR="$MB_PATH/plans"
TODAY=$(date +%Y-%m-%d)

CANDIDATES=$(python3 "$CHECKLIST_V2" plan --checklist "$CHECKLIST" --plans-dir "$PLANS_DIR")

if [ -z "$CANDIDATES" ]; then
  echo "# No archive candidates."
else
  echo "# Archive candidates:"
  printf '%s\n' "$CANDIDATES" | while IFS=$'\t' read -r _key label _blob; do
    echo "  archive: $label → progress.md"
  done
fi

if [ "$MODE" != "apply" ]; then
  exit 0
fi

# Archive each candidate BEFORE it leaves the checklist: append, then verify the
# heading is on disk. An unconfirmed append (lock held, write error) drops the
# candidate — the block stays in the checklist rather than vanishing.
PROGRESS="$MB_PATH/progress.md"
DROP_ARGS=()
if [ -n "$CANDIDATES" ]; then
  while IFS=$'\t' read -r key label blob; do
    [ -n "$key" ] || continue
    heading="## [checklist archive] $TODAY — $label"
    if [ ! -f "$PROGRESS" ] || ! grep -qxF "$heading" "$PROGRESS"; then
      body=$(printf '%s' "$blob" | base64 -d)
      bash "$APPEND_SH" --text "$heading"$'\n\n'"$body" --mb "$MB_PATH" || true
    fi
    if [ -f "$PROGRESS" ] && grep -qxF "$heading" "$PROGRESS"; then
      DROP_ARGS+=(--drop "$key")
    else
      echo "[warn] archive append unconfirmed for '$label' — leaving it in checklist.md" >&2
    fi
  done <<< "$CANDIDATES"
fi

set +e
python3 "$CHECKLIST_V2" apply --checklist "$CHECKLIST" --plans-dir "$PLANS_DIR" \
  --cap "$CAP" "${DROP_ARGS[@]+"${DROP_ARGS[@]}"}"
rc=$?
set -e
exit "$rc"
