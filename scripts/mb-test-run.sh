#!/usr/bin/env bash
# mb-test-run.sh — structured test runner with per-stack output parsing.
#
# Usage:
#   mb-test-run.sh [--dir <path>] [--out json|human|both]
#                  [--changed-since <git-ref>] [--files <path>[,<path>...]]
#
# Targeted run: --changed-since (diff vs ref + untracked files) and/or --files
# (comma-separated, repeatable) run only tests related to those files: changed
# test files, naming convention (foo.py -> test_foo*.py / foo_test.py,
# x.sh -> test_x*.bats, x.go -> its package dir) and, when the code graph is
# fresh, `mb-graph-query.py tests --file`. Falls back to the full suite (with
# "reason") on an invalid ref, an empty mapping or a shared test-infra change.
# JSON then gains "selection", "selected" and "reason"; without these flags the
# output is unchanged.
#
# Wraps scripts/mb-metrics.sh for stack detection, then runs tests directly
# with predictable flags so output parsing is deterministic.
#
# Exit code is always 0. pass/fail is reported via `tests_pass` in the JSON
# so callers do not confuse "script broke" with "tests failed".
#
# Supported stacks: bats (*.bats under tests/ or hooks/tests/), python (pytest), go (go test).
# Every stack with tests runs; counts and failures are summed and "stack" joins
# them with "+" (e.g. "bats+python"). A single-stack repo reports as before.
# --test-command / MB_TEST_COMMAND for explicit override; empty dirs emit not_applicable=true.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

DIR="."
OUT="json"

TEST_CMD_CLI=""
CHANGED_SINCE=""
FILES_ARG=""
TARGETED_REQ=0

# shellcheck disable=SC2034  # CHANGED_SINCE is read by _test_select.sh
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)  DIR="${2:-.}";   shift 2 ;;
    --out)  OUT="${2:-json}"; shift 2 ;;
    --test-command) TEST_CMD_CLI="${2:-}"; shift 2 ;;
    --changed-since) CHANGED_SINCE="${2:-}"; TARGETED_REQ=1; shift 2 ;;
    --files) FILES_ARG="${FILES_ARG:+$FILES_ARG,}${2:-}"; TARGETED_REQ=1; shift 2 ;;
    --help|-h)
      sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

case "$OUT" in
  json|human|both) ;;
  *) echo "invalid --out: $OUT (allowed: json|human|both)" >&2; exit 2 ;;
esac

# ---- helpers ----------------------------------------------------------------

now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '"%s"' "$s"
}

# Build a single failure JSON object.
failure_json() {
  local file="$1" name="$2" error_head="$3"
  printf '{"file":%s,"name":%s,"error_head":%s}' \
    "$(json_escape "$file")" \
    "$(json_escape "$name")" \
    "$(json_escape "$error_head")"
}


# Strip ANSI colour escapes from a captured log, in place. Runners ask their
# child not to colourize (run_uncolored below), but pytest colourizes into a
# file anyway when FORCE_COLOR is set in the environment, so the parse must not
# depend on whether a given tool version honours the variable.
strip_ansi_file() {
  local f="$1" tmp
  tmp="$(mktemp)"
  sed $'s/\033\[[0-9;]*[a-zA-Z]//g' "$f" >"$tmp"
  mv "$tmp" "$f"
}

# Run a command with colour output disabled in the child environment.
run_uncolored() {
  env -u FORCE_COLOR -u CLICOLOR_FORCE NO_COLOR=1 "$@"
}

