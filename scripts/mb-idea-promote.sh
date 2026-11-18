#!/usr/bin/env bash
# mb-idea-promote.sh — promote a READY idea (I-NNN) into an active plan.
#
# Usage:
#   mb-idea-promote.sh <I-NNN> <type> [mb_path]
#     type ∈ feature|fix|refactor|experiment
#
# Effects (design.md C7), all under <bank>/.locks/backlog.lock:
#   1. Read the entry; only state READY may be promoted (needs a valid **Brief:**).
#   2. Create the plan via mb-plan.sh (or reuse the plan a failed earlier run created).
#   3. Apply READY → IN-PROGRESS + `**Plan:** [plans/..](plans/..)` in ONE atomic
#      write through the shared mb_backlog_transition_locked primitive.
#   4. Run mb-plan-sync.sh so the plan appears in the active-plans blocks.
# A failure after the plan exists → exit 1, stderr
# `code=promote_partial plan=<bank-relative path> backlog_updated=<true|false>`;
# re-running the same promote finishes the missing step without a second plan.
#
# Path to READY: NEW → NEEDS-INFO → TRIAGED → READY (annotate a Brief) via
# mb-backlog-state.sh. The legacy PLANNED token is never written.
#
# Exit codes: 0 OK, 1 missing files / idea not found / unknown status / failed
# write, 2 domain refusal (not READY, already in progress/closed, legacy token),
# 3 invalid type.
# Test seam: MB_PROMOTE_FAULT=after_plan|after_rename injects a failure at that point.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

ID="${1:?Usage: mb-idea-promote.sh <I-NNN> <type> [mb_path]}"
TYPE="${2:?Usage: mb-idea-promote.sh <I-NNN> <type> [mb_path]}"
MB_PATH=$(mb_resolve_path "${3:-}")

case "$TYPE" in
  feature|fix|refactor|experiment) ;;
  *) echo "[error] Invalid type: $TYPE (feature|fix|refactor|experiment)" >&2; exit 3 ;;
esac

BACKLOG="$MB_PATH/backlog.md"
[ -f "$BACKLOG" ] || { echo "[error] backlog.md not found: $BACKLOG" >&2; exit 1; }

if ! [[ "$ID" =~ ^I-[0-9]{3}$ ]]; then
  echo "[error] Invalid ID format: $ID (expected I-NNN)" >&2
  exit 1
fi

LOCK_DIR="$MB_PATH/.locks/backlog.lock"
mkdir -p "$MB_PATH/.locks"
if ! LOCK_TOKEN="$(mb_lock_acquire "$LOCK_DIR" "${MB_BACKLOG_LOCK_TIMEOUT:-10}" "${MB_BACKLOG_LOCK_TTL:-120}")"; then
  echo "[error] could not acquire backlog lock: $LOCK_DIR" >&2
  exit 1
fi
trap 'mb_lock_release "$LOCK_DIR" "$LOCK_TOKEN" >/dev/null 2>&1 || true' EXIT

engine() { "${MB_PYTHON:-python3}" "$SCRIPT_DIR/mb_backlog_state_engine.py" "$@"; }

idea_line=$(grep -E "^### ${ID} — " "$BACKLOG" | head -1 || true)
if [ -z "$idea_line" ]; then
  echo "[error] Idea $ID not found in backlog.md" >&2
  exit 1
fi

title=$("${MB_PYTHON:-python3}" - "$idea_line" "$ID" <<'PY'
import re, sys
line, idea_id = sys.argv[1], sys.argv[2]
m = re.match(
    rf"^### {re.escape(idea_id)} — (?P<title>.*?) \[(?P<prio>[^,]+),\s*(?P<status>[^,]+),\s*(?P<date>[^\]]+)\]$",
    line,
)
print(m.group("title") if m else "")
PY
)
if [ -z "$title" ]; then
  echo "[error] Failed to parse title from idea line: $idea_line" >&2
  exit 1
fi
status=$(engine getstate "$BACKLOG" "$ID") || exit 1

plan_link=$(sed -n "/^### ${ID} — /,/^### /p" "$BACKLOG" | grep -m1 '^\*\*Plan:\*\*' || true)

partial() {  # $1 = backlog_updated
  echo "code=promote_partial plan=plans/$plan_basename backlog_updated=$1" >&2
  exit 1
}

finish_sync() {
  "$SCRIPT_DIR/mb-plan-sync.sh" "$MB_PATH/plans/$plan_basename" "$MB_PATH" >/dev/null || partial true
}

case "$status" in
  READY) ;;
  NEW|NEEDS-INFO|TRIAGED)
    echo "[error] Idea $ID is $status — promote needs READY. Path: mb-backlog-state.sh transition $ID NEEDS-INFO → TRIAGED, annotate --brief, transition $ID READY, then promote" >&2
    exit 2 ;;
  IN-PROGRESS)
    # Heal a previous partial run (backlog written, sync missing); else refuse.
    plan_basename=$(printf '%s' "$plan_link" | sed -n 's/.*(plans\/\([^)]*\)).*/\1/p')
    if [ -n "$plan_basename" ] && [ -f "$MB_PATH/plans/$plan_basename" ] \
       && ! grep -qF "$plan_basename" "$MB_PATH/roadmap.md" 2>/dev/null; then
      finish_sync
      echo "[promote] $ID → $plan_basename (sync completed)"
      printf '%s\n' "$MB_PATH/plans/$plan_basename"
      exit 0
    fi
    echo "[error] Idea $ID is already IN-PROGRESS" >&2; exit 2 ;;
  DONE|WONTFIX)
    echo "[error] Idea $ID is already $status — cannot promote" >&2; exit 2 ;;
  PLANNED|DEFERRED|OPEN|PROPOSED|RESOLVED|DECLINED)
    echo "[error] Idea $ID has legacy status $status — run mb-backlog-migrate.sh first" >&2; exit 2 ;;
  *) echo "[error] Unknown idea status: $status" >&2; exit 1 ;;
esac

# Validate the READY gate BEFORE creating anything (no plan on refusal).
if ! mb_backlog_transition_locked "$BACKLOG" "$ID" IN-PROGRESS --check; then
  echo "[error] Idea $ID cannot enter IN-PROGRESS (READY without a valid **Brief:**?)" >&2
  exit 2
fi

# Reuse the plan a failed earlier run created for this exact idea/type.
SAFE_TOPIC=$(mb_sanitize_topic "$title")
plan_basename=""
for existing in "$MB_PATH"/plans/*_"${TYPE}_${SAFE_TOPIC}".md; do
  [ -f "$existing" ] && plan_basename=$(basename "$existing")
done
if [ -z "$plan_basename" ]; then
  plan_path=$("$SCRIPT_DIR/mb-plan.sh" "$TYPE" "$title" "$MB_PATH")
  plan_basename=$(basename "$plan_path")
fi
plan_path="$MB_PATH/plans/$plan_basename"

[ "${MB_PROMOTE_FAULT:-}" = "after_plan" ] && partial false
mb_backlog_transition_locked "$BACKLOG" "$ID" IN-PROGRESS \
  --plan "[plans/$plan_basename](plans/$plan_basename)" || partial false
[ "${MB_PROMOTE_FAULT:-}" = "after_rename" ] && partial true
finish_sync

echo "[promote] $ID → $plan_basename"
printf '%s\n' "$plan_path"
