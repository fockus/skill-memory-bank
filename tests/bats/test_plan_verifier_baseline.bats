#!/usr/bin/env bats
# Tests for the Baseline commit field in scripts/mb-plan.sh scaffold.
#
# Contract (Stage 1 of plans/2026-04-21_refactor_agents-quality.md):
#   - mb-plan.sh MUST write `**Baseline commit:** <hash>` as the second-or-third
#     line of the plan file, below `# Plan: <type> — <topic>`.
#   - <hash> is derived from `git rev-parse HEAD` when the invoking directory
#     is inside a git repo with at least one commit.
#   - When git is unavailable, uninitialized, or has no commits, the value is
#     the literal string `unknown` (no stale hash, no empty field).
#   - Format is exact: leading `**Baseline commit:** ` (with trailing space), no
#     backticks around the hash, line ends at newline. Downstream plan-verifier
#     parses this with `grep -E '^\*\*Baseline commit:\*\* '`.
#
# RED-phase target: mb-plan.sh currently does not emit this line.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PLAN_SH="$REPO_ROOT/scripts/mb-plan.sh"

  TMPROOT="$(mktemp -d)"
  TMPBANK="$TMPROOT/.memory-bank"
  mkdir -p "$TMPBANK/plans"

  # Fresh git repo with one commit so HEAD resolves deterministically.
  cd "$TMPROOT"
  git init --quiet
  git -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m "init"
  BASELINE_HASH="$(git rev-parse HEAD)"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && [ -d "$TMPROOT" ] && rm -rf "$TMPROOT"
}

@test "baseline: mb-plan.sh writes '**Baseline commit:** <hash>' line" {
  cd "$TMPROOT"
  run bash "$PLAN_SH" feature "baseline-test" "$TMPBANK"
  [ "$status" -eq 0 ]
  PLAN_PATH="$output"
  [ -f "$PLAN_PATH" ]
  grep -E '^\*\*Baseline commit:\*\* ' "$PLAN_PATH"
}

@test "baseline: hash matches git rev-parse HEAD exactly" {
  cd "$TMPROOT"
  run bash "$PLAN_SH" fix "baseline-hash" "$TMPBANK"
  [ "$status" -eq 0 ]
  PLAN_PATH="$output"
  # Extract the hash — everything after the prefix up to end-of-line.
  WRITTEN_HASH="$(grep -E '^\*\*Baseline commit:\*\* ' "$PLAN_PATH" | head -n1 \
    | sed -E 's/^\*\*Baseline commit:\*\* //')"
  [ "$WRITTEN_HASH" = "$BASELINE_HASH" ]
}

@test "baseline: outside git repo → writes 'unknown' fallback" {
  # Use a SIBLING directory of $TMPROOT so git does not discover the setup-init'd
  # .git upward. We also unset GIT_DIR / GIT_WORK_TREE to rule out env inheritance.
  NOGIT_ROOT="$(mktemp -d)"
  mkdir -p "$NOGIT_ROOT/.memory-bank/plans"
  cd "$NOGIT_ROOT"
  run env -u GIT_DIR -u GIT_WORK_TREE bash "$PLAN_SH" refactor "nogit-test" "$NOGIT_ROOT/.memory-bank"
  [ "$status" -eq 0 ]
  PLAN_PATH="$output"
  WRITTEN="$(grep -E '^\*\*Baseline commit:\*\* ' "$PLAN_PATH" | head -n1 \
    | sed -E 's/^\*\*Baseline commit:\*\* //')"
  rm -rf "$NOGIT_ROOT"
  [ "$WRITTEN" = "unknown" ]
}

@test "baseline: line placement — above the first '## Context' header" {
  cd "$TMPROOT"
  run bash "$PLAN_SH" experiment "baseline-order" "$TMPBANK"
  [ "$status" -eq 0 ]
  PLAN_PATH="$output"
  # Find line numbers with grep -n. Baseline must come before '## Context'.
  BL_LINE="$(grep -nE '^\*\*Baseline commit:\*\* ' "$PLAN_PATH" | head -n1 | cut -d: -f1)"
  CTX_LINE="$(grep -nE '^## Context' "$PLAN_PATH" | head -n1 | cut -d: -f1)"
  [ -n "$BL_LINE" ]
  [ -n "$CTX_LINE" ]
  [ "$BL_LINE" -lt "$CTX_LINE" ]
}
