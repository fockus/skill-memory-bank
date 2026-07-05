#!/usr/bin/env bash
# mb-work-pivot.sh — strategic pivot decision + telemetry
# (work-loop-v2 design.md §5 "Strategic pivoting" / "Pivot decision",
# "Pivot dispatch", "Telemetry"; REQ-112/REQ-114).
#
# On a CHANGES_REQUESTED review verdict, the orchestrator (scripts/mb-review.sh
# + scripts/mb-work-trend.sh already compute progress_trend per cycle) asks
# this script whether to keep refining in place or to force a strategic pivot:
#
#   consecutive_stagnant = count of consecutive `stagnant` trends (this cycle
#                           included) -- caller-supplied, this script does not
#                           track history itself.
#   if consecutive_stagnant >= pivot_after_cycles (default 2):
#     pivot_mode = "pivot_in_role"                # first escalation
#     if current_cycle >= pivot_escalate_to_architect_on (default 4):
#       pivot_mode = "pivot_via_architect"        # heavier escalation
#   else:
#     pivot_mode = "refine"                       # existing behavior
#
# Usage:
#   mb-work-pivot.sh decide --mb <bank> --consecutive-stagnant <N> --cycle <C>
#                    [--item-id <id>] [--rationale <text>]
#   mb-work-pivot.sh prompt-prefix --mode <pivot_in_role|pivot_via_architect>
#                    --stagnant <N>
#   mb-work-pivot.sh --help
#
# `decide` prints exactly one of `refine|pivot_in_role|pivot_via_architect` on
# stdout, exit 0. `pivot_after_cycles`/`pivot_escalate_to_architect_on` are
# resolved from the project pipeline.yaml (project override -> shipped
# references/pipeline.default.yaml), read from the `review:` block first
# (where the shipped default places them, alongside max_cycles/on_max_cycles)
# and falling back to a top-level key of the same name for projects that
# prefer a flat pipeline.yaml; fail-safe defaults 2 and 4 apply when the file
# is absent, unparseable, or PyYAML is not installed (mirrors
# scripts/mb-work-budget.sh's resolve_pipeline_defaults).
#
# When the decision is a pivot (mode != refine) AND `--item-id` is given, a
# single JSON line is ALSO appended to `<bank>/tmp/pivot-log.jsonl`:
#   { "ts": "<ISO-8601>", "item_id": "<id>", "cycle": <N>,
#     "mode": "pivot_in_role|pivot_via_architect", "rationale_hash": "sha256:..." }
# `rationale_hash` hashes `--rationale` verbatim when given, else a
# deterministic `"<mode>:<cycle>"` fallback string -- either way the same
# inputs always produce the same hash. `refine` NEVER writes telemetry. This
# file is intentionally not tracked by git (analysis data, not project
# memory). A missing/uncreatable tmp dir, or any hashing/JSON-encoding
# failure, degrades to a stderr warning and exit 0 -- telemetry must never
# wedge the loop.
#
# `prompt-prefix` is a pure STRING emitter (no dispatch side effects) — it
# prints the PIVOT INSTRUCTION prompt prefix from design.md §5 for the host
# loop to prepend when it re-dispatches the role-agent (`pivot_in_role`) or,
# for `pivot_via_architect`, documents the two-step escalation (architect
# redesign sketch first, then the role-agent with the issue list + sketch).
# Actually dispatching subagents is the host loop's job (agent-native), not
# this script's.
#
# Exit codes:
#   0  success
#   2  usage error (missing subcommand/flags, bad input)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,45p' "$0" >&2
}

is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# $1 = mb_arg -> echoes "pivot_after_cycles pivot_escalate_to_architect_on"
# (mirrors scripts/mb-work-budget.sh's resolve_pipeline_defaults pattern).
resolve_pipeline_defaults() {
  local mb_arg="$1" pipeline_path
  pipeline_path=$(bash "$PIPELINE" path "$mb_arg" 2>/dev/null || true)
  if [ -z "$pipeline_path" ]; then
    pipeline_path="$SCRIPT_DIR/../references/pipeline.default.yaml"
  fi
  PIPELINE_YAML="$pipeline_path" python3 - <<'PY'
import os
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    review = cfg.get("review") if isinstance(cfg.get("review"), dict) else {}
    after = review.get("pivot_after_cycles", cfg.get("pivot_after_cycles", 2))
    escalate = review.get(
        "pivot_escalate_to_architect_on",
        cfg.get("pivot_escalate_to_architect_on", 4),
    )
    print(f"{int(after)} {int(escalate)}")
except Exception:
    print("2 4")
PY
}

