#!/usr/bin/env bats
# proportional-effort Sprint 2, Stage 1 — targeted test selection in mb-test-run.sh.
#
# Contract:
#   mb-test-run.sh --changed-since <git-ref> | --files <path>[,<path>...]
#   JSON gains: selection ("targeted"|"full"), selected ([test files]; [] for full),
#   reason (why a targeted request fell back to full; null otherwise).
#   Without the flags the output is byte-identical to the previous runner.
#   Fallback is always the full suite, never "nothing ran".

load lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-test-run.sh"
  command -v jq >/dev/null || skip "jq required"
  command -v git >/dev/null || skip "git required"
  TMPROOT="$(mktemp -d)"
}

teardown() {
  if [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ]; then rm -rf "$TMPROOT"; fi
}

git_init_commit() {
  git -C "$1" init -q
  git -C "$1" -c user.email=t@t -c user.name=t add -A
  git -C "$1" -c user.email=t@t -c user.name=t commit -qm base
}

# Python fixture: a.py → test_a.py (1 test), b.py → test_b.py (2 tests),
# c.py has no tests. Full suite = 3 tests.
make_python_fixture() {
  [ -x "$REPO_ROOT/.venv/bin/pytest" ] || skip "repo .venv with pytest required"
  local d="$TMPROOT/py"
  mkdir -p "$d/tests"
  printf '[project]\nname = "fixture"\nversion = "0.0.0"\n' >"$d/pyproject.toml"
  printf '.venv\n' >"$d/.gitignore"
  printf 'def a():\n    return 1\n' >"$d/a.py"
  printf 'def b():\n    return 2\n' >"$d/b.py"
  printf 'def c():\n    return 3\n' >"$d/c.py"
  printf '' >"$d/tests/conftest.py"
  printf 'def test_a(): assert 1 == 1\n' >"$d/tests/test_a.py"
  printf 'def test_b1(): assert 2 == 2\ndef test_b2(): assert 2 == 2\n' >"$d/tests/test_b.py"
  git_init_commit "$d"
  ln -s "$REPO_ROOT/.venv" "$d/.venv"
  PY="$d"
}

# Bats fixture: scripts/x.sh → tests/test_x.bats (1 test); tests/test_y.bats (2).
make_bats_fixture() {
  command -v bats >/dev/null || skip "bats required"
  local d="$TMPROOT/sh"
  mkdir -p "$d/scripts" "$d/tests/lib"
  printf '#!/usr/bin/env bash\necho x\n' >"$d/scripts/x.sh"
  printf '#!/usr/bin/env bash\necho z\n' >"$d/scripts/z.sh"
  printf 'helper() { :; }\n' >"$d/tests/lib/helper.bash"
  printf '@test "x" { true; }\n' >"$d/tests/test_x.bats"
  printf '@test "y1" { true; }\n@test "y2" { true; }\n' >"$d/tests/test_y.bats"
  git_init_commit "$d"
  SH="$d"
}

# The runner before targeted selection existed (proportional-effort Sprint 2):
# no-flag output must stay byte-identical to it. A shallow clone without this
# commit skips the comparison.
PRE_TARGETED_REF=e351a17

# assert_same_as_head <dir> — json/human/both output of the pre-targeted runner
# and the current one match byte for byte once durations are normalised.
assert_same_as_head() {
  local old="$TMPROOT/old"
  mkdir -p "$old"
  git -C "$REPO_ROOT" cat-file -e "$PRE_TARGETED_REF:scripts/mb-test-run.sh" 2>/dev/null \
    || skip "baseline commit $PRE_TARGETED_REF not available (shallow clone)"
  git -C "$REPO_ROOT" show "$PRE_TARGETED_REF:scripts/mb-test-run.sh" >"$old/mb-test-run.sh"
  cp "$REPO_ROOT/scripts/_lib.sh" "$REPO_ROOT/scripts/mb-metrics.sh" "$old/"
  local mode norm='s/"duration_ms":[0-9]*/"duration_ms":0/; s/duration=[0-9]*ms/duration=0ms/'
  for mode in json human both; do
    run bash "$old/mb-test-run.sh" --dir "$1" --out "$mode"
    local before
    before="$(printf '%s\n' "$output" | sed "$norm")"
    run bash "$RUN" --dir "$1" --out "$mode"
    [ "$(printf '%s\n' "$output" | sed "$norm")" = "$before" ]
    refute_substring "$output" "selection"
  done
}

