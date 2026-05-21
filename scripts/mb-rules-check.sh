#!/usr/bin/env bash
# mb-rules-check.sh — deterministic rules enforcement (SRP / Clean Arch / TDD).
#
# Usage:
#   mb-rules-check.sh --files <csv> [--diff-files <csv>] [--out json|human|both]
#                     [--srp-threshold <N>] [--profile <path>]
#
# Contract:
#   --files        Comma-separated list of files to inspect (required).
#                  Empty string means zero files — emits an empty result.
#   --diff-files   Comma-separated full set of files touched in the diff range.
#                  Used only by tdd/delta and stack checks. When omitted, those
#                  checks are skipped (no false positives).
#   --out          Output mode. Default: json.
#   --srp-threshold  Override SRP line limit. Default: 300.
#   --profile      Path to a rules-profile JSON file. When omitted, auto-resolve
#                  via MB_PROFILE env var or fall back to baseline defaults.
#
# Output (json mode):
#   {
#     "violations": [
#       {"rule": "solid/srp", "rule_id": "solid/srp", "severity": "WARNING|CRITICAL",
#        "file": "<path>", "line": N, "excerpt": "<text>", "rationale": "<text>",
#        "profile_source": "baseline"},
#       ...
#     ],
#     "profile": {
#       "role": "...", "stack": "...", "architecture": "...",
#       "delivery": "...", "strictness": "...",
#       "sources": {...}, "prompt_summary": "..."
#     },
#     "stats": {"files_scanned": N, "checks_run": K, "duration_ms": N}
#   }
#
# Rules implemented:
#   - solid/srp                          — file > threshold lines (with exclusions)
#   - clean_arch/direction               — domain/ file imports from infrastructure/
#   - tdd/delta                          — source changed without matching test
#   - stack.go.context-propagation       — Go handler/func missing ctx (advisory)
#   - stack.go.goroutine-context         — goroutine spawned without context (advisory)
#   - stack.python.type-hints            — Python def missing type hints (advisory)
#   - stack.python.no-business-mocks     — mock imports in business logic (warn)
#   - stack.typescript.no-any            — TypeScript `any` usage (warn)
#   - stack.javascript.strict-equality   — JS == instead of === (advisory)
#   - architecture.fsd.import-direction  — FSD upward imports (warn)
#
# Not in v1 (KISS + YAGNI):
#   - solid/isp             — needs AST parsing
#   - dry/repetition        — needs normalized-line hashing
# The closed rule-ID vocabulary in contract tests enumerates all five so the
# script can evolve without breaking downstream consumers.

# shellcheck disable=SC2094
# SC2094: false positive — "read and write same file" fires on `while read; done < "$f"`
# patterns where $f is only ever read, not written.
set -euo pipefail

# Locate the repo root so we can resolve the memory_bank_skill Python module
# regardless of the caller's cwd (bats runs from a temp dir).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ---- arg parsing ------------------------------------------------------------

FILES_CSV=""
DIFF_CSV=""
OUT="json"
SRP_THRESHOLD="${MB_SRP_THRESHOLD:-300}"
PROFILE_PATH="${MB_PROFILE:-}"

print_help() {
  sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files)          FILES_CSV="${2:-}";       shift 2 ;;
    --diff-files)     DIFF_CSV="${2:-}";        shift 2 ;;
    --out)            OUT="${2:-json}";         shift 2 ;;
    --srp-threshold)  SRP_THRESHOLD="${2:-300}"; shift 2 ;;
    --profile)        PROFILE_PATH="${2:-}";    shift 2 ;;
    --help|-h)        print_help; exit 0 ;;
    *) printf 'unknown arg: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$OUT" in
  json|human|both) ;;
  *) printf 'invalid --out: %s (allowed: json|human|both)\n' "$OUT" >&2; exit 2 ;;
esac

# ---- helpers ----------------------------------------------------------------

now_ms() {
  python3 -c 'import time; print(int(time.time()*1000))'
}

