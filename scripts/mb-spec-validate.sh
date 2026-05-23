#!/usr/bin/env bash
# mb-spec-validate.sh — validate the integrity of a Kiro-style spec triple.
#
# A spec triple lives at `<mb>/specs/<topic>/` and contains:
#   - requirements.md  (EARS REQ list)
#   - design.md        (architecture / interfaces / decisions / risks)
#   - tasks.md         (numbered tasks with <!-- mb-task:N --> markers)
#
# Checks performed (each violation → one entry on stderr / JSON list):
#   1. requirements.md exists and passes `mb-ears-validate.sh`.
#   2. tasks.md exists and `mb_work_items.parse_work_items()` returns ≥ 1 item.
#   3. Each task has a non-empty `**Covers:**` field.
#   4. Each task has ≥ 1 DoD checkbox line.
#   5. Each task body contains a `Testing` section (case-insensitive).
#   6. Each REQ-NNN from requirements.md is referenced by ≥ 1 task's covers.
#
# Usage:
#   mb-spec-validate.sh [--json] <topic|spec-dir|spec-file> [mb_path]
#
# Resolver:
#   - If the first non-flag argument points to an existing directory or file →
#     used directly (a file is treated as its parent directory).
#   - Otherwise → resolved to `<mb>/specs/<arg>/` (mb defaults via `mb_resolve_path`).
#
# Exit codes:
#   0 — clean (no violations)
#   1 — one or more violations (details on stderr; --json prints structured)
#   2 — usage / resolver error

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

JSON_MODE=0
TARGET=""
MB_ARG=""

for arg in "$@"; do
  case "$arg" in
    --json) JSON_MODE=1 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      if [ -z "$TARGET" ]; then
        TARGET="$arg"
      else
        MB_ARG="$arg"
      fi
      ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "Usage: mb-spec-validate.sh [--json] <topic|spec-dir|spec-file> [mb_path]" >&2
  exit 2
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
EARS_SCRIPT="$SCRIPT_DIR/mb-ears-validate.sh"
WORK_ITEMS_SCRIPT="$SCRIPT_DIR/mb_work_items.py"

# ─────────────────────────────────────────────────────────────────────────────
# Resolve the spec directory.
# ─────────────────────────────────────────────────────────────────────────────

SPEC_DIR=""
if [ -d "$TARGET" ]; then
  SPEC_DIR="$TARGET"
elif [ -f "$TARGET" ]; then
  SPEC_DIR=$(dirname "$TARGET")
else
  # Treat as topic; resolve under <mb>/specs/<topic>/.
  MB_PATH=$(mb_resolve_path "$MB_ARG")
  if [ -z "$MB_PATH" ] || [ ! -d "$MB_PATH" ]; then
    echo "[error] memory bank not found at: ${MB_PATH:-<unset>}" >&2
    exit 2
  fi
  SAFE_TOPIC=$(mb_sanitize_topic "$TARGET")
  if [ -z "$SAFE_TOPIC" ]; then
    echo "[error] topic contains only non-ASCII characters: $TARGET" >&2
    exit 2
  fi
  SPEC_DIR="$MB_PATH/specs/$SAFE_TOPIC"
  if [ ! -d "$SPEC_DIR" ]; then
    echo "[error] spec directory not found: $SPEC_DIR" >&2
    exit 2
  fi
fi

REQ_FILE="$SPEC_DIR/requirements.md"
TASKS_FILE="$SPEC_DIR/tasks.md"

# ─────────────────────────────────────────────────────────────────────────────
# Collect violations into a temp file so we can both print them and emit JSON.
# ─────────────────────────────────────────────────────────────────────────────

VIOLATIONS_FILE=$(mktemp -t mb-spec-validate.XXXXXX)
trap 'rm -f "$VIOLATIONS_FILE"' EXIT

record_violation() {
  printf '%s\n' "$1" >>"$VIOLATIONS_FILE"
}

# ─────────────────────────────────────────────────────────────────────────────
# Check 1: requirements.md exists + EARS valid.
# ─────────────────────────────────────────────────────────────────────────────

if [ ! -f "$REQ_FILE" ]; then
  record_violation "requirements.md missing in $SPEC_DIR"
