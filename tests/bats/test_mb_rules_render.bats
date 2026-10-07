#!/usr/bin/env bats
# Contract of `mb-rules.sh render|sync` — the managed `## Key rules` block
# (<!-- mb-key-rules:start/end -->) at the TOP of CLAUDE.md / AGENTS.md:
# after the mb-language block when present, before everything else; one
# `- <text>` line per resolved key rule, custom rules last with "(your rule)",
# and a final pointer to the detailed rules (AGR-066). Project CLAUDE.md /
# AGENTS.md carry only the project's differences from the user-level rules
# (AGR-083); per-host rule files (Windsurf/Cline/Kilo) carry the full block. Temp HOME + temp
# project only — never the real ~/.claude or this repo's own files.

load lib/assert

bats_require_minimum_version 1.5.0

START='<!-- mb-key-rules:start -->'
END='<!-- mb-key-rules:end -->'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$REPO_ROOT/scripts/mb-rules.sh"
  TMPROOT="$(mktemp -d)"
  export HOME="$TMPROOT/home"
  PROJECT="$TMPROOT/project"
  BANK="$PROJECT/.memory-bank"
  mkdir -p "$HOME" "$BANK"
  unset MB_PATH MB_AGENT || true
  printf '# My project\n\nSome foreign text.\n' > "$PROJECT/CLAUDE.md"
}

teardown() {
  [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"
}

sync_project() { run bash "$SCRIPT" sync --scope=project --project="$PROJECT"; }

user_profile() {
  mkdir -p "$HOME/.claude/memory-bank"
  printf '%s\n' "$1" > "$HOME/.claude/memory-bank/rules-profile.json"
}

@test "sync project: block becomes the first section and the rest is byte-identical" {
  cp "$PROJECT/CLAUDE.md" "$TMPROOT/orig"
  sync_project
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$PROJECT/CLAUDE.md")" = "$START" ]
  assert_grep -qF '## Key rules' "$PROJECT/CLAUDE.md"
  # Everything after the end marker + one separator line is the untouched original.
  awk -v e="$END" 'seen && skip { skip = 0; next } seen { print } index($0, e) { seen = 1; skip = 1 }' \
    "$PROJECT/CLAUDE.md" > "$TMPROOT/rest"
  cmp "$TMPROOT/orig" "$TMPROOT/rest"
}

@test "sync project: block goes right after the mb-language block" {
  printf '<!-- mb-language:start -->\n> **Language (this project)** — ru.\n<!-- mb-language:end -->\n\n# My project\n' \
    > "$PROJECT/CLAUDE.md"
  sync_project
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$PROJECT/CLAUDE.md")" = '<!-- mb-language:start -->' ]
  [ "$(sed -n 3p "$PROJECT/CLAUDE.md")" = '<!-- mb-language:end -->' ]
  [ "$(sed -n 5p "$PROJECT/CLAUDE.md")" = "$START" ]
  [ "$(tail -n 1 "$PROJECT/CLAUDE.md")" = '# My project' ]
}

@test "sync project: second run is byte-identical" {
  sync_project
  cp "$PROJECT/CLAUDE.md" "$TMPROOT/first"
  sync_project
  [ "$status" -eq 0 ]
  cmp "$TMPROOT/first" "$PROJECT/CLAUDE.md"
}

@test "sync project: a user-level change is not a project override; the full render follows it" {
  run bash "$SCRIPT" render --target=project --mode=full --project="$PROJECT"
  assert_substring "$output" 'Deletion over addition'
  user_profile '{"key_rules": {"disabled": ["deletion-over-addition"]}}'
  sync_project
  [ "$status" -eq 0 ]
  assert_grep -qF 'Global Key rules apply' "$PROJECT/CLAUDE.md"
  refute_grep -qF 'deletion-over-addition' "$PROJECT/CLAUDE.md"
  run bash "$SCRIPT" render --target=project --mode=full --project="$PROJECT"
  refute_substring "$output" 'Deletion over addition'
  [ "$(grep -cF "$START" "$PROJECT/CLAUDE.md")" -eq 1 ]
}

@test "sync project: only the project's custom rules, with (your rule); full mode lists both" {
  user_profile '{"key_rules": {"custom": ["prefer composition over inheritance"]}}'
  printf '%s\n' '{"key_rules": {"custom": ["no ORM in this repo"]}}' > "$BANK/rules-profile.json"
  sync_project
  [ "$status" -eq 0 ]
  block="$(sed -n "/$START/,/$END/p" "$PROJECT/CLAUDE.md")"
  assert_substring "$block" '- no ORM in this repo (your rule)'
  refute_substring "$block" 'prefer composition'
  run bash "$SCRIPT" render --target=project --mode=full --project="$PROJECT"
  assert_substring "$output" '- prefer composition over inheritance (your rule)
- no ORM in this repo (your rule)'
}

