#!/usr/bin/env bash
# mb-work-budget.sh — token budget tracker for /mb work --budget, with
# optional per-run isolation under MB_WORK_PARALLEL=1. Plans:
#   .memory-bank/plans/2026-07-04_fix_mb-work-parallel-runs.md (I-094 S2)
#
# Subcommands (each takes [--mb <path>] for bank override):
#   init <total_tokens> [--warn-at PCT] [--stop-at PCT] [--run-id ID]  start tracking
#   add <tokens> [--run-id ID]                            increment spent
#   status [--run-id ID]                                  show current state
#   check [--run-id ID]                                   0=ok, 1=warn, 2=stop
#   clear [--run-id ID]                                   remove state
#
# State file: <bank>/.work-budget.json, or under MB_WORK_PARALLEL=1 with a
# non-empty --run-id, <bank>/.work-budget/<run_id>.json —
#   { total, spent, warn_at_percent, stop_at_percent, started, run_id }
#
# Defaults are read from pipeline.yaml:budget.{warn_at_percent, stop_at_percent}.
#
# Parallel runs (I-094 S2, opt-in MB_WORK_PARALLEL=1): every subcommand
# resolves its state path via scripts/mb-work-slots.sh:mbw_budget_slot, which
# routes to a per-run slot only when MB_WORK_PARALLEL is truthy AND a run_id
# is given — otherwise it always returns the legacy singleton
# <bank>/.work-budget.json (mb-fanout.sh reads this exact path; unaffected).
# Per-run slots are physically separate files, so each run's `check` is now a
# real gate against its own spend — never the old cross-run warn-not-stop.
#
# run_id binding (I-093 S2): `init --run-id ID` stamps the budget with the
# owning run. `add`/`check --run-id ID` compare against the stamped run_id —
# a mismatch means the on-disk budget is orphaned from an aborted run, so it
# is treated as stale: exit 1 (warn), zero mutation, never a false stop. This
# stays as a second safety net (now rarely hit once slots are separate).
# Omitting `--run-id` on `add`/`check` keeps today's behaviour byte-identical
# (back-compat: no binding is enforced).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PIPELINE="$SCRIPT_DIR/mb-pipeline.sh"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

usage() {
  sed -n '2,17p' "$0" >&2
}

resolve_pipeline_defaults() {
  # $1 = mb_arg → echoes "warn stop"
  local mb_arg="$1"
  local pipeline_path
  pipeline_path=$(bash "$PIPELINE" path "$mb_arg" 2>/dev/null || true)
  if [ -z "$pipeline_path" ]; then
    pipeline_path="$SCRIPT_DIR/../references/pipeline.default.yaml"
  fi
  PIPELINE_YAML="$pipeline_path" python3 - <<'PY'
import os, sys
try:
    import yaml  # type: ignore
    cfg = yaml.safe_load(open(os.environ["PIPELINE_YAML"], encoding="utf-8")) or {}
    b = cfg.get("budget") or {}
    print(f"{b.get('warn_at_percent', 80)} {b.get('stop_at_percent', 100)}")
except Exception:
    print("80 100")
PY
}

# Returns 0 (true) when the on-disk budget's stamped run_id matches $2, or
# when the budget predates run_id stamping (field absent/empty — treated as
# unbound, never a false mismatch). $1=state path, $2=requested run_id.
require_matching_run_id() {
  local state="$1" run_id="$2"
  STATE="$state" RUN_ID="$run_id" python3 -c '
import json, os, sys
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
state_run_id = data.get("run_id", "")
sys.exit(0 if (not state_run_id or state_run_id == os.environ["RUN_ID"]) else 1)
'
}

cmd_init() {
  local total=""
  local warn=""
  local stop=""
  local mb_arg=""
  local run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --warn-at) warn="${2:-}"; shift 2 ;;
      --warn-at=*) warn="${1#--warn-at=}"; shift ;;
      --stop-at) stop="${2:-}"; shift 2 ;;
      --stop-at=*) stop="${1#--stop-at=}"; shift ;;
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) if [ -z "$total" ]; then total="$1"; fi; shift ;;
    esac
  done
  if [ -z "$total" ]; then
    echo "[budget] init <total_tokens> required" >&2
    exit 2
  fi

  local defaults
  defaults=$(resolve_pipeline_defaults "$mb_arg")
  local def_warn def_stop
  def_warn=$(echo "$defaults" | awk '{print $1}')
  def_stop=$(echo "$defaults" | awk '{print $2}')
  [ -z "$warn" ] && warn="$def_warn"
  [ -z "$stop" ] && stop="$def_stop"

  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state
  state=$(mbw_budget_slot "$bank" "$run_id")
  mkdir -p "$(dirname "$state")"

  # init always writes a fresh state (spent=0) — this is also how a stale
  # run_id from an aborted run gets auto-reset when a new run_id is passed.
  TOTAL="$total" WARN="$warn" STOP="$stop" RUN_ID="$run_id" STATE="$state" python3 - <<'PY'
