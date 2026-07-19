#!/usr/bin/env bash
# mb-estimate-check.sh — deterministic validator for the /mb discuss size
# estimate (svp-interview-upgrade design C1, NFR-002) AND the spec-triple /
# candidate budget gate (svp-sdd-core design C3, REQ-009). Reads token
# estimates, checks their structure, and compares against the configured
# budget. No LLM, no PyYAML dependency.
#
# Usage:
#   mb-estimate-check.sh <context-file> [--spec-budget <positive-int>]   # S1 C1
#   mb-estimate-check.sh --spec <topic|spec-dir> [--mb <bank>]           # S2 C3
#   mb-estimate-check.sh --tasks-file <path> [--mb <bank>]               # S2 C3
#
# Exactly one source. `--spec` + `--tasks-file`, or either combined with the
# positional <context-file>, is a usage error (exit 2).
#
# --- Context-file mode (S1 C1) -------------------------------------------
# Thresholds (D-13; one integer formula for any budget):
#   near_lower = floor(spec_budget * 9 / 10)
#   total < near_lower              → estimate=ok    (exit 0)
#   near_lower <= total <= budget   → estimate=near  (exit 0, advisory)
#   total > budget                  → estimate=over  (exit 1)
# stdout : `estimate=<ok|near|over|missing|malformed> spec.total=<N> spec_budget=<N>`
#
# --- Spec / candidate mode (S2 C3) ---------------------------------------
# Reads only explicitly written `Budget:` fields from the tasks.md task blocks.
# Legacy tasks without the field are excluded from the sums and listed as
# `legacy_missing=<csv>` with a single stderr warning.
# stdout (one key=value per line, both sub-modes identical):
#   task.<id>=<tokens>      (ascending task id, only tasks with explicit Budget)
#   stage.<id>=<tokens>     (ascending stage id)
#   spec.total=<tokens>
#   task_over=<csv|none>    (tasks whose Budget > 120000, D-13 hard cap)
#   stage_over=<csv|none>   (stages whose sum > 400000, D-13 hard cap)
#   spec=<ok|near|over>     (ok <900000; near 900000–1000000; over >1000000)
#   legacy_missing=<csv|none>
# Frontmatter tasks.md `estimated_tokens.{total,stages."<id>"}`, when present,
# must equal the computed sums; a mismatch is an overflow-class error (exit 1),
# not a format break.
# exit : 0 = spec ok/near and no task/stage/spec overflow and frontmatter ok;
#        1 = any task/stage/spec overflow or frontmatter mismatch;
#        2 = usage / unresolvable spec or file / malformed Budget field.
#
# The script is a pure checker: it writes, moves, and deletes nothing, and it
# never reads `budget_override` (the transfer decision belongs to the caller).

set -euo pipefail