@test "sync project: CLAUDE.md + AGENTS.md get the delta, the Windsurf rule file the full block" {
  printf '# Agents\n' > "$PROJECT/AGENTS.md"
  mkdir -p "$PROJECT/.windsurf/rules"
  WS="$PROJECT/.windsurf/rules/memory-bank.md"
  # shellcheck source=/dev/null
  (source "$REPO_ROOT/adapters/_lib_agents_md.sh" && mb_rule_file_body "$REPO_ROOT" "$PROJECT") > "$WS"
  printf '%s\n' '{"quality": {"testing_trophy": "off"}, "key_rules": {"custom": ["no ORM in this repo"]}}' \
    > "$BANK/rules-profile.json"
  sync_project
  [ "$status" -eq 0 ]
  local f
  for f in "$PROJECT/CLAUDE.md" "$PROJECT/AGENTS.md"; do
    assert_grep -qF '## Key rules — project overrides' "$f"
    assert_grep -qF -- '- Off in this project: `testing-trophy`.' "$f"
    assert_grep -qF -- '- no ORM in this repo (your rule)' "$f"
    refute_grep -qF 'TDD: new logic' "$f"
  done
  [ "$(head -n 1 "$WS")" = '# Memory Bank — Project Rules' ]
  [ "$(grep -cF "$START" "$WS")" -eq 1 ]
  assert_grep -qF 'TDD: new logic' "$WS"
  assert_grep -qF -- '- no ORM in this repo (your rule)' "$WS"
  refute_grep -qF 'Testing Trophy:' "$WS"
  refute_grep -qF 'project overrides' "$WS"
  assert_grep -qF '## Memory Bank' "$WS"
  # Second sync changes nothing.
  for f in "$PROJECT/CLAUDE.md" "$PROJECT/AGENTS.md" "$WS"; do snapshot "$f" "$f.first"; done
  sync_project
  [ "$status" -eq 0 ]
  for f in "$PROJECT/CLAUDE.md" "$PROJECT/AGENTS.md" "$WS"; do assert_unchanged "$f" "$f.first"; done
}

@test "sync project: rule files without the Key rules block are left alone" {
  mkdir -p "$PROJECT/.kilocode/rules"
  printf '# Kilo notes\n' > "$PROJECT/.kilocode/rules/memory-bank.md"
  snapshot "$PROJECT/.kilocode/rules/memory-bank.md" "$TMPROOT/kilo"
  sync_project
  [ "$status" -eq 0 ]
  assert_unchanged "$PROJECT/.kilocode/rules/memory-bank.md" "$TMPROOT/kilo"
}

@test "sync project: only existing files are written; CLAUDE.md symlink kept" {
  sync_project
  refute_file "$PROJECT/AGENTS.md"
  rm "$PROJECT/CLAUDE.md"
  printf '# Agents\n' > "$PROJECT/AGENTS.md"
  ln -s AGENTS.md "$PROJECT/CLAUDE.md"
  sync_project
  [ "$status" -eq 0 ]
  [ -L "$PROJECT/CLAUDE.md" ]
  [ "$(grep -cF "$START" "$PROJECT/AGENTS.md")" -eq 1 ]
}

@test "render: project block without overrides is <= 300 B, full mode <= 3 KB; writes nothing" {
  cp "$PROJECT/CLAUDE.md" "$TMPROOT/orig"
  run bash "$SCRIPT" render --target=project --project="$PROJECT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TMPROOT/block"
  [ "$(wc -c < "$TMPROOT/block")" -le 300 ]
  [ "$(head -n 1 "$TMPROOT/block")" = "$START" ]
  [ "$(tail -n 1 "$TMPROOT/block")" = "$END" ]
  assert_substring "$output" 'Global Key rules apply'
  assert_substring "$output" 'create `RULES.md` in the project root'
  run bash "$SCRIPT" render --target=project --mode=full --project="$PROJECT"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$TMPROOT/full"
  [ "$(wc -c < "$TMPROOT/full")" -le 3072 ]
  assert_substring "$output" 'TDD: new logic'
  run bash "$SCRIPT" render --target=project --mode=sideways --project="$PROJECT"
  [ "$status" -ne 0 ]
  cmp "$TMPROOT/orig" "$PROJECT/CLAUDE.md"
}

@test "render project: pointer prefers <repo>/RULES.md, then <bank>/RULES.md, else a create hint" {
  run bash "$SCRIPT" render --target=project --project="$PROJECT"
  assert_substring "$output" 'create `RULES.md` in the project root'
  touch "$BANK/RULES.md"
  run bash "$SCRIPT" render --target=project --project="$PROJECT"
  assert_substring "$output" '`.memory-bank/RULES.md`'
  touch "$PROJECT/RULES.md"
  run bash "$SCRIPT" render --target=project --project="$PROJECT"
  [ "$status" -eq 0 ]
  assert_substring "$output" 'Details: `RULES.md`'
  refute_substring "$output" '.memory-bank/RULES.md'
}

@test "sync user: global files point at their host's global RULES.md; missing hosts skipped" {
  mkdir -p "$HOME/.claude" "$HOME/.codex"
  printf '# Global\n' > "$HOME/.claude/CLAUDE.md"
  printf '# Codex\n' > "$HOME/.codex/AGENTS.md"
  run bash "$SCRIPT" sync --scope=user
  [ "$status" -eq 0 ]
  [ "$(head -n 1 "$HOME/.claude/CLAUDE.md")" = "$START" ]
  assert_grep -qF 'Details: `~/.claude/RULES.md`' "$HOME/.claude/CLAUDE.md"
  assert_grep -qF 'Details: `~/.codex/skills/memory-bank/rules/RULES.md`' "$HOME/.codex/AGENTS.md"
  refute_file "$HOME/.pi/agent/AGENTS.md"
  refute_file "$HOME/.config/opencode/AGENTS.md"
  # project files are not user scope
  refute_grep -qF "$START" "$PROJECT/CLAUDE.md"
}

@test "sync user: project profile does not leak into global files" {
  mkdir -p "$HOME/.claude"
  printf '# Global\n' > "$HOME/.claude/CLAUDE.md"
  printf '%s\n' '{"key_rules": {"custom": ["project only rule"]}}' > "$BANK/rules-profile.json"
  cd "$PROJECT"
  run bash "$SCRIPT" sync --scope=user
  [ "$status" -eq 0 ]
  refute_grep -qF 'project only rule' "$HOME/.claude/CLAUDE.md"
}