import json, os, datetime
state = {
    "total": int(os.environ["TOTAL"]),
    "spent": 0,
    "warn_at_percent": int(os.environ["WARN"]),
    "stop_at_percent": int(os.environ["STOP"]),
    "started": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "run_id": os.environ.get("RUN_ID", ""),
}
open(os.environ["STATE"], "w", encoding="utf-8").write(json.dumps(state) + "\n")
PY
  echo "[budget] initialized: total=$total warn=$warn% stop=$stop%"
}

cmd_add() {
  local delta=""
  local mb_arg=""
  local run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) if [ -z "$delta" ]; then delta="$1"; fi; shift ;;
    esac
  done
  if [ -z "$delta" ]; then
    echo "[budget] add <tokens> required" >&2
    exit 2
  fi
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state
  state=$(mbw_budget_slot "$bank" "$run_id")
  if [ ! -f "$state" ]; then
    echo "[budget] no active budget (run 'init' first)" >&2
    exit 1
  fi
  # Back-compat: an empty/absent --run-id enforces no binding at all.
  if [ -n "$run_id" ]; then
    require_matching_run_id "$state" "$run_id" || {
      echo "[budget] run_id mismatch (stale budget) — ignoring add, no mutation" >&2
      exit 1
    }
  fi
  STATE="$state" DELTA="$delta" python3 - <<'PY'
import json, os
p = os.environ["STATE"]
data = json.loads(open(p, encoding="utf-8").read())
data["spent"] = int(data.get("spent", 0)) + int(os.environ["DELTA"])
open(p, "w", encoding="utf-8").write(json.dumps(data) + "\n")
print(f"[budget] spent={data['spent']}")
PY
}

cmd_status() {
  local mb_arg=""
  local run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) shift ;;
    esac
  done
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state
  state=$(mbw_budget_slot "$bank" "$run_id")
  if [ ! -f "$state" ]; then
    echo "[budget] no active budget" >&2
    exit 1
  fi
  STATE="$state" python3 - <<'PY'
import json, os
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
total = int(data["total"])
spent = int(data.get("spent", 0))
pct = (spent / total * 100) if total else 0
run_id = data.get("run_id", "")
print(
    f"total={total} spent={spent} pct={pct:.1f}% warn={data['warn_at_percent']}% "
    f"stop={data['stop_at_percent']}% run_id={run_id}"
)
PY
}

cmd_check() {
  local mb_arg=""
  local run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) shift ;;
    esac
  done
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state
  state=$(mbw_budget_slot "$bank" "$run_id")
  if [ ! -f "$state" ]; then
    echo "[budget] no active budget" >&2
    exit 1
  fi
  # A mismatched run_id means the on-disk budget is orphaned from a
  # different run: treat it as stale (warn, exit 1) — never a false STOP.
  if [ -n "$run_id" ]; then
    require_matching_run_id "$state" "$run_id" || {
      echo "[budget] run_id mismatch (stale budget) — ignoring, not a stop" >&2
      exit 1
    }
  fi
  STATE="$state" python3 - <<'PY'
import json, os, sys
data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
total = int(data["total"])
spent = int(data.get("spent", 0))
warn = int(data["warn_at_percent"])
stop = int(data["stop_at_percent"])
if total <= 0:
    sys.exit(0)
pct = spent * 100 / total
if pct >= stop:
    sys.stderr.write(f"[budget] STOP: spent {spent}/{total} ({pct:.1f}% >= {stop}%)\n")
    sys.exit(2)
if pct >= warn:
    sys.stderr.write(f"[budget] WARN: spent {spent}/{total} ({pct:.1f}% >= {warn}%)\n")
    sys.exit(1)
sys.exit(0)
PY
}

cmd_clear() {
  local mb_arg=""
  local run_id=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --run-id) run_id="${2:-}"; shift 2 ;;
      --run-id=*) run_id="${1#--run-id=}"; shift ;;
      --mb) mb_arg="${2:-}"; shift 2 ;;
      --mb=*) mb_arg="${1#--mb=}"; shift ;;
      *) shift ;;
    esac
  done
  local bank
  bank=$(mb_resolve_path "$mb_arg")
  local state
  state=$(mbw_budget_slot "$bank" "$run_id")
  rm -f "$state"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage; exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    init) shift; cmd_init "$@" ;;
    add) shift; cmd_add "$@" ;;
    status) shift; cmd_status "$@" ;;
    check) shift; cmd_check "$@" ;;
    clear) shift; cmd_clear "$@" ;;
    *) echo "[budget] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
