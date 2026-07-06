#!/usr/bin/env bats
# Tests for scripts/mb-reviewer-resolve.sh — B8 (CDX-5, Codex delta): the
# SKILLS_ROOTS builder only looked in `$HOME/.cursor/skills` and
# `$HOME/.claude/skills` — a reviewer-override placed in a Codex/Pi/OpenCode
# skill-root (with no Claude/Cursor tree present at all) was silently never
# found, breaking discovery parity across agents.
#
# Contract under test (mirrors tests/pytest/test_mb_reviewer_resolve.py, which
# stays untouched — that file is parallel-session domain for the core
# resolver; this NEW file targets ONLY the B8 skill-roots gap):
#   - `$HOME/.codex/skills`, `$HOME/.pi/agent/skills`, and
#     `$HOME/.config/opencode/skills` are added as SKILLS_ROOTS candidates.
#   - `MB_SKILLS_ROOT` (when set) still wins outright — no other candidate is
#     even considered.
#   - Missing directories are skipped silently (no error).
#   - Multiple present roots are all searched (deterministic: first match by
#     the existing colon-joined SKILLS_ROOTS order wins).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-reviewer-resolve.sh"
  MB="$(mktemp -d)/.memory-bank"
  mkdir -p "$MB"
  FAKE_HOME="$(mktemp -d)"
}

teardown() {
  [ -n "${MB:-}" ] && [ -d "$(dirname "$MB")" ] && rm -rf "$(dirname "$MB")"
  [ -n "${FAKE_HOME:-}" ] && [ -d "$FAKE_HOME" ] && rm -rf "$FAKE_HOME"
}

@test "reviewer-resolve: finds an override in the Codex skill-root (no Claude/Cursor tree)" {
  mkdir -p "$FAKE_HOME/.codex/skills/superpowers"
  run env HOME="$FAKE_HOME" PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    bash "$SCRIPT" --mb "$MB"
  [ "$status" -eq 0 ]
  [ "$output" = "superpowers:requesting-code-review" ]
}

@test "reviewer-resolve: finds an override in the Pi skill-root (no Claude/Cursor tree)" {
  mkdir -p "$FAKE_HOME/.pi/agent/skills/superpowers"
  run env HOME="$FAKE_HOME" PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    bash "$SCRIPT" --mb "$MB"
  [ "$status" -eq 0 ]
  [ "$output" = "superpowers:requesting-code-review" ]
}

@test "reviewer-resolve: finds an override in the OpenCode skill-root (no Claude/Cursor tree)" {
  mkdir -p "$FAKE_HOME/.config/opencode/skills/superpowers"
  run env HOME="$FAKE_HOME" PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    bash "$SCRIPT" --mb "$MB"
  [ "$status" -eq 0 ]
  [ "$output" = "superpowers:requesting-code-review" ]
}

@test "reviewer-resolve: MB_SKILLS_ROOT still wins over any agent skill-root" {
  mkdir -p "$FAKE_HOME/.codex/skills/superpowers"
  local other_root
  other_root="$(mktemp -d)/skills-empty"
  mkdir -p "$other_root"
  run env HOME="$FAKE_HOME" MB_SKILLS_ROOT="$other_root" \
    PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    bash "$SCRIPT" --mb "$MB"
  [ "$status" -eq 0 ]
  # MB_SKILLS_ROOT points at an empty dir — no override found there, so the
  # default agent must be printed even though a codex-root override exists.
  [ "$output" = "mb-reviewer" ]
  rm -rf "$(dirname "$other_root")"
}

@test "reviewer-resolve: default agent when none of the agent skill-roots have the override" {
  run env HOME="$FAKE_HOME" PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    bash "$SCRIPT" --mb "$MB"
  [ "$status" -eq 0 ]
  [ "$output" = "mb-reviewer" ]
}

@test "reviewer-resolve: missing agent skill-root directories do not error (only some present)" {
  mkdir -p "$FAKE_HOME/.config/opencode/skills/superpowers"
  # Deliberately do NOT create .codex or .pi — resolver must skip them silently.
  run env HOME="$FAKE_HOME" PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
    bash "$SCRIPT" --mb "$MB"
  [ "$status" -eq 0 ]
  [ "$output" = "superpowers:requesting-code-review" ]
}
