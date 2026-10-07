#!/usr/bin/env bats
# install.sh "Key rules" onboarding step (plan key-rules-onboarding, Stage 4).
#   - TTY and no --non-interactive: numbered checklist (numbers toggle, Enter
#     accepts), then "Your own rules" one per line; writes the user rules
#     profile and syncs the Key rules block into the global files.
#   - --non-interactive / no TTY: default selection on first install, keep on
#     re-install; --key-rules=default|keep forces either.
# The TTY is a real pseudo-terminal from `script(1)`. Temp HOME only.

load lib/assert

bats_require_minimum_version 1.5.0

START='<!-- mb-key-rules:start -->'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  SANDBOX="$(mktemp -d)"
  export HOME="$SANDBOX/home"
  export MB_USER_RULES_AUTO_PROMPT=off
  unset MB_CLIENTS MB_LANGUAGE MB_WITH_EXTENSIONS MB_PATH MB_AGENT || true
  mkdir -p "$HOME" "$SANDBOX/project"
  cd "$SANDBOX/project" || return 1
  PROFILE="$HOME/.claude/memory-bank/rules-profile.json"
}

teardown() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

# on_tty <stdin-text> <cmd...> — run cmd on a pseudo-terminal fed with stdin-text.
# The writer stays open until cmd exits: on EOF script(1) sends ^D to the
# terminal, which a waiting read would take as an empty answer.
on_tty() {
  local input="$1" done_flag="$SANDBOX/tty.done" rc
  shift
  rm -f "$done_flag"
  {
    printf '%s' "$input"
    while [ ! -f "$done_flag" ]; do sleep 0.2; done
  } | {
    if script --version >/dev/null 2>&1; then
      script -qec "$(printf '%q ' "$@")" /dev/null    # util-linux
    else
      script -q /dev/null "$@"                         # BSD / macOS
    fi
    rc=$?
    touch "$done_flag"
    return "$rc"
  }
}

install_tty() {
  run on_tty "$1" bash "$INSTALL" --clients claude-code --language en "${@:2}"
}

install_quiet() {
  run bash "$INSTALL" --clients claude-code --language en "$@" </dev/null
}

# First line of ~/.claude/CLAUDE.md after an optional mb-language block.
first_section_line() {
  awk '/<!-- mb-language:start -->/ { skip = 1 } skip { if (/<!-- mb-language:end -->/) skip = 0; next } NF { print; exit }' \
    "$HOME/.claude/CLAUDE.md"
}

@test "install on a TTY: checklist toggles + own rules land in profile and CLAUDE.md" {
  install_tty $'19\n\nprefer composition over inheritance\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  assert_substring "$output" "Key rules"
  assert_substring "$output" "[x]  3. kiss"
  assert_substring "$output" "[*]  5. fail-fast"
  assert_substring "$output" "Your own rules"
  assert_grep -qF '"testing_trophy": "off"' "$PROFILE"
  assert_grep -qF 'prefer composition over inheritance' "$PROFILE"
  [ "$(first_section_line)" = "$START" ]
  refute_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'prefer composition over inheritance (your rule)' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF '# [MEMORY-BANK-SKILL]' "$HOME/.claude/CLAUDE.md"
}

@test "install --non-interactive: default Key rules block, no prompt, no profile" {
  install_quiet --non-interactive
  [ "$status" -eq 0 ]
  refute_substring "$output" "Your own rules"
  [ "$(first_section_line)" = "$START" ]
  assert_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'TDD: new logic' "$HOME/.claude/CLAUDE.md"
  refute_file "$PROFILE"
  [ "$(grep -cF "$START" "$HOME/.claude/CLAUDE.md")" -eq 1 ]
  assert_grep -qF "$START" "$HOME/.codex/AGENTS.md"
}

