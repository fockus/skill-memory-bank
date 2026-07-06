#!/usr/bin/env bash
# mb-drive.sh — the drive-loop decision function (drive-loop design.md
# §"The decision function"; Task 1 — REQ-DR-002/010/011/012/013/014/020/021).
#
# "The agent is the runtime; mb-drive.sh is the brain." Computes NOTHING new:
# given the outputs of five ALREADY-EXISTING scripts, prints exactly one
# deterministic next action and exits 0. No daemon, no cross-invocation
# state, no second done-authority/cycle-counter/trend-calculator/budget-gate
# (ADR-1/ADR-2).
#
# Subcommands:
#   next   --bank <b> [--route R] [--phase P] [--budget TOK] [--run-id ID]
#          [--consecutive-stagnant N] — gathers the 5 signals from the real
#          scripts (Reuse map below), applies the table, prints ONE action
#          line, exit 0.
#   status --bank <b> [same flags as next] — read-only: gathered signals +
#          the action `next` would take, as one JSON object (debugging aid).
#   decide --gate 0|1|2 --done-pct 0-100 [--bud ok|exceeded]
#          [--cyc-exhausted 0|1] [--stall 0|1]
#          [--last-pivot none|in_role|via_architect]
#          [--pivot-mode refine|pivot_in_role|pivot_via_architect] [--route R]
#          [--current-item TXT] [--next-item TXT] [--broken-check NAME]
#          TEST SEAM (the chosen signal-injection mechanism): runs the SAME
#          pure decision core (`mbd_decide` below) off explicit values — no
#          bank, no live goal/firewall needed. `next`/`decide` share ONE
#          implementation; `next` just supplies signals by asking the real
#          scripts instead of `--flags`.
#
# Action grammar (prints exactly one line, exit 0):
#   implement <route> <item> | repair <item> | pivot <in_role|via_architect> <item>
#   stop_success | stop_human <check-broke:<name>|max-cycle|stall|undecidable> | stop_budget
#
# Decision table (first match wins — ORDER IS THE SAFETY CONTRACT; stops
# before progress; pivot before repair):
#   1. gate==2                                          -> stop_human check-broke:<name>
#   2. bud==exceeded                                     -> stop_budget
#   3. done_pct==100 AND gate==0                         -> stop_success
#   4. cyc_exhausted OR (stall AND last_pivot==architect)-> stop_human max-cycle|stall
#   5. gate==1 AND pivot_mode != refine                  -> pivot <mode> <item>
#   6. gate==1                                           -> repair <item>
#   7. done_pct<100                                      -> implement <route> <item>
# `stop_success` is IMPOSSIBLE unless BOTH firewall exit 0 AND acceptance 100%
# (REQ-DR-014) — "done" against a red firewall (gate==1) always falls through
# to repair/pivot, never stop_success.
#
# Reuse map (net-new logic: none; each overridable via env var for tests,
# mirroring mb-flow-verify.sh's MB_SEVERITY_GATE/MB_TEST_RUN_BIN pattern):
#   acc   MB_GOAL_ACCEPTANCE_BIN mb-goal-acceptance.sh "" <bank>      -> ok true/false/null, findings[]
#   gate  MB_FLOW_VERIFY_BIN     mb-flow-verify.sh <bank> [--phase P] -> exit 0/1/2, checks[]
#   cyc   MB_WORK_STATE_BIN      mb-work-state.sh status --mb <bank>  -> cycle,max_cycles, READ-ONLY
#                                (the LOOP calls `cycle` to increment, never this script — REQ-DR-021)
#   bud   MB_WORK_BUDGET_BIN     mb-work-budget.sh check --mb <bank>  -> exit 0/1 ok, 2 exceeded
#   pivot MB_WORK_PIVOT_BIN      mb-work-pivot.sh decide --consecutive-stagnant N --cycle C --mb <bank>
#                                -> refine|pivot_in_role|pivot_via_architect (no --item-id -> no telemetry)
#
# Fail-closed (never a silent wrong action; fix-cycle 1 hardened this): ANY
# reused script exiting/emitting outside its documented contract (missing
# binary, crash, timeout, unparseable JSON, an out-of-enum/non-boolean value)
# forces gate==2 — `stop_human check-broke:<offender>` — dominating the other
# four signals; see `_mbd_gather` for the per-signal validation (type-strict
# acceptance `ok`, numeric-or-absent work-state fields, `[budget]`-prefixed
# budget exit-1, timeout-wrapped calls).
#
# Seam left for Task 3: the Phase-2 `mb-flow` fence (mb-flow-sync.sh) writes
# `stall_count` but ships no reader, and no field records "last pivot was
# via_architect" — `next` defaults `--consecutive-stagnant`/`stall`/
# `last_pivot` to 0/0/"none" until Task 3 wires the real fence reader. Rules
# 4/5 are already fully implemented in the core.
#
# Portability: bash-3.2 safe; no new third-party dependency (python3 already
# a project-wide assumption); `timeout`/`gtimeout` optional (§Reuse map).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

