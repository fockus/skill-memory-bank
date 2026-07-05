#!/usr/bin/env bash
# mb-work-trend.sh — trend calculator + previous-cycle verdict cache
# (work-loop-v2 design.md §5 "Strategic pivoting" / "Trend signal";
# REQ-111/REQ-114).
#
# Given the current cycle's NORMALIZED reviewer verdict (the JSON shape
# scripts/mb-work-review-parse.sh prints on stdout:
#   {"verdict": "...", "counts": {"blocker": N, "major": N, "minor": N}, ...}
# ) and an item key, this script computes `progress_trend` deterministically
# and maintains the previous-cycle cache the next call reads from.
#
# Usage:
#   mb-work-trend.sh key --plan <path> --stage <N> --item <M>
#   mb-work-trend.sh compute --mb <bank> --item-key <key>
#                    [--verdict-file <file>] [--no-store]
#                    (reads the current verdict from --verdict-file, else stdin)
#   mb-work-trend.sh --help
#
# `key` prints the sha256 hex digest of (plan_path, stage_no, item_no) — the
# SINGLE source of truth for the item-key derivation (design.md §5: "Item key
# = sha256 of (plan_path + stage_no + item_no)"). Callers that need the same
# key across two invocations MUST go through this subcommand rather than
# recomputing it inline.
#
# `compute` prints exactly one of `improving|stagnant|regressing|null` on
# stdout, per:
#   weighted_score(v) = 10*counts.blocker + 3*counts.major + 1*counts.minor
#   current  = weighted_score(this cycle)
#   previous = weighted_score(last cycle)   -- null on first cycle
#   improving:  current < previous (strictly less)
#   stagnant:   |current - previous| <= 1 AND current > 0
#   regressing: current > previous
#   null:       first cycle (no previous cache) -- ALSO the 0/0 "converged"
#               edge (both cycles at zero weighted score). The spec's
#               `stagnant` boundary explicitly requires `current > 0`, so 0/0
#               is not stagnant by the letter of the design; calling a flat
#               0->0 "improving" would misreport "getting better" when
#               nothing changed. `null` ("no trend signal") is the reading
#               that keeps a stray zero-to-zero recheck (e.g. re-reviewing an
#               already-APPROVED item) from ever being miscounted toward
#               `pivot_after_cycles`'s consecutive-stagnant tally downstream.
#
# Unless --no-store is given, `compute` OVERWRITES the previous-cycle cache
# with the current verdict (atomic mktemp+mv) so the NEXT call sees this
# cycle as its "previous". Fail-safe throughout: a missing, unreadable, or
# corrupt cache file is always treated as "no previous" (never a crash); a
# missing bank/tmp directory is created on demand and a failure to persist
# degrades to a silent no-op rather than a non-zero exit (the printed trend
# for THIS call is unaffected either way).
#
# Cache path: <bank>/tmp/last-verdict-<item-key>.json — SAME directory and
# filename convention as scripts/mb-review.sh's last_verdict_cache_path()
# (`tmp/last-verdict-<X>.json`). NOTE (reconciliation, tracked for backlog):
# that helper is currently inert (I-096) and derives X via
# mb_sanitize_topic("$item") on a bare --item value, NOT sha256(plan+stage+
# item) as design.md §5 specifies. This script is the one that implements the
# documented sha256 derivation. When reviewer-2.0 wires progress_trend
# emission for real, mb-review.sh's cache-key derivation must be reconciled
# to call `mb-work-trend.sh key` (or be updated to match it) so both sides
# agree on the SAME key for the SAME item — they must not diverge into two
# independent schemes writing to two different cache files.
#
# Exit codes:
#   0  success
#   2  usage error (missing subcommand/flags, bad input)

set -eu

usage() {
  sed -n '2,46p' "$0" >&2
}

# $1=plan $2=stage $3=item -> sha256 hex digest of "plan<US>stage<US>item"
# (unit-separator joined so a plan path containing a literal pipe/colon can
# never collide with a different (plan,stage,item) triple). Fail-safe: if
# python3 is unavailable/errors, echoes a constant fallback token so callers
# never crash — mirrors scripts/mb-work-slots.sh:mbw_source_hash.
item_key() {
  local plan="$1" stage="$2" item="$3"
  PLAN="$plan" STAGE="$stage" ITEM="$item" python3 -c '
import hashlib, os
combined = "\x1f".join([os.environ["PLAN"], os.environ["STAGE"], os.environ["ITEM"]])
print(hashlib.sha256(combined.encode("utf-8")).hexdigest())
' 2>/dev/null || printf 'nohash\n'
}