@test "targeted python: editing a.py runs only tests/test_a.py" {
  make_python_fixture
  printf 'def a():\n    return 11\n' >"$PY/a.py"
  run bash "$RUN" --dir "$PY" --changed-since HEAD --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selection == "targeted"'
  echo "$output" | jq -e '.selected == ["tests/test_a.py"]'
  echo "$output" | jq -e '.reason == null'
  # The runner really executed only test_a.py: 1 test, not the full 3.
  echo "$output" | jq -e '.tests_total == 1 and .tests_pass == true'
}

@test "targeted python: a changed test file selects itself" {
  make_python_fixture
  printf 'def test_b1(): assert 2 == 2\n' >"$PY/tests/test_b.py"
  run bash "$RUN" --dir "$PY" --changed-since HEAD --out json
  echo "$output" | jq -e '.selected == ["tests/test_b.py"]'
  echo "$output" | jq -e '.tests_total == 1'
}

@test "targeted python: conftest.py change falls back to full with reason" {
  make_python_fixture
  printf '# touched\n' >"$PY/tests/conftest.py"
  run bash "$RUN" --dir "$PY" --changed-since HEAD --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selection == "full"'
  echo "$output" | jq -e '.selected == []'
  assert_substring "$(echo "$output" | jq -r '.reason')" "tests/conftest.py"
  echo "$output" | jq -e '.tests_total == 3'
}

@test "targeted python: a change with no mapped tests falls back to full with reason" {
  make_python_fixture
  printf 'def c():\n    return 33\n' >"$PY/c.py"
  run bash "$RUN" --dir "$PY" --changed-since HEAD --out json
  echo "$output" | jq -e '.selection == "full"'
  assert_substring "$(echo "$output" | jq -r '.reason')" "no tests mapped"
  echo "$output" | jq -e '.tests_total == 3'
}

@test "targeted python: invalid ref falls back to full with reason" {
  make_python_fixture
  run bash "$RUN" --dir "$PY" --changed-since no-such-ref --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.selection == "full"'
  assert_substring "$(echo "$output" | jq -r '.reason')" "invalid ref"
  echo "$output" | jq -e '.tests_total == 3'
}

@test "targeted python: --files gives the same selection as --changed-since" {
  make_python_fixture
  printf 'def a():\n    return 11\n' >"$PY/a.py"
  printf 'def b():\n    return 22\n' >"$PY/b.py"
  run bash "$RUN" --dir "$PY" --changed-since HEAD --out json
  local via_ref
  via_ref="$(echo "$output" | jq -c '{selection, selected, reason, tests_total}')"
  run bash "$RUN" --dir "$PY" --files a.py,b.py --out json
  [ "$(echo "$output" | jq -c '{selection, selected, reason, tests_total}')" = "$via_ref" ]
  assert_substring "$via_ref" '"selected":["tests/test_a.py","tests/test_b.py"]'
}

@test "targeted python: the code graph adds tests outside the naming convention" {
  make_python_fixture
  command -v python3 >/dev/null || skip "python3 required"
  printf 'from b import b\ndef test_integration(): assert b() == 2\n' >"$PY/tests/test_integration.py"
  git -C "$PY" -c user.email=t@t -c user.name=t add -A
  git -C "$PY" -c user.email=t@t -c user.name=t commit -qm graph
  mkdir -p "$PY/.memory-bank/codebase"
  local sha
  sha="$(git -C "$PY" rev-parse --short=12 HEAD)"
  {
    printf '{"type": "meta", "schema": 1, "generated_at": "%s", "commit": "%s", "nodes": 2, "edges": 1, "src_root": "."}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$sha"
    printf '{"type": "node", "kind": "module", "name": "b.py", "file": "b.py", "line": 1}\n'
    printf '{"type": "node", "kind": "function", "name": "b", "file": "b.py", "line": 1}\n'
    printf '{"type": "edge", "kind": "calls", "src": "tests/test_integration.py:test_integration", "dst": "b"}\n'
  } >"$PY/.memory-bank/codebase/graph.json"
  run bash "$RUN" --dir "$PY" --files b.py --out json
  echo "$output" | jq -e '.selected == ["tests/test_b.py","tests/test_integration.py"]'
  echo "$output" | jq -e '.tests_total == 3'
}

@test "targeted bats: editing scripts/x.sh runs only tests/test_x.bats" {
  make_bats_fixture
  printf '#!/usr/bin/env bash\necho xx\n' >"$SH/scripts/x.sh"
  run bash "$RUN" --dir "$SH" --changed-since HEAD --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.stack == "bats" and .selection == "targeted"'
  echo "$output" | jq -e '.selected == ["tests/test_x.bats"]'
  echo "$output" | jq -e '.tests_total == 1'
}

