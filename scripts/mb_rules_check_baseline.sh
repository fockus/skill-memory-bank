# shellcheck shell=bash
# Baseline deterministic checks for mb-rules-check.sh.

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
