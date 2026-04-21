#!/usr/bin/env bash
# mb-rules-check.sh — deterministic rules enforcement (SRP / Clean Arch / TDD).
#
# Usage:
#   mb-rules-check.sh --files <csv> [--diff-files <csv>] [--out json|human|both]
#                     [--srp-threshold <N>]
#
# Contract:
#   --files        Comma-separated list of files to inspect (required).
#                  Empty string means zero files — emits an empty result.
#   --diff-files   Comma-separated full set of files touched in the diff range.
#                  Used only by tdd/delta check. When omitted, tdd/delta is
#                  skipped (no false positives).
#   --out          Output mode. Default: json.
#   --srp-threshold  Override SRP line limit. Default: 300.
#
# Output (json mode):
#   {
#     "violations": [
#       {"rule": "solid/srp", "severity": "WARNING|CRITICAL",
#        "file": "<path>", "line": N, "excerpt": "<text>", "rationale": "<text>"},
#       ...
#     ],
#     "stats": {"files_scanned": N, "checks_run": K, "duration_ms": N}
#   }
#
# Rules implemented:
#   - solid/srp             — file > threshold lines (with exclusions)
#   - clean_arch/direction  — domain/ file imports from infrastructure/
#   - tdd/delta             — source changed without matching test in diff
#
# Not in v1 (KISS + YAGNI; documented in plan Stage 2):
#   - solid/isp             — needs AST parsing
#   - dry/repetition        — needs normalized-line hashing
# The closed rule-ID vocabulary in contract tests enumerates all five so the
# script can evolve without breaking downstream consumers.

set -euo pipefail

# ---- arg parsing ------------------------------------------------------------

FILES_CSV=""
DIFF_CSV=""
OUT="json"
SRP_THRESHOLD="${MB_SRP_THRESHOLD:-300}"

print_help() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)          FILES_CSV="${2:-}";       shift 2 ;;
    --diff-files)     DIFF_CSV="${2:-}";        shift 2 ;;
    --out)            OUT="${2:-json}";         shift 2 ;;
    --srp-threshold)  SRP_THRESHOLD="${2:-300}"; shift 2 ;;
    --help|-h)        print_help; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$OUT" in
  json|human|both) ;;
  *) echo "invalid --out: $OUT (allowed: json|human|both)" >&2; exit 2 ;;
esac

# ---- helpers ----------------------------------------------------------------

now_ms() {
  # portable-ish: python3 is a hard dep of this skill, so use it
  python3 -c 'import time; print(int(time.time()*1000))'
}

# Split a CSV string into a bash array, skipping empty entries.
split_csv() {
  local csv="$1"; shift
  local -n out="$1"
  out=()
  [[ -z "$csv" ]] && return 0
  local IFS=,
  # shellcheck disable=SC2206
  out=($csv)
  # drop accidental empty entries (e.g. trailing comma)
  local i=0 cleaned=()
  for i in "${!out[@]}"; do
    [[ -n "${out[$i]}" ]] && cleaned+=("${out[$i]}")
  done
  out=("${cleaned[@]+"${cleaned[@]}"}")
}

# JSON string escape: quote + escape backslash/quote/newline.
# Keeps output self-contained without jq dependency on the emit path.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

emit_violation() {
  # args: rule severity file line excerpt rationale
  local rule="$1" sev="$2" file="$3" line="$4" excerpt="$5" rationale="$6"
  VIOLATIONS+=("$(printf '{"rule":%s,"severity":%s,"file":%s,"line":%s,"excerpt":%s,"rationale":%s}' \
    "$(json_escape "$rule")" \
    "$(json_escape "$sev")" \
    "$(json_escape "$file")" \
    "$line" \
    "$(json_escape "$excerpt")" \
    "$(json_escape "$rationale")")")
}

# ---- exclusions -------------------------------------------------------------

