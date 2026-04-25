#!/usr/bin/env bash
# mb-work-range.sh — emit per-stage indices (plan mode) or per-sprint paths
# (phase mode) filtered by --range expression (spec §8.3).
#
# Usage:
#   mb-work-range.sh <plan-file> [--range <expr>]            # plan mode
#   mb-work-range.sh --phase <p1.md> [<p2.md> ...] [--range <expr>] # phase mode
#
# Range expressions:
#   N        single element (1-indexed)
#   A-B      closed range
#   A-       open range (A to max)
#   (omit)   all elements
#
# Exit codes:
#   0  success (one element per stdout line)
#   1  out of bounds / no stages / invalid expr / phase mode missing sprint
#   2  usage error

set -eu

usage() {
  sed -n '2,16p' "$0" >&2
}

PHASE_MODE=0
RANGE=""
positional=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --phase) PHASE_MODE=1; shift ;;
    --range) RANGE="${2:-}"; shift 2 ;;
    --range=*) RANGE="${1#--range=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) positional+=("$1"); shift ;;
  esac
done

if [ "${#positional[@]}" -eq 0 ]; then
  usage; exit 2
fi

# Parse range into start/end (1-indexed). Empty RANGE → 1-MAX.
parse_range() {
  local expr="$1"
  local total="$2"
  if [ -z "$expr" ]; then
    printf '1 %d' "$total"; return 0
  fi
  if [[ "$expr" =~ ^([0-9]+)$ ]]; then
    local n="${BASH_REMATCH[1]}"
    printf '%d %d' "$n" "$n"; return 0
  fi
  if [[ "$expr" =~ ^([0-9]+)-$ ]]; then
    local a="${BASH_REMATCH[1]}"
    printf '%d %d' "$a" "$total"; return 0
  fi
  if [[ "$expr" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    printf '%d %d' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; return 0
  fi
  return 1
}

if [ "$PHASE_MODE" -eq 1 ]; then
  # Phase mode: positional plans, sort by sprint frontmatter.
  if [ "${#positional[@]}" -eq 0 ]; then
    echo "[work-range] phase mode requires plan paths" >&2
    exit 2
  fi
  python3 - "$RANGE" "${positional[@]}" <<'PY'
import os, re, sys

range_expr = sys.argv[1]
paths = sys.argv[2:]

entries = []
for p in paths:
    if not os.path.isfile(p):
        sys.stderr.write(f"[work-range] missing plan: {p}\n")
        sys.exit(1)
    text = open(p, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        sys.stderr.write(f"[work-range] phase mode requires sprint frontmatter (no frontmatter in {p})\n")
        sys.exit(1)
    sprint_match = re.search(r"^sprint:\s*(\d+)\s*$", m.group(1), re.M)
    if not sprint_match:
        sys.stderr.write(f"[work-range] phase mode requires sprint frontmatter (none in {p})\n")
        sys.exit(1)
    entries.append((int(sprint_match.group(1)), os.path.realpath(p)))

entries.sort()
total = len(entries)
if total == 0:
    sys.stderr.write("[work-range] no plans collected\n")
    sys.exit(1)

if not range_expr:
    start, end = 1, total
else:
    m1 = re.fullmatch(r"(\d+)", range_expr)
    m2 = re.fullmatch(r"(\d+)-", range_expr)
    m3 = re.fullmatch(r"(\d+)-(\d+)", range_expr)
    if m1:
        start = end = int(m1.group(1))
    elif m2:
        start, end = int(m2.group(1)), total
    elif m3:
        start, end = int(m3.group(1)), int(m3.group(2))
    else:
        sys.stderr.write(f"[work-range] invalid range expr: {range_expr}\n")
        sys.exit(1)

if start < 1 or end > total or start > end:
    sys.stderr.write(f"[work-range] range {range_expr} out of bounds (1..{total})\n")
    sys.exit(1)

for sprint_no, abspath in entries:
    if start <= sprint_no <= end:
        print(abspath)
PY
  exit $?
fi

# Plan mode: positional[0] is the plan file
PLAN="${positional[0]}"
if [ ! -f "$PLAN" ]; then
  echo "[work-range] plan not found: $PLAN" >&2
  exit 1
fi

PLAN_PATH="$PLAN" RANGE_EXPR="$RANGE" python3 - <<'PY'
import os, re, sys

path = os.environ["PLAN_PATH"]
range_expr = os.environ["RANGE_EXPR"]
text = open(path, encoding="utf-8").read()

stages = sorted({int(m.group(1)) for m in re.finditer(r"<!--\s*mb-stage:(\d+)\s*-->", text)})
if not stages:
    sys.stderr.write(f"[work-range] no stages in {path}\n")
    sys.exit(1)

total = max(stages)

if not range_expr:
    start, end = 1, total
else:
    m1 = re.fullmatch(r"(\d+)", range_expr)
    m2 = re.fullmatch(r"(\d+)-", range_expr)
    m3 = re.fullmatch(r"(\d+)-(\d+)", range_expr)
    if m1:
        start = end = int(m1.group(1))
    elif m2:
        start, end = int(m2.group(1)), total
    elif m3:
        start, end = int(m3.group(1)), int(m3.group(2))
    else:
        sys.stderr.write(f"[work-range] invalid range expr: {range_expr}\n")
        sys.exit(1)

if start < 1 or end > total or start > end:
    sys.stderr.write(f"[work-range] range {range_expr} out of bounds (1..{total})\n")
    sys.exit(1)

for s in stages:
    if start <= s <= end:
        print(s)
PY