# $1=bank $2=item_id $3=cycle $4=mode $5=rationale (may be empty) -> appends
# one JSONL line to <bank>/tmp/pivot-log.jsonl. Fail-safe: any failure along
# the way degrades to a stderr warning + return 0, never a non-zero exit.
write_telemetry() {
  local bank="$1" item_id="$2" cycle="$3" mode="$4" rationale="$5"
  local dir="$bank/tmp"
  if ! mkdir -p "$dir" 2>/dev/null; then
    echo "[work-pivot] warning: cannot create $dir — telemetry not recorded" >&2
    return 0
  fi
  local log="$dir/pivot-log.jsonl"

  local hash_input
  if [ -n "$rationale" ]; then
    hash_input="$rationale"
  else
    hash_input="${mode}:${cycle}"
  fi

  local line
  line=$(ITEM_ID="$item_id" CYCLE="$cycle" MODE="$mode" HASH_INPUT="$hash_input" python3 - <<'PY' 2>/dev/null
import datetime
import hashlib
import json
import os

item_id = os.environ["ITEM_ID"]
cycle = int(os.environ["CYCLE"])
mode = os.environ["MODE"]
digest = hashlib.sha256(os.environ["HASH_INPUT"].encode("utf-8")).hexdigest()
ts = datetime.datetime.now(datetime.timezone.utc).isoformat()

print(json.dumps({
    "ts": ts,
    "item_id": item_id,
    "cycle": cycle,
    "mode": mode,
    "rationale_hash": f"sha256:{digest}",
}))
PY
  ) || line=""

  if [ -z "$line" ]; then
    echo "[work-pivot] warning: could not build telemetry line — not recorded" >&2
    return 0
  fi

  if ! printf '%s\n' "$line" >>"$log" 2>/dev/null; then
    echo "[work-pivot] warning: cannot append to $log — telemetry not recorded" >&2
  fi
  return 0
}

cmd_decide() {
  local mb_arg="" consecutive="" cycle="" item_id="" rationale=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      --consecutive-stagnant) consecutive="${2:-}"; shift 2 ;;
      --consecutive-stagnant=*) consecutive="${1#--consecutive-stagnant=}"; shift ;;
      --cycle) cycle="${2:-}"; shift 2 ;;
      --cycle=*) cycle="${1#--cycle=}"; shift ;;
      --item-id) item_id="${2:-}"; shift 2 ;;
      --item-id=*) item_id="${1#--item-id=}"; shift ;;
      --rationale) rationale="${2:-}"; shift 2 ;;
      --rationale=*) rationale="${1#--rationale=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[work-pivot] decide: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done

  if ! is_uint "$consecutive" || ! is_uint "$cycle"; then
    echo "[work-pivot] decide requires --consecutive-stagnant and --cycle as non-negative integers" >&2
    exit 2
  fi

  local bank
  bank=$(mb_resolve_path "$mb_arg")

  local defaults after escalate
  defaults=$(resolve_pipeline_defaults "$mb_arg")
  after=$(echo "$defaults" | awk '{print $1}')
  escalate=$(echo "$defaults" | awk '{print $2}')
  is_uint "$after" || after=2
  is_uint "$escalate" || escalate=4

  local mode="refine"
  if [ "$consecutive" -ge "$after" ]; then
    mode="pivot_in_role"
    if [ "$cycle" -ge "$escalate" ]; then
      mode="pivot_via_architect"
    fi
  fi

  printf '%s\n' "$mode"

  if [ "$mode" != "refine" ] && [ -n "$item_id" ]; then
    write_telemetry "$bank" "$item_id" "$cycle" "$mode" "$rationale"
  fi
}

cmd_prompt_prefix() {
  local mode="" stagnant=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mode) mode="${2:-}"; shift 2 ;;
      --mode=*) mode="${1#--mode=}"; shift ;;
      --stagnant) stagnant="${2:-}"; shift 2 ;;
      --stagnant=*) stagnant="${1#--stagnant=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[work-pivot] prompt-prefix: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done

  if [ "$mode" != "pivot_in_role" ] && [ "$mode" != "pivot_via_architect" ]; then
    echo "[work-pivot] prompt-prefix requires --mode pivot_in_role|pivot_via_architect" >&2
    exit 2
  fi
  [ -n "$stagnant" ] || stagnant="N"

  cat <<EOF
PIVOT INSTRUCTION: Your previous attempts did not converge on a passing review (stagnant trend for ${stagnant} cycles). Do NOT continue refining the current approach. Discard it. Read the issue list as constraints, not as edits. Propose a different architecture/strategy/abstraction and implement it from scratch. State explicitly at the top of your work: "Pivot rationale: <one line>".
EOF

  if [ "$mode" = "pivot_via_architect" ]; then
    cat <<'EOF'

ESCALATION (pivot_via_architect): this is the heavier pivot, used only when
the cheaper pivot_in_role has not converged. Two-step dispatch:
  1. Dispatch mb-architect FIRST with the issue list and current code state.
     It writes a redesign sketch to
     .memory-bank/notes/<date>_pivot-<topic>.md.
  2. Dispatch the role-agent with BOTH the issue list and the architect's
     sketch as context, then apply the PIVOT INSTRUCTION above.
EOF
  fi
}

main() {
  if [ "$#" -lt 1 ]; then
    usage
    exit 2
  fi
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    decide)
      shift
      cmd_decide "$@"
      ;;
    prompt-prefix)
      shift
      cmd_prompt_prefix "$@"
      ;;
    *)
      echo "[work-pivot] unknown subcommand '$1'" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
