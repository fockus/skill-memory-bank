#!/usr/bin/env bats
# Tests for scripts/mb-no-todo.sh — the L5 residual-placeholder runner.
#
# Contract (REQ-DF-042, ADR-3):
#   - emits {"name":"no_todo","ok":true|false|null,"findings":[...]}
#   - ALWAYS exits 0 — pass/fail/skip carried ONLY by `ok`.
#   - ok=false + findings when an unexempted placeholder (TODO/FIXME/XXX/HACK
#     and the repo's existing deny-set) is found in a scanned file.
#   - ok=true when scanned files carry no placeholders.
#   - ok=null when there is nothing to scan (no --dir and no changed files).
#   - Reuses mb-rules-check.sh's exemptions: tests/* paths and any line tagged
#     `# mb-rules-check: allow-placeholder` are skipped.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-no-todo.sh"
  command -v jq >/dev/null || skip "jq required"
  WORK="$(mktemp -d)"
}

teardown() {
  [ -n "${WORK:-}" ] && rm -rf "$WORK"
}

json_of() {
  printf '%s\n' "$1" | grep '^{' | tail -n1
}

@test "no_todo: script exists" {
  [ -f "$RUN" ]
}

@test "no_todo: --help exits 0 and mentions --dir" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dir"* ]]
}

# ---- PASS case --------------------------------------------------------------

@test "no_todo: clean dir → ok=true, exit 0, no findings" {
  mkdir -p "$WORK/src"
  printf 'def f():\n    return 1\n' >"$WORK/src/clean.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.name == "no_todo"'
  echo "$j" | jq -e '.ok == true'
  echo "$j" | jq -e '.findings | length == 0'
}

# ---- FAIL case --------------------------------------------------------------

@test "no_todo: file with TODO → ok=false, exit 0, finding names the file" {
  mkdir -p "$WORK/src"
  printf 'def f():\n    return 1  # TODO finish this\n' >"$WORK/src/dirty.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.ok == false'
  echo "$j" | jq -e '.findings | length >= 1'
  echo "$j" | jq -e '[.findings[] | test("dirty.py")] | any'
}

@test "no_todo: FIXME / XXX / HACK are all detected" {
  mkdir -p "$WORK/src"
  printf '# FIXME a\n# XXX b\n# HACK c\n' >"$WORK/src/markers.sh"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == false'
}

@test "no_todo: FAIL case STILL exits 0 (ADR-3 — no fail-loud in runner)" {
  mkdir -p "$WORK/src"
  printf '# TODO\n' >"$WORK/src/x.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == false'
}

# ---- exemptions (reuse mb-rules-check.sh semantics) -------------------------

@test "no_todo: tests/ paths are exempt (placeholder there is intentional)" {
  mkdir -p "$WORK/tests"
  printf '# TODO example fixture\n' >"$WORK/tests/fixture.py"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}

@test "no_todo: line tagged allow-placeholder is skipped" {
  mkdir -p "$WORK/src"
  printf 'DENY="TODO,FIXME"  # mb-rules-check: allow-placeholder\n' >"$WORK/src/lib.sh"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}

@test "no_todo: markdown files are exempt (prose markers are legitimate)" {
  printf '# Notes\nTODO: write more docs later\n' >"$WORK/README.md"
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}

# ---- NULL / skip case -------------------------------------------------------

@test "no_todo: empty dir (nothing to scan) → ok=null, exit 0" {
  run bash "$RUN" --dir "$WORK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == null'
}
