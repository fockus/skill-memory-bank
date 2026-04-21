#!/usr/bin/env bats
# Contract tests for git-safety gate in agents/mb-doctor.md.
#
# Stage 5 adds Step 3.5 that:
#   - Emits a "Pre-fix git state" report section showing
#     `git rev-parse HEAD` + `git status --short` before any Edit fix.
#   - Recommends `git stash` when the working tree is dirty.
#   - Refuses to auto-fix when env MB_DOCTOR_REQUIRE_CLEAN_TREE=1 AND tree
#     is dirty — surfacing an actionable message instead.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMPT="$REPO_ROOT/agents/mb-doctor.md"
  [ -f "$PROMPT" ]
}

@test "git-safety: prompt references pre-fix git state capture" {
  grep -Eq 'git rev-parse HEAD' "$PROMPT"
  grep -Eq 'git status --short|git status -s' "$PROMPT"
}

@test "git-safety: prompt names 'Pre-fix git state' report section" {
  grep -Fq 'Pre-fix git state' "$PROMPT"
}

@test "git-safety: prompt recommends git stash on dirty tree" {
  grep -Eq 'git stash' "$PROMPT"
}

@test "git-safety: MB_DOCTOR_REQUIRE_CLEAN_TREE env toggle documented" {
  grep -Fq 'MB_DOCTOR_REQUIRE_CLEAN_TREE' "$PROMPT"
}

@test "git-safety: prompt instructs refusal-with-message when flag set + dirty" {
  # Must say the doctor refuses (not silently ignores) when the guard is on.
  grep -Eiq 'refuse|refuses|do not (auto-)?fix|stop auto-fix|block auto-fix' "$PROMPT"
}
