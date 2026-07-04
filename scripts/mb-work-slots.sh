# mb-work-slots.sh — sourced helper: per-run state/budget slot-path
# resolution + a source→run claim index, gated behind MB_WORK_PARALLEL.
#
# NOT an executable entry point (no `main`, no shebang-driven exec path) —
# source it from mb-work-state.sh (and, in later I-094 stages, budget /
# checkbox / resolve / diff):
#   # shellcheck source=mb-work-slots.sh
#   source "$SCRIPT_DIR/mb-work-slots.sh"
#
# Public functions (all fail-safe — never crash the sourcing script; a
# missing/unreadable/corrupt index or slot always degrades to "" / the
# singleton path, never a non-zero exit from this file):
#   mbw_parallel_on                            true (exit 0) when
#                                               MB_WORK_PARALLEL is truthy
#   mbw_state_slot   <bank> [run_id]           echoes the state-file path
#   mbw_budget_slot  <bank> [run_id]           echoes the budget-file path
#   mbw_source_hash  <source>                  echoes a stable short hash
#   mbw_index_set    <bank> <source> <run_id>  claims <source> for <run_id>
#   mbw_index_get    <bank> <source>           echoes the claiming run_id,
#                                               or "" (fail-safe)
#   mbw_index_del    <bank> <source>           releases the claim, if any
#
# Isolation model: when MB_WORK_PARALLEL is unset/falsy, mbw_state_slot /
# mbw_budget_slot ALWAYS return the legacy singleton path
# (<bank>/.work-state.json / <bank>/.work-budget.json) — byte-identical to
# pre-I-094 behaviour — regardless of whether a run_id was supplied. Only
# `MB_WORK_PARALLEL=1` together with a non-empty run_id routes to a per-run
# slot at <bank>/.work-state/<run_id>.json / <bank>/.work-budget/<run_id>.json.
# This is what keeps the singleton default byte-identical while still letting
# a caller pass --run-id for other reasons (budget's existing run_id-mismatch
# guard, I-093) without accidentally isolating it.
#
# The claim index lives at <bank>/.work-state/by-source/<hash-of-source>, a
# one-line file containing the owning run_id (chosen over a symlink for
# portability across filesystems that don't support them). All index reads
# are fail-safe: a missing/unreadable/corrupt entry degrades to "" (treated
# as "unclaimed"), never an error.

# shellcheck shell=bash

mbw_parallel_on() {
  case "${MB_WORK_PARALLEL:-}" in
    1 | true | TRUE | True | yes | YES | on | ON) return 0 ;;
    *) return 1 ;;
  esac
}

# $1 = bank, $2 = run_id (optional) → echoes the state-file path for a run.
mbw_state_slot() {
  local bank="$1" run_id="${2:-}"
  if mbw_parallel_on && [ -n "$run_id" ]; then
    printf '%s/.work-state/%s.json\n' "$bank" "$run_id"
  else
    printf '%s/.work-state.json\n' "$bank"
  fi
}

# $1 = bank, $2 = run_id (optional) → echoes the budget-file path for a run.
mbw_budget_slot() {
  local bank="$1" run_id="${2:-}"
  if mbw_parallel_on && [ -n "$run_id" ]; then
    printf '%s/.work-budget/%s.json\n' "$bank" "$run_id"
  else
    printf '%s/.work-budget.json\n' "$bank"
  fi
}

# $1 = source string → echoes a stable, filename-safe short hash.
# Fails safe: if python3 is unavailable/errors, echoes a constant fallback
# token so callers never crash — worst case is index collisions, not a
# crash, and the claim logic degrades to "unclaimed" on any read mismatch.
mbw_source_hash() {
  local source="${1:-}"
  python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest()[:16])' \
    "$source" 2>/dev/null || printf 'nohash\n'
}

# Internal: path to the by-source claim-index entry. Not part of the public
# surface (leading underscore) — callers use mbw_index_set/get/del.
_mbw_index_path() {
  local bank="$1" source="$2" hash
  hash=$(mbw_source_hash "$source")
  printf '%s/.work-state/by-source/%s\n' "$bank" "$hash"
}

# $1 = bank, $2 = source, $3 = run_id → claims <source> for <run_id>.
# Atomic write (mktemp → mv). Fail-safe: an unwritable bank/dir degrades to a
# silent no-op (exit 0), never wedges the caller.
mbw_index_set() {
  local bank="$1" source="$2" run_id="${3:-}" idx dir tmp
  [ -z "$run_id" ] && return 0
  idx=$(_mbw_index_path "$bank" "$source")
  dir=$(dirname "$idx")
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp=$(mktemp "$dir/.idx.XXXXXX" 2>/dev/null) || return 0
  if ! printf '%s\n' "$run_id" >"$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    return 0
  fi
  mv "$tmp" "$idx" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  return 0
}

# $1 = bank, $2 = source → echoes the claiming run_id, or "" (fail-safe:
# missing file, unreadable file, or a corrupt entry — e.g. a directory sitting
# where a one-line file is expected — all degrade to "", never an error).
mbw_index_get() {
  local bank="$1" source="$2" idx val
  idx=$(_mbw_index_path "$bank" "$source")
  val=""
  if [ -f "$idx" ]; then
    val=$(cat "$idx" 2>/dev/null || true)
    val=$(printf '%s' "$val" | tr -d '[:space:]')
  fi
  printf '%s\n' "$val"
  return 0
}

# $1 = bank, $2 = source → releases the claim on <source>, if any.
# Fail-safe: a missing entry is a silent no-op.
mbw_index_del() {
  local bank="$1" source="$2" idx
  idx=$(_mbw_index_path "$bank" "$source")
  rm -f "$idx" 2>/dev/null || true
  return 0
}

# $1 = json file path, $2 = field name → echoes the field's string value, or
# "" when the file is absent/corrupt/unreadable. Fail-safe: always exit 0.
mbw_read_field() {
  local path="$1" field="$2"
  [ -f "$path" ] || { printf '\n'; return 0; }
  STATE="$path" FIELD="$field" python3 -c '
import json, os
try:
    data = json.loads(open(os.environ["STATE"], encoding="utf-8").read())
    print(data.get(os.environ["FIELD"], ""))
except Exception:
    print("")
' 2>/dev/null || printf '\n'
}

# $1 = bank, $2 = state-file path → releases the claim recorded by that
# state's `source` field, if any. Fail-safe: a missing/empty source (or a
# read error via mbw_read_field) is a silent no-op; always exit 0.
mbw_release_claim() {
  local bank="$1" state="$2" src
  src=$(mbw_read_field "$state" "source")
  if [ -n "$src" ]; then
    mbw_index_del "$bank" "$src"
  fi
  return 0
}

# $1 = bank, $2 = source, $3 = own run_id → echoes the run_id of a live
# foreign claim on <source> (a different run whose own slot exists and whose
# phase != done), or "" when unclaimed / self-claimed / the claimant's slot
# is missing or done. Fail-safe: never errors, always exit 0.
mbw_claim_conflict() {
  local bank="$1" source="$2" own="$3" claimant claimant_state
  claimant=$(mbw_index_get "$bank" "$source")
  if [ -z "$claimant" ] || [ "$claimant" = "$own" ]; then
    printf '\n'
    return 0
  fi
  claimant_state=$(mbw_state_slot "$bank" "$claimant")
  if [ -f "$claimant_state" ] && [ "$(mbw_read_field "$claimant_state" "phase")" != "done" ]; then
    printf '%s\n' "$claimant"
  else
    printf '\n'
  fi
}
