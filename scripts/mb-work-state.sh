#!/usr/bin/env bash
# mb-work-state.sh — durable /mb work loop-state + max_cycles enforcement,
# with optional per-run isolation/claim under MB_WORK_PARALLEL=1. Plans:
#   .memory-bank/plans/2026-07-04_fix_mb-work-resilience.md (I-093)
#   .memory-bank/plans/2026-07-04_fix_mb-work-parallel-runs.md (I-094)
#
# Subcommands (all take [--mb <path>]; per-run ones also [--run-id ID] /
# $MB_WORK_RUN_ID): init <source> <item_no> [--max-cycles N] [--heading TXT]
# [--takeover] (prints run_id) · new-run-id (prints a uuid, writes nothing) ·
# step <name> · cycle (exit 3 when exhausted) · status [--all] · list (alias
# for `status --all`) · done (frees any claim) · clear (frees any claim).
#
# State file: <bank>/.work-state.json, or under MB_WORK_PARALLEL=1 with a
# run_id, <bank>/.work-state/<run_id>.json — { run_id, source, item_no,
# heading, cycle, max_cycles, steps[], phase, baseline_ref, updated }.
#
# max_cycles (when omitted) resolves from the pipeline's
# workflows.governed-execution.loop.max_cycles, falling back to 2 (PyYAML-
# optional, same pattern as scripts/mb-work-budget.sh).
#
# Parallel runs (I-094, opt-in MB_WORK_PARALLEL=1): `init` claims <source> in
# a source→run index (scripts/mb-work-slots.sh); a second `init` for a source
# still claimed by a live (phase != done) run refuses with exit 4 unless
# --takeover. `init` also records `baseline_ref` (HEAD at claim time, ""
# outside a git repo) for later baseline-scoped diffing. Unset ⇒ the single
# legacy path, unchanged from pre-I-094 behaviour.
#
# Exit codes: 0 ok · 2 usage error · 3 cycle budget exhausted (I-093) ·
# 4 claim refused under MB_WORK_PARALLEL (I-094; pass --takeover to override).
#
# Fail-safe: status/claim-index reads on missing/corrupt data degrade to
# `{}` / "unclaimed" — never crash or wedge a session.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

usage() {
  sed -n '2,33p' "$0" >&2
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
  # $1 = mb_arg, $2 = run_id (optional) → echoes the state-file path
  local bank
  bank=$(mb_resolve_path "${1:-}")
  mbw_state_slot "$bank" "${2:-}"
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

# Shared flag parser for step/cycle/status/list/done/clear: consumes
# --run-id/--run-id=X, --mb/--mb=X, --all, -h/--help (exits via usage) from
# "$@". Sets globals PARSED_RUN_ID (falls back to $MB_WORK_RUN_ID),
# PARSED_MB, PARSED_ALL (0/1) and REST_ARGS (bash-3.2-safe indexed array)
# with everything else, in order. `init` has extra flags, so it parses on
# its own instead of using this helper.
parse_common_flags() {
  PARSED_RUN_ID=""
  PARSED_MB=""
  PARSED_ALL=0
  REST_ARGS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) PARSED_RUN_ID="${2:-}"; shift 2 ;;
      --run-id=*) PARSED_RUN_ID="${1#--run-id=}"; shift ;;
      --mb) PARSED_MB="${2:-}"; shift 2 ;;
      --mb=*) PARSED_MB="${1#--mb=}"; shift ;;
      --all) PARSED_ALL=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) REST_ARGS+=("$1"); shift ;;
    esac
  done
  if [ -z "$PARSED_RUN_ID" ]; then
    PARSED_RUN_ID="${MB_WORK_RUN_ID:-}"
  fi
}

