#!/usr/bin/env bats
# `--skip <name>` — drop a check from the DEFAULT set without respecifying it.
#
# Motivating case: the Stop-hook closure gate cannot afford the `tests` check
# (the project's whole suite, minutes), while the other four default checks run
# in under a second. Skipping by name keeps the default commands in ONE place
# (this script) instead of forcing every caller to re-declare them via --check.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VERIFY="$REPO_ROOT/scripts/mb-flow-verify.sh"
  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK"
  cat > "$TMPBANK/pipeline.yaml" <<'EOF'
review:
  severity_gate:
    blocker: 0
    major: 0
    minor: 0
EOF
}

teardown() {
  [ -n "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "skip: --skip tests drops the tests check from the default set" {
  run bash "$VERIFY" "$TMPBANK" --skip tests
  [[ "$output" == *'"checks"'* ]]
  [[ "$output" != *'"name": "tests"'* ]]
  [[ "$output" != *'"name":"tests"'* ]]
  # The other defaults still ran.
  [[ "$output" == *'lint'* ]]
  [[ "$output" == *'acceptance'* ]]
}

@test "skip: a skipped check is not merely reported as skipped — it never runs" {
  # A `tests` check that actually ran would leave the runner's own trace; assert
  # on the summary instead: the name must be absent from `checks` entirely.
  run bash "$VERIFY" "$TMPBANK" --skip tests
  names="$(printf '%s' "$output" | python3 -c 'import json,sys; print(",".join(c["name"] for c in json.loads(sys.stdin.read())["checks"]))')"
  [[ "$names" != *"tests"* ]]
  [[ "$names" == *"no_todo"* ]]
}

@test "skip: repeatable and comma-separated forms both work" {
  run bash "$VERIFY" "$TMPBANK" --skip tests --skip lint
  names="$(printf '%s' "$output" | python3 -c 'import json,sys; print(",".join(c["name"] for c in json.loads(sys.stdin.read())["checks"]))')"
  [[ "$names" != *"tests"* ]]
  [[ "$names" != *"lint"* ]]

  run bash "$VERIFY" "$TMPBANK" --skip tests,lint
  names="$(printf '%s' "$output" | python3 -c 'import json,sys; print(",".join(c["name"] for c in json.loads(sys.stdin.read())["checks"]))')"
  [[ "$names" != *"tests"* ]]
  [[ "$names" != *"lint"* ]]
}

@test "skip: without --skip the default set still carries tests" {
  # Guards the fix against silently disabling the check for every caller.
  run bash "$VERIFY" "$TMPBANK" --check "tests=printf '%s' '{\"name\":\"tests\",\"ok\":true,\"findings\":[]}'"
  names="$(printf '%s' "$output" | python3 -c 'import json,sys; print(",".join(c["name"] for c in json.loads(sys.stdin.read())["checks"]))')"
  [ "$names" = "tests" ]
  grep -q 'CHECK_NAMES=( tests lint no_todo diff_scope acceptance )' "$VERIFY"
}

@test "skip: --skip of an explicit --check name is honoured too" {
  run bash "$VERIFY" "$TMPBANK" \
    --check "a=printf '%s' '{\"name\":\"a\",\"ok\":true,\"findings\":[]}'" \
    --check "b=printf '%s' '{\"name\":\"b\",\"ok\":true,\"findings\":[]}'" \
    --skip b
  names="$(printf '%s' "$output" | python3 -c 'import json,sys; print(",".join(c["name"] for c in json.loads(sys.stdin.read())["checks"]))')"
  [ "$names" = "a" ]
}

@test "skip: --skip needs a value" {
  run bash "$VERIFY" "$TMPBANK" --skip
  [ "$status" -eq 2 ]
  # Names the flag it is complaining about — not the generic unknown-flag path.
  [[ "$output" == *"--skip needs a value"* ]]
}