usage() {
  sed -n '2,44p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# JSON introspection for `_mbd_gather` (one python boilerplate, several
# modes). $1=json $2=mode: field:<n> -> true/false/null/<raw>/__ERR__ ·
# bool_field:<n> -> true/false ONLY for a literal JSON boolean, else __ERR__
# (type-STRICT: {"ok":"true"} must never coerce to real `true`) ·
# first_finding -> first acceptance pending finding, or "" · first_broken_check
# -> name of the first flow-verify check with status==broke, or "unknown".
_mbd_json() {
  MBD_JSON="$1" MBD_MODE="$2" python3 - <<'PY' 2>/dev/null
import json, os

mode = os.environ.get("MBD_MODE", "")
try:
    obj = json.loads(os.environ.get("MBD_JSON", ""))
except Exception:
    obj = None

if mode.startswith("bool_field:"):
    v = obj.get(mode[len("bool_field:"):]) if isinstance(obj, dict) else None
    print("true" if v is True else "false" if v is False else "__ERR__")
elif mode.startswith("field:"):
    if not isinstance(obj, dict):
        print("__ERR__")
    else:
        v = obj.get(mode[len("field:"):])
        print("true" if v is True else "false" if v is False else "null" if v is None else v)
elif mode == "first_finding":
    findings = obj.get("findings") if isinstance(obj, dict) else None
    print(findings[0] if isinstance(findings, list) and findings else "")
elif mode == "first_broken_check":
    name = "unknown"
    for c in (obj.get("checks") or []) if isinstance(obj, dict) else []:
        if isinstance(c, dict) and c.get("status") == "broke":
            name = c.get("name") or "unknown"
            break
    print(name)
else:
    print("__ERR__")
PY
}

# $1 -> 0 if non-empty and single-line (safe as a printf action token), else 1.
# Guards rules 5/6/7 below: a progress action with an empty/multiline route or
# item is a malformed line that breaks the host loop's parsing (fix-cycle 1 #2).
_mbd_valid_token() {
  case "$1" in
    "") return 1 ;;
    *$'\n'*) return 1 ;;
    *) return 0 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────
# The decision core — pure, side-effect-free. See header for the table.
# $1 gate $2 done_pct $3 bud_status $4 cyc_exhausted $5 stall $6 last_pivot
# $7 pivot_mode $8 route $9 current_item $10 next_item $11 broken_check
# ─────────────────────────────────────────────────────────────────────────
mbd_decide() {
  local gate="$1" done_pct="$2" bud_status="$3" cyc_exhausted="$4" stall="$5" \
        last_pivot="$6" pivot_mode="$7" route="$8" current_item="$9" next_item="${10}" \
        broken_check="${11:-}"

  # Rule 1 — a check script itself broke: the loudest failure, dominates all.
  if [ "$gate" -eq 2 ]; then printf 'stop_human check-broke:%s\n' "${broken_check:-unknown}"; return 0; fi

  # Rule 2 — over budget: stop BEFORE dispatching any more work.
  if [ "$bud_status" = "exceeded" ]; then printf 'stop_budget\n'; return 0; fi

  # Rule 3 — the ONLY door to success (REQ-DR-014): firewall green AND
  # acceptance 100%. Never the model's self-assessment.
  if [ "$done_pct" -eq 100 ] && [ "$gate" -eq 0 ]; then printf 'stop_success\n'; return 0; fi

  # Rule 4 — durable cycle budget exhausted, or stalled after the heaviest
  # (via_architect) pivot already failed to move the trend.
  if [ "$cyc_exhausted" = "1" ]; then printf 'stop_human max-cycle\n'; return 0; fi
  if [ "$stall" = "1" ] && [ "$last_pivot" = "via_architect" ]; then printf 'stop_human stall\n'; return 0; fi

  # Rule 5 — pivot beats repair: escalate a stagnant item instead of grinding.
  # Guarded: an empty item can never reach a bare "pivot <mode> " line.
  if [ "$gate" -eq 1 ] && { [ "$pivot_mode" = "pivot_in_role" ] || [ "$pivot_mode" = "pivot_via_architect" ]; }; then
    if ! _mbd_valid_token "$current_item"; then printf 'stop_human undecidable\n'; return 0; fi
    local mode_token="in_role"
    [ "$pivot_mode" = "pivot_via_architect" ] && mode_token="via_architect"
    printf 'pivot %s %s\n' "$mode_token" "$current_item"
    return 0
  fi

  # Rule 6 — red firewall, same item, another cycle (the LOOP increments the
  # durable cycle via mb-work-state.sh cycle, never this function — REQ-DR-021).
  # Guarded: an empty item can never reach a bare "repair " line.
  if [ "$gate" -eq 1 ]; then
    if _mbd_valid_token "$current_item"; then printf 'repair %s\n' "$current_item"; else printf 'stop_human undecidable\n'; fi
    return 0
  fi

  # Rule 7 — green firewall, goal not yet complete: keep going. Guarded: an
  # empty next_item means acceptance couldn't name one (its own ok:false
  # contract requires >=1 finding) -> check-broke:acceptance, never a bare
  # "implement <route> " line; an empty route is a separate config problem.
  if [ "$done_pct" -lt 100 ]; then
    if ! _mbd_valid_token "$next_item"; then
      printf 'stop_human check-broke:acceptance\n'
    elif ! _mbd_valid_token "$route"; then
      printf 'stop_human undecidable\n'
    else
      printf 'implement %s %s\n' "$route" "$next_item"
    fi
    return 0
  fi

  # Unreachable given validated inputs (gate in {0,1,2} is exhaustively
  # handled by rules 1/5/6/7 above) — a defensive net, never silent.
  printf 'stop_human undecidable\n'
}

