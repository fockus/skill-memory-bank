#!/usr/bin/env bats
# Contract of the `mb-rules.sh` selection commands (`/mb rules`):
#   list | enable <id> | disable <id> | add "<text>" | remove <n> | init [...] | sync
#   --scope=user|project (default: project when a bank resolves, else user).
# A mutating command writes the scope's rules profile (only the `key_rules`
# field of an existing profile changes) and re-syncs that scope's files only:
# project → <project>/CLAUDE.md + AGENTS.md (only the project's differences from the
# user-level rules, AGR-083), user → global host files (full block).
# Temp HOME + temp project only.

load lib/assert

bats_require_minimum_version 1.5.0

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
  printf '# Project agents\n' > "$PROJECT/AGENTS.md"
  printf '# Global\n' > "$HOME/.claude/CLAUDE.md"
  printf '# Codex\n' > "$HOME/.codex/AGENTS.md"
  cd "$PROJECT" || return 1
}

teardown() {
  [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

rules() { run bash "$SCRIPT" "$@"; }

@test "disable --scope=project: project files lose the rule, global files untouched" {
  bash "$SCRIPT" sync --scope=user >/dev/null
  snapshot "$HOME/.claude/CLAUDE.md" "$TMPROOT/g1"
  snapshot "$HOME/.codex/AGENTS.md" "$TMPROOT/g2"
  rules disable testing-trophy --scope=project
  [ "$status" -eq 0 ]
  refute_grep -qF 'Testing Trophy:' "$PROJECT/CLAUDE.md"
  refute_grep -qF 'Testing Trophy:' "$PROJECT/AGENTS.md"
  assert_grep -qF -- '- Off in this project: `testing-trophy`.' "$PROJECT/CLAUDE.md"
  assert_grep -qF -- '- Off in this project: `testing-trophy`.' "$PROJECT/AGENTS.md"
  assert_unchanged "$HOME/.claude/CLAUDE.md" "$TMPROOT/g1"
  assert_unchanged "$HOME/.codex/AGENTS.md" "$TMPROOT/g2"
  assert_grep -qF '"testing_trophy": "off"' "$BANK/rules-profile.json"
  refute_file "$USER_PROFILE"
}

@test "disable --scope=user: global files lose the rule, project files untouched" {
  bash "$SCRIPT" sync --scope=project >/dev/null
  snapshot "$PROJECT/CLAUDE.md" "$TMPROOT/p1"
  snapshot "$PROJECT/AGENTS.md" "$TMPROOT/p2"
  rules disable testing-trophy --scope=user
  [ "$status" -eq 0 ]
  refute_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  refute_grep -qF 'Testing Trophy:' "$HOME/.codex/AGENTS.md"
  assert_grep -qF 'TDD: new logic' "$HOME/.claude/CLAUDE.md"
  assert_unchanged "$PROJECT/CLAUDE.md" "$TMPROOT/p1"
  assert_unchanged "$PROJECT/AGENTS.md" "$TMPROOT/p2"
  refute_file "$BANK/rules-profile.json"
}

@test "disable a locked rule: exit 2 with the reason, nothing written" {
  snapshot "$PROJECT/CLAUDE.md" "$TMPROOT/p1"
  rules disable fail-fast --scope=project
  [ "$status" -eq 2 ]
  assert_substring "$output" "locked"
  refute_file "$BANK/rules-profile.json"
  assert_unchanged "$PROJECT/CLAUDE.md" "$TMPROOT/p1"
}

@test "disable a principle: stored in quality.principles, KISS line gone, enable restores" {
  rules disable kiss --scope=project
  [ "$status" -eq 0 ]
  refute_grep -qF 'KISS:' "$PROJECT/CLAUDE.md"
  assert_grep -qF -- '- Off in this project: `kiss`.' "$PROJECT/CLAUDE.md"
  run jq -c '[.quality.principles, (.key_rules.disabled // [])]' "$BANK/rules-profile.json"
  [ "$output" = '[{"kiss":"off"},[]]' ]
  run bash "$REPO_ROOT/scripts/mb-profile.sh" validate "$BANK/rules-profile.json"
  [ "$status" -eq 0 ]
  rules enable kiss --scope=project
  [ "$status" -eq 0 ]
  assert_grep -qF 'Global Key rules apply; this project has no overrides.' "$PROJECT/CLAUDE.md"
  refute_grep -qF '"kiss"' "$BANK/rules-profile.json"
}

@test "discipline strict: profile field adds the strict lines to the block; calm removes them" {
  rules discipline strict --scope=project
  [ "$status" -eq 0 ]
  assert_grep -qF '"discipline": "strict"' "$BANK/rules-profile.json"
  assert_grep -qF 'Strict:' "$PROJECT/CLAUDE.md"
  rules discipline calm --scope=project
  [ "$status" -eq 0 ]
  refute_grep -qF 'Strict:' "$PROJECT/CLAUDE.md"
  rules discipline loud --scope=project
  [ "$status" -eq 2 ]
}

@test "unknown rule id: exit 2 naming the id" {
  rules enable no-such-rule --scope=project
  [ "$status" -eq 2 ]
  assert_substring "$output" "no-such-rule"
}

@test "enable after disable restores the rule and leaves an empty selection" {
  bash "$SCRIPT" disable testing-trophy --scope=project >/dev/null
  rules enable testing-trophy --scope=project
  [ "$status" -eq 0 ]
  assert_grep -qF 'Global Key rules apply; this project has no overrides.' "$PROJECT/CLAUDE.md"
  refute_grep -qF 'testing' "$BANK/rules-profile.json"
}

@test "enable a default-off rule, project scope only" {
  rules enable coverage --scope=project
  [ "$status" -eq 0 ]
  assert_grep -qF 'Coverage: overall 85%+' "$PROJECT/CLAUDE.md"
  refute_grep -qF 'Coverage:' "$HOME/.claude/CLAUDE.md"
}

@test "add then remove a custom rule by its listed number" {
  rules add "prefer composition over inheritance" --scope=project
  [ "$status" -eq 0 ]
  assert_grep -qF -- '- prefer composition over inheritance (your rule)' "$PROJECT/AGENTS.md"
  bash "$SCRIPT" add "no ORM in this repo" --scope=project >/dev/null
  rules list --scope=project
  assert_substring "$output" "1. prefer composition over inheritance"
  assert_substring "$output" "2. no ORM in this repo"
  rules remove 1 --scope=project
  [ "$status" -eq 0 ]
  refute_grep -qF 'prefer composition' "$PROJECT/CLAUDE.md"
  assert_grep -qF 'no ORM in this repo (your rule)' "$PROJECT/CLAUDE.md"
}

@test "remove an out-of-range custom number: exit 2" {
  rules remove 3 --scope=project
  [ "$status" -eq 2 ]
}

@test "list: numbered by group with [x] / [ ] / [*] marks" {
  bash "$SCRIPT" disable testing-trophy --scope=user >/dev/null
  rules list --scope=user
  [ "$status" -eq 0 ]
  assert_substring "$output" "Principles"
  assert_substring "$output" "[x]  3. kiss"
  assert_substring "$output" "[*]  5. fail-fast"
  assert_substring "$output" "[ ] 19. testing-trophy"
  assert_substring "$output" "[x] 17. tdd"
  assert_substring "$output" "[ ] 21. coverage"
  assert_substring "$output" "[x] 16. architecture — Clean Architecture"
}

@test "default scope: project when a bank resolves, user otherwise" {
  rules add "bank rule"
  [ "$status" -eq 0 ]
  assert_grep -qF 'bank rule' "$BANK/rules-profile.json"
  mkdir -p "$TMPROOT/nobank"
  cd "$TMPROOT/nobank"
  rules add "user rule"
  [ "$status" -eq 0 ]
  assert_grep -qF 'user rule' "$USER_PROFILE"
  assert_grep -qF 'user rule (your rule)' "$HOME/.claude/CLAUDE.md"
}

@test "init: replaces the scope selection from --disable / --enable / --custom" {
  bash "$SCRIPT" add "old rule" --scope=user >/dev/null
  rules init --scope=user --disable=testing-trophy,contract-first --enable=coverage \
    --custom="prefer composition over inheritance" --custom="ADR for every new module"
  [ "$status" -eq 0 ]
  refute_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  refute_grep -qF 'Contract-First:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'Coverage:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'ADR for every new module (your rule)' "$HOME/.claude/CLAUDE.md"
  refute_grep -qF 'old rule' "$USER_PROFILE"
}

@test "init: a locked id in --disable is refused with exit 2" {
  rules init --scope=user --disable=fail-fast
  [ "$status" -eq 2 ]
  refute_file "$USER_PROFILE"
}

@test "existing profile: only key_rules changes, other fields kept" {
  bash "$REPO_ROOT/scripts/mb-profile.sh" init --scope=user --role=frontend --stack=typescript >/dev/null
  rules disable testing-trophy --scope=user
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/scripts/mb-profile.sh" validate "$USER_PROFILE"
  [ "$status" -eq 0 ]
  assert_grep -qF '"frontend"' "$USER_PROFILE"
  assert_grep -qF '"testing_trophy": "off"' "$USER_PROFILE"
}

@test "new profile written by mb-rules.sh passes mb-profile.sh validate" {
  bash "$SCRIPT" disable testing-trophy --scope=project >/dev/null
  run bash "$REPO_ROOT/scripts/mb-profile.sh" validate "$BANK/rules-profile.json"
  [ "$status" -eq 0 ]
}

@test "init --interactive: numbers toggle, locked refused, own rules appended" {
  run bash "$SCRIPT" init --interactive --scope=user <<'EOF'
19 5
21

prefer composition over inheritance

EOF
  [ "$status" -eq 0 ]
  assert_substring "$output" "locked"
  assert_substring "$output" "Your own rules"
  refute_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'KISS:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'Coverage:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'prefer composition over inheritance (your rule)' "$HOME/.claude/CLAUDE.md"
}

@test "init --interactive: Enter on both prompts keeps the current selection" {
  bash "$SCRIPT" disable testing-trophy --scope=user >/dev/null
  bash "$SCRIPT" add "keep me" --scope=user >/dev/null
  snapshot "$USER_PROFILE" "$TMPROOT/prof"
  run bash "$SCRIPT" init --interactive --scope=user < /dev/null
  [ "$status" -eq 0 ]
  assert_substring "$output" "[ ] 19. testing-trophy"
  assert_substring "$output" "keep me"
  assert_unchanged "$USER_PROFILE" "$TMPROOT/prof"
}
