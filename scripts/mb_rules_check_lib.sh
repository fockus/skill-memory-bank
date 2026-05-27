#!/usr/bin/env bash
# Shared helpers for mb-rules-check.sh. Sourced by the main dispatcher.

# ---- helpers ----------------------------------------------------------------

now_ms() {
  # portable-ish: python3 is a hard dep of this skill, so use it
  python3 -c 'import time; print(int(time.time()*1000))'
}

# Split a CSV string into a bash array, skipping empty entries.
split_csv() {
  local csv="$1"; shift
  local out_name="$1"
  local -a raw=()
  local -a cleaned=()
  local i

  eval "$out_name=()"
  [[ -z "$csv" ]] && return 0

  local IFS=,
  # shellcheck disable=SC2206
  raw=($csv)
  # drop accidental empty entries (e.g. trailing comma)
  for i in "${!raw[@]}"; do
    [[ -n "${raw[$i]}" ]] && cleaned+=("${raw[$i]}")
  done
  eval "$out_name=(\"\${cleaned[@]}\")"
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

# ---- exclusions -------------------------------------------------------------

# Returns 0 if the file should be fully excluded from structural checks
# (SRP is the main user). Matches extensions + path segments.
is_fully_excluded() {
  local f="$1"
  case "$f" in
    install.sh|uninstall.sh) return 0 ;;
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
  local stem="$1" src_basename="$2"
  # Build the candidate stem list: original + dash/underscore variants +
  # versions with a leading `mb-` prefix stripped. Scripts named `mb-foo.sh`
  # are routinely covered by `test_foo_*.bats` (the test targets the
  # conceptual feature, not the prefixed script name). Without this strip
  # step the matcher emits false-positive tdd/delta CRITICALs even when
  # full coverage exists.
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
  # Pass 1 — basename-based matching (fast path). Catches the common
  # same-stem convention used by most projects.
  for df in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    base="$(basename "$df")"
    for s in "${stems[@]}"; do
      if [[ "$base" == "test_${s}."* || "$base" == "${s}_test."* \
            || "$base" == "${s}.test."* || "$base" == "${s}.spec."* ]]; then
        return 0
      fi
    done
  done
  # Pass 2 — content-based matching (fallback). When tests are named after
  # the agent/feature rather than the script (e.g. test_rules_enforcer_*.bats
  # exercises scripts/mb-rules-check.sh), basename matching misses real
  # coverage. Grep each diff-changed test file for the source basename; a
  # single literal reference counts as co-change intent.
  [[ -z "$src_basename" ]] && return 1
  for df in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    base="$(basename "$df")"
    # Only inspect files that look like tests.
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