# Timeout wrapper (fix-cycle 1 #5): a hung sub-script must not hang the loop.
# Uses `timeout`/macOS `gtimeout` when on PATH (neither ships on stock macOS
# bash-3.2); degrades to unwrapped when absent, never a hard-fail on that
# alone. $MB_DRIVE_TIMEOUT seconds (default 20); a timeout kill's exit code
# already falls into each call site's existing "unexpected code" bucket.
_mbd_init_timeout() {
  MBD_TO_SECS="${MB_DRIVE_TIMEOUT:-20}"
  if command -v timeout >/dev/null 2>&1; then MBD_TO_BIN="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then MBD_TO_BIN="gtimeout"
  else MBD_TO_BIN=""
  fi
}

_mbd_run() {
  if [ -n "$MBD_TO_BIN" ]; then "$MBD_TO_BIN" "$MBD_TO_SECS" "$@"; else "$@"; fi
}

# ─────────────────────────────────────────────────────────────────────────
# Real-signal gathering. Sets (exported, for cmd_status) MBD_* globals; never
# returns non-zero itself — an unexpectedly-broken sub-script is folded into
# MBD_GATE=2 (fail-closed). $1=bank $2=route $3=phase $4=run_id $5=consecutive
# ─────────────────────────────────────────────────────────────────────────
export MBD_NEXT_ITEM MBD_DONE_PCT MBD_GATE MBD_BROKEN_CHECK MBD_CYCLE MBD_MAX_CYCLES \
  MBD_CYC_EXHAUSTED MBD_BUD MBD_PIVOT_MODE MBD_STALL MBD_LAST_PIVOT MBD_ROUTE MBD_CURRENT_ITEM