@test "targeted bats: a tests/lib helper change falls back to full" {
  make_bats_fixture
  printf 'helper() { true; }\n' >"$SH/tests/lib/helper.bash"
  run bash "$RUN" --dir "$SH" --changed-since HEAD --out json
  echo "$output" | jq -e '.selection == "full"'
  assert_substring "$(echo "$output" | jq -r '.reason')" "tests/lib/helper.bash"
  echo "$output" | jq -e '.tests_total == 3'
}

@test "targeted bats: untracked new script without tests falls back to full" {
  make_bats_fixture
  printf '#!/usr/bin/env bash\n' >"$SH/scripts/new.sh"
  run bash "$RUN" --dir "$SH" --changed-since HEAD --out json
  echo "$output" | jq -e '.selection == "full"'
  assert_substring "$(echo "$output" | jq -r '.reason')" "no tests mapped"
  echo "$output" | jq -e '.tests_total == 3'
}

@test "targeted: human output names the selection" {
  make_bats_fixture
  run bash "$RUN" --dir "$SH" --files scripts/x.sh --out human
  assert_substring "$output" "selection=targeted"
  assert_substring "$output" "tests/test_x.bats"
}

@test "no flags: bats repo output is identical to the HEAD runner (duration aside)" {
  make_bats_fixture
  assert_same_as_head "$SH"
}

@test "no flags: python repo output is identical to the HEAD runner (duration aside)" {
  make_python_fixture
  printf 'def test_b1(): assert 2 == 3\ndef test_b2(): assert 2 == 2\n' >"$PY/tests/test_b.py"
  assert_same_as_head "$PY"
}

# Mixed fixture: python (a.py → test_a.py 1 test, test_b.py 2 tests) plus
# bats (scripts/x.sh → tests/test_x.bats 1 test). Full suite = 4 tests.
make_mixed_fixture() {
  make_python_fixture
  command -v bats >/dev/null || skip "bats required"
  mkdir -p "$PY/scripts"
  printf '#!/usr/bin/env bash\necho x\n' >"$PY/scripts/x.sh"
  printf '@test "x" { true; }\n' >"$PY/tests/test_x.bats"
  git -C "$PY" -c user.email=t@t -c user.name=t add -A
  git -C "$PY" -c user.email=t@t -c user.name=t commit -qm mixed
}

@test "mixed full: bats and pytest both run, totals summed" {
  make_mixed_fixture
  run bash "$RUN" --dir "$PY" --out json
  [ "$status" -eq 0 ]
  assert_substring "$output" '"stack":"bats+python"'
  assert_substring "$output" '"tests_pass":true,"tests_total":4,"tests_failed":0'
  refute_substring "$output" '"selection"'
}

@test "mixed full: a failing pytest is reported with its file" {
  make_mixed_fixture
  printf 'def test_b1(): assert 2 == 3\ndef test_b2(): assert 2 == 2\n' >"$PY/tests/test_b.py"
  run bash "$RUN" --dir "$PY" --out json
  assert_substring "$output" '"tests_pass":false,"tests_total":4,"tests_failed":1'
  assert_substring "$output" '"file":"tests/test_b.py","name":"test_b1"'
}

@test "mixed targeted: editing a.py runs only pytest test_a.py, no bats" {
  make_mixed_fixture
  printf 'def a():\n    return 11\n' >"$PY/a.py"
  run bash "$RUN" --dir "$PY" --changed-since HEAD --out json
  assert_substring "$output" '"stack":"python"'
  assert_substring "$output" '"tests_total":1,'
  assert_substring "$output" '"selection":"targeted","selected":["tests/test_a.py"],"reason":null'
}

@test "mixed targeted: python and shell edits run both selections" {
  make_mixed_fixture
  run bash "$RUN" --dir "$PY" --files a.py,scripts/x.sh --out json
  assert_substring "$output" '"stack":"bats+python"'
  assert_substring "$output" '"tests_total":2,'
  assert_substring "$output" '"selected":["tests/test_x.bats","tests/test_a.py"]'
}

@test "mixed targeted: nothing mapped in any stack falls back to the full mixed suite" {
  make_mixed_fixture
  run bash "$RUN" --dir "$PY" --files c.py --out json
  assert_substring "$output" '"stack":"bats+python"'
  assert_substring "$output" '"tests_total":4,'
  assert_substring "$output" '"selection":"full","selected":[],"reason":"no tests mapped to changed files"'
}