# $1=bank $2=item-key -> echoes the previous-verdict cache path.
cache_path() {
  local bank="$1" key="$2"
  printf '%s/tmp/last-verdict-%s.json\n' "$bank" "$key"
}

cmd_key() {
  local plan="" stage="" item=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --plan) plan="${2:-}"; shift 2 ;;
      --plan=*) plan="${1#--plan=}"; shift ;;
      --stage) stage="${2:-}"; shift 2 ;;
      --stage=*) stage="${1#--stage=}"; shift ;;
      --item) item="${2:-}"; shift 2 ;;
      --item=*) item="${1#--item=}"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[work-trend] key: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  if [ -z "$plan" ] || [ -z "$stage" ] || [ -z "$item" ]; then
    echo "[work-trend] key requires --plan, --stage, --item" >&2
    exit 2
  fi
  item_key "$plan" "$stage" "$item"
}

cmd_compute() {
  local bank="" item_key_arg="" verdict_file="" no_store=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --mb) bank="${2:-}"; shift 2 ;;
      --mb=*) bank="${1#--mb=}"; shift ;;
      --item-key) item_key_arg="${2:-}"; shift 2 ;;
      --item-key=*) item_key_arg="${1#--item-key=}"; shift ;;
      --verdict-file) verdict_file="${2:-}"; shift 2 ;;
      --verdict-file=*) verdict_file="${1#--verdict-file=}"; shift ;;
      --no-store) no_store=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "[work-trend] compute: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  if [ -z "$bank" ] || [ -z "$item_key_arg" ]; then
    echo "[work-trend] compute requires --mb and --item-key" >&2
    exit 2
  fi

  local current_json
  if [ -n "$verdict_file" ]; then
    if [ ! -f "$verdict_file" ]; then
      echo "[work-trend] verdict file not found: $verdict_file" >&2
      exit 2
    fi
    current_json=$(cat "$verdict_file")
  else
    current_json=$(cat -)
  fi
  if [ -z "$current_json" ]; then
    echo "[work-trend] empty verdict input (pass --verdict-file or stdin)" >&2
    exit 2
  fi

  local cache
  cache=$(cache_path "$bank" "$item_key_arg")

  local trend
  trend=$(CURRENT_JSON="$current_json" CACHE_PATH="$cache" python3 - <<'PY'
import json
import os

def weighted_score(counts):
    if not isinstance(counts, dict):
        return 0
    total = 0
    for key, weight in (("blocker", 10), ("major", 3), ("minor", 1)):
        v = counts.get(key, 0)
        if isinstance(v, bool) or not isinstance(v, int) or v < 0:
            v = 0
        total += weight * v
    return total

current_json = os.environ["CURRENT_JSON"]
cache_path = os.environ["CACHE_PATH"]

try:
    current = json.loads(current_json)
except Exception:
    current = {}
current_score = weighted_score(current.get("counts") if isinstance(current, dict) else None)

previous_score = None
try:
    with open(cache_path, encoding="utf-8") as fh:
        prev = json.loads(fh.read())
    if isinstance(prev, dict):
        previous_score = weighted_score(prev.get("counts"))
except Exception:
    previous_score = None

if previous_score is None:
    trend = "null"
elif current_score < previous_score:
    trend = "improving"
elif abs(current_score - previous_score) <= 1 and current_score > 0:
    # Checked BEFORE "regressing" on purpose: design.md §5 lists improving /
    # stagnant / regressing in that priority order, so a delta-of-1 uptick
    # (e.g. 3 -> 4, which also satisfies current > previous) is reported as
    # `stagnant`, not `regressing` -- only a delta of 2+ counts as regressing.
    trend = "stagnant"
elif current_score > previous_score:
    trend = "regressing"
else:
    # 0/0 converged edge -- see the script header comment for the rationale.
    trend = "null"

print(trend)
PY
) || trend="null"

  printf '%s\n' "$trend"

  if [ "$no_store" -eq 0 ]; then
    local dir tmp
    dir=$(dirname "$cache")
    mkdir -p "$dir" 2>/dev/null || return 0
    tmp=$(mktemp "$dir/.last-verdict.XXXXXX" 2>/dev/null) || return 0
    if printf '%s' "$current_json" >"$tmp" 2>/dev/null; then
      mv "$tmp" "$cache" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
    else
      rm -f "$tmp" 2>/dev/null || true
    fi
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
    key)
      shift
      cmd_key "$@"
      ;;
    compute)
      shift
      cmd_compute "$@"
      ;;
    *)
      echo "[work-trend] unknown subcommand '$1'" >&2
      usage
      exit 2
      ;;
  esac
}

main "$@"