# Split a CSV string into a bash array (bash 3.2 compatible — no local -n).
# Usage: split_csv "$csv_string" ARRAY_NAME
split_csv() {
  local csv="$1"
  local out_name="$2"
  local -a raw=()
  local -a cleaned=()
  local i

  eval "${out_name}=()"
  [[ -z "$csv" ]] && return 0

  local IFS=,
  # shellcheck disable=SC2206
  raw=($csv)
  for i in "${!raw[@]}"; do
    [[ -n "${raw[$i]}" ]] && cleaned+=("${raw[$i]}")
  done
  if (( ${#cleaned[@]} > 0 )); then
    eval "${out_name}=(\"\${cleaned[@]}\")"
  fi
}

# JSON string escape — no jq needed on emit path.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

# emit_violation rule severity file line excerpt rationale [rule_id] [profile_source]
emit_violation() {
  local rule="$1" sev="$2" file="$3" line="$4" excerpt="$5" rationale="$6"
  local rule_id="${7:-$rule}"
  local profile_source="${8:-baseline}"
  VIOLATIONS+=("$(printf \
    '{"rule":%s,"rule_id":%s,"severity":%s,"file":%s,"line":%s,"excerpt":%s,"rationale":%s,"profile_source":%s}' \
    "$(json_escape "$rule")" \
    "$(json_escape "$rule_id")" \
    "$(json_escape "$sev")" \
    "$(json_escape "$file")" \
    "$line" \
    "$(json_escape "$excerpt")" \
    "$(json_escape "$rationale")" \
    "$(json_escape "$profile_source")")")
}

# ---- profile loading --------------------------------------------------------

# PROFILE_JSON holds the resolved profile as a JSON string.
PROFILE_JSON=""

load_profile() {
  local py_args=()
  if [[ -n "$PROFILE_PATH" && -f "$PROFILE_PATH" ]]; then
    py_args=("--project=$PROFILE_PATH")
  fi

  PROFILE_JSON="$(PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m memory_bank_skill.rules_profile resolve \
    "${py_args[@]+"${py_args[@]}"}" 2>/dev/null)" || true

  # Fallback: if Python call failed, produce a baseline profile JSON manually
  if [[ -z "$PROFILE_JSON" ]]; then
    PROFILE_JSON='{"role":"backend","stack":"generic","architecture":"clean","delivery":"tdd","strictness":"warn","sources":{"role":"baseline","stack":"baseline","architecture":"baseline","delivery":"baseline","strictness":"baseline"},"immutable_rules":["no-placeholders","protected-files","destructive-confirm","fail-fast","dry-kiss-yagni","verification-before-completion","explicit-storage-choice"],"prompt_summary":"# Active Rule Profile\nrole=backend  stack=generic  architecture=clean\ndelivery=tdd  strictness=warn\n\n## Sources\n  All: baseline\n\n## Immutable Baseline (non-overridable)\n  All safety rules active\n\n## Guidance\nFollow clean architecture with tdd delivery.\nStrictness: warn."}'
  fi
}

# Extract a scalar field from PROFILE_JSON without jq.
profile_field() {
  local field="$1"
  printf '%s' "$PROFILE_JSON" | \
    python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('${field}',''))" \
    2>/dev/null || true
}

# Extract the sources sub-dict for a given dimension.
profile_source_for() {
  local dim="$1"
  printf '%s' "$PROFILE_JSON" | \
    python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('sources',{}).get('${dim}','baseline'))" \
    2>/dev/null || printf 'baseline'
}

# ---- exclusions -------------------------------------------------------------

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
  if [[ "$f" =~ (^|/)\.[^/]+/ ]]; then
    return 0
  fi
  if [[ -f "$f" ]]; then
    local first_line
    first_line="$(head -n1 "$f" 2>/dev/null || true)"
    if [[ "$first_line" == *"GENERATED"* ]]; then
      return 0
    fi
  fi
  return 1
}

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
    agents/*) return 0 ;;
    tests/*|*/tests/*|*_test.*|*.test.*|*.spec.*) return 0 ;;
  esac
  return 1
}

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

has_matching_test() {
  local stem="$1" src_basename="$2"
  local -a stems=("$stem" "${stem//-/_}" "${stem//_/-}")
  case "$stem" in
    mb-*)
      local stripped="${stem#mb-}"
      stems+=("$stripped" "${stripped//-/_}" "${stripped//_/-}")
      ;;
    mb_*)
      local stripped="${stem#mb_}"
      stems+=("$stripped" "${stripped//-/_}" "${stripped//_/-}")
      ;;
  esac

  local df base s
  for df in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    base="$(basename "$df")"
    for s in "${stems[@]}"; do
      if [[ "$base" == "test_${s}."* || "$base" == "${s}_test."* \
            || "$base" == "${s}.test."* || "$base" == "${s}.spec."* ]]; then
        return 0
      fi
    done
  done
  [[ -z "$src_basename" ]] && return 1
  for df in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    base="$(basename "$df")"
    case "$base" in
      test_*|*_test.*|*.test.*|*.spec.*) ;;
      *) continue ;;
    esac
    [[ -f "$df" ]] || continue
    if grep -Fq "$src_basename" "$df" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# ---- baseline checks --------------------------------------------------------

check_srp() {
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local -a offenders=()
  local -a counts=()
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
  local total="${#offenders[@]}"
  (( total == 0 )) && return 0
  local sev="WARNING"
  if (( total >= 3 )); then
    sev="CRITICAL"
  fi
  local i
  for i in "${!offenders[@]}"; do
    emit_violation "solid/srp" "$sev" "${offenders[$i]}" 1 \
      "${counts[$i]} lines" \
      "File exceeds SRP threshold (>${SRP_THRESHOLD}); consider splitting into cohesive modules." \
      "solid/srp" "baseline"
  done
}

check_clean_arch() {
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local f
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *"/domain/"* || "$f" == "domain/"* ]] || continue
    local hit
    hit="$(grep -nE '(^|[[:space:]])(from|import)[[:space:]].*infrastructure|require.*infrastructure|"[^"]*/infrastructure[^"]*"' \
      "$f" 2>/dev/null | head -n1 || true)"
    [[ -z "$hit" ]] && continue
    local line_no="${hit%%:*}"
    local line_text="${hit#*:}"
    line_text="${line_text:0:120}"
    emit_violation "clean_arch/direction" "CRITICAL" "$f" "$line_no" \
      "$line_text" \
      "domain/ layer must not depend on infrastructure/; invert the dependency via an interface owned by domain." \
      "clean_arch/direction" "baseline"
  done
}

