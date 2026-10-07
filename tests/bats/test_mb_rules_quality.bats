#!/usr/bin/env bats
# Project quality settings rendered from the rules profile (plan project-quality-settings,
# Stages 2 and 4): the Key rules architecture/tests lines and the
# <!-- mb-project-rules:start/end --> block in the project RULES.md come from the
# profile (`architecture`, `quality`); `mb-rules.sh set <key> <value>` is the writer.
# Temp HOME + temp project only.

load lib/assert

bats_require_minimum_version 1.5.0

PR_START='<!-- mb-project-rules:start -->'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-rules.sh"
  TMPROOT="$(mktemp -d)"
  export HOME="$TMPROOT/home"
  PROJECT="$TMPROOT/project"
  BANK="$PROJECT/.memory-bank"
  USER_PROFILE="$HOME/.claude/memory-bank/rules-profile.json"
  mkdir -p "$HOME/.claude" "$HOME/.codex" "$BANK"
  unset MB_PATH MB_AGENT || true
  printf '# Project\n' > "$PROJECT/CLAUDE.md"
  printf '# Global\n' > "$HOME/.claude/CLAUDE.md"
  printf '# Codex\n' > "$HOME/.codex/AGENTS.md"
  printf '# Our rules\n\nNo ORM in this repo.\n' > "$PROJECT/RULES.md"
  cd "$PROJECT" || return 1
}