# ── init ────────────────────────────────────────────────────────────────
cmd_init() {
  local source_="" item_no="" run_id="" max_cycles="" heading="" mb_arg="" takeover=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --max-cycles) max_cycles="${2:-}"; shift 2 ;;
      --max-cycles=*) max_cycles="${1#--max-cycles=}"; shift ;;
      --heading) heading="${2:-}"; shift 2 ;;
      --heading=*) heading="${1#--heading=}"; shift ;;
      --takeover) takeover=1; shift ;;
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

  [ -z "$run_id" ] && run_id="${MB_WORK_RUN_ID:-}"
  [ -z "$run_id" ] && run_id=$(gen_run_id)
  [ -z "$max_cycles" ] && max_cycles=$(resolve_max_cycles "$mb_arg")
  if ! is_uint "$max_cycles"; then
    echo "[work-state] max-cycles must be a non-negative integer" >&2
    exit 2
  fi

  local bank; bank=$(mb_resolve_path "$mb_arg")
  mkdir -p "$bank"

  # Claim check (I-094): only under MB_WORK_PARALLEL, unless --takeover.
  if mbw_parallel_on && [ "$takeover" != "1" ]; then
    local claimant; claimant=$(mbw_claim_conflict "$bank" "$source_" "$run_id")
    if [ -n "$claimant" ]; then
      echo "[work-state] source '$source_' already claimed by run $claimant; pass --takeover to override" >&2
      exit 4
    fi
  fi

  local baseline_ref; baseline_ref=$(git rev-parse HEAD 2>/dev/null || true)

  local state tmp
  state=$(mbw_state_slot "$bank" "$run_id")
  mkdir -p "$(dirname "$state")"

  tmp=$(mktemp)
  RUN_ID="$run_id" SOURCE="$source_" ITEM_NO="$item_no" HEADING="$heading" \
    MAX_CYCLES="$max_cycles" BASELINE_REF="$baseline_ref" TMP="$tmp" python3 - <<'PY'
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
    "baseline_ref": os.environ.get("BASELINE_REF", ""),
    "updated": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(state) + "\n")
PY
  mv "$tmp" "$state"

  if mbw_parallel_on; then
    mbw_index_set "$bank" "$source_" "$run_id"
  fi

  printf '%s\n' "$run_id"
}

# ── new-run-id ──────────────────────────────────────────────────────────
cmd_new_run_id() {
  gen_run_id
}

# ── step ────────────────────────────────────────────────────────────────
cmd_step() {
  parse_common_flags "$@"
  local name="${REST_ARGS[0]:-}"
  if [ -z "$name" ]; then
    echo "[work-state] step <name> required" >&2
    exit 2
  fi

  local state tmp
  state=$(state_path "$PARSED_MB" "$PARSED_RUN_ID")
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
  parse_common_flags "$@"
  if [ "${#REST_ARGS[@]}" -gt 0 ]; then
    echo "[work-state] unexpected arg '${REST_ARGS[0]}'" >&2
    exit 2
  fi

  local state tmp exhausted
  state=$(state_path "$PARSED_MB" "$PARSED_RUN_ID")
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
  parse_common_flags "$@"
  if [ "$PARSED_ALL" = "1" ]; then
    cmd_list --mb "$PARSED_MB"
    return
  fi

  local state
  state=$(state_path "$PARSED_MB" "$PARSED_RUN_ID")
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

# ── list (alias: status --all) ───────────────────────────────────────────
# Enumerates every live run's state — the singleton (if present) plus every
# <bank>/.work-state/*.json slot — as a JSON array. Fail-safe: a corrupt slot
# is silently skipped, never crashes the listing.
cmd_list() {
  parse_common_flags "$@"
  local bank
  bank=$(mb_resolve_path "$PARSED_MB")
  BANK="$bank" python3 - <<'PY'
import glob
import json
import os

bank = os.environ["BANK"]
paths = []
singleton = os.path.join(bank, ".work-state.json")
if os.path.isfile(singleton):
    paths.append(singleton)
paths.extend(sorted(glob.glob(os.path.join(bank, ".work-state", "*.json"))))

entries = []
for p in paths:
    try:
        with open(p, encoding="utf-8") as fh:
            entries.append(json.load(fh))
    except Exception:
        continue
print(json.dumps(entries))
PY
}

# ── done ────────────────────────────────────────────────────────────────
cmd_done() {
  parse_common_flags "$@"
  local state tmp
  state=$(state_path "$PARSED_MB" "$PARSED_RUN_ID")
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

  # A finished run no longer holds its source claim (I-094).
  if mbw_parallel_on; then
    mbw_release_claim "$(mb_resolve_path "$PARSED_MB")" "$state"
  fi
}

# ── clear ───────────────────────────────────────────────────────────────
cmd_clear() {
  parse_common_flags "$@"
  local state
  state=$(state_path "$PARSED_MB" "$PARSED_RUN_ID")

  # Release this run's source claim before removing its slot (I-094).
  if mbw_parallel_on && [ -f "$state" ]; then
    mbw_release_claim "$(mb_resolve_path "$PARSED_MB")" "$state"
  fi

  rm -f "$state"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage; exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    new-run-id) shift; cmd_new_run_id "$@" ;;
    step) shift; cmd_step "$@" ;;
    cycle) shift; cmd_cycle "$@" ;;
    status) shift; cmd_status "$@" ;;
    list) shift; cmd_list "$@" ;;
    done) shift; cmd_done "$@" ;;
    clear) shift; cmd_clear "$@" ;;
    *) echo "[work-state] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
