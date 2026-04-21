#!/usr/bin/env bats
# Tests for scripts/mb-upgrade.sh — skill self-update pre-flight checks.
#
# Network-dependent behaviors (`fetch`, `pull`) are not tested — only
# pre-flight guards: git repo detection, dirty tree, missing VERSION.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-upgrade.sh"
  TMPDIR="$(mktemp -d)"

  [ -f "$SCRIPT" ] || skip "scripts/mb-upgrade.sh not implemented yet (TDD red)"
}

teardown() {
  [ -n "${TMPDIR:-}" ] && [ -d "$TMPDIR" ] && rm -rf "$TMPDIR"
}

# ═══ Pre-flight: not a git repo ═══

@test "upgrade: fails when MB_SKILL_DIR is not a git repo" {
  mkdir -p "$TMPDIR/fake-skill"
  MB_SKILL_DIR="$TMPDIR/fake-skill" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"git"* || "$output$stderr" == *"repository"* ]]
}

@test "upgrade: fails when MB_SKILL_DIR does not exist" {
  MB_SKILL_DIR="$TMPDIR/nonexistent" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
}

# ═══ Pre-flight: dirty working tree ═══

@test "upgrade: fails when working tree has unstaged changes" {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "v1" > VERSION
  git add VERSION
  git commit -q -m "init"
  # Make dirty
  echo "dirty" >> VERSION

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"dirty"* || "$output$stderr" == *"local changes"* || "$output$stderr" == *"uncommitted"* ]]
}

@test "upgrade: fails when working tree has staged but uncommitted changes" {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "v1" > VERSION
  git add VERSION
  git commit -q -m "init"
  echo "staged" > new.txt
  git add new.txt  # staged but not committed

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --check
  [ "$status" -ne 0 ]
}

# ═══ Version reading ═══

@test "upgrade: reads VERSION file correctly" {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "1.2.3" > VERSION
  git add VERSION
  git commit -q -m "init"

  # `--check` without a remote means `fetch` fails, but VERSION must still be read
  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --check
  # Any exit code is acceptable, but output must contain 1.2.3
  [[ "$output" == *"1.2.3"* ]]
}

@test "upgrade: handles missing VERSION file gracefully" {
  cd "$TMPDIR"
  mkdir -p skill
  cd skill
  git init -q
  git config user.email "test@test"
  git config user.name "Test"
  echo "file" > README.md
  git add README.md
  git commit -q -m "init"

  MB_SKILL_DIR="$TMPDIR/skill" run bash "$SCRIPT" --check
  # It must not fail because VERSION is missing — output should contain "unknown"
  [[ "$output" == *"unknown"* ]]
}
