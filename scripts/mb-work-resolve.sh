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
#   1  not found / no active plan / parse error
#   2  ambiguous (multiple substring matches; list printed to stderr)
#   3  freeform target (driver must resolve via LLM; candidate list to stderr)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=_lib.sh
source "$SCRIPT_DIR/_lib.sh"

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
positional=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --mb=*) MB_ARG="${1#--mb=}"; shift ;;
    -h|--help)
      sed -n '2,17p' "$0"
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
  elif [ "$count" -eq 1 ]; then
    rel=$(printf '%s' "$links" | head -1)
    abs_path=$(abs "$BANK/$rel")
    if [ ! -f "$abs_path" ]; then
      echo "[work-resolve] active plan link points at missing file: $abs_path" >&2
      exit 1
    fi
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
  abs "$TARGET"
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
    abs "$matches"
    exit 0
  elif [ "$count" -gt 1 ]; then
    echo "[work-resolve] ambiguous substring '$TARGET' matches:" >&2
    printf '%s\n' "$matches" >&2
    exit 2
  fi
fi

# ── Form 3: topic → specs/<topic>/tasks.md ─────────────────────────
safe=$(mb_sanitize_topic "$TARGET")
if [ -n "$safe" ]; then
  tasks="$BANK/specs/$safe/tasks.md"
  if [ -f "$tasks" ]; then
    abs "$tasks"
    exit 0
  fi
fi

# ── Form 4: freeform (≥3 words) ─────────────────────────────────────
words=$(count_words "$TARGET")
if [ "$words" -ge 3 ]; then
  echo "[work-resolve] freeform target ($words words); driver must match against active plans" >&2
  if [ -d "$plans_dir" ]; then
    echo "candidates:" >&2
    find "$plans_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sed 's/^/  /' >&2 || true
  fi
  exit 3
fi

echo "[work-resolve] target '$TARGET' not found" >&2
exit 1
