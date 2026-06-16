#!/usr/bin/env bash
# mb-flow-branch-sink.sh — per-branch result sinks + fence-write-once discipline
# (dynamic-flow Task 12, open-Q2 / ADR-9 / REQ-DF-030/031).
#
# Resolves the concurrency hazard that ADR-9 flagged as load-bearing: because
# `mb-fanout.sh` runs branches in PARALLEL, the single `<!-- mb-flow -->` fence
# and any shared sink must have a write discipline. The discipline (open-Q2):
#
#   • Each PARALLEL branch writes its OWN result to `.mb-flow/branch-<i>.json`
#     (one file per index → two branches never write the same path → no race).
#   • The `<!-- mb-flow -->` fence is written EXACTLY ONCE, SERIALLY, by the
#     INITIATING agent AFTER it has collected the per-branch sinks — NEVER by a
#     branch. A branch context is structurally forbidden from touching the fence.
#
# This script is the single tool for BOTH halves, with a hard guard between them:
#
#   write  — a SINGLE branch writes ONE `.mb-flow/branch-<i>.json` (atomic: tmp
#            + mv). It NEVER opens status.md / the fence. Asking it to also write
#            the fence (`--fence`) is REFUSED — a branch may not write the fence.
#   fence  — the INITIATOR aggregates `.mb-flow/branch-*.json` and writes the
#            `<!-- mb-flow -->` fence ONCE by REUSING mb-flow-sync.sh, so content
#            OUTSIDE the markers is byte-preserved (REQ-DF-030) and goal.md is
#            never opened (REQ-DF-031). Idempotent on identical inputs.
#
# Usage:
#   mb-flow-branch-sink.sh [mb_path] write --index N (--result JSON | --result-file F)
#   mb-flow-branch-sink.sh [mb_path] fence [--route R] [--phase k/n] [--phases CSV]
#                          [--gate PASS|FAIL] [--last-verify-sha SHA] [--stall-count N]
#
#   mb_path  Memory Bank path (default via _lib.sh::mb_resolve_path).
#   write --index N      branch index (non-negative integer) → branch-N.json.
#   write --result JSON  the branch result; MUST be a valid JSON value.
#   write --result-file F  read the result JSON from file F instead.
#   fence  flags pass through to mb-flow-sync.sh (route/phase/gate/...).
#
# Exit codes:
#   0  OK.
#   1  argument error / invalid JSON / a branch attempted to write the fence
#      (the open-Q2 guard) / mb-flow-sync write error.
#   2  internal error (mb-flow-sync lock timeout, propagated).
#
# Portability: bash 3.2 safe (no associative arrays, no mapfile, empty-array
# expansions guarded); set -euo pipefail; JSON validated via python3 json.loads.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

FLOW_SYNC="${MB_FLOW_SYNC_BIN:-$SCRIPT_DIR/mb-flow-sync.sh}"

usage() {
  sed -n '2,46p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  printf '[mb-flow-branch-sink] %s\n' "$1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# write mode — one branch writes ONE per-branch sink. NEVER the fence.
# ---------------------------------------------------------------------------
do_write() {
  local mb="$1"; shift
  local index="" result="" result_file="" fence_flag=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --index)
        [ "$#" -ge 2 ] || die "--index needs a value"
        index="$2"; shift 2 ;;
      --index=*) index="${1#--index=}"; shift ;;
      --result)
        [ "$#" -ge 2 ] || die "--result needs a value"
        result="$2"; shift 2 ;;
      --result=*) result="${1#--result=}"; shift ;;
      --result-file)
        [ "$#" -ge 2 ] || die "--result-file needs a value"
        result_file="$2"; shift 2 ;;
      --result-file=*) result_file="${1#--result-file=}"; shift ;;
      # open-Q2 GUARD: a branch context may NEVER write the fence. Asking the
      # write path to also touch the fence is a contract breach → refuse loudly.
      --fence) fence_flag=1; shift ;;
      *) die "write: unexpected argument: $1" ;;
    esac
  done

  if [ "$fence_flag" -eq 1 ]; then
    die "a branch (write mode) may NOT write the mb-flow fence — the fence is written ONCE, serially, by the initiating agent (open-Q2). Use 'fence' mode from the initiator."
  fi

  # Index must be a non-negative integer (digits only, ≤18 digits to stay within
  # a 64-bit int; an absurd digit string is a usage error, not a crash).
  case "$index" in
    ''|*[!0-9]*) die "--index must be a non-negative integer: '$index'" ;;
  esac
  [ "${#index}" -le 18 ] || die "--index out of range (too many digits): $index"

  # Read the result from a file if requested (mutually exclusive with --result).
  if [ -n "$result_file" ]; then
    [ -z "$result" ] || die "pass exactly one of --result / --result-file"
    [ -f "$result_file" ] || die "--result-file: no such file: $result_file"
    result="$(cat "$result_file" 2>/dev/null)" || die "--result-file: cannot read file: $result_file"
  fi
  [ -n "$result" ] || die "write needs --result or --result-file"

  # Validate the result is a parseable JSON VALUE before writing — a branch sink
  # must never persist garbage that the initiator's aggregation would choke on.
  # Reject non-strict JSON: Python's json accepts NaN/Infinity/-Infinity by
  # default, but those are NOT valid per the JSON spec and break strict downstream
  # readers. parse_constant fires for exactly those tokens — raise to reject them.
  if ! printf '%s' "$result" | "${MB_PYTHON:-python3}" -c 'import json,sys
