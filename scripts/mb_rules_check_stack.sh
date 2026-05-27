# shellcheck shell=bash
# shellcheck disable=SC2094
# Stack-aware and architecture-aware checks for mb-rules-check.sh.

check_stack_go() {
  (( ${#DIFF_FILES[@]} == 0 && ${#FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local stack_source f
  stack_source="$(profile_source_for stack)"
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" && "$f" == *.go ]] || continue
    local lineno=0 line
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if [[ "$line" =~ ^[[:space:]]*func[[:space:]]+[A-Z][A-Za-z0-9_]*\( ]]; then
        if [[ "$line" == *"http.ResponseWriter"* || "$line" == *"http.Handler"* ]]; then
          if [[ "$line" != *"context.Context"* && "$line" != *"ctx"* ]]; then
            emit_violation "stack.go.context-propagation" "WARNING" "$f" "$lineno" \
              "${line:0:120}" \
              "Public HTTP handler lacks context.Context parameter; context should propagate through the call chain." \
              "stack.go.context-propagation" "$stack_source"
          fi
        fi
      fi
    done < "$f"

    lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if [[ "$line" =~ ^[[:space:]]*go[[:space:]] ]]; then
        if [[ "$line" != *"ctx"* && "$line" != *"context"* ]]; then
          emit_violation "stack.go.goroutine-context" "WARNING" "$f" "$lineno" \
            "${line:0:120}" \
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
  local stack_source f
  stack_source="$(profile_source_for stack)"
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" && "$f" == *.py ]] || continue
    local lineno=0 line
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if [[ "$line" =~ ^[[:space:]]*def[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*\( ]]; then
        local func_name params_area
        func_name="$(printf '%s' "$line" | sed 's/.*def[[:space:]]\+\([a-zA-Z_][a-zA-Z0-9_]*\).*/\1/')"
        [[ "$func_name" == test_* ]] && continue
        params_area="${line#*\(}"
        params_area="${params_area%%\)*}"
        [[ -z "${params_area// /}" ]] && continue
        [[ "${params_area// /}" == "self" ]] && continue
        [[ "${params_area// /}" == "cls" ]] && continue
        [[ "${params_area// /}" == "self," ]] && continue
        if [[ "$params_area" != *":"* ]]; then
          emit_violation "stack.python.type-hints" "WARNING" "$f" "$lineno" \
            "${line:0:120}" \
            "Function lacks type annotations on parameters; add type hints for clarity and static analysis." \
            "stack.python.type-hints" "$stack_source"
        fi
      fi
    done < "$f"

    local is_diff=0 df
    for df in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
      [[ "$df" == "$f" ]] && is_diff=1 && break
    done
    (( is_diff == 0 )) && continue
    is_test_file "$f" && continue
    lineno=0
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if [[ "$line" =~ ^[[:space:]]*(import[[:space:]]+unittest\.mock|from[[:space:]]+unittest\.mock) ]]; then
        emit_violation "stack.python.no-business-mocks" "WARNING" "$f" "$lineno" \
          "${line:0:120}" \
          "Business logic module imports unittest.mock; mocks belong in test files only." \
          "stack.python.no-business-mocks" "$stack_source"
      fi
    done < "$f"
  done
}

check_stack_typescript() {
  (( ${#DIFF_FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local stack_source f
  stack_source="$(profile_source_for stack)"
  for f in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    case "$f" in *.ts|*.tsx) ;; *) continue ;; esac
    local lineno=0 line
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if [[ "$line" =~ :[[:space:]]*any[[:space:],\)\;]|:[[:space:]]*any$ ]] || \
         [[ "$line" =~ \<any\> ]] || \
         [[ "$line" =~ [[:space:]]as[[:space:]]any ]]; then
        emit_violation "stack.typescript.no-any" "WARNING" "$f" "$lineno" \
          "${line:0:120}" \
          "TypeScript \`any\` type usage detected; use specific types or \`unknown\` instead." \
          "stack.typescript.no-any" "$stack_source"
      fi
    done < "$f"
  done
}

check_stack_javascript() {
  (( ${#DIFF_FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local stack_source f
  stack_source="$(profile_source_for stack)"
  for f in "${DIFF_FILES[@]+"${DIFF_FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    case "$f" in *.js|*.jsx) ;; *) continue ;; esac
    local lineno=0 line stripped
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if printf '%s\n' "$line" | grep -qE '[^=!<>]==[^=]'; then
        stripped="${line#"${line%%[! ]*}"}"
        [[ "$stripped" == //* || "$stripped" == \** ]] && continue
        emit_violation "stack.javascript.strict-equality" "WARNING" "$f" "$lineno" \
          "${line:0:120}" \
          "Loose equality (==) detected; use strict equality (===) to avoid type coercion bugs." \
          "stack.javascript.strict-equality" "$stack_source"
      fi
    done < "$f"
  done
}

check_arch_fsd() {
  (( ${#FILES[@]} == 0 )) && return 0
  CHECKS_RUN=$((CHECKS_RUN + 1))
  local arch_source f
  arch_source="$(profile_source_for architecture)"
  for f in "${FILES[@]+"${FILES[@]}"}"; do
    [[ -f "$f" ]] || continue
    case "$f" in */entities/*|entities/*|*/shared/*|shared/*) ;; *) continue ;; esac
    local lineno=0 line
    while IFS= read -r line; do
      lineno=$((lineno + 1))
      if [[ "$line" =~ from[[:space:]]+[\"\'].*features/ ]] || \
         [[ "$line" =~ from[[:space:]]+[\"\'].*widgets/ ]]; then
        emit_violation "architecture.fsd.import-direction" "WARNING" "$f" "$lineno" \
          "${line:0:120}" \
          "FSD violation: entities/ and shared/ must not import from features/ or widgets/ (upward import)." \
          "architecture.fsd.import-direction" "$arch_source"
      fi
    done < "$f"
  done
}