# Resolve this script's own physical directory through its FULL symlink chain
# (portable — no realpath on bare macOS) so the sourced parser lib is always
# found next to the real script, not next to a symlink.
_mb_resolve_self_dir() {
  local src="$1" dir
  while [ -h "$src" ]; do
    dir="$(cd -P "$(dirname "$src")" 2>/dev/null && pwd)"
    src="$(readlink "$src")"
    case "$src" in
      /*) ;;
      *) src="$dir/$src" ;;
    esac
  done
  cd -P "$(dirname "$src")" 2>/dev/null && pwd
}
SCRIPT_DIR="$(_mb_resolve_self_dir "$0")"
# shellcheck source=scripts/mb-estimate-lib.sh
. "$SCRIPT_DIR/mb-estimate-lib.sh"

usage_error() { printf 'error=usage\n' >&2; exit 2; }

FILE=""
SPEC_BUDGET=1000000
BUDGET_SET=0
SPEC_TOPIC=""
TASKS_FILE=""
MB_BANK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --spec-budget)
      [ "$#" -ge 2 ] || usage_error
      SPEC_BUDGET="$2"
      BUDGET_SET=1
      shift
      ;;
    --spec)
      [ "$#" -ge 2 ] || usage_error
      [ -z "$SPEC_TOPIC" ] || usage_error
      SPEC_TOPIC="$2"
      shift
      ;;
    --tasks-file)
      [ "$#" -ge 2 ] || usage_error
      [ -z "$TASKS_FILE" ] || usage_error
      TASKS_FILE="$2"
      shift
      ;;
    --mb)
      [ "$#" -ge 2 ] || usage_error
      MB_BANK="$2"
      shift
      ;;
    --*) usage_error ;;
    *)
      [ -z "$FILE" ] || usage_error
      FILE="$1"
      ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Spec / candidate mode (S2 C3): exactly one of --spec / --tasks-file, never
# combined with each other or with the positional <context-file>.
# ---------------------------------------------------------------------------
if [ -n "$SPEC_TOPIC" ] || [ -n "$TASKS_FILE" ]; then
  # Mutual exclusion: no positional context file, not both new flags.
  [ -z "$FILE" ] || usage_error
  if [ -n "$SPEC_TOPIC" ] && [ -n "$TASKS_FILE" ]; then usage_error; fi
  # --spec-budget belongs to the positional context mode only (C3 fixes the
  # spec thresholds at 900k/1M); it is a usage error in spec/candidate mode.
  [ "$BUDGET_SET" -eq 0 ] || usage_error

  if [ -n "$TASKS_FILE" ]; then
    # Candidate mode: read exactly the passed file; never resolve the triple.
    TP="$TASKS_FILE"
  else
    # Accepted-spec mode: explicit spec-dir wins, else <bank>/specs/<topic>.
    if [ -d "$SPEC_TOPIC" ]; then
      TP="$SPEC_TOPIC/tasks.md"
    else
      bank="${MB_BANK:-.memory-bank}"
      TP="$bank/specs/$SPEC_TOPIC/tasks.md"
    fi
  fi

  if [ ! -f "$TP" ] || [ ! -r "$TP" ]; then
    printf '%s:0:unresolvable\n' "$TP" >&2
    exit 2
  fi

  parse="$(mb_estimate_lib_spec "$TP")"

  # Malformed Budget/Stage field → exit 2 (format break), no key=value stdout.
  mal="$(printf '%s\n' "$parse" | sed -n 's/^__malformed=//p' | head -1)"
  if [ -n "$mal" ]; then
    printf '%s:%s:malformed\n' "$TP" "$mal" >&2
    exit 2
  fi

  # Emit the contract stdout (drop control lines).
  printf '%s\n' "$parse" | grep -v '^__'

  # One stderr warning if any legacy task lacked an explicit Budget.
  leg="$(printf '%s\n' "$parse" | sed -n 's/^__legacy=//p' | head -1)"
  if [ -n "$leg" ]; then
    printf '%s:0:legacy_missing:%s\n' "$TP" "$leg" >&2
  fi

  mismatch="$(printf '%s\n' "$parse" | sed -n 's/^__mismatch=//p' | head -1)"
  overflow="$(printf '%s\n' "$parse" | sed -n 's/^__overflow=//p' | head -1)"
  if [ "$mismatch" = "1" ] || [ "$overflow" = "1" ]; then
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Context-file mode (S1 C1) — strict frontmatter schema: estimated_tokens must
# live in the first YAML frontmatter and carry a `breakdown:` map with EXACTLY
# the six known category keys, each once; unknown or duplicated keys are
# rejected (estimate=malformed), never silently dropped from the total.
# ---------------------------------------------------------------------------
[ -n "$FILE" ] || usage_error
# --mb belongs to spec/candidate mode only; the HEAD context checker rejected
# unsupported flags with exit 2 and that behaviour is restored here.
[ -z "$MB_BANK" ] || usage_error

# --spec-budget must be a positive integer.
case "$SPEC_BUDGET" in
  ''|*[!0-9]*) usage_error ;;
esac
[ "$SPEC_BUDGET" -gt 0 ] || usage_error

if [ ! -f "$FILE" ] || [ ! -r "$FILE" ]; then
  printf '%s:0:unreadable\n' "$FILE" >&2
  exit 2
fi

# Parse + validate in awk (mb-estimate-lib.sh). Emits:
#   status=<ok|near|over|missing|malformed>
#   total=<N>
#   M <line> <field>            (one per malformed finding)
parse="$(mb_estimate_lib_context "$SPEC_BUDGET" "$FILE")"

status="$(printf '%s\n' "$parse" | sed -n 's/^status=//p' | head -1)"
etotal="$(printf '%s\n' "$parse" | sed -n 's/^total=//p' | head -1)"

case "$status" in
  ok|near)
    printf 'estimate=%s spec.total=%s spec_budget=%s\n' "$status" "$etotal" "$SPEC_BUDGET"
    exit 0
    ;;
  over)
    printf 'estimate=over spec.total=%s spec_budget=%s\n' "$etotal" "$SPEC_BUDGET"
    exit 1
    ;;
  missing)
    printf 'estimate=missing spec.total=0 spec_budget=%s\n' "$SPEC_BUDGET"
    printf '%s:0:estimated_tokens:missing\n' "$FILE" >&2
    exit 2
    ;;
  malformed)
    printf 'estimate=malformed spec.total=%s spec_budget=%s\n' "$etotal" "$SPEC_BUDGET"
    printf '%s\n' "$parse" | sed -n 's/^M //p' | sort -k1,1n | while read -r ln fld; do
      [ -n "$fld" ] || continue
      printf '%s:%s:%s:malformed\n' "$FILE" "$ln" "$fld" >&2
    done
    exit 2
    ;;
  *)
    usage_error
    ;;
esac
