#!/usr/bin/env bash
# mb-work-state.sh — durable /mb work loop-state + max_cycles enforcement.
#
# Persists the per-item work-loop state across compaction/abort so
# `max_cycles` is enforced deterministically (by exit code), not from the
# orchestrator's context. See:
#   .memory-bank/plans/2026-07-04_fix_mb-work-resilience.md (Stage 1, I-093)
#
# Subcommands (each takes [--mb <path>] for bank override):
#   init <source> <item_no> [--run-id ID] [--max-cycles N] [--heading TXT]
#                                        start/reset loop-state; prints run_id
#   step <name>                         append a step-name transition
#   cycle                                increment cycle; exit 3 when exhausted
#   status                               print state JSON (fail-safe)
#   done                                 mark phase=done
#   clear                                remove state file
#
# State file: <bank>/.work-state.json
#   { run_id, source, item_no, heading, cycle, max_cycles, steps[], phase, updated }
#
# max_cycles (when --max-cycles is omitted) is resolved from the effective
# pipeline's workflows.governed-execution.loop.max_cycles, falling back to 2
# when PyYAML/the field is unavailable — same PIPELINE_YAML PyYAML-optional
# pattern as scripts/mb-work-budget.sh.
#
# Exit codes:
#   0  ok
#   2  usage error (bad args; cycle/step/done with no active/valid state)
#   3  cycle budget exhausted — the ONE intentional enforcement exit
#
# Fail-safe: `status` on a missing/corrupt state file always exits 0 with an
# empty JSON object — it must never wedge a session.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,30p' "$0" >&2
}

resolve_max_cycles() {
  # $1 = mb_arg → echoes an integer
  local mb_arg="$1"
  local pipeline_path
  pipeline_path=$(bash "$PIPELINE" path "$mb_arg" 2>/dev/null || true)
  if [ -z "$pipeline_path" ]; then
    pipeline_path="$SCRIPT_DIR/../references/pipeline.default.yaml"
  fi
  PIPELINE_YAML="$pipeline_path" python3 - <<'PY'
import os
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    loop = (((cfg.get("workflows") or {}).get("governed-execution") or {}).get("loop") or {})
    print(int(loop.get("max_cycles", 2)))
except Exception:
    print(2)
PY
}

state_path() {
  # $1 = mb_arg → echoes the state-file path
  local bank
  bank=$(mb_resolve_path "${1:-}")
  printf '%s/.work-state.json\n' "$bank"
}

gen_run_id() {
  python3 -c 'import uuid; print(uuid.uuid4().hex)'
}

is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Fails closed with a usage error unless $1 exists AND parses as JSON.
require_valid_state() {
  local state="$1"
  if [ ! -f "$state" ] || ! python3 -c '
import json, sys
json.loads(open(sys.argv[1], encoding="utf-8").read())
' "$state" >/dev/null 2>&1; then
    echo "[work-state] no active work-state; run init first" >&2
    exit 2
  fi
}

# ── init ────────────────────────────────────────────────────────────────
cmd_init() {
  local source_="" item_no="" run_id="" max_cycles="" heading="" mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --max-cycles) max_cycles="${2:-}"; shift 2 ;;
      --max-cycles=*) max_cycles="${1#--max-cycles=}"; shift ;;
      --heading) heading="${2:-}"; shift 2 ;;
      --heading=*) heading="${1#--heading=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *)
        if [ -z "$source_" ]; then source_="$1";
        elif [ -z "$item_no" ]; then item_no="$1";
        fi
        shift ;;
    esac
  done

  if [ -z "$source_" ] || [ -z "$item_no" ]; then
    echo "[work-state] init <source> <item_no> required" >&2
    exit 2
  fi
  if ! is_uint "$item_no"; then
    echo "[work-state] item_no must be a non-negative integer" >&2
    exit 2
  fi

  [ -z "$run_id" ] && run_id=$(gen_run_id)
  if [ -z "$max_cycles" ]; then
    max_cycles=$(resolve_max_cycles "$mb_arg")
  fi
  if ! is_uint "$max_cycles"; then
    echo "[work-state] max-cycles must be a non-negative integer" >&2
    exit 2
  fi

  local state bank tmp
  state=$(state_path "$mb_arg")
  bank=$(dirname "$state")
  mkdir -p "$bank"

  tmp=$(mktemp)
  RUN_ID="$run_id" SOURCE="$source_" ITEM_NO="$item_no" HEADING="$heading" \
    MAX_CYCLES="$max_cycles" TMP="$tmp" python3 - <<'PY'
