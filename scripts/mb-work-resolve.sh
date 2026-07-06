#!/usr/bin/env bash
# mb-work-resolve.sh — resolve <target> arg into a plan/spec path (spec §8.2).
#
# Resolution order:
#   1. Existing path → use as-is
#   2. Substring search in <bank>/plans/*.md (excluding done/)
#   3. Topic name → <bank>/specs/<safe>/tasks.md
#   4. Freeform (≥3 words) → exit 3 (driver delegates to LLM-driven match)
#   5. Empty → first plan link inside <bank>/roadmap.md mb-active-plans block
#
# Exit codes:
#   0  resolved (single absolute path printed to stdout)
#   1  not found / no active plan / parse error / all active plans claimed
#   2  ambiguous (multiple substring matches; list printed to stderr)
#   3  freeform target (driver must resolve via LLM; candidate list to stderr)
#
# Parallel runs (I-094 T2, opt-in MB_WORK_PARALLEL=1): `--skip-claimed` makes
# the empty-target branch (Form 5) skip active-plan links whose source is
# claimed by a live (phase != done) foreign run — see scripts/mb-work-slots.sh
# — returning the first unclaimed one; if every active plan is claimed, exits
# 1 with "all active plans claimed" on stderr. Independently, whenever
# MB_WORK_PARALLEL is on, any successfully resolved path (any form) that is
# claimed by a live foreign run gets an informational stderr claim-note
# ("claimed by run <id>; pass --takeover") — the hard enforcement gate stays
# `mb-work-state.sh init` exit 4; this script never refuses on its own.
# Without `--skip-claimed`/`MB_WORK_PARALLEL`, resolution is byte-identical
# to pre-I-094 behaviour.

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"
# shellcheck source=mb-work-slots.sh
source "$SCRIPT_DIR/mb-work-slots.sh"

abs() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" <<'PY'
import os, sys
print(os.path.realpath(sys.argv[1]))
PY
  else
    printf '%s\n' "$1"
  fi
}

count_words() {
  echo "$1" | awk '{print NF}'
}

# $1 = bank, $2 = resolved absolute path → prints an informational
# claim-note to stderr when $2 is claimed by a live foreign run under
# MB_WORK_PARALLEL. No-op (and never fails) when parallel mode is off, or
# when the path is unclaimed/self-claimed/claimed by a finished run.
claim_note() {
  local bank="$1" path="$2" claimant
  mbw_parallel_on || return 0
  claimant=$(mbw_claim_conflict "$bank" "$path" "")
  if [ -n "$claimant" ]; then
    echo "[work-resolve] claimed by run $claimant; pass --takeover" >&2
  fi
  return 0
}

list_active_plan_links_portable() {
  local bank
  local rm
  bank="$1"
  rm="$bank/roadmap.md"
  [ -f "$rm" ] || return 1
  python3 - "$rm" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<!--\s*mb-active-plans\s*-->(.*?)<!--\s*/mb-active-plans\s*-->", text, re.S)
if not m:
    sys.exit(0)
for line in m.group(1).splitlines():
    mo = re.search(r"\(([^)]+)\)", line)
    if mo:
        print(mo.group(1))
PY
}

TARGET=""
MB_ARG=""
SKIP_CLAIMED=0
positional=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    --skip-claimed) SKIP_CLAIMED=1; shift ;;
    -h|--help)
      sed -n '2,27p' "$0"
      exit 0
      ;;
    *) positional+=("$1"); shift ;;
  esac
done

# Heuristic for backwards compatibility: if exactly one positional and it's a
# directory, treat it as mb_path. Two positionals → first is target, second is
# mb_path.
case "${#positional[@]}" in
  0) ;;
  1)
    if [ -z "$MB_ARG" ] && [ -d "${positional[0]}" ]; then
      MB_ARG="${positional[0]}"
    else
      TARGET="${positional[0]}"
    fi
    ;;
  2)
    TARGET="${positional[0]}"
    if [ -z "$MB_ARG" ]; then
      MB_ARG="${positional[1]}"
    fi
    ;;
  *)
    echo "[work-resolve] too many positional arguments" >&2
    exit 1
    ;;
esac

BANK=$(mb_resolve_path "$MB_ARG")

# ── Form 5: empty target ────────────────────────────────────────────
if [ -z "$TARGET" ]; then
  links=$(list_active_plan_links_portable "$BANK" || true)
  count=0
  if [ -n "$links" ]; then
    count=$(printf '%s\n' "$links" | grep -c .)
  fi
  if [ "$count" -eq 0 ]; then
    echo "[work-resolve] no active plan in $BANK/roadmap.md" >&2
    exit 1
  fi

  # --skip-claimed (only honored under MB_WORK_PARALLEL): drop links whose
  # source is claimed by a live foreign run before picking one.
  if mbw_parallel_on && [ "$SKIP_CLAIMED" = "1" ]; then
    unclaimed=""
    while IFS= read -r rel; do
      [ -z "$rel" ] && continue
      cand_abs=$(abs "$BANK/$rel")
      if [ -z "$(mbw_claim_conflict "$BANK" "$cand_abs" "")" ]; then
        unclaimed="${unclaimed}${rel}