_mbd_gather() {
  local bank="$1" route="$2" phase="$3" run_id="$4" consecutive="$5"
  local broken_name="" out rc bin
  _mbd_init_timeout

  # acceptance (contract: ALWAYS exits 0) -> MBD_NEXT_ITEM. `ok` is TYPE-STRICT
  # (bool_field:, see header Fail-closed) -> REQ-DR-014.
  bin="${MB_GOAL_ACCEPTANCE_BIN:-$SCRIPT_DIR/mb-goal-acceptance.sh}"
  set +e; out="$(_mbd_run "$bin" "" "$bank" 2>/dev/null)"; rc=$?; set -e
  MBD_NEXT_ITEM=""
  local acc_ok="false"
  if [ "$rc" -ne 0 ]; then
    broken_name="acceptance"
  else
    acc_ok="$(_mbd_json "$out" bool_field:ok)"
    case "$acc_ok" in
      true|false) MBD_NEXT_ITEM="$(_mbd_json "$out" first_finding)" ;;
      *) broken_name="acceptance"; acc_ok="false" ;;
    esac
  fi
  # done_pct is a BINARY 0/100 signal (mb-goal-acceptance.sh reports only a
  # boolean, no fractional percentage) — never a real completion percentage.
  MBD_DONE_PCT=0
  [ "$acc_ok" = "true" ] && MBD_DONE_PCT=100

  # firewall (contract: exits ONLY 0/1/2) -> MBD_GATE, MBD_BROKEN_CHECK
  bin="${MB_FLOW_VERIFY_BIN:-$SCRIPT_DIR/mb-flow-verify.sh}"
  set +e
  if [ -n "$phase" ]; then out="$(_mbd_run "$bin" "$bank" --phase "$phase" 2>/dev/null)"; else out="$(_mbd_run "$bin" "$bank" 2>/dev/null)"; fi
  rc=$?
  set -e
  case "$rc" in
    0|1|2) MBD_GATE="$rc" ;;
    *) MBD_GATE=2; [ -z "$broken_name" ] && broken_name="mb-flow-verify" ;;
  esac
  MBD_BROKEN_CHECK=""
  if [ "$MBD_GATE" -eq 2 ] && [ "$rc" = "2" ] && [ -z "$broken_name" ]; then
    MBD_BROKEN_CHECK="$(_mbd_json "$out" first_broken_check)"
  fi

  # durable cycle counter (READ-ONLY; `next` never mutates it) -> MBD_CYCLE,
  # MBD_MAX_CYCLES, MBD_CYC_EXHAUSTED, MBD_CURRENT_ITEM. absent/null field ==
  # legit no-run-yet (0); PRESENT-but-non-numeric/unparseable == check-broke,
  # never masked to cycle=0 (see header Fail-closed).
  bin="${MB_WORK_STATE_BIN:-$SCRIPT_DIR/mb-work-state.sh}"
  local ws_args=(status --mb "$bank")
  [ -n "$run_id" ] && ws_args+=(--run-id "$run_id")
  set +e; out="$(_mbd_run "$bin" "${ws_args[@]}" 2>/dev/null)"; rc=$?; set -e
  MBD_CURRENT_ITEM="(current)"
  local cycle="0" max_cycles="0" c m h
  if [ "$rc" -ne 0 ]; then
    [ -z "$broken_name" ] && broken_name="work-state"
  else
    c="$(_mbd_json "$out" field:cycle)"
    m="$(_mbd_json "$out" field:max_cycles)"
    h="$(_mbd_json "$out" field:heading)"
    case "$c" in null) : ;; *) is_uint "$c" && cycle="$c" || { [ -z "$broken_name" ] && broken_name="work-state"; } ;; esac
    case "$m" in null) : ;; *) is_uint "$m" && max_cycles="$m" || { [ -z "$broken_name" ] && broken_name="work-state"; } ;; esac
    [ -n "$h" ] && [ "$h" != "null" ] && [ "$h" != "__ERR__" ] && MBD_CURRENT_ITEM="$h"
  fi
  MBD_CYCLE="$cycle"; MBD_MAX_CYCLES="$max_cycles"
  MBD_CYC_EXHAUSTED=0
  [ "$max_cycles" -gt 0 ] && [ "$cycle" -ge "$max_cycles" ] && MBD_CYC_EXHAUSTED=1

  # budget -> MBD_BUD (0->ok, 2->exceeded). exit 1 is ambiguous in the source
  # (no-budget/stale/WARN share it with a crash) -> disambiguate via the
  # `[budget] `-prefixed stderr every documented path emits (header Fail-closed).
  bin="${MB_WORK_BUDGET_BIN:-$SCRIPT_DIR/mb-work-budget.sh}"
  local bud_args=(check --mb "$bank") bud_err
  [ -n "$run_id" ] && bud_args+=(--run-id "$run_id")
  set +e; bud_err="$(_mbd_run "$bin" "${bud_args[@]}" 2>&1 >/dev/null)"; rc=$?; set -e
  case "$rc" in
    0) MBD_BUD="ok" ;;
    2) MBD_BUD="exceeded" ;;
    1)
      case "$bud_err" in
        '[budget]'*) MBD_BUD="ok" ;;
        *) MBD_BUD="ok"; [ -z "$broken_name" ] && broken_name="work-budget" ;;
      esac
      ;;
    *) MBD_BUD="ok"; [ -z "$broken_name" ] && broken_name="work-budget" ;;
  esac

  # pivot mode -> MBD_PIVOT_MODE (best-effort; --consecutive-stagnant
  # defaults to 0 until the Phase-2 fence exposes a stall_count reader — the
  # header "Seam" note). Never passes --item-id, so no telemetry side effect.
  bin="${MB_WORK_PIVOT_BIN:-$SCRIPT_DIR/mb-work-pivot.sh}"
  set +e
  MBD_PIVOT_MODE="$(_mbd_run "$bin" decide --mb "$bank" --consecutive-stagnant "$consecutive" --cycle "$cycle" 2>/dev/null)"
  rc=$?
  set -e
  case "$MBD_PIVOT_MODE" in
    refine|pivot_in_role|pivot_via_architect) : ;;
    *) MBD_PIVOT_MODE="refine"; rc=1 ;;
  esac
  if [ "$rc" -ne 0 ]; then
    MBD_PIVOT_MODE="refine"
    [ -z "$broken_name" ] && broken_name="work-pivot"
  fi

  # stall / last_pivot: not yet wired from the Phase-2 fence (seam, see header)
  MBD_STALL=0
  MBD_LAST_PIVOT="none"

  # fail-closed override: any unexpectedly-broken sub-script forces gate==2,
  # dominating whatever the other four signals reported.
  if [ -n "$broken_name" ]; then
    MBD_GATE=2
    MBD_BROKEN_CHECK="$broken_name"
  fi

  MBD_ROUTE="$route"
}