@test "re-install --non-interactive keeps the selection; --key-rules=default resets it" {
  install_tty $'19\n\nmy own rule\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  snapshot "$PROFILE" "$SANDBOX/prof"
  install_quiet --non-interactive
  [ "$status" -eq 0 ]
  assert_unchanged "$PROFILE" "$SANDBOX/prof"
  refute_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'my own rule (your rule)' "$HOME/.claude/CLAUDE.md"
  [ "$(grep -cF "$START" "$HOME/.claude/CLAUDE.md")" -eq 1 ]
  install_quiet --non-interactive --key-rules=default
  [ "$status" -eq 0 ]
  assert_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  refute_grep -qF 'my own rule' "$HOME/.claude/CLAUDE.md"
}

@test "re-install on a TTY shows the current selection; Enter keeps it" {
  install_tty $'19\n\nmy own rule\n\n\n\n\n\n'
  snapshot "$PROFILE" "$SANDBOX/prof"
  install_tty $'\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  assert_substring "$output" "[ ] 19. testing-trophy"
  assert_substring "$output" "my own rule"
  assert_unchanged "$PROFILE" "$SANDBOX/prof"
}

@test "install on a TTY: Quality step sets architecture, TDD, Trophy, coverage" {
  install_tty $'\n\n2,3\noff\non\n80/95/70\n'
  [ "$status" -eq 0 ]
  assert_substring "$output" "Quality"
  assert_substring "$output" "2. hexagonal"
  assert_substring "$output" "8. event-driven"
  "$REPO_ROOT/.venv/bin/python" - "$PROFILE" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
assert p["architecture"] == ["hexagonal", "modular-monolith"], p
assert p["quality"]["tdd"] == "off", p
assert p["quality"]["coverage"] == {"enabled": True, "overall": 80, "core": 95, "infra": 70}, p
PY
  assert_grep -qF 'Hexagonal:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'Modular monolith:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'Coverage: overall 80%+' "$HOME/.claude/CLAUDE.md"
  refute_grep -qF 'TDD: new logic' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
}

@test "re-install on a TTY shows current Quality values; Enter keeps them" {
  install_tty $'\n\n2,3\noff\non\n80/95/70\n'
  snapshot "$PROFILE" "$SANDBOX/prof"
  install_tty $'\n\n\n\n\n\n'
  [ "$status" -eq 0 ]
  assert_substring "$output" "current: hexagonal, modular-monolith"
  assert_substring "$output" "current: 80/95/70"
  assert_unchanged "$PROFILE" "$SANDBOX/prof"
  install_quiet --non-interactive
  [ "$status" -eq 0 ]
  assert_unchanged "$PROFILE" "$SANDBOX/prof"
  assert_grep -qF 'Coverage: overall 80%+' "$HOME/.claude/CLAUDE.md"
}

@test "install --non-interactive: no Quality prompt, default settings" {
  install_quiet --non-interactive
  [ "$status" -eq 0 ]
  refute_substring "$output" "Quality settings"
  refute_grep -qF 'Coverage:' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'Clean Architecture' "$HOME/.claude/CLAUDE.md"
}

@test "install on a TTY with --key-rules=keep skips the prompt" {
  install_tty '' --key-rules=keep
  [ "$status" -eq 0 ]
  refute_substring "$output" "Your own rules"
  [ "$(first_section_line)" = "$START" ]
}

@test "install: invalid --key-rules value exits 1" {
  install_quiet --key-rules=bogus
  [ "$status" -eq 1 ]
  assert_substring "$output" "--key-rules"
}

@test "uninstall strips the Key rules block from the global files" {
  mkdir -p "$HOME/.claude"
  printf '# My own global notes\n' > "$HOME/.claude/CLAUDE.md"
  install_quiet --non-interactive
  [ "$status" -eq 0 ]
  assert_grep -qF "$START" "$HOME/.claude/CLAUDE.md"
  run bash -c 'echo y | bash "$1/uninstall.sh"' _ "$REPO_ROOT"
  [ "$status" -eq 0 ]
  refute_grep -qF "$START" "$HOME/.claude/CLAUDE.md"
  assert_grep -qF '# My own global notes' "$HOME/.claude/CLAUDE.md"
  refute_file "$HOME/.cursor/AGENTS.md"
}