# Returns 0 if the file should be fully excluded from structural checks
# (SRP is the main user). Matches extensions + path segments.
is_fully_excluded() {
  local f="$1"
  case "$f" in
    *.md|*.json|*.lock|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.ico|*.pdf) return 0 ;;
    *.yaml|*.yml|*.toml) return 0 ;;
  esac
  case "$f" in
    */vendor/*|vendor/*) return 0 ;;
    */node_modules/*|node_modules/*) return 0 ;;
    */__pycache__/*|__pycache__/*) return 0 ;;
  esac
  # Hidden dir in any segment.
  if [[ "$f" =~ (^|/)\.[^/]+/ ]]; then
    return 0
  fi
  # Generated marker on line 1.
  if [[ -f "$f" ]]; then
    local first_line
    first_line="$(head -n1 "$f" 2>/dev/null || true)"
    if [[ "$first_line" == *"GENERATED"* ]]; then
      return 0
    fi
  fi
  return 1
}

# TDD-delta exclusions: these files are allowed to change without tests.
is_tdd_exempt() {
  local f="$1"
  case "$f" in
    *.md|*.lock|*.json|*.yaml|*.yml|*.toml|*.svg|*.png|*.jpg|*.jpeg|*.gif|*.ico) return 0 ;;
  esac
  case "$f" in
    docs/*|*/docs/*) return 0 ;;
    migrations/*|*/migrations/*) return 0 ;;
    .github/*|*/.github/*) return 0 ;;
    .memory-bank/*) return 0 ;;
    .claude/*|*/.claude/*) return 0 ;;
    references/*|templates/*) return 0 ;;
    agents/*) return 0 ;;  # agent prompts are text; tests target scripts they wrap
    # tests themselves: they ARE the coverage
    tests/*|*/tests/*|*_test.*|*.test.*|*.spec.*) return 0 ;;
  esac
  return 1
}

# Identify if a path looks like a test file (for matching).
is_test_file() {
  local f="$1"
  case "$f" in
    tests/*|*/tests/*) return 0 ;;
    *_test.*|*.test.*|*.spec.*) return 0 ;;
    test_*.py|test_*.bats|test_*.sh) return 0 ;;
    *test*/test_*|*/test_*) return 0 ;;
  esac
  return 1
}

# Given a source basename stem, check if any file in DIFF_FILES matches
# a test pattern for that stem.
has_matching_test() {
  local stem="$1"
  # Normalize stem: replace '-' and '_' both ways when looking for a test.
  local stem_alt_1="${stem//-/_}"
  local stem_alt_2="${stem//_/-}"

  local df
  for df in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    local base
    base="$(basename "$df")"
    # test_<stem>.* / test_<stem-alt>.*
    if [[ "$base" == "test_${stem}."* || "$base" == "test_${stem_alt_1}."* || "$base" == "test_${stem_alt_2}."* ]]; then
      return 0
    fi
    # <stem>_test.* / <stem>.test.* / <stem>.spec.*
    if [[ "$base" == "${stem}_test."* || "$base" == "${stem}.test."* || "$base" == "${stem}.spec."* ]]; then
      return 0
    fi
    if [[ "$base" == "${stem_alt_1}_test."* || "$base" == "${stem_alt_1}.test."* || "$base" == "${stem_alt_1}.spec."* ]]; then
      return 0
    fi
    if [[ "$base" == "${stem_alt_2}_test."* || "$base" == "${stem_alt_2}.test."* || "$base" == "${stem_alt_2}.spec."* ]]; then
      return 0
    fi
  done
  return 1
}

# ---- checks -----------------------------------------------------------------