# ─────────────────────────────────────────────────────────────────────────
# Subcommands
# ─────────────────────────────────────────────────────────────────────────

_mbd_parse_gather_flags() {
  # Shared flag parser for `next`/`status` -> BANK_ARG ROUTE PHASE RUN_ID
  # CONSECUTIVE globals. --budget is accepted for interface parity (design.md
  # §Interfaces) but is a no-op: the ceiling is set via `mb-work-budget.sh
  # init` by the `/mb drive` wrapper (Task 2); `next` only ever *reads* it.
  BANK_ARG=""; ROUTE="auto"; PHASE=""; RUN_ID=""; CONSECUTIVE="0"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --bank) BANK_ARG="${2:-}"; shift 2 ;; --bank=*) BANK_ARG="${1#--bank=}"; shift ;;
      --route) ROUTE="${2:-}"; shift 2 ;; --route=*) ROUTE="${1#--route=}"; shift ;;
      --phase) PHASE="${2:-}"; shift 2 ;; --phase=*) PHASE="${1#--phase=}"; shift ;;
      --budget) shift 2 ;; --budget=*) shift ;;
      --run-id) RUN_ID="${2:-}"; shift 2 ;; --run-id=*) RUN_ID="${1#--run-id=}"; shift ;;
      --consecutive-stagnant) CONSECUTIVE="${2:-}"; shift 2 ;;
      --consecutive-stagnant=*) CONSECUTIVE="${1#--consecutive-stagnant=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[drive] unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  is_uint "$CONSECUTIVE" || CONSECUTIVE=0
}

cmd_next() {
  _mbd_parse_gather_flags "$@"
  local bank; bank=$(mb_resolve_path "$BANK_ARG")
  _mbd_gather "$bank" "$ROUTE" "$PHASE" "$RUN_ID" "$CONSECUTIVE"
  mbd_decide "$MBD_GATE" "$MBD_DONE_PCT" "$MBD_BUD" "$MBD_CYC_EXHAUSTED" "$MBD_STALL" \
    "$MBD_LAST_PIVOT" "$MBD_PIVOT_MODE" "$MBD_ROUTE" "$MBD_CURRENT_ITEM" "$MBD_NEXT_ITEM" \
    "$MBD_BROKEN_CHECK"
}