def _reject(_c): raise ValueError("non-finite JSON literal not allowed")
json.loads(sys.stdin.read(), parse_constant=_reject)' 2>/dev/null; then
    die "write: --result is not valid (strict) JSON"
  fi

  local flow_dir="$mb/.mb-flow"
  mkdir -p "$flow_dir"
  local sink="$flow_dir/branch-$index.json"

  # Atomic write: render to a per-branch tmp (the index keeps tmp names distinct
  # across parallel branches), then mv into place. status.md / the fence / goal.md
  # are NEVER opened here — a branch only ever touches its own sink.
  local tmp="$flow_dir/.branch-$index.tmp.$$"
  printf '%s' "$result" > "$tmp" || die "could not write sink tmp: $tmp"
  mv -f "$tmp" "$sink" || { rm -f "$tmp" 2>/dev/null || true; die "could not place sink: $sink"; }

  printf '[mb-flow-branch-sink] wrote %s\n' "$sink"
  return 0
}

# ---------------------------------------------------------------------------
# fence mode — the INITIATOR writes the mb-flow fence ONCE by reusing
# mb-flow-sync.sh (the idempotent marker-fence writer). Content outside the
# markers is byte-preserved (REQ-DF-030); goal.md is never opened (REQ-DF-031).
# The per-branch sinks under .mb-flow/ are the aggregation inputs; this script
# does not duplicate their content into the fence (the fence stays POINTER-only,
# ADR-5) — it records the route/phase/gate runtime fields the initiator passes.
# ---------------------------------------------------------------------------
do_fence() {
  local mb="$1"; shift
  # open-Q2 STRUCTURAL guard: the fence is written ONCE, serially, by the
  # INITIATOR — NEVER by a fan-out branch. mb-fanout.sh exports
  # MB_FANOUT_BRANCH_INDEX into every branch context, so its presence here means a
  # branch is trying to write the fence DIRECTLY (bypassing the `write --fence`
  # guard). Refuse loudly — otherwise two parallel branches could race the single
  # fence. The initiator has NO MB_FANOUT_BRANCH_INDEX, so it is unaffected.
  if [ -n "${MB_FANOUT_BRANCH_INDEX:-}" ]; then
    die "fence mode is initiator-only: refusing to write the mb-flow fence from a branch context (MB_FANOUT_BRANCH_INDEX=$MB_FANOUT_BRANCH_INDEX). The fence is written ONCE, serially, by the initiating agent (open-Q2/DoD#3)."
  fi
  # All remaining flags pass straight through to mb-flow-sync.sh, which owns the
  # fence schema + byte-preservation + idempotency. We add NOTHING to its exit
  # semantics (0 OK / 1 write or malformed-fence / 2 lock timeout).
  if [ "$#" -gt 0 ]; then
    bash "$FLOW_SYNC" "$mb" "$@"
  else
    bash "$FLOW_SYNC" "$mb"
  fi
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
main() {
  local mb_arg="" mode=""
  local rest
  rest=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0 ;;
      write|fence)
        if [ -z "$mode" ]; then
          mode="$1"
        else
          rest+=("$1")
        fi
        shift ;;
      --)
        shift ;;
      -*)
        # A flag before a mode was selected is invalid; otherwise it belongs to
        # the mode's own arg parser (collected into rest).
        if [ -z "$mode" ]; then
          die "unknown flag before mode: $1"
        fi
        rest+=("$1")
        shift ;;
      *)
        if [ -z "$mode" ] && [ -z "$mb_arg" ]; then
          mb_arg="$1"
        elif [ -z "$mode" ]; then
          die "unexpected argument before mode: $1"
        else
          rest+=("$1")
        fi
        shift ;;
    esac
  done

  [ -n "$mode" ] || die "a mode is required: 'write' or 'fence'"

  local mb
  mb="$(mb_resolve_path "$mb_arg")"
  if [ ! -d "$mb" ]; then
    die ".memory-bank not found at: $mb"
  fi

  case "$mode" in
    write)
      if [ "${#rest[@]}" -gt 0 ]; then
        do_write "$mb" "${rest[@]}"
      else
        do_write "$mb"
      fi
      ;;
    fence)
      if [ "${#rest[@]}" -gt 0 ]; then
        do_fence "$mb" "${rest[@]}"
      else
        do_fence "$mb"
      fi
      ;;
  esac
}

main "$@"