"
      fi
    done < <(printf '%s\n' "$links")
    if [ -z "$unclaimed" ]; then
      echo "[work-resolve] all active plans claimed" >&2
      exit 1
    fi
    links="$unclaimed"
    count=$(printf '%s\n' "$links" | grep -c .)
  fi

  if [ "$count" -eq 1 ]; then
    rel=$(printf '%s' "$links" | head -1)
    case "$rel" in
      /*|*..*)
        echo "[work-resolve] active plan link rejected (absolute or traversal): $rel" >&2
        exit 1
        ;;
    esac
    abs_path=$(mb_canonical_under "$BANK" "$BANK/$rel") || {
      echo "[work-resolve] active plan link escapes bank: $rel" >&2
      exit 1
    }
    if ! mb_is_allowed_plan_path "$BANK" "$abs_path"; then
      echo "[work-resolve] active plan link is not a plan or spec tasks file: $abs_path" >&2
      exit 1
    fi
    if [ ! -f "$abs_path" ]; then
      echo "[work-resolve] active plan link points at missing file: $abs_path" >&2
      exit 1
    fi
    claim_note "$BANK" "$abs_path"
    printf '%s\n' "$abs_path"
    exit 0
  else
    echo "[work-resolve] multiple active plans (use explicit target):" >&2
    printf '%s\n' "$links" >&2
    exit 2
  fi
fi

# ── Form 1: existing path ───────────────────────────────────────────
if [ -f "$TARGET" ]; then
  target_abs=$(abs "$TARGET")
  claim_note "$BANK" "$target_abs"
  printf '%s\n' "$target_abs"
  exit 0
fi

# ── Form 2: substring search in plans/ (excluding done/) ────────────
plans_dir="$BANK/plans"
if [ -d "$plans_dir" ]; then
  matches=$(find "$plans_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | grep -F "$TARGET" || true)
  count=0
  if [ -n "$matches" ]; then
    count=$(printf '%s\n' "$matches" | grep -c .)
  fi
  if [ "$count" -eq 1 ]; then
    match_abs=$(abs "$matches")
    claim_note "$BANK" "$match_abs"
    printf '%s\n' "$match_abs"
    exit 0
  elif [ "$count" -gt 1 ]; then
    echo "[work-resolve] ambiguous substring '$TARGET' matches:" >&2
    printf '%s\n' "$matches" >&2
    exit 2
  fi
fi

# ── Form 2b: bank-relative plans/* or specs/* (from any CWD) ───────
case "$TARGET" in
  plans/*|specs/*)
    case "$TARGET" in
      /*|*..*) ;;
      *)
        abs_path=$(mb_canonical_under "$BANK" "$BANK/$TARGET") || {
          echo "[work-resolve] bank-relative target escapes bank: $TARGET" >&2
          exit 1
        }
        if ! mb_is_allowed_plan_path "$BANK" "$abs_path"; then
          echo "[work-resolve] bank-relative target is not a plan or spec tasks file: $TARGET" >&2
          exit 1
        fi
        if [ -f "$abs_path" ]; then
          printf '%s\n' "$abs_path"
          exit 0
        fi
        ;;
    esac
    ;;
esac

# ── Form 3: topic → specs/<topic>/tasks.md ─────────────────────────
safe=$(mb_sanitize_topic "$TARGET")
if [ -n "$safe" ]; then
  tasks="$BANK/specs/$safe/tasks.md"
  if [ -f "$tasks" ]; then
    tasks_abs=$(abs "$tasks")
    claim_note "$BANK" "$tasks_abs"
    printf '%s\n' "$tasks_abs"
    exit 0
  fi
fi

# ── Form 4: freeform (≥3 words) ─────────────────────────────────────
words=$(count_words "$TARGET")
if [ "$words" -ge 3 ]; then
  echo "[work-resolve] freeform target ($words words); driver must match against active plans" >&2
  echo "candidates:" >&2
  if [ -d "$plans_dir" ]; then
    find "$plans_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sed 's/^/  /' >&2 || true
  fi
  # Also include specs/*/tasks.md files that contain mb-task or mb-stage markers.
  if [ -d "$BANK/specs" ]; then
    while IFS= read -r spec_tasks; do
      if grep -qE '<!--[[:space:]]*mb-(task|stage):[0-9]+[[:space:]]*-->' "$spec_tasks" 2>/dev/null; then
        printf '  %s\n' "$spec_tasks" >&2
      fi
    done < <(find "$BANK/specs" -mindepth 2 -maxdepth 2 -name 'tasks.md' 2>/dev/null)
  fi
  exit 3
fi

echo "[work-resolve] target '$TARGET' not found" >&2
exit 1