else
  EARS_STDERR=$(bash "$EARS_SCRIPT" "$REQ_FILE" 2>&1 >/dev/null) || EARS_EXIT=$?
  EARS_EXIT="${EARS_EXIT:-0}"
  if [ "$EARS_EXIT" -ne 0 ]; then
    while IFS= read -r line; do
      [ -n "$line" ] && record_violation "EARS: $line"
    done <<<"$EARS_STDERR"
  fi
  unset EARS_EXIT
fi

# ─────────────────────────────────────────────────────────────────────────────
# Check 2: tasks.md exists + parses to ≥ 1 WorkItem.
# ─────────────────────────────────────────────────────────────────────────────

TASKS_JSONL=""
if [ ! -f "$TASKS_FILE" ]; then
  record_violation "tasks.md missing in $SPEC_DIR"
else
  if ! TASKS_JSONL=$(python3 "$WORK_ITEMS_SCRIPT" "$TASKS_FILE" 2>&1); then
    record_violation "tasks.md unparseable: ${TASKS_JSONL//$'\n'/ | }"
    TASKS_JSONL=""
  fi

  if [ -n "$TASKS_JSONL" ]; then
    TASK_COUNT=$(printf '%s\n' "$TASKS_JSONL" | grep -c . || true)
    if [ "$TASK_COUNT" -eq 0 ]; then
      record_violation "tasks.md contains no <!-- mb-task:N --> markers"
    fi
  else
    # Empty stdout from parser is legitimate only when tasks.md is empty.
    # Treat that as "no tasks" violation too.
    if [ -f "$TASKS_FILE" ]; then
      record_violation "tasks.md contains no <!-- mb-task:N --> markers"
    fi
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Checks 3-5: per-task validation (covers, DoD, Testing section).
# Check 6: REQ orphan detection.
# ─────────────────────────────────────────────────────────────────────────────

if [ -n "$TASKS_JSONL" ] && [ -f "$REQ_FILE" ]; then
  TASKS_DATA="$TASKS_JSONL" REQ_PATH="$REQ_FILE" \
    python3 - >>"$VIOLATIONS_FILE" <<'PY'
import json
import os
import re

tasks_raw = os.environ.get("TASKS_DATA", "")
req_path = os.environ.get("REQ_PATH", "")

tasks = []
for line in tasks_raw.splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        tasks.append(json.loads(line))
    except json.JSONDecodeError:
        # Already reported by check 2; skip silently here.
        continue

req_text = ""
if req_path and os.path.exists(req_path):
    with open(req_path, encoding="utf-8") as fh:
        req_text = fh.read()
req_ids = set(re.findall(r"\bREQ-(\d{3,})\b", req_text))

covered = set()
testing_re = re.compile(r"\btesting\b", re.IGNORECASE)
for item in tasks:
    no = item.get("item_no", "?")
    covers = item.get("covers") or []
    if not covers:
        print(f"task {no} missing Covers field")
    for c in covers:
        m = re.match(r"REQ-(\d{3,})$", str(c))
        if m:
            covered.add(m.group(1))
    if not item.get("dod_lines"):
        print(f"task {no} missing DoD checkboxes")
    body = item.get("body") or ""
    if not testing_re.search(body):
        print(f"task {no} missing Testing section")

for req in sorted(req_ids):
    if req not in covered:
        print(f"REQ-{req} orphan (no task Covers)")
PY
fi

# ─────────────────────────────────────────────────────────────────────────────
# Emit results.
# ─────────────────────────────────────────────────────────────────────────────

if [ "$JSON_MODE" -eq 1 ]; then
  VIOL_FILE="$VIOLATIONS_FILE" python3 - <<'PY'
import json
import os

path = os.environ["VIOL_FILE"]
violations = []
if os.path.exists(path):
    with open(path, encoding="utf-8") as fh:
        violations = [line.rstrip("\n") for line in fh if line.strip()]
print(json.dumps({"violations": violations}, ensure_ascii=False))
PY
fi

if [ -s "$VIOLATIONS_FILE" ]; then
  if [ "$JSON_MODE" -eq 0 ]; then
    while IFS= read -r line; do
      printf '[spec-validate] %s\n' "$line" >&2
    done <"$VIOLATIONS_FILE"
  fi
  exit 1
fi

exit 0