# Collect *.bats paths relative to DIR (tests/ or hooks/tests/).
find_bats_files() {
  local d f
  for d in tests hooks/tests; do
    [ -d "$DIR/$d" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      printf '%s\n' "${f#"$DIR"/}"
    done < <(find "$DIR/$d" -name '*.bats' 2>/dev/null | sort)
  done
}

# shellcheck source=_test_select.sh
source "$(dirname "$0")/_test_select.sh"

SELECTION=""        # "" (no targeted request) | targeted | full
SELECT_REASON=""
SEL_BATS=(); SEL_PY=(); SEL_GO=()

NOT_APPLICABLE="false"
RUNNER_ERROR="false"

# ---- stack detection --------------------------------------------------------

# Use mb-metrics.sh (no --run) for stack + test_cmd.
# eval line format: key=value.
METRICS_OUT="$(bash "$(dirname "$0")/mb-metrics.sh" "$DIR" 2>/dev/null || true)"
STACK="$(printf '%s\n' "$METRICS_OUT" | awk -F= '$1=="stack"{print $2; exit}')"
[[ -z "$STACK" ]] && STACK="unknown"

# Global accumulators.
TESTS_PASS="null"   # null | true | false
TESTS_TOTAL=0
TESTS_FAILED=0
FAILURES_JSON=()
COV_OVERALL="null"

START_MS="$(now_ms)"

# Add one stack's counts to the accumulators; verdict follows the totals.
add_counts() {
  TESTS_TOTAL=$((TESTS_TOTAL + $1))
  TESTS_FAILED=$((TESTS_FAILED + $2))
  if (( TESTS_TOTAL == 0 )); then
    TESTS_PASS="null"
  elif (( TESTS_FAILED == 0 )); then
    TESTS_PASS="true"
  else
    TESTS_PASS="false"
  fi
}

# ---- per-stack runners ------------------------------------------------------

run_python() {
  # Prefer the project's own venv over PATH: a bare `pytest` may resolve to a
  # pyenv shim / global install WITHOUT the project installed, which yields
  # mass phantom collection errors reported as failures.
  # Use `python -m pytest` (NOT the pytest entry script): -m prepends the CWD
  # to sys.path, which repos rely on for `from tests....` helper imports —
  # the entry script omits it and dies with collection ImportErrors.
  # A bare `pytest` on PATH may be a wrapper, so probe the interpreters.
  local -a pytest_cmd=()
  if [[ -x "$DIR/.venv/bin/python" ]] && "$DIR/.venv/bin/python" -c 'import pytest' >/dev/null 2>&1; then
    pytest_cmd=("$DIR/.venv/bin/python" -m pytest)
  elif python3 -c 'import pytest' >/dev/null 2>&1; then
    pytest_cmd=(python3 -m pytest)
  else
    echo "[warn] pytest importable from neither $DIR/.venv/bin/python nor python3; skipping python run" >&2
    return 0
  fi
  local log
  log="$(mktemp)"
  # -q: quiet; --tb=line: one-line traceback; -r a: summary for all; -p no:cacheprovider to avoid stale cache.
  # Exit codes: 0 passed, 1 failed, 5 no tests collected.
  (cd "$DIR" && run_uncolored "${pytest_cmd[@]}" -q --tb=line --no-header -r a -p no:cacheprovider ${SEL_PY[@]+"${SEL_PY[@]}"}) >"$log" 2>&1 || true
  strip_ansi_file "$log"
  local rc=0
  # Use grep exit codes to infer.
  # Parse summary line: "X failed, Y passed in Zs" | "N passed in Zs" | "no tests ran".
  local summary
  summary="$(grep -E '^(=+ )?([0-9]+ (failed|passed|error|skipped|warnings)[,]? ?)+.*in [0-9.]+' "$log" | tail -n1 || true)"
  if [[ -z "$summary" ]]; then
    # "no tests ran" or similar → leave counts at 0, tests_pass=null.
    rm -f "$log"
    return 0
  fi

  local passed failed errors
  passed="$(echo "$summary" | grep -oE '[0-9]+ passed'   | head -n1 | awk '{print $1}' || true)"
  failed="$(echo "$summary" | grep -oE '[0-9]+ failed'   | head -n1 | awk '{print $1}' || true)"
  errors="$(echo "$summary" | grep -oE '[0-9]+ error'    | head -n1 | awk '{print $1}' || true)"
  passed="${passed:-0}"
  failed="${failed:-0}"
  errors="${errors:-0}"

  add_counts $((passed + failed + errors)) $((failed + errors))

  # Extract FAILED lines from pytest short summary:
  # "FAILED tests/foo.py::test_bar - AssertionError: ..."
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Strip the "FAILED " prefix.
    local rest="${line#FAILED }"
    # Split at first " - " for nodeid vs error_head.
    local nodeid="${rest%% - *}"
    local err="${rest#* - }"
    [[ "$err" == "$rest" ]] && err=""
    # nodeid = tests/foo.py::test_bar  →  file=tests/foo.py, name=test_bar
    local file="${nodeid%%::*}"
    local name="${nodeid#*::}"
    [[ "$name" == "$nodeid" ]] && name=""
    FAILURES_JSON+=("$(failure_json "$file" "$name" "$err")")
  done < <(grep '^FAILED ' "$log" || true)

  rm -f "$log"
  return $rc
}

run_go() {
  command -v go >/dev/null || {
    echo "[warn] go not in PATH; skipping go run" >&2
    return 0
  }
  local log
  log="$(mktemp)"
  local -a pkgs=(./...)
  [[ "$SELECTION" == "targeted" ]] && pkgs=("${SEL_GO[@]}")
  (cd "$DIR" && go test "${pkgs[@]}" -v 2>&1) >"$log" || true

  local passed failed
  passed="$(grep -cE '^--- PASS:' "$log" || true)"
  failed="$(grep -cE '^--- FAIL:' "$log" || true)"
  passed="${passed:-0}"
  failed="${failed:-0}"

  add_counts $((passed + failed)) "$failed"

  # Each "--- FAIL: TestName (0.00s)" line → failure entry.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # "--- FAIL: TestBad (0.00s)" → name=TestBad
    local name
    name="$(echo "$line" | sed -nE 's/^--- FAIL:[[:space:]]*([^[:space:]]+).*$/\1/p')"
    [[ -z "$name" ]] && continue
    # Error head: grep nearby lines mentioning "<file>_test.go:N: ..."
    local err_head
    err_head="$(grep -E '_test\.go:[0-9]+:' "$log" | head -n5 | tr '\n' ' ' || true)"
    FAILURES_JSON+=("$(failure_json "" "$name" "$err_head")")
  done < <(grep '^--- FAIL:' "$log" || true)

  rm -f "$log"
  return 0
}


run_bats() {
  local files
  local -a file_args=()
  files="$(find_bats_files)"
  [[ -z "$files" ]] && return 1
  command -v bats >/dev/null || {
    echo "[warn] bats not in PATH; cannot run shell tests" >&2
    NOT_APPLICABLE="true"
    return 0
  }
  local log
  log="$(mktemp)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    file_args+=("$f")
  done <<< "$files"
  [[ "$SELECTION" == "targeted" ]] && file_args=("${SEL_BATS[@]}")
  (cd "$DIR" && run_uncolored bats "${file_args[@]}") >"$log" 2>&1 || true
  strip_ansi_file "$log"
  local summary total failed
  summary="$(grep -E '^[0-9]+ tests?, [0-9]+ failures?' "$log" | tail -n1 || true)"
  if [[ -z "$summary" ]]; then
    total="$(grep -cE '^ok |^not ok ' "$log" || true)"
    failed="$(grep -cE '^not ok ' "$log" || true)"
    total="${total:-0}"
    failed="${failed:-0}"
  else
    total="$(echo "$summary" | sed -nE 's/^([0-9]+) tests?, .*/\1/p')"
    failed="$(echo "$summary" | sed -nE 's/^[0-9]+ tests?, ([0-9]+) failures?/\1/p')"
    total="${total:-0}"
    failed="${failed:-0}"
  fi
  add_counts "$total" "$failed"
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local num name rest
    num="${line#not ok }"
    num="${num%% *}"
    rest="${line#not ok "$num" }"
    name="${rest%% *}"
    FAILURES_JSON+=("$(failure_json "" "$name" "bats failure")")
  done < <(grep '^not ok ' "$log" || true)
  rm -f "$log"
  return 0
}

run_test_command() {
  local cmd="${1:-}"
  [[ -z "$cmd" ]] && return 1
  STACK="custom"
  set +e
  (cd "$DIR" && eval "$cmd") >/dev/null 2>&1
  local rc=$?
  set -e
  TESTS_TOTAL=1
  if (( rc == 0 )); then
    TESTS_PASS="true"
    TESTS_FAILED=0
  else
    TESTS_PASS="false"
    TESTS_FAILED=1
    RUNNER_ERROR="true"
    FAILURES_JSON+=("$(failure_json "" "test_command" "exit rc=$rc")")
  fi
  return 0
}

# Dispatch: explicit test command → every detected stack → not_applicable.
EFFECTIVE_CMD="${TEST_CMD_CLI:-${MB_TEST_COMMAND:-}}"
if [[ -n "$EFFECTIVE_CMD" ]]; then
  if (( TARGETED_REQ == 1 )); then
    SELECTION="full"
    SELECT_REASON="custom test command: targeted selection unsupported"
  fi
  run_test_command "$EFFECTIVE_CMD"
else
  STACKS="$(detect_test_stacks)"
  if (( TARGETED_REQ == 1 )) && [[ -n "$STACKS" ]]; then
    select_tests "$STACKS"
  fi
  RAN=""
  for st in $STACKS; do
    if [[ "$SELECTION" == "targeted" ]]; then
      case "$st" in
        bats) (( ${#SEL_BATS[@]} )) || continue ;;
        python) (( ${#SEL_PY[@]} )) || continue ;;
        go) (( ${#SEL_GO[@]} )) || continue ;;
      esac
    fi
    case "$st" in
      bats) run_bats ;;
      python) run_python ;;
      go) run_go ;;
    esac
    RAN="${RAN:+$RAN+}$st"
  done
  if [[ -n "$RAN" ]]; then
    STACK="$RAN"
    if (( TESTS_TOTAL > 0 )); then NOT_APPLICABLE="false"; fi
  else
    NOT_APPLICABLE="true"
    TESTS_PASS="null"
  fi
fi

END_MS="$(now_ms)"
DURATION=$((END_MS - START_MS))

# ---- emit -------------------------------------------------------------------

emit_json() {
  local na re
  case "$NOT_APPLICABLE" in true) na="true" ;; *) na="false" ;; esac
  case "$RUNNER_ERROR" in true) re="true" ;; *) re="false" ;; esac
  printf '{"stack":%s,"tests_pass":%s,"tests_total":%d,"tests_failed":%d,"not_applicable":%s,"runner_error":%s,"failures":[' \
    "$(json_escape "$STACK")" "$TESTS_PASS" "$TESTS_TOTAL" "$TESTS_FAILED" "$na" "$re"
  local i
  for i in "${!FAILURES_JSON[@]}"; do
    (( i > 0 )) && printf ','
    printf '%s' "${FAILURES_JSON[$i]}"
  done
  printf '],"coverage":{"overall":%s,"per_file":{}},"duration_ms":%d' \
    "$COV_OVERALL" "$DURATION"
  if [[ -n "$SELECTION" ]]; then
    printf ',"selection":%s,"selected":[' "$(json_escape "$SELECTION")"
    if [[ "$SELECTION" == "targeted" ]]; then
      local sep="" f
      for f in ${SEL_BATS[@]+"${SEL_BATS[@]}"} ${SEL_PY[@]+"${SEL_PY[@]}"} ${SEL_GO[@]+"${SEL_GO[@]}"}; do
        printf '%s' "$sep"; json_escape "$f"; sep=","
      done
    fi
    printf '],"reason":'
    if [[ -n "$SELECT_REASON" ]]; then json_escape "$SELECT_REASON"; else printf 'null'; fi
  fi
  printf '}\n'
}

