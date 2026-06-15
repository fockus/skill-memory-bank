#!/usr/bin/env bash
# mb-goal-acceptance.sh — L5 goal-acceptance aggregator (REQ-DF-042).
#
# Aggregates the `[x]/N` ratio from a goal.md's `## Acceptance criteria`
# section and reports whether every criterion is satisfied. Parses the SAME
# way as scripts/mb-goal-validate.sh's `acceptance_item_count`: checkbox lines
# inside Markdown code fences (``` / ~~~) are ignored, and only items under an
# active `## Acceptance criteria` heading are counted.
#
# Per ADR-3 this is a CHECK RUNNER, not the firewall: it ALWAYS exits 0 and
# reports pass/fail/skip ONLY through the JSON `ok` field. The L5 fan-out
# (mb-flow-verify.sh) owns exit codes.
#
# Usage:
#   mb-goal-acceptance.sh [goal-path] [mb_path]
#     goal-path : optional explicit path to a goal.md
#                 (default: <mb>/goal.md, mb via mb_resolve_path; an empty
#                  first arg "" also falls back to the resolved default)
#     mb_path   : optional explicit Memory Bank path (overrides mb_resolve_path)
#
# Output (stdout, always exit 0):
#   {"name":"acceptance","ok":true|false|null,"findings":[ unchecked-items ]}
#     ok=true   → N>=1 criteria AND all are [x]; findings=[]
#     ok=false  → >=1 unchecked criterion; findings list the unchecked items
#     ok=null   → no goal.md OR zero acceptance criteria (skip / N/A)

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

GOAL_PATH=""
MB_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
    *)
      if [[ -z "$GOAL_PATH" && -z "${GOAL_SET:-}" ]]; then
        GOAL_PATH="$1"
        GOAL_SET=1
      elif [[ -z "$MB_ARG" && -z "${MB_SET:-}" ]]; then
        MB_ARG="$1"
        MB_SET=1
      else
        echo "too many arguments: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

MB_PATH="$(mb_resolve_path "$MB_ARG")"
[[ -z "$GOAL_PATH" ]] && GOAL_PATH="$MB_PATH/goal.md"

# ---- helpers ----------------------------------------------------------------

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

# Emit the runner JSON and exit 0. $1 = ok literal (true|false|null);
# remaining positional args are finding strings.
emit() {
  local ok="$1"; shift
  printf '{"name":"acceptance","ok":%s,"findings":[' "$ok"
  local i=0 f
  for f in "$@"; do
    (( i > 0 )) && printf ','
    json_escape "$f"
    i=$((i + 1))
  done
  printf ']}\n'
  exit 0
}

# ---- skip: missing goal -----------------------------------------------------

if [[ ! -f "$GOAL_PATH" ]]; then
  echo "[acceptance] no goal.md at $GOAL_PATH — skipping (ok=null)" >&2
  emit null
fi

# ---- count + collect unchecked items (code-fence-aware) ---------------------
# Parity with mb-goal-validate.sh::acceptance_item_count — same fence state
# machine + same `## Acceptance criteria` section gating. We additionally
# distinguish [x]/[X] (done) from [ ] (pending) and print the pending item
# texts so findings can name them.
#
# Output protocol on stdout:
#   line 1: "<total> <done>"
#   lines 2..: one pending-item text per line (label only)
PARSE="$(
  awk '
    BEGIN {
      in_acc = 0; in_fence = 0; fence_marker = ""
      total = 0; done = 0
    }
    /^[[:space:]]*(```|~~~)/ {
      if (!in_fence) {
        match($0, /^[[:space:]]*(```+|~~~+)/)
        fence_marker = substr($0, RSTART, RLENGTH)
        gsub(/^[[:space:]]+/, "", fence_marker)
        in_fence = 1
        next
      } else {
        line = $0
        gsub(/^[[:space:]]+/, "", line)
        if (index(line, fence_marker) == 1) {
          in_fence = 0; fence_marker = ""; next
        }
      }
    }
    in_fence { next }
    /^##[[:space:]]+[Aa]cceptance[[:space:]]+criteria[[:space:]]*$/ { in_acc = 1; next }
    in_acc && /^#/ { in_acc = 0 }
    in_acc && /^[[:space:]]*-[[:space:]]+\[[ xX]\]/ {
      total++
      if ($0 ~ /^[[:space:]]*-[[:space:]]+\[[xX]\]/) {
        done++
      } else {
        label = $0
        sub(/^[[:space:]]*-[[:space:]]+\[[ xX]\][[:space:]]*/, "", label)
        pending[++p] = label
      }
    }
    END {
      print total " " done
      for (i = 1; i <= p; i++) print pending[i]
    }
  ' "$GOAL_PATH"
)"

TOTAL="$(printf '%s\n' "$PARSE" | sed -n '1p' | awk '{print $1}')"
DONE="$(printf '%s\n' "$PARSE" | sed -n '1p' | awk '{print $2}')"
TOTAL="${TOTAL:-0}"
DONE="${DONE:-0}"

# Collect pending labels (lines 2..) into an array.
PENDING=()
while IFS= read -r label; do
  [[ -z "$label" ]] && continue
  PENDING+=("$label")
done < <(printf '%s\n' "$PARSE" | sed -n '2,$p')

# ---- verdict ----------------------------------------------------------------

if [[ "$TOTAL" -lt 1 ]]; then
  echo "[acceptance] zero acceptance criteria in $GOAL_PATH — skipping (ok=null)" >&2
  emit null
fi

if [[ "$DONE" -eq "$TOTAL" ]]; then
  emit true
fi

emit false "${PENDING[@]+"${PENDING[@]}"}"
