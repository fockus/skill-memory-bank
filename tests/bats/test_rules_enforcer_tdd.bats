#!/usr/bin/env bats
# Tests for TDD-delta check in scripts/mb-rules-check.sh.
#
# Rule: a source file under `src/`, `scripts/`, `agents/`, `lib/` is in the
# diff, but no matching test file (matched by basename stem) is also in the
# diff. The enforcer takes --diff-files as the authoritative list of ALL
# files touched in the range; missing test match → tdd/delta violation.
#
# Matching heuristic:
#   stem of src/foo.py       → test_foo.py OR foo_test.py OR foo.test.* OR foo.spec.*
#   stem of scripts/mb-x.sh  → test_mb-x.bats / test_mb_x.bats OR mb-x_test.* etc.
#
# Exclusions: *.md (docs), any path under migrations/, .github/, docs/,
# *.lock, *.json manifests, and files matching the `tdd_exceptions`
# entry from RULES.md when present (not tested here — tested in contract).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CHECK="$REPO_ROOT/scripts/mb-rules-check.sh"
  command -v jq >/dev/null || skip "jq required"

  TMPROOT="$(mktemp -d)"
  cd "$TMPROOT"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "tdd: src file changed without matching test → CRITICAL" {
  mkdir -p src
  echo "def foo(): return 1" > src/foo.py
  run bash "$CHECK" --files "src/foo.py" --diff-files "src/foo.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta")) | length) == 1'
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta"))[0].severity) == "CRITICAL"'
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta"))[0].file) == "src/foo.py"'
}

@test "tdd: src file changed WITH matching tests/test_foo.py in diff → no violation" {
  mkdir -p src tests
  echo "def foo(): return 1" > src/foo.py
  echo "def test_foo(): pass" > tests/test_foo.py
  run bash "$CHECK" \
    --files "src/foo.py,tests/test_foo.py" \
    --diff-files "src/foo.py,tests/test_foo.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta")) | length) == 0'
}

@test "tdd: src file with matching foo.test.ts in diff → no violation" {
  mkdir -p src
  echo "export const foo = 1;" > src/foo.ts
  echo "test('foo', () => {})" > src/foo.test.ts
  run bash "$CHECK" \
    --files "src/foo.ts,src/foo.test.ts" \
    --diff-files "src/foo.ts,src/foo.test.ts" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta")) | length) == 0'
}

@test "tdd: .md docs change is exempt" {
  mkdir -p docs
  echo "# readme update" > docs/something.md
  run bash "$CHECK" --files "docs/something.md" --diff-files "docs/something.md" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta")) | length) == 0'
}

@test "tdd: migrations/ path is exempt" {
  mkdir -p migrations
  echo "ALTER TABLE ..." > migrations/001_init.sql
  run bash "$CHECK" --files "migrations/001_init.sql" --diff-files "migrations/001_init.sql" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta")) | length) == 0'
}

@test "tdd: .github/ workflow is exempt" {
  mkdir -p .github/workflows
  echo "name: ci" > .github/workflows/ci.yml
  run bash "$CHECK" --files ".github/workflows/ci.yml" --diff-files ".github/workflows/ci.yml" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta")) | length) == 0'
}

@test "tdd: without --diff-files, tdd/delta check is skipped gracefully" {
  # If caller did not supply diff-files, we can't reason about co-change.
  # Script must not synthesize a false positive; it simply omits the check.
  mkdir -p src
  echo "def foo(): return 1" > src/foo.py
  run bash "$CHECK" --files "src/foo.py" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta")) | length) == 0'
}

@test "tdd: bash script with matching bats test → no violation" {
  mkdir -p scripts tests/bats
  echo "#!/usr/bin/env bash" > scripts/mb-hello.sh
  echo "@test 'hello' { true; }" > tests/bats/test_mb-hello.bats
  run bash "$CHECK" \
    --files "scripts/mb-hello.sh,tests/bats/test_mb-hello.bats" \
    --diff-files "scripts/mb-hello.sh,tests/bats/test_mb-hello.bats" --out json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '(.violations | map(select(.rule == "tdd/delta")) | length) == 0'
}
