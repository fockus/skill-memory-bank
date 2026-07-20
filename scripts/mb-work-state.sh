#!/usr/bin/env bash
# mb-work-state.sh — durable /mb work loop-state + max_cycles enforcement, with
# optional per-run isolation/claim under MB_WORK_PARALLEL=1. Plans: I-093
# (.../2026-07-04_fix_mb-work-resilience.md), I-094 (.../mb-work-parallel-runs.md)
#
# Subcommands (all take [--mb <path>]; per-run ones also [--run-id ID] /
# $MB_WORK_RUN_ID): init <source> <item_no> [--source-path P] [--source-topic T]
# [--max-cycles N] [--heading TXT] [--takeover] (prints run_id) · new-run-id ·
# step <name> · cycle (exit 3 when exhausted) · status [--all] · list · done ·
# clear (both free any claim) · eval-red --cmd-file <path> --output-re <ERE>
# [--expected-exit N] · eval-green --cmd-file <path> (svp-sdd-core C6, REQ-008).
#
# `source` is the CATEGORY (plan|spec); --source-path/--source-topic carry the
# concrete declaration file and MUST be threaded from mb-work-plan.sh's JSON —
# the eval gate binds against them, and passing only the category ungated the
# whole loop (review [9]). `init` REFUSES a bare spec/plan source (exit 2).
#
# State file: <bank>/.work-state.json, or under MB_WORK_PARALLEL=1 with a run_id,
# <bank>/.work-state/<run_id>.json — { run_id, source, source_path, source_topic,
# item_no, heading, cycle, max_cycles, steps[], phase, eval_gate, baseline_ref,
# updated,
# eval{cmd, cmd_hash, red_exit, red_observed, red_match, green_exit, sig} }.
#
# eval-red / eval-green (C6): the helper is the SOLE executor and judge of the
# Eval command — it runs an immutable snapshot of --cmd-file from the repo root
# and derives red/green from the observed output+exit, so no CLI flag can spoof a
# verdict. A red REQUIRES non-zero exit AND an --output-re match. `sig`
# (scripts/mb_work_eval_proof.py) binds cmd_hash + red fields + green_exit:
# checksum-grade integrity, NOT tamper-proofing (AGR-026 — key ships in repo).
#
# `done` refuses (exit 5) an item whose DECLARED, non-waived Eval has no proven
# red→green (valid sig, red_observed/red_match true, green_exit 0), or whose
# declaration file resolves but lacks the item. EVERY done records `eval_gate` —
# verified:red_green | waived:eval_none | unverified:no_declaration_surface —
# and prints it when not verified, so an unverifiable pass is never mistaken for
# a checked one (AGR-013 honest degradation; review [11] + round-2 gap).
#
# max_cycles (when omitted) resolves from the pipeline's
# workflows.governed-execution.loop.max_cycles, falling back to 2 (PyYAML-opt).
#
# Parallel runs (I-094, opt-in MB_WORK_PARALLEL=1): `init` claims <source> in a
# source→run index (scripts/mb-work-slots.sh); a second `init` for a live-claimed
# source exits 4 unless --takeover. `init` also records `baseline_ref`. Unset ⇒
# the legacy single path, unchanged.
#
# Exit codes: 0 ok · 2 usage error · 3 cycle budget exhausted (I-093) · 4 claim
# refused under MB_WORK_PARALLEL (I-094; --takeover overrides) · 5 done refused,
# declared Eval unproven (review [11]).
#
# Fail-safe: status/claim-index reads on missing/corrupt data degrade to `{}` /
# "unclaimed" — never crash or wedge a session.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"
# shellcheck source=mb-work-state-lib.sh
source "$SCRIPT_DIR/mb-work-state-lib.sh"
# shellcheck source=mb-work-state-eval.sh
source "$SCRIPT_DIR/mb-work-state-eval.sh"

usage() {
  sed -n '2,52p' "$0" >&2
}