check_tdd_delta() {
  (( ${#DIFF_FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local f
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    is_tdd_exempt "$f" && continue
    is_test_file "$f" && continue
    case "$f" in
      src/*|*/src/*|scripts/*|lib/*|*/lib/*|internal/*|*/internal/*|pkg/*|*/pkg/*|cmd/*|*/cmd/*) ;;
      *) continue ;;
    esac
    local base stem
    base="$(basename "$f")"
    stem="${base%.*}"
    if ! has_matching_test "$stem" "$base"; then
      emit_violation "tdd/delta" "CRITICAL" "$f" 1 \
        "no matching test in diff" \
        "Source file changed without a co-changed test; add or update tests in the same commit range." \
        "tdd/delta" "baseline"
    fi
  done
}

# ---- stack-aware checks (4.2) -----------------------------------------------

check_stack_go() {
  # Only activate for .go files in the diff.
  (( ${#DIFF_FILES[@]} == 0 && ${#FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))

  local stack_source
  stack_source="$(profile_source_for stack)"

  local f
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.go ]] || continue

    # Check 1: public handler/func with http.ResponseWriter but no context.Context
    local lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      # Match func declarations with http.ResponseWriter parameter
      if [[ "$line" =~ ^[[:space:]]*func[[:space:]]+[A-Z][A-Za-z0-9_]*\( ]]; then
        if [[ "$line" == *"http.ResponseWriter"* || "$line" == *"http.Handler"* ]]; then
          if [[ "$line" != *"context.Context"* && "$line" != *"ctx"* ]]; then
            local excerpt="${line:0:120}"
            emit_violation \
              "stack.go.context-propagation" "WARNING" "$f" "$lineno" \
              "$excerpt" \
              "Public HTTP handler lacks context.Context parameter; context should propagate through the call chain." \
              "stack.go.context-propagation" "$stack_source"
          fi
        fi
      fi
    done < "$f"

    # Check 2: goroutine spawns without context access (advisory)
    lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if [[ "$line" =~ ^[[:space:]]*go[[:space:]] ]]; then
        if [[ "$line" != *"ctx"* && "$line" != *"context"* ]]; then
          local excerpt="${line:0:120}"
          emit_violation \
            "stack.go.goroutine-context" "WARNING" "$f" "$lineno" \
            "$excerpt" \
            "Goroutine spawned without apparent context propagation; ensure context cancellation is handled." \
            "stack.go.goroutine-context" "$stack_source"
        fi
      fi
    done < "$f"
  done
}

check_stack_python() {
  (( ${#FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))

  local stack_source
  stack_source="$(profile_source_for stack)"

  local f
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    [[ "$f" == *.py ]] || continue

    # Check 1: def lines without type hints on parameters
    local lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      # Match def lines: "def name(params):"
      if [[ "$line" =~ ^[[:space:]]*def[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*\( ]]; then
        # Skip if it's a test function (test_ prefix)
        local func_name
        func_name="$(printf '%s' "$line" | sed 's/.*def[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/')"
        [[ "$func_name" == test_* ]] && continue
        # Check for absence of type hints: no colon before comma/paren (except closing)
        # Heuristic: if params exist (non-empty between parens) and no ":" in param area
        local params_area="${line#*\(}"
        params_area="${params_area%%\)*}"
        # Skip trivial: no params or just self/cls
        [[ -z "${params_area// /}" ]] && continue
        [[ "${params_area// /}" == "self" ]] && continue
        [[ "${params_area// /}" == "cls" ]] && continue
        [[ "${params_area// /}" == "self," ]] && continue
        # If no ":" appears in param area, type hints are missing
        if [[ "$params_area" != *":"* ]]; then
          local excerpt="${line:0:120}"
          emit_violation \
            "stack.python.type-hints" "WARNING" "$f" "$lineno" \
            "$excerpt" \
            "Function lacks type annotations on parameters; add type hints for clarity and static analysis." \
            "stack.python.type-hints" "$stack_source"
        fi
      fi
    done < "$f"

    # Check 2: mock imports in business-logic modules (warn) — only for diff files
    local is_diff=0
    local df
    for df in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
      [[ "$df" == "$f" ]] && is_diff=1 && break
    done
    (( is_diff == 0 )) && continue

    # Skip test files
    is_test_file "$f" && continue

    lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if [[ "$line" =~ ^[[:space:]]*(import[[:space:]]+unittest\.mock|from[[:space:]]+unittest\.mock) ]]; then
        local excerpt="${line:0:120}"
        emit_violation \
          "stack.python.no-business-mocks" "WARNING" "$f" "$lineno" \
          "$excerpt" \
          "Business logic module imports unittest.mock; mocks belong in test files only." \
          "stack.python.no-business-mocks" "$stack_source"
      fi
    done < "$f"
  done
}

check_stack_typescript() {
  (( ${#DIFF_FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))

  local stack_source
  stack_source="$(profile_source_for stack)"

  local f
  for f in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *.ts|*.tsx) ;;
      *) continue ;;
    esac

    local lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      # Match `: any` or `<any>` or `as any` patterns (type annotation any)
      if [[ "$line" =~ :[[:space:]]*any[[:space:],\)\;]|:[[:space:]]*any$ ]] || \
         [[ "$line" =~ \<any\> ]] || \
         [[ "$line" =~ [[:space:]]as[[:space:]]any ]]; then
        local excerpt="${line:0:120}"
        emit_violation \
          "stack.typescript.no-any" "WARNING" "$f" "$lineno" \
          "$excerpt" \
          "TypeScript \`any\` type usage detected; use specific types or \`unknown\` instead." \
          "stack.typescript.no-any" "$stack_source"
      fi
    done < "$f"
  done
}

check_stack_javascript() {
  (( ${#DIFF_FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))

  local stack_source
  stack_source="$(profile_source_for stack)"

  local f
  for f in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *.js|*.jsx) ;;
      *) continue ;;
    esac

    local lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      # Match == but not === (loose equality) via grep
      if printf '%s\n' "$line" | grep -qE '[^=!<>]==[^=]'; then
        # Exclude lines that are comments
        local stripped="${line#"${line%%[! ]*}"}"
        [[ "$stripped" == //* ]] && continue
        [[ "$stripped" == \** ]] && continue
        local excerpt="${line:0:120}"
        emit_violation \
          "stack.javascript.strict-equality" "WARNING" "$f" "$lineno" \
          "$excerpt" \
          "Loose equality (==) detected; use strict equality (===) to avoid type coercion bugs." \
          "stack.javascript.strict-equality" "$stack_source"
      fi
    done < "$f"
  done
}

# ---- architecture-aware checks (4.3) ----------------------------------------

check_arch_fsd() {
  (( ${#FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))

  local arch_source
  arch_source="$(profile_source_for architecture)"

  local f
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    # Only fire on files under entities/ or shared/
    case "$f" in
      */entities/*|entities/*|*/shared/*|shared/*) ;;
      *) continue ;;
    esac

    # Scan for imports that go upward to features/ or widgets/
    local lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      # Match: from '../../features/...', from '../../widgets/...', etc.
      if [[ "$line" =~ from[[:space:]]+[\"\'].*features/ ]] || \
         [[ "$line" =~ from[[:space:]]+[\"\'].*widgets/ ]]; then
        local excerpt="${line:0:120}"
        emit_violation \
          "architecture.fsd.import-direction" "WARNING" "$f" "$lineno" \
          "$excerpt" \
          "FSD violation: entities/ and shared/ must not import from features/ or widgets/ (upward import)." \
          "architecture.fsd.import-direction" "$arch_source"
      fi
    done < "$f"
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

# Load the resolved profile (4.1)
load_profile

# Read profile dimensions for conditional checks
PROFILE_STACK="$(profile_field stack)"
PROFILE_ARCH="$(profile_field architecture)"
PROFILE_STRICTNESS="$(profile_field strictness)"

# ---- baseline checks (always run) -------------------------------------------
check_srp
check_clean_arch
check_tdd_delta

# ---- stack-aware checks (4.2) — gated on resolved stack --------------------
case "$PROFILE_STACK" in
  go)
    check_stack_go
    ;;
  python)
    check_stack_python
    ;;
  typescript)
    check_stack_typescript
    ;;
  javascript)
    check_stack_javascript
    ;;
  *)
    # generic or unknown: no stack-specific checks
    ;;
esac

# ---- architecture-aware checks (4.3) — gated on resolved architecture ------
case "$PROFILE_ARCH" in
  fsd)
    check_arch_fsd
    ;;
esac

END_MS="$(now_ms)"
DURATION=$((END_MS - START_MS))

# ---- determine exit code based on strictness (4.4) -------------------------
# Default: 0 (backward compatible)
EXIT_CODE=0
if [[ "$PROFILE_STRICTNESS" == "block" ]]; then
  for v in "${VIOLATIONS[@]+"${VIOLATIONS[@]}"}"; do
    if [[ "$v" == *'"severity":"CRITICAL"'* ]]; then
      EXIT_CODE=1
      break
    fi
  done
fi
# advisory: always 0

# ---- emit output (4.5) — profile block in JSON envelope --------------------

emit_json() {
  # Build profile block — use python3 to avoid hand-rolling nested JSON
  local profile_json
  profile_json="$(python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
# Keep only fields needed for envelope
out = {
  'role': d.get('role','backend'),
  'stack': d.get('stack','generic'),
  'architecture': d.get('architecture','clean'),
  'delivery': d.get('delivery','tdd'),
  'strictness': d.get('strictness','warn'),
  'sources': d.get('sources',{}),
  'prompt_summary': d.get('prompt_summary',''),
}
print(json.dumps(out))
" <<< "$PROFILE_JSON" 2>/dev/null)" || \
  profile_json='{"role":"backend","stack":"generic","architecture":"clean","delivery":"tdd","strictness":"warn","sources":{},"prompt_summary":""}'

  printf '{"violations":['
  local i
  for i in "${!VIOLATIONS[@]}"; do
    (( i > 0 )) && printf ','
    printf '%s' "${VIOLATIONS[$i]}"
  done
  printf '],"profile":%s,"stats":{"files_scanned":%d,"checks_run":%d,"duration_ms":%d}}\n' \
    "$profile_json" \
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
  for v in "${VIOLATIONS[@]+"${VIOLATIONS[@]}"}"; do
    rule="$(printf '%s' "$v"     | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["rule"])')"
    sev="$(printf '%s' "$v"      | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["severity"])')"
    file="$(printf '%s' "$v"     | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["file"])')"
    line="$(printf '%s' "$v"     | python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["line"])')"
    rationale="$(printf '%s' "$v"| python3 -c 'import sys,json; print(json.loads(sys.stdin.read())["rationale"])')"
    printf '  [%s] %s — %s:%s — %s\n' "$sev" "$rule" "$file" "$line" "$rationale"
  done
}

case "$OUT" in
  json)  emit_json ;;
  human) emit_human ;;
  both)  emit_human; emit_json ;;
esac

exit "$EXIT_CODE"