teardown() {
  [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

project_profile() { printf '%s\n' "$1" > "$BANK/rules-profile.json"; }
sync_project() { run bash "$SCRIPT" sync --scope=project; }

@test "architecture modular-monolith: Key rules and RULES.md carry its rules, not clean" {
  project_profile '{"schema_version":1,"scope":"project","architecture":"modular-monolith"}'
  sync_project
  [ "$status" -eq 0 ]
  assert_grep -qF 'Modular monolith:' "$PROJECT/CLAUDE.md"
  refute_grep -qF 'Clean Architecture' "$PROJECT/CLAUDE.md"
  assert_grep -qF "$PR_START" "$PROJECT/RULES.md"
  assert_grep -qF 'no-cross-module-internals' "$PROJECT/RULES.md"
  assert_grep -qF '[block]' "$PROJECT/RULES.md"
  refute_grep -qF 'layer-direction' "$PROJECT/RULES.md"
}

@test "default profile: Key rules carry clean + FSD + DDD folders, TDD small+ wording, Trophy, no coverage" {
  # The full list lives in the global file; the project file only says no overrides (AGR-083).
  run bash "$SCRIPT" sync --scope=user
  [ "$status" -eq 0 ]
  assert_grep -qF 'Clean Architecture:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'FSD (frontend):' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'DDD folders:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'TDD: new logic' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'standard+ tier' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  refute_grep -qF 'Coverage:' "$HOME/.claude/CLAUDE.md"
  sync_project
  [ "$status" -eq 0 ]
  assert_grep -qF 'Global Key rules apply; this project has no overrides.' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'Coverage: off' "$PROJECT/RULES.md"
}

@test "tdd off: no TDD line in Key rules; RULES.md says off" {
  project_profile '{"schema_version":1,"scope":"project","quality":{"tdd":"off"}}'
  sync_project
  [ "$status" -eq 0 ]
  refute_grep -qF 'TDD:' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'TDD: off' "$PROJECT/RULES.md"
}

@test "coverage 80/95/70: numbers in Key rules and in RULES.md" {
  project_profile '{"schema_version":1,"scope":"project","quality":{"coverage":{"enabled":true,"overall":80,"core":95,"infra":70}}}'
  sync_project
  [ "$status" -eq 0 ]
  assert_grep -qF 'Coverage: overall 80%+, core/business 95%+, infrastructure 70%+' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'overall 80%' "$PROJECT/RULES.md"
  assert_grep -qF 'infrastructure 70%' "$PROJECT/RULES.md"
}

@test "RULES.md: block on top, free text kept, second sync byte-identical" {
  sync_project
  [ "$(head -n 1 "$PROJECT/RULES.md")" = "$PR_START" ]
  assert_grep -qF '# Our rules' "$PROJECT/RULES.md"
  assert_grep -qF 'No ORM in this repo.' "$PROJECT/RULES.md"
  snapshot "$PROJECT/RULES.md" "$TMPROOT/r1"
  snapshot "$PROJECT/CLAUDE.md" "$TMPROOT/c1"
  sync_project
  [ "$status" -eq 0 ]
  assert_unchanged "$PROJECT/RULES.md" "$TMPROOT/r1"
  assert_unchanged "$PROJECT/CLAUDE.md" "$TMPROOT/c1"
  [ "$(grep -cF "$PR_START" "$PROJECT/RULES.md")" -eq 1 ]
}

@test "RULES.md: sync never creates it; falls back to <bank>/RULES.md; init creates it" {
  rm "$PROJECT/RULES.md"
  sync_project
  [ "$status" -eq 0 ]
  refute_file "$PROJECT/RULES.md"
  refute_file "$BANK/RULES.md"
  printf 'bank notes\n' > "$BANK/RULES.md"
  sync_project
  assert_grep -qF "$PR_START" "$BANK/RULES.md"
  assert_grep -qF 'bank notes' "$BANK/RULES.md"
  rm "$BANK/RULES.md"
  run bash "$SCRIPT" init --scope=project
  [ "$status" -eq 0 ]
  assert_grep -qF "$PR_START" "$PROJECT/RULES.md"
  # shellcheck disable=SC2016  # literal markdown backticks
  assert_grep -qF 'Details: `RULES.md`' "$PROJECT/CLAUDE.md"
}

@test "sync --scope=user does not touch the project RULES.md" {
  snapshot "$PROJECT/RULES.md" "$TMPROOT/r1"
  run bash "$SCRIPT" sync --scope=user
  [ "$status" -eq 0 ]
  assert_unchanged "$PROJECT/RULES.md" "$TMPROOT/r1"
}

@test "set architecture hexagonal --scope=project: profile, Key rules, RULES.md; global files untouched" {
  bash "$SCRIPT" sync --scope=user >/dev/null
  snapshot "$HOME/.claude/CLAUDE.md" "$TMPROOT/g1"
  snapshot "$HOME/.codex/AGENTS.md" "$TMPROOT/g2"
  run bash "$SCRIPT" set architecture hexagonal --scope=project
  [ "$status" -eq 0 ]
  run jq -r '.architecture' "$BANK/rules-profile.json"
  [ "$output" = hexagonal ]
  assert_grep -qF 'Hexagonal:' "$PROJECT/CLAUDE.md"
  refute_grep -qF 'Clean Architecture' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'ports-in-domain' "$PROJECT/RULES.md"
  assert_unchanged "$HOME/.claude/CLAUDE.md" "$TMPROOT/g1"
  assert_unchanged "$HOME/.codex/AGENTS.md" "$TMPROOT/g2"
  refute_file "$USER_PROFILE"
  run bash "$REPO_ROOT/scripts/mb-profile.sh" validate "$BANK/rules-profile.json"
  [ "$status" -eq 0 ]
}

@test "set architecture: several names and custom text" {
  run bash "$SCRIPT" set architecture 'fsd,custom:ports for every adapter' --scope=project
  [ "$status" -eq 0 ]
  run jq -c '.architecture' "$BANK/rules-profile.json"
  [ "$output" = '["fsd",{"custom":"ports for every adapter"}]' ]
  assert_grep -qF 'FSD (frontend)' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'Architecture: ports for every adapter' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'ports for every adapter' "$PROJECT/RULES.md"
}

@test "set principle kiss off: KISS line gone, RULES.md says KISS off" {
  run bash "$SCRIPT" set principle kiss off --scope=project
  [ "$status" -eq 0 ]
  refute_grep -qF 'KISS:' "$PROJECT/CLAUDE.md"
  assert_grep -qF -- '- Off in this project: `kiss`.' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'KISS: off' "$PROJECT/RULES.md"
  run jq -c '.quality.principles' "$BANK/rules-profile.json"
  [ "$output" = '{"kiss":"off"}' ]
}

@test "set tdd / trophy / coverage write quality and re-render" {
  bash "$SCRIPT" set tdd on --scope=project >/dev/null
  bash "$SCRIPT" set trophy off --scope=project >/dev/null
  run bash "$SCRIPT" set coverage 80/95/70 --scope=project
  [ "$status" -eq 0 ]
  run jq -c '.quality' "$BANK/rules-profile.json"
  [ "$output" = '{"tdd":"on","testing_trophy":"off","coverage":{"enabled":true,"overall":80,"core":95,"infra":70}}' ]
  refute_grep -qF 'standard+ tier' "$PROJECT/CLAUDE.md"
  refute_grep -qF 'Testing Trophy:' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'overall 80%+' "$PROJECT/CLAUDE.md"
  run bash "$SCRIPT" set coverage off --scope=project
  [ "$status" -eq 0 ]
  refute_grep -qF 'Coverage:' "$PROJECT/CLAUDE.md"
  run jq -c '.quality.coverage' "$BANK/rules-profile.json"
  [ "$output" = '{"enabled":false,"overall":80,"core":95,"infra":70}' ]
}

@test "set: invalid values exit 2 and write nothing" {
  local bad
  for bad in "tdd maybe" "trophy yes" "coverage 80/95" "coverage 80/150/70" "architecture serverless-mesh" \
             "principle clean off" "principle kiss maybe" "discipline loud" "colour blue"; do
    # shellcheck disable=SC2086
    run bash "$SCRIPT" set $bad --scope=project
    [ "$status" -eq 2 ] || { echo "set $bad -> $status: $output"; return 1; }
  done
  refute_file "$BANK/rules-profile.json"
}

@test "set discipline strict and the old discipline form are the same writer" {
  run bash "$SCRIPT" set discipline strict --scope=project
  [ "$status" -eq 0 ]
  assert_grep -qF 'Strict:' "$PROJECT/CLAUDE.md"
  run bash "$SCRIPT" discipline calm --scope=project
  [ "$status" -eq 0 ]
  assert_grep -qF '"discipline": "calm"' "$BANK/rules-profile.json"
  refute_grep -qF 'Strict:' "$PROJECT/CLAUDE.md"
}

@test "set --scope=user: user profile and global files; project files untouched" {
  bash "$SCRIPT" sync --scope=project >/dev/null
  snapshot "$PROJECT/CLAUDE.md" "$TMPROOT/p1"
  snapshot "$PROJECT/RULES.md" "$TMPROOT/r1"
  run bash "$SCRIPT" set tdd off --scope=user
  [ "$status" -eq 0 ]
  refute_grep -qF 'TDD:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF '"tdd": "off"' "$USER_PROFILE"
  assert_unchanged "$PROJECT/CLAUDE.md" "$TMPROOT/p1"
  assert_unchanged "$PROJECT/RULES.md" "$TMPROOT/r1"
}

@test "old architecture toggle ids are refused with profile_setting" {
  run bash "$SCRIPT" enable mobile-udf --scope=project
  [ "$status" -eq 2 ]
  assert_substring "$output" "profile_setting"
  assert_substring "$output" "set architecture"
}
