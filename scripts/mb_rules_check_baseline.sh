# shellcheck shell=bash
# Baseline deterministic checks for mb-rules-check.sh.

# Line count of a file at $BASE_REF (0 when it did not exist there). Paths may be relative
# or absolute; the lookup uses the path from the repository root.
_srp_lines_at_base() {
  local f="$1" dir prefix
  dir="$(cd "$(dirname "$f")" 2>/dev/null && pwd)" || { printf '0'; return; }
  prefix="$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)" || { printf '0'; return; }
  { git -C "$dir" show "${BASE_REF}:${prefix}$(basename "$f")" 2>/dev/null || true; } | wc -l | tr -d ' '
}

# A check the rules profile switched off (AGR-077): one INFO entry with the reason
# instead of silence. <rule> <profile key>.
_emit_skipped() {
  emit_violation "$1" "INFO" "" 0 "skipped" \
    "Skipped: $2 is off in the rules profile (AGR-077)." "$1" "$2"
}

check_srp() {
  [[ "${QUALITY_SOLID:-on}" == "off" ]] && { _emit_skipped "solid/srp" "quality.principles.solid"; return 0; }
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
  (( ${#offenders[@]} == 0 )) && return 0
  # Size alone is a split candidate (WARNING). With --base, a file this change pushed over
  # the threshold (or created over it) blocks: CRITICAL. Canon: rules/RULES.md § SOLID.
  local i sev rationale base_n
  for i in "${!offenders[@]}"; do
    sev="WARNING"
    rationale="File exceeds SRP threshold (>${SRP_THRESHOLD}); split candidate."
    if [[ -n "${BASE_REF:-}" ]]; then
      base_n="$(_srp_lines_at_base "${offenders[$i]}")"
      if (( ${base_n:-0} <= SRP_THRESHOLD )); then
        sev="CRITICAL"
        rationale="This change pushed the file over the SRP threshold (${base_n:-0} → ${counts[$i]} lines); split it."
      fi
    fi
    emit_violation "solid/srp" "$sev" "${offenders[$i]}" 1 \
      "${counts[$i]} lines" "$rationale" "solid/srp" "baseline"
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
  [[ "${QUALITY_TDD:-on}" == "off" ]] && { _emit_skipped "tdd/delta" "quality.tdd"; return 0; }
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
    if ! has_matching_test "$stem" "$base" "$f"; then
      emit_violation "tdd/delta" "CRITICAL" "$f" 1 \
        "no matching test in diff" \
        "Source file changed without a co-changed test; add or update tests in the same commit range." \
        "tdd/delta" "baseline"
    fi
  done
}
