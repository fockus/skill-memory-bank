#!/usr/bin/env bats
# scope_eval: — I-174. A task's declared `**Eval:**` must actually run the test
# files its own `**Scope:**` claims, or the gate measures a part and reports for
# the whole.
#
# HOW THE DEFECT WAS BORN (it is worth keeping, because the gate is shaped by it)
# ------------------------------------------------------------------------------
# svp-sdd-core task 9 owned three test files and its Eval named one. The split
# that created the third file added it to `**Scope:**` and not to `**Eval:**`,
# in a single edit, and the author then verified the Eval against WHAT HE HAD
# SPLIT OUT — his intent — instead of against the Scope line he had just
# written. `eval.9=ready` then read as "task 9 is green" while meaning "the two
# files listed are green". Nothing saw it: CPR-D compares design↔tasks
# byte-for-byte, and both sides were equally incomplete.
#
# WHY THE GATE HAS THREE OUTCOMES AND NOT ONE
# -------------------------------------------
# Measured across the eight group specs before writing it: 7 raw mismatches, of
# which 2 were false positives of the obvious classifier (a JSON fixture and a
# `lib/*.bash` helper — inputs to tests, not runnable tests, and impossible as a
# runner target). A gate that demands the impossible gets ignored within days,
# so the classifier is narrow, and the two cases that need a HUMAN decision
# (a glob Scope, a cross-runner file) are named without blocking.
#
# Name convention (X-05): every @test starts with `scope_eval: `.

bats_require_minimum_version 1.5.0

load lib/assert
load lib/spec_validate_fixture

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-spec-validate.sh"
  export LC_ALL=C
  TMPDIR="$(mktemp -d)"
  SPECS="$TMPDIR/specs"
  mkdir -p "$SPECS"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# _scope <dir> <scope-line-value> — set task 1's Scope (the baseline has none).
_scope() {
  perl -0pi -e "s{\\*\\*Role:\\*\\* backend\\n}{**Role:** backend\n**Scope:** $2\n}" "$1/tasks.md"
}

# _eval <dir> <command> — rewrite BOTH sides of the Eval line (CPR-D keeps them
# byte-identical, so a fixture that changes one must change the other).
_eval() {
  local dir="$1" cmd="$2" tail
  tail=" ${DASH} red: demo assertion fails; exit: 1; output~: \`not ok [0-9]+ demo_persist\`"
  perl -0pi -e "s{\\*\\*Eval:\\*\\* .*\\n}{**Eval:** \`$cmd\`$tail\n}" "$dir/tasks.md"
  perl -0pi -e "s{  \\*\\*Eval:\\*\\* .*\\n}{  **Eval:** \`$cmd\`$tail\n}" "$dir/design.md"
}

# ── the pair: same rule, one input it must catch, one it must ignore ────────

@test "scope_eval: [I-174] a Scope test file absent from the Eval is a violation" {
  local dir; dir="$(mkbase demo)"
  _scope "$dir" 'scripts/demo.sh, tests/bats/test_demo.bats, tests/bats/test_extra.bats'
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "the missing test file passed the gate (rc=$status): $output"; false; }
  assert_substring "$output" "test_extra.bats" \
    || { echo "the violation does not name the file it is about: $output"; false; }
  assert_substring "$output" "I-174"
}

@test "scope_eval: [I-174] the SAME spec is silent once the Eval names the file" {
  # The pair to the test above: identical fixture except that the Eval command
  # runs both files. A gate that fires on both is indistinguishable from a
  # broken regex.
  local dir; dir="$(mkbase demo)"
  _scope "$dir" 'scripts/demo.sh, tests/bats/test_demo.bats, tests/bats/test_extra.bats'
  _eval "$dir" 'bats tests/bats/test_demo.bats tests/bats/test_extra.bats'
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "a compliant spec was rejected: $output"; false; }
  refute_substring "$output" "I-174"
}

# ── the two false positives that would kill the gate ───────────────────────

@test "scope_eval: a test-NAMED file under fixtures/ is a corpus input, not a test" {
  # This one carries a RUNNABLE name (`test_*.py`) and is still an input,
  # because of where it lives — a pytest corpus file under tests/fixtures/.
  # The path-segment rule is the only thing standing between it and a demand
  # that no runner could satisfy; the extension rule cannot see it.
  local dir; dir="$(mkbase demo)"
  _scope "$dir" 'scripts/demo.sh, tests/bats/test_demo.bats, tests/fixtures/test_corpus_case.py'
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "a fixture corpus file was demanded as an Eval target: $output"; false; }
  refute_substring "$output" "test_corpus_case.py"
}