import json, os, datetime
state = {
    "run_id": os.environ["RUN_ID"],
    "source": os.environ["SOURCE"],
    "item_no": int(os.environ["ITEM_NO"]),
    "heading": os.environ.get("HEADING", ""),
    "cycle": 0,
    "max_cycles": int(os.environ["MAX_CYCLES"]),
    "steps": [],
    "phase": "in-progress",
    "updated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(state) + "\n")
PY
  mv "$tmp" "$state"
  printf '%s\n' "$run_id"
}

# ── step ────────────────────────────────────────────────────────────────
cmd_step() {
  local name="" mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) if [ -z "$name" ]; then name="$1"; fi; shift ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "[work-state] step <name> required" >&2
    exit 2
  fi

  local state tmp
  state=$(state_path "$mb_arg")
  require_valid_state "$state"

  tmp=$(mktemp)
  STATE="$state" NAME="$name" TMP="$tmp" python3 - <<'PY'
import json, os, datetime
p = os.environ["STATE"]
data = json.loads(open(p, encoding="utf-8").read())
data.setdefault("steps", []).append(os.environ["NAME"])
data["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
  mv "$tmp" "$state"
}

# ── cycle ───────────────────────────────────────────────────────────────
cmd_cycle() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[work-state] unexpected arg '$1'" >&2; exit 2 ;;
    esac
  done

  local state tmp exhausted
  state=$(state_path "$mb_arg")
  require_valid_state "$state"

  tmp=$(mktemp)
  exhausted=$(STATE="$state" TMP="$tmp" python3 - <<'PY'
import json, os, datetime
p = os.environ["STATE"]
data = json.loads(open(p, encoding="utf-8").read())
cycle = int(data.get("cycle", 0)) + 1
max_cycles = int(data.get("max_cycles", 0))
data["cycle"] = cycle
data["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(data) + "\n")
print(f"{cycle} {max_cycles} {'1' if cycle > max_cycles else '0'}")
PY
)
  mv "$tmp" "$state"

  local cyc max flag
  cyc=$(printf '%s' "$exhausted" | awk '{print $1}')
  max=$(printf '%s' "$exhausted" | awk '{print $2}')
  flag=$(printf '%s' "$exhausted" | awk '{print $3}')

  if [ "$flag" = "1" ]; then
    echo "[work-state] cycle budget exhausted (cycle=$cyc max_cycles=$max)" >&2
    exit 3
  fi
}

# ── status ──────────────────────────────────────────────────────────────
cmd_status() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) shift ;;
    esac
  done

  local state
  state=$(state_path "$mb_arg")
  if [ ! -f "$state" ]; then
    printf '{}\n'
    exit 0
  fi

  # Fail-safe: never crash a session on corrupt JSON — degrade to `{}`.
  STATE="$state" python3 - <<'PY' || printf '{}\n'
import json, os, sys
try:
    data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
except Exception:
    print("{}")
    sys.exit(0)
print(json.dumps(data))
PY
}

# ── done ────────────────────────────────────────────────────────────────
cmd_done() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) shift ;;
    esac
  done

  local state tmp
  state=$(state_path "$mb_arg")
  require_valid_state "$state"

  tmp=$(mktemp)
  STATE="$state" TMP="$tmp" python3 - <<'PY'
import json, os, datetime
p = os.environ["STATE"]
data = json.loads(open(p, encoding="utf-8").read())
data["phase"] = "done"
data["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
  mv "$tmp" "$state"
}

# ── clear ───────────────────────────────────────────────────────────────
cmd_clear() {
  local mb_arg=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) shift ;;
    esac
  done
  local state
  state=$(state_path "$mb_arg")
  rm -f "$state"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage; exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    step) shift; cmd_step "$@" ;;
    cycle) shift; cmd_cycle "$@" ;;
    status) shift; cmd_status "$@" ;;
    done) shift; cmd_done "$@" ;;
    clear) shift; cmd_clear "$@" ;;
    *) echo "[work-state] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
