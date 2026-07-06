#!/usr/bin/env bash
# mb-test-run.sh — structured test runner with per-stack output parsing.
#
# Usage:
#   mb-test-run.sh [--dir <path>] [--out json|human|both]
#
# Wraps scripts/mb-metrics.sh for stack detection, then runs tests directly
# with predictable flags so output parsing is deterministic.
#
# Exit code is always 0. pass/fail is reported via `tests_pass` in the JSON
# so callers do not confuse "script broke" with "tests failed".
#
# Supported stacks: bats (*.bats under tests/ or hooks/tests/), python (pytest), go (go test).
# --test-command / MB_TEST_COMMAND for explicit override; empty dirs emit not_applicable=true.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

DIR="."
OUT="json"

TEST_CMD_CLI=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)  DIR="${2:-.}";   shift 2 ;;
    --out)  OUT="${2:-json}"; shift 2 ;;
    --test-command) TEST_CMD_CLI="${2:-}"; shift 2 ;;
    --help|-h)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
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

# ---- per-stack runners ------------------------------------------------------

run_python() {
  command -v pytest >/dev/null || {
    echo "[warn] pytest not in PATH; skipping python run" >&2
    return 0
  }
  local log
  log="$(mktemp)"
  # -q: quiet; --tb=line: one-line traceback; -r a: summary for all; -p no:cacheprovider to avoid stale cache.
  # Exit codes: 0 passed, 1 failed, 5 no tests collected.
  (cd "$DIR" && pytest -q --tb=line --no-header -r a -p no:cacheprovider) >"$log" 2>&1 || true
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

  TESTS_TOTAL=$((passed + failed + errors))
  TESTS_FAILED=$((failed + errors))

  if (( TESTS_TOTAL == 0 )); then
    TESTS_PASS="null"
  elif (( TESTS_FAILED == 0 )); then
    TESTS_PASS="true"
  else
    TESTS_PASS="false"
  fi

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
  (cd "$DIR" && go test ./... -v 2>&1) >"$log" || true

  local passed failed
  passed="$(grep -cE '^--- PASS:' "$log" || true)"
  failed="$(grep -cE '^--- FAIL:' "$log" || true)"
  passed="${passed:-0}"
  failed="${failed:-0}"

  TESTS_TOTAL=$((passed + failed))
  TESTS_FAILED=$failed

  if (( TESTS_TOTAL == 0 )); then
    TESTS_PASS="null"
  elif (( TESTS_FAILED == 0 )); then
    TESTS_PASS="true"
  else
    TESTS_PASS="false"
  fi

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
    STACK="bats"
    return 0
  }
  STACK="bats"
  local log
  log="$(mktemp)"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    file_args+=("$f")
  done <<< "$files"
  (cd "$DIR" && bats "${file_args[@]}") >"$log" 2>&1 || true
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
  TESTS_TOTAL=$total
  TESTS_FAILED=$failed
  if (( TESTS_TOTAL == 0 )); then
    TESTS_PASS="null"
  elif (( TESTS_FAILED == 0 )); then
    TESTS_PASS="true"
  else
    TESTS_PASS="false"
  fi
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

# Dispatch: explicit test command → bats files → python/go → not_applicable.
EFFECTIVE_CMD="${TEST_CMD_CLI:-${MB_TEST_COMMAND:-}}"
if [[ -n "$EFFECTIVE_CMD" ]]; then
  run_test_command "$EFFECTIVE_CMD"
elif [[ -n "$(find_bats_files)" ]]; then
  run_bats
elif [[ "$STACK" == "python" ]]; then
  run_python
elif [[ "$STACK" == "go" ]]; then
  run_go
else
  NOT_APPLICABLE="true"
  TESTS_PASS="null"
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
  printf '],"coverage":{"overall":%s,"per_file":{}},"duration_ms":%d}\n' \
    "$COV_OVERALL" "$DURATION"
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