check_srp() {
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local offenders=()
  local counts=()
  local f
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    is_fully_excluded "$f" && continue
    local n
    n="$(wc -l < "$f" | tr -d ' ')"
    if (( n > SRP_THRESHOLD )); then
      offenders+=("$f")
      counts+=("$n")
    fi
  done
  local total=${#offenders[@]}
  (( total == 0 )) && return 0
  local sev="WARNING"
  if (( total >= 3 )); then
    sev="CRITICAL"
  fi
  local i
  for i in "${!offenders[@]}"; do
    emit_violation "solid/srp" "$sev" "${offenders[$i]}" 1 \
      "${counts[$i]} lines" \
      "File exceeds SRP threshold (>${SRP_THRESHOLD}); consider splitting into cohesive modules."
  done
}

check_clean_arch() {
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local f
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    # Must be under a 'domain/' path segment.
    [[ "$f" == *"/domain/"* || "$f" == "domain/"* ]] || continue
    # Look for import from an 'infrastructure' path.
    local hit
    hit="$(grep -nE '(^|[[:space:]])(from|import)[[:space:]].*infrastructure|require.*infrastructure|"[^"]*/infrastructure[^"]*"' "$f" 2>/dev/null | head -n1 || true)"
    [[ -z "$hit" ]] && continue
    local line_no="${hit%%:*}"
    local line_text="${hit#*:}"
    line_text="${line_text:0:120}"
    emit_violation "clean_arch/direction" "CRITICAL" "$f" "$line_no" \
      "$line_text" \
      "domain/ layer must not depend on infrastructure/; invert the dependency via an interface owned by domain."
  done
}

check_tdd_delta() {
  # Only if caller supplied --diff-files.
  (( ${#DIFF_FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local f
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    is_tdd_exempt "$f" && continue
    is_test_file "$f" && continue
    # Only apply to "source" roots we care about.
    case "$f" in
      src/*|*/src/*|scripts/*|lib/*|*/lib/*|internal/*|*/internal/*|pkg/*|*/pkg/*|cmd/*|*/cmd/*) ;;
      *) continue ;;
    esac
    local base stem
    base="$(basename "$f")"
    stem="${base%.*}"
    if ! has_matching_test "$stem"; then
      emit_violation "tdd/delta" "CRITICAL" "$f" 1 \
        "no matching test in diff" \
        "Source file changed without a co-changed test; add or update tests in the same commit range."
    fi
  done
}

# ---- main -------------------------------------------------------------------

START_MS="$(now_ms)"
VIOLATIONS=()
CHECKS_RUN=0
FILES=()
DIFF_FILES=()

split_csv "$FILES_CSV" FILES
split_csv "$DIFF_CSV"  DIFF_FILES

check_srp
check_clean_arch
check_tdd_delta

END_MS="$(now_ms)"
DURATION=$((END_MS - START_MS))

emit_json() {
  printf '{"violations":['
  local i
  for i in "${!VIOLATIONS[@]}"; do
    (( i > 0 )) && printf ','
    printf '%s' "${VIOLATIONS[$i]}"
  done
  printf '],"stats":{"files_scanned":%d,"checks_run":%d,"duration_ms":%d}}\n' \
    "${#FILES[@]}" "$CHECKS_RUN" "$DURATION"
}

emit_human() {
  if (( ${#VIOLATIONS[@]} == 0 )); then
    printf 'rules-check: 0 violations (%d files, %d checks, %dms)\n' \
      "${#FILES[@]}" "$CHECKS_RUN" "$DURATION"
    return
  fi
  printf 'rules-check: %d violation(s)\n' "${#VIOLATIONS[@]}"
  local v rule sev file line rationale
  for v in "${VIOLATIONS[@]}"; do
    rule="$(echo "$v"     | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["rule"])')"
    sev="$(echo "$v"      | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["severity"])')"
    file="$(echo "$v"     | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["file"])')"
    line="$(echo "$v"     | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["line"])')"
    rationale="$(echo "$v"| python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["rationale"])')"
    printf '  [%s] %s — %s:%s — %s\n' "$sev" "$rule" "$file" "$line" "$rationale"
  done
}

case "$OUT" in
  json)  emit_json ;;
  human) emit_human ;;
  both)  emit_human; emit_json ;;
esac