emit_human() {
  local verdict
  case "$TESTS_PASS" in
    true)  verdict="✅ PASS" ;;
    false) verdict="❌ FAIL" ;;
    *)     verdict="⚠️  NOT-RUN" ;;
  esac
  printf 'test-run: stack=%s verdict=%s total=%d failed=%d duration=%dms\n' \
    "$STACK" "$verdict" "$TESTS_TOTAL" "$TESTS_FAILED" "$DURATION"
  if [[ "$SELECTION" == "targeted" ]]; then
    printf 'selection=targeted files: %s\n' "${SEL_BATS[*]+${SEL_BATS[*]} }${SEL_PY[*]+${SEL_PY[*]} }${SEL_GO[*]-}"
  elif [[ -n "$SELECTION" ]]; then
    printf 'selection=full reason: %s\n' "$SELECT_REASON"
  fi
  if (( ${#FAILURES_JSON[@]} > 0 )); then
    printf 'failures:\n'
    local f name file err
    for f in "${FAILURES_JSON[@]}"; do
      name="$(echo "$f" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("name",""))')"
      file="$(echo "$f" | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("file",""))')"
      err="$(echo "$f"  | python3 -c 'import sys,json; print(json.loads(sys.stdin.read()).get("error_head",""))')"
      printf '  - %s :: %s — %s\n' "$file" "$name" "$err"
    done
  fi
}

case "$OUT" in
  json)  emit_json ;;
  human) emit_human ;;
  both)  emit_human; emit_json ;;
esac

exit 0