cmd_status() {
  _mbd_parse_gather_flags "$@"
  local bank; bank=$(mb_resolve_path "$BANK_ARG")
  _mbd_gather "$bank" "$ROUTE" "$PHASE" "$RUN_ID" "$CONSECUTIVE"
  local action
  action=$(mbd_decide "$MBD_GATE" "$MBD_DONE_PCT" "$MBD_BUD" "$MBD_CYC_EXHAUSTED" "$MBD_STALL" \
    "$MBD_LAST_PIVOT" "$MBD_PIVOT_MODE" "$MBD_ROUTE" "$MBD_CURRENT_ITEM" "$MBD_NEXT_ITEM" \
    "$MBD_BROKEN_CHECK")
  ACTION="$action" python3 - <<'PY'
import json, os
e = os.environ
print(json.dumps({
    "gate": int(e["MBD_GATE"]), "done_pct": int(e["MBD_DONE_PCT"]), "bud": e["MBD_BUD"],
    "cycle": int(e["MBD_CYCLE"]), "max_cycles": int(e["MBD_MAX_CYCLES"]),
    "cyc_exhausted": e["MBD_CYC_EXHAUSTED"] == "1", "stall": e["MBD_STALL"] == "1",
    "last_pivot": e["MBD_LAST_PIVOT"], "pivot_mode": e["MBD_PIVOT_MODE"], "route": e["MBD_ROUTE"],
    "current_item": e["MBD_CURRENT_ITEM"], "next_item": e["MBD_NEXT_ITEM"],
    "broken_check": e["MBD_BROKEN_CHECK"], "action": e["ACTION"],
}))
PY
}

cmd_decide() {
  local gate="" done_pct="" bud="ok" cyc_exhausted="0" stall="0" last_pivot="none" \
    pivot_mode="refine" route="auto" current_item="(current)" next_item="" broken_check=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --gate) gate="${2:-}"; shift 2 ;; --gate=*) gate="${1#--gate=}"; shift ;;
      --done-pct) done_pct="${2:-}"; shift 2 ;; --done-pct=*) done_pct="${1#--done-pct=}"; shift ;;
      --bud) bud="${2:-}"; shift 2 ;; --bud=*) bud="${1#--bud=}"; shift ;;
      --cyc-exhausted) cyc_exhausted="${2:-}"; shift 2 ;;
      --cyc-exhausted=*) cyc_exhausted="${1#--cyc-exhausted=}"; shift ;;
      --stall) stall="${2:-}"; shift 2 ;; --stall=*) stall="${1#--stall=}"; shift ;;
      --last-pivot) last_pivot="${2:-}"; shift 2 ;;
      --last-pivot=*) last_pivot="${1#--last-pivot=}"; shift ;;
      --pivot-mode) pivot_mode="${2:-}"; shift 2 ;;
      --pivot-mode=*) pivot_mode="${1#--pivot-mode=}"; shift ;;
      --route) route="${2:-}"; shift 2 ;; --route=*) route="${1#--route=}"; shift ;;
      --current-item) current_item="${2:-}"; shift 2 ;;
      --current-item=*) current_item="${1#--current-item=}"; shift ;;
      --next-item) next_item="${2:-}"; shift 2 ;; --next-item=*) next_item="${1#--next-item=}"; shift ;;
      --broken-check) broken_check="${2:-}"; shift 2 ;;
      --broken-check=*) broken_check="${1#--broken-check=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[drive] decide: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done

  case "$gate" in 0|1|2) : ;; *) echo "[drive] decide requires --gate 0|1|2" >&2; exit 2 ;; esac
  is_uint "$done_pct" && [ "$done_pct" -le 100 ] || {
    echo "[drive] decide requires --done-pct 0..100" >&2
    exit 2
  }
  case "$bud" in ok|exceeded) : ;; *) echo "[drive] decide requires --bud ok|exceeded" >&2; exit 2 ;; esac
  case "$cyc_exhausted" in 0|1) : ;; *) echo "[drive] decide requires --cyc-exhausted 0|1" >&2; exit 2 ;; esac
  case "$stall" in 0|1) : ;; *) echo "[drive] decide requires --stall 0|1" >&2; exit 2 ;; esac
  case "$last_pivot" in none|in_role|via_architect) : ;; *) echo "[drive] decide requires --last-pivot none|in_role|via_architect" >&2; exit 2 ;; esac
  case "$pivot_mode" in refine|pivot_in_role|pivot_via_architect) : ;; *) echo "[drive] decide requires --pivot-mode refine|pivot_in_role|pivot_via_architect" >&2; exit 2 ;; esac

  mbd_decide "$gate" "$done_pct" "$bud" "$cyc_exhausted" "$stall" "$last_pivot" \
    "$pivot_mode" "$route" "$current_item" "$next_item" "$broken_check"
}

main() {
  if [ "$#" -lt 1 ]; then
    usage; exit 2
  fi
  case "$1" in
    -h|--help) usage; exit 0 ;;
    next) shift; cmd_next "$@" ;;
    status) shift; cmd_status "$@" ;;
    decide) shift; cmd_decide "$@" ;;
    *) echo "[drive] unknown subcommand '$1'" >&2; usage; exit 2 ;;
  esac
}

main "$@"