state_path() {
  # $1 = mb_arg, $2 = run_id (optional) → echoes the state-file path
  local bank
  bank=$(mb_resolve_path "${1:-}")
  mbw_state_slot "$bank" "${2:-}"
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
  local source_path="" source_topic=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --source-path) source_path="${2:-}"; shift 2 ;;
      --source-path=*) source_path="${1#--source-path=}"; shift ;;
      --source-topic) source_topic="${2:-}"; shift 2 ;;
      --source-topic=*) source_topic="${1#--source-topic=}"; shift ;;
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

  # `spec`/`plan` are CATEGORIES, not locators. A spec task always lives in a
  # tasks.md, so `init spec 1` with no locator is malformed by construction —
  # and it used to silently produce a state whose eval gate could never resolve,
  # letting `done` pass unchecked. Refuse it here rather than labelling it later.
  case "$source_" in
    spec|plan)
      if [ -z "$source_path" ] && [ -z "$source_topic" ]; then
        echo "[work-state] init: '$source_' is a category, not a locator — pass --source-topic and/or --source-path (from mb-work-plan.sh's JSON) so the eval gate can resolve the declaration" >&2
        exit 2
      fi
      ;;
  esac

  local bank_early; bank_early=$(mb_resolve_path "$mb_arg")

  # Containment (r3 [2]) — resolver lives in the lib (init_spec_locator).
  if [ "$source_" = "spec" ]; then
    local _loc
    _loc=$(init_spec_locator "$bank_early" "$source_topic" "$source_path") || {
      echo "[work-state] init: spec source must be a contained <bank>/specs/<topic>/tasks.md (refusing an out-of-bank, traversing or symlink-escaping locator)" >&2
      exit 2; }
    source_topic=${_loc%%$'\037'*}
    source_path=${_loc#*$'\037'}
  fi

  [ -z "$run_id" ] && run_id="${MB_WORK_RUN_ID:-}"
  [ -z "$run_id" ] && run_id=$(gen_run_id)
  [ -z "$max_cycles" ] && max_cycles=$(resolve_max_cycles "$mb_arg")
  if ! is_uint "$max_cycles"; then
    echo "[work-state] max-cycles must be a non-negative integer" >&2
    exit 2
  fi

  local bank; bank="$bank_early"
  mkdir -p "$bank"

  # Bind the whole declaration surface NOW (r3 [1]); `done` refuses on change.
  local decl_json
  decl_json=$(eval_bind_declaration "$bank" "$source_path" "$source_topic" "$item_no" "$source_")

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
  write_init_state "$tmp" "$run_id" "$source_" "$item_no" "$heading" \
    "$source_path" "$source_topic" "$decl_json" "$max_cycles" "$baseline_ref"
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

# ── done ────────────────────────────────────────────────────────────────
cmd_done() {
  parse_common_flags "$@"
  local state tmp
  state=$(state_path "$PARSED_MB" "$PARSED_RUN_ID")
  require_valid_state "$state"

  # A declared, non-waived Eval must have gone red→green first (review [11]):
  # `done` is the last gate before the DoD checkboxes flip.
  # shellcheck disable=SC2034  # read by eval_require_done_proof (sourced eval layer)
  PARSED_EVAL_MB="$PARSED_MB"
  MBW_DONE_GATE=""
  eval_require_done_proof "$state"

  tmp=$(mktemp)
  STATE="$state" TMP="$tmp" GATE="$MBW_DONE_GATE" python3 - <<'PY'
import json, os, datetime
p = os.environ["STATE"]
data = json.loads(open(p, encoding="utf-8").read())
data["phase"] = "done"
# Never record a done without stating whether its Eval was actually verified.
data["eval_gate"] = os.environ.get("GATE") or "unverified:no_declaration_surface"
data["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
open(os.environ["TMP"], "w", encoding="utf-8").write(json.dumps(data) + "\n")
PY
  mv "$tmp" "$state"

  # Say it out loud too: a silent pass is what made the old bypass invisible.
  case "$MBW_DONE_GATE" in
    verified:red_green) : ;;
    waived:eval_none)
      echo "[work-state] done: eval waived by the spec (Eval: none) — not verified" ;;
    *)
      echo "[work-state] done: eval UNVERIFIED (no Eval declaration resolvable for this source) — the red→green gate did not run" ;;
  esac

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
    eval-red) shift; cmd_eval_red "$@" ;;
    eval-green) shift; cmd_eval_green "$@" ;;
    *) echo "[work-state] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