@test "scope_eval: a test HELPER library in Scope is ignored (extension rule)" {
  # Measured on svp-interview-upgrade #1: `tests/bats/lib/discuss_contract.bash`
  # is `load`ed by tests, never run as one. Here it is the EXTENSION that
  # protects (`.bash` is not a runnable test), which is a different rule from
  # the one above — hence a separate case, killed by a different mutation.
  local dir; dir="$(mkbase demo)"
  _scope "$dir" 'scripts/demo.sh, tests/bats/test_demo.bats, tests/bats/lib/demo_contract.bash'
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "a helper library was demanded as an Eval target: $output"; false; }
  refute_substring "$output" "demo_contract.bash"
}

@test "scope_eval: a JSON fixture in Scope is ignored (extension rule)" {
  # Measured on svp-parallel-engine #5: `tests/fixtures/svp_group_ordering.json`.
  local dir; dir="$(mkbase demo)"
  _scope "$dir" 'scripts/demo.sh, tests/bats/test_demo.bats, tests/fixtures/demo_case.json'
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "a JSON fixture was demanded as an Eval target: $output"; false; }
  refute_substring "$output" "demo_case.json"
}

# ── the two cases that need a human decision: named, never blocking ────────

@test "scope_eval: a GLOB Scope is reported as a named notice, not a violation" {
  # `tests/**` cannot be resolved without the filesystem. Passing it silently
  # would make it the standard bypass (the I-165 shape); blocking it would
  # reject a legitimate declaration. So it is said out loud and let through.
  local dir; dir="$(mkbase demo)"
  _scope "$dir" 'scripts/demo.sh, tests/bats/test_demo.bats, tests/bats/test_more_*.bats'
  run --separate-stderr bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "a glob Scope was treated as a violation: $output"; false; }
  assert_substring "$stderr" "test_more_*.bats" \
    || { echo "the glob limit is not named anywhere: $stderr"; false; }
}

@test "scope_eval: a CROSS-RUNNER test file is a notice, not a violation" {
  # svp-sdd-core #5: Scope carries a pytest file while the Eval runs bats.
  # Appending it would change what `exit:`/`output~:` mean for that command —
  # a decision about the declaration, not a typo to fix by concatenation.
  local dir; dir="$(mkbase demo)"
  _scope "$dir" 'scripts/demo.sh, tests/bats/test_demo.bats, tests/pytest/test_demo_extra.py'
  run --separate-stderr bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "a cross-runner file was treated as a violation: $output"; false; }
  assert_substring "$stderr" "test_demo_extra.py" \
    || { echo "the cross-runner case is not named: $stderr"; false; }
}

# ── exemptions that must stay exempt ───────────────────────────────────────

@test "scope_eval: a validated waiver exempts the task entirely" {
  local dir; dir="$(mkbase demo)"
  # non-gated task 2 with a waiver and a test file in its Scope
  cat >>"$dir/tasks.md" <<EOF

<!-- mb-task:2 -->
## Task 2: docs only

**Covers:** REQ-100
**Role:** developer
**Scope:** docs/**, tests/bats/test_never_run.bats
**Eval:** none ${DASH} waiver: pure documentation, no runtime surface

**Testing:** none needed.

**DoD:**
- [ ] docs updated.
<!-- /mb-task:2 -->
EOF
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "a waived task was gated: $output"; false; }
  refute_substring "$output" "test_never_run.bats"
}

@test "scope_eval: a legacy spec without Scope/Eval gains no new error (D-26)" {
  local dir="$SPECS/legacy"; mkdir -p "$dir"
  write_req "$dir"
  cat >"$dir/tasks.md" <<EOF
# Tasks: legacy

<!-- mb-task:1 -->
## Task 1: legacy

**Covers:** REQ-001
**Role:** backend

**DoD:**
- [ ] done.
<!-- /mb-task:1 -->
EOF
  printf '# Design: legacy\n' >"$dir/design.md"
  run bash "$VALIDATE" "$dir"
  refute_substring "$output" "I-174"
}
