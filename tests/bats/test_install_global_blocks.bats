#!/usr/bin/env bats
# install.sh global host blocks + client order (plan 2026-10-06_fix_agents-md-diet, Stage 3):
#   - the OpenCode global block uses its own marker (memory-bank-opencode); an
#     upgrade over the old shared `memory-bank` marker leaves exactly one block;
#   - the Cursor project client runs after the AGENTS.md hosts, so the .mdc sees
#     our Key rules in the project AGENTS.md and does not repeat them;
#   - the Cursor global guard reinstalls when the subagents are missing even
#     though the manifest version and language match, or when the rendered
#     ~/.cursor/AGENTS.md section changed on the same VERSION.
# Installs from a copy of the repo into a temp HOME + temp project (the real
# ~/.config/opencode, ~/.cursor, ... are never touched; the repo manifest is not shared).

load lib/assert

KR_START='<!-- mb-key-rules:start -->'
OC_START='<!-- memory-bank-opencode:start -->'
OLD_START='<!-- memory-bank:start -->'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  YAML_SITE="$(python3 -c 'import os, yaml; print(os.path.dirname(os.path.dirname(yaml.__file__)))' 2>/dev/null || true)"
  export HOME="$BATS_TEST_TMPDIR/home"
  PROJECT="$BATS_TEST_TMPDIR/project"
  SRC="$BATS_TEST_TMPDIR/skill"
  export MB_USER_RULES_AUTO_PROMPT=off
  unset MB_CLIENTS MB_LANGUAGE MB_WITH_EXTENSIONS MB_PATH MB_AGENT || true
  mkdir -p "$HOME" "$PROJECT" "$SRC"
  command -v jq >/dev/null || skip "jq required"
  rsync -a --exclude='.git' --exclude='.index' --exclude='.memsearch' \
    --exclude='/tests' --exclude='node_modules' --exclude='.venv' \
    --exclude='/.memory-bank' --exclude='.installed-manifest.json' "$REPO_ROOT/" "$SRC/"
  git -C "$PROJECT" init -q
}

_install() {
  MB_SKIP_DEPS_CHECK=1 bash "$SRC/install.sh" --clients "$1" --project-root "$PROJECT" \
    --non-interactive </dev/null >"$BATS_TEST_TMPDIR/install.log" 2>&1
}

@test "opencode global: block uses the memory-bank-opencode marker" {
  _install claude-code
  local f="$HOME/.config/opencode/AGENTS.md"
  assert_grep -qF "$OC_START" "$f"
  assert_grep -qF '<!-- memory-bank-opencode:end -->' "$f"
  refute_grep -qF "$OLD_START" "$f"
}

@test "opencode global: upgrade over the old marker keeps one block and the user's text" {
  mkdir -p "$HOME/.config/opencode"
  cat > "$HOME/.config/opencode/AGENTS.md" <<EOF
# User OpenCode rules

$OLD_START
# Memory Bank — OpenCode Global Entry Point
old body
<!-- memory-bank:end -->

Keep answers concise.
EOF
  _install claude-code
  _install claude-code
  local f="$HOME/.config/opencode/AGENTS.md"
  [ "$(grep -cF "$OC_START" "$f")" -eq 1 ]
  [ "$(grep -cF '# Memory Bank — OpenCode Global Entry Point' "$f")" -eq 1 ]
  refute_grep -qF "$OLD_START" "$f"
  refute_grep -qF 'old body' "$f"
  assert_grep -qF '# User OpenCode rules' "$f"
  assert_grep -qF 'Keep answers concise.' "$f"
  [ "$(grep -cF "$KR_START" "$f")" -eq 1 ]
}

@test "uninstall: strips the OpenCode global block under the new and the old marker" {
  _install claude-code
  printf '\n%s\nstale old block\n<!-- memory-bank:end -->\n# User tail\n' "$OLD_START" \
    >> "$HOME/.config/opencode/AGENTS.md"
  MB_SKIP_DEPS_CHECK=1 bash "$SRC/uninstall.sh" -y </dev/null >/dev/null 2>&1 || true
  local f="$HOME/.config/opencode/AGENTS.md"
  assert_grep -qF '# User tail' "$f"
  refute_grep -qF "$OC_START" "$f"
  refute_grep -qF "$OLD_START" "$f"
  refute_grep -qF 'stale old block' "$f"
}

@test "install order: cursor listed first still runs after codex, .mdc does not repeat Key rules" {
  _install cursor,codex
  assert_grep -qF "$KR_START" "$PROJECT/AGENTS.md"
  refute_grep -qF "$KR_START" "$PROJECT/.cursor/rules/memory-bank.mdc"
  # The .mdc keeps the Memory Bank pointers.
  assert_grep -qF 'rules/RULES.md' "$PROJECT/.cursor/rules/memory-bank.mdc"
}

@test "cursor global guard: same VERSION and language but subagents missing → reinstalls them" {
  _install claude-code
  ls "$HOME/.cursor/agents/"mb-*.md >/dev/null
  rm -rf "$HOME/.cursor/agents"
  _install claude-code
  ls "$HOME/.cursor/agents/"mb-*.md >/dev/null
  refute_grep -qF 'Cursor global artifacts already current' "$BATS_TEST_TMPDIR/install.log"
}

@test "cursor global guard: everything present → install is skipped" {
  _install claude-code
  _install claude-code
  assert_grep -qF 'Cursor global artifacts already current' "$BATS_TEST_TMPDIR/install.log"
}

@test "cursor global guard: same VERSION, changed AGENTS.md section → re-rendered" {
  _install claude-code
  sed -i.bak 's/# Memory Bank — Cursor Global Entry Point/# Memory Bank — Cursor Global Entry Point (edited)/' \
    "$SRC/adapters/cursor.sh"
  _install claude-code
  refute_grep -qF 'Cursor global artifacts already current' "$BATS_TEST_TMPDIR/install.log"
  assert_grep -qF 'Cursor Global Entry Point (edited)' "$HOME/.cursor/AGENTS.md"
  _install claude-code
  assert_grep -qF 'Cursor global artifacts already current' "$BATS_TEST_TMPDIR/install.log"
}

@test "codex roles: install renders the pipeline tier model like codex.sh render-agents; reinstall is byte-identical" {
  # PyYAML may live in the real user site-packages, which a temp HOME hides.
  [ -z "$YAML_SITE" ] || export PYTHONPATH="$YAML_SITE${PYTHONPATH:+:$PYTHONPATH}"
  _install claude-code
  local role="$HOME/.codex/agents/mb-developer.toml"
  [ -n "$YAML_SITE" ] || skip "PyYAML required (role models need it)"
  assert_grep -qE '^model = "' "$role"
  # `/mb config init --host codex` re-renders through the adapter: same pipeline, same bytes.
  cp "$role" "$BATS_TEST_TMPDIR/role.before"
  bash "$SRC/adapters/codex.sh" render-agents "$PROJECT" >/dev/null
  cmp "$BATS_TEST_TMPDIR/role.before" "$role"
  _install claude-code
  cmp "$BATS_TEST_TMPDIR/role.before" "$role"
  run find "$HOME/.codex/agents" -name '*.pre-mb-backup*'
  [ -z "$output" ]
}
