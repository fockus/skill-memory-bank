#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # Bats intentionally isolates each test.
# Tests for adapters/opencode.sh — OpenCode cross-agent adapter.
#
# Contract:
#   adapters/opencode.sh install [PROJECT_ROOT]
#   adapters/opencode.sh uninstall [PROJECT_ROOT]
#
# Generates:
#   <project>/AGENTS.md                     — shared format (uses markers)
#   <project>/.opencode/commands/*.md        — project slash commands
#   <project>/.opencode/plugins/memory-bank.js — auto-discovered JS plugin
#   <project>/.opencode/.mb-manifest.json    — ownership tracking
#
# The generated bootstrap is exercised through the native V2 context contract.

load lib/assert
load lib/v2_plugin_harness

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/opencode.sh"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
  # Isolated $HOME sandbox (adapter-parity T5: global agent roster lands under
  # $HOME/.config/opencode/agent — must never touch the real dev machine).
  SANDBOX_HOME="$(mktemp -d)"
  # Keep a user-site PyYAML importable when a test moves HOME (tier-model render).
  PYTHONUSERBASE="$(python3 -m site --user-base || true)"
  export PYTHONUSERBASE
  export HOME="$SANDBOX_HOME"
  unset XDG_CONFIG_HOME MB_PATH MB_SKILLS_ROOT MB_OC_PARITY_ACCEPTED
  unset MB_SUMMARIZE_BIN MB_UPDATE_NOTIFY_BIN MB_AGENTS_LIB MB_AUTO_REFRESH
  unset MB_SESSION_CAPTURE MB_AUTO_CAPTURE MB_CAPTURE_SUBPROCESS MB_MANIFEST_PATH
  export XDG_DATA_HOME="$HOME/.local/share" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  export XDG_CONFIG_DIRS="$HOME/config-dirs" XDG_DATA_DIRS="$HOME/data-dirs"
  export XDG_RUNTIME_DIR="$HOME/run" CODEX_HOME="$HOME/.codex"
  export MB_MANIFEST_PATH="$HOME/install-manifest.json"
  export TMPDIR="$HOME/tmp"
  mkdir -p "$TMPDIR" "$XDG_RUNTIME_DIR"
}

# Full installer aliases must resolve to this private bundle, never the checkout.
opencode_frozen_bundle() {
  local bundle="$SANDBOX_HOME/frozen-bundle"
  mkdir -p "$bundle"
  rsync -a --exclude='.env*' --exclude='__pycache__' \
    "$REPO_ROOT/"{adapters,agents,commands,hooks,scripts,rules,references,templates,flow-templates,settings,memory_bank_skill} \
    "$REPO_ROOT/"{install.sh,uninstall.sh,VERSION,SKILL.md} "$bundle/"
  REPO_ROOT="$bundle"
  ADAPTER="$bundle/adapters/opencode.sh"
}

assert_opencode_preserved() {
  assert_unchanged "$1" "$2"
  assert_substring "$output" "$1"
  printf '%s\n' "$output" | grep -Eiq 'preserv|refus|skip|manual|modified|unmanaged'
  [ "$status" -ne 0 ]
}

@test "opencode S5: pristine upgrade and rerender remain owned through reinstall and uninstall" {
  opencode_frozen_bundle
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  printf '\nUpgrade command sentinel\n' >> "$REPO_ROOT/commands/mb.md"
  printf 'roles:\n  developer: {agent: mb-developer, model: fixture/upgrade}\n' > "$PROJECT/.memory-bank/pipeline.yaml"
  MB_OC_PARITY_ACCEPTED=1 run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q 'Upgrade command sentinel' "$PROJECT/.opencode/commands/mb.md"
  grep -q 'extended: true' "$PROJECT/.opencode/plugins/memory-bank.js"
  grep -q '^model: fixture/upgrade$' "$PROJECT/.opencode/agent/mb-developer.md"
  snapshot "$PROJECT/.opencode/commands/mb.md" "$PROJECT/command.before"
  MB_OC_PARITY_ACCEPTED=1 run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  assert_unchanged "$PROJECT/.opencode/commands/mb.md" "$PROJECT/command.before"
  printf 'roles:\n  developer: {agent: mb-developer, model: fixture/rerender}\n' > "$PROJECT/.memory-bank/pipeline.yaml"
  run_adapter render-agents "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q '^model: fixture/rerender$' "$PROJECT/.opencode/agent/mb-developer.md"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  refute_file "$PROJECT/.opencode/commands/mb.md"
  refute_file "$PROJECT/.opencode/plugins/memory-bank.js"
  refute_file "$PROJECT/.opencode/agent/mb-developer.md"
  [ -z "$(find "$PROJECT/.opencode" -name '*.pre-mb-backup.*' 2>/dev/null)" ]
}

@test "opencode S5: reinstall preserves edited plugin command role and replaced symlinks without blessing them" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local rel file
  for rel in plugins/memory-bank.js commands/mb.md agent/mb-developer.md agent/mb-doctor.md; do
    file="$PROJECT/.opencode/$rel"
    cp -p "$file" "$PROJECT/mtime"
    printf '\nUser post-install edit: %s\n' "$rel" >> "$file"
    touch -r "$PROJECT/mtime" "$file"
    snapshot "$file" "$PROJECT/$(basename "$file").before"
  done
  jq --arg p "$PROJECT/.opencode/agent/mb-doctor.md" 'del(.file_sha256[$p])' \
    "$PROJECT/.opencode/.mb-manifest.json" > "$PROJECT/manifest.new"
  mv "$PROJECT/manifest.new" "$PROJECT/.opencode/.mb-manifest.json"
  printf 'Private symlink target\n' > "$PROJECT/target"
  snapshot "$PROJECT/target" "$PROJECT/target.before"
  rm "$PROJECT/.opencode/commands/start.md"
  ln -s "$PROJECT/target" "$PROJECT/.opencode/commands/start.md"

  run_adapter install "$PROJECT"
  for rel in plugins/memory-bank.js commands/mb.md agent/mb-developer.md agent/mb-doctor.md; do
    file="$PROJECT/.opencode/$rel"
    assert_opencode_preserved "$file" "$PROJECT/$(basename "$file").before"
  done
  [ -L "$PROJECT/.opencode/commands/start.md" ]
  [ "$(readlink "$PROJECT/.opencode/commands/start.md")" = "$PROJECT/target" ]
  assert_unchanged "$PROJECT/target" "$PROJECT/target.before"
  run_adapter uninstall "$PROJECT"
  for rel in plugins/memory-bank.js commands/mb.md agent/mb-developer.md agent/mb-doctor.md; do
    assert_unchanged "$PROJECT/.opencode/$rel" "$PROJECT/$(basename "$rel").before"
  done
  [ -L "$PROJECT/.opencode/commands/start.md" ]
  assert_unchanged "$PROJECT/target" "$PROJECT/target.before"
}

@test "opencode S5: reinstall preserves a replaced plugin symlink even when target bytes match" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  snapshot "$plugin" "$PROJECT/target"
  snapshot "$PROJECT/target" "$PROJECT/target.before"
  rm "$plugin"
  ln -s "$PROJECT/target" "$plugin"
  run_adapter install "$PROJECT"
  [ -L "$plugin" ]
  [ "$(readlink "$plugin")" = "$PROJECT/target" ]
  assert_opencode_preserved "$plugin" "$PROJECT/target.before"
  assert_unchanged "$PROJECT/target" "$PROJECT/target.before"
}

@test "opencode S5: render-agents preserves edited roles and changed symlinks" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local role="$PROJECT/.opencode/agent/mb-developer.md"
  cp -p "$role" "$PROJECT/mtime"
  printf '\nUser role instructions\n' >> "$role"
  touch -r "$PROJECT/mtime" "$role"
  snapshot "$role" "$PROJECT/role.before"
  printf 'User linked role\n' > "$PROJECT/target"
  snapshot "$PROJECT/target" "$PROJECT/target.before"
  rm "$PROJECT/.opencode/agent/mb-reviewer.md"
  ln -s "$PROJECT/target" "$PROJECT/.opencode/agent/mb-reviewer.md"
  run_adapter render-agents "$PROJECT"
  assert_opencode_preserved "$role" "$PROJECT/role.before"
  [ -L "$PROJECT/.opencode/agent/mb-reviewer.md" ]
  assert_unchanged "$PROJECT/target" "$PROJECT/target.before"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/adapters/_framework.sh"
  run _mb_owned_unedited "$role" "$PROJECT/.opencode/.mb-manifest.json" "$PROJECT/.opencode"
  [ "$status" -ne 0 ]
}

@test "opencode S5: global role reinstall preserves edits and changed symlinks" {
  run_adapter install-global-agents "$PROJECT"
  [ "$status" -eq 0 ]
  local dir="$HOME/.config/opencode/agent" role="$HOME/.config/opencode/agent/mb-developer.md"
  cp -p "$role" "$PROJECT/mtime"
  printf '\nUser global role instructions\n' >> "$role"
  touch -r "$PROJECT/mtime" "$role"
  snapshot "$role" "$PROJECT/role.before"
  printf 'User linked global role\n' > "$PROJECT/target"
  snapshot "$PROJECT/target" "$PROJECT/target.before"
  rm "$dir/mb-reviewer.md"
  ln -s "$PROJECT/target" "$dir/mb-reviewer.md"
  run_adapter install-global-agents "$PROJECT"
  assert_opencode_preserved "$role" "$PROJECT/role.before"
  [ -L "$dir/mb-reviewer.md" ]
  assert_unchanged "$PROJECT/target" "$PROJECT/target.before"
  # shellcheck source=/dev/null
  source "$REPO_ROOT/adapters/_framework.sh"
  run _mb_owned_unedited "$role" "$HOME/.config/opencode/.mb-global-extensions-manifest.json" "$HOME/.config/opencode"
  [ "$status" -ne 0 ]
}

@test "opencode S5: uninstall preserves modified managed files and changed symlink identity" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local rel file
  for rel in plugins/memory-bank.js commands/mb.md agent/mb-developer.md; do
    file="$PROJECT/.opencode/$rel"
    cp -p "$file" "$PROJECT/mtime"
    printf '\nUser edit\n' >> "$file"
    touch -r "$PROJECT/mtime" "$file"
    snapshot "$file" "$PROJECT/$(basename "$file").before"
  done
  printf 'User target\n' > "$PROJECT/target"
  snapshot "$PROJECT/target" "$PROJECT/target.before"
  rm "$PROJECT/.opencode/commands/start.md"
  ln -s "$PROJECT/target" "$PROJECT/.opencode/commands/start.md"
  run_adapter uninstall "$PROJECT"
  for rel in plugins/memory-bank.js commands/mb.md agent/mb-developer.md; do
    file="$PROJECT/.opencode/$rel"
    assert_unchanged "$file" "$PROJECT/$(basename "$file").before"
    assert_substring "$output" "$file"
  done
  [ -L "$PROJECT/.opencode/commands/start.md" ]
  [ "$(readlink "$PROJECT/.opencode/commands/start.md")" = "$PROJECT/target" ]
  assert_unchanged "$PROJECT/target" "$PROJECT/target.before"
  refute_file "$PROJECT/.opencode/commands/done.md"
}

@test "opencode S5: uninstall refuses hash-matched manifest paths outside root or through unsafe ancestors" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  mkdir -p "$PROJECT/outside"
  printf 'Outside-root canary\n' > "$PROJECT/outside/canary"
  snapshot "$PROJECT/outside/canary" "$PROJECT/canary.before"
  ln -s "$PROJECT/outside" "$PROJECT/.opencode/escape"
  local path
  for path in "$PROJECT/outside/canary" "$PROJECT/.opencode/escape/canary"; do
    jq --arg p "$path" --arg h "$(shasum -a 256 "$path" | cut -d' ' -f1)" \
      '.files += [$p] | .file_sha256[$p] = $h' "$PROJECT/.opencode/.mb-manifest.json" > "$PROJECT/manifest.new"
    mv "$PROJECT/manifest.new" "$PROJECT/.opencode/.mb-manifest.json"
  done
  run_adapter uninstall "$PROJECT"
  assert_unchanged "$PROJECT/outside/canary" "$PROJECT/canary.before"
  [ -L "$PROJECT/.opencode/escape" ]
  printf '%s\n' "$output" | grep -Eiq 'unsafe|outside|refus|skip'
}

@test "opencode V2: native definition registers hooks and disposes without a server" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  v2_node <<'JS'
const plugin = await loadV2();
assert(plugin.hooks.has('session.context'));
assert(plugin.hooks.has('tool.execute.before'));
await plugin.dispose();
JS
}

@test "opencode V2: parent and child get current Key rules and compact applicable RULES pointers" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  mkdir -p "$HOME/.config/opencode"
  printf '<!-- mb-key-rules:start -->\nGlobal key rule sentinel\n<!-- mb-key-rules:end -->\n' > "$HOME/.config/opencode/AGENTS.md"
  printf '\n<!-- mb-key-rules:start -->\nProject key rule sentinel\n<!-- mb-key-rules:end -->\n' >> "$PROJECT/AGENTS.md"
  printf 'Global detailed rule body must stay on disk\n%.0s' {1..1000} > "$HOME/.config/opencode/RULES.md"
  printf 'Project detailed rule body must stay on disk\n%.0s' {1..1000} > "$PROJECT/RULES.md"
  printf 'Bank detailed rule body must stay on disk\n%.0s' {1..1000} > "$PROJECT/.memory-bank/RULES.md"
  REPO_ROOT="$REPO_ROOT" v2_node <<'JS'
const plugin = await loadV2({ child: { id: 'child', parentID: 'root', location: { directory } } });
const globalAgents = path.join(process.env.HOME, '.config/opencode/AGENTS.md');
const projectAgents = path.join(directory, 'AGENTS.md');
const rules = [
  path.join(process.env.REPO_ROOT, 'rules/RULES.md'),
  path.join(process.env.HOME, '.config/opencode/RULES.md'),
  path.join(directory, 'RULES.md'),
  path.join(directory, '.memory-bank/RULES.md'),
];
async function assertContext(id, prefix = '') {
  const event = request(id);
  await plugin.hook('session.context', event);
  const text = event.system.map(p => p.text).join('\n');
  assert(text.includes(`${prefix}Global key rule sentinel`));
  assert(text.includes(`${prefix}Project key rule sentinel`));
  for (const file of rules) assert(text.includes(file), `missing applicable rules pointer: ${file}`);
  assert.doesNotMatch(text, /detailed rule body must stay on disk/);
  assert(text.length < 3000, `instruction binding must stay compact, got ${text.length} chars`);
  assert.match(text, /subagent.*agent.*description.*prompt/);
  return text;
}
for (const id of ['root', 'child']) await assertContext(id);
for (const file of [globalAgents, projectAgents]) {
  fs.writeFileSync(file, fs.readFileSync(file, 'utf8').replace(/(Global|Project) key rule sentinel/g, 'Updated $1 key rule sentinel'));
}
for (const id of ['root', 'child']) await assertContext(id, 'Updated ');
fs.unlinkSync(path.join(directory, 'RULES.md'));
const withoutRootRules = request('child');
await plugin.hook('session.context', withoutRootRules);
assert(!withoutRootRules.system.some(p => p.text.includes(path.join(directory, 'RULES.md'))), 'missing rules file must not be presented as applicable');
await plugin.dispose();
JS
}

@test "opencode V2: global roles honor XDG and never enable a global plugin" {
  export XDG_CONFIG_HOME="$SANDBOX_HOME/custom config"
  run_adapter install-global-agents "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/opencode/agent/mb-backend.md" ]
  [ -f "$XDG_CONFIG_HOME/opencode/.mb-global-extensions-manifest.json" ]
  [ ! -e "$HOME/.config/opencode/agent" ]
  [ ! -e "$XDG_CONFIG_HOME/opencode/plugins" ]
  [ ! -e "$PROJECT/.opencode" ]
}

@test "opencode V2: dangerous native shell input is blocked before execution" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  v2_node <<'JS'
const plugin = await loadV2();
await assert.rejects(plugin.hook('tool.execute.before', { tool: 'shell', input: { command: 'rm -rf /' } }), /BLOCKED/);
await plugin.hook('tool.execute.before', { tool: 'shell', input: { command: 'printf safe' } });
await plugin.dispose();
JS
}

@test "opencode V2: native no-bank requests do not initialize memory" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  rm -rf "$PROJECT/.memory-bank"
  printf '#!/usr/bin/env bash\necho invoked > "%s"\n' "$PROJECT/no-bank-summary" > "$PROJECT/summary.sh"
  export MB_SUMMARIZE_BIN="$PROJECT/summary.sh"
  v2_node <<'JS'
const plugin = await loadV2();
const event = request();
await plugin.hook('session.context', event);
await plugin.emit('session.status', { sessionID: 'root', status: { type: 'idle' } });
assert(!fs.existsSync(path.join(directory, '.memory-bank')));
assert(!fs.existsSync(path.join(directory, 'no-bank-summary')));
assert(event.system.some(p => p.text.includes('subagent(')));
await plugin.dispose();
JS
}

@test "opencode V2: installer preserves other-host resources and XDG foreign settings on reinstall" {
  opencode_frozen_bundle
  export XDG_CONFIG_HOME="$SANDBOX_HOME/config space"
  export MB_MANIFEST_PATH="$SANDBOX_HOME/install-manifest.json" MB_SKIP_DEPS_CHECK=1
  mkdir -p "$XDG_CONFIG_HOME/opencode" "$HOME/.claude" "$HOME/.codex" "$HOME/.pi/agent"
  printf 'Foreign OpenCode rules\n' > "$XDG_CONFIG_HOME/opencode/AGENTS.md"
  printf '{"plugins":["foreign-plugin"],"theme":"foreign"}\n' > "$XDG_CONFIG_HOME/opencode/opencode.json"
  echo 'Foreign Claude rules' > "$HOME/.claude/CLAUDE.md"
  echo 'Foreign Codex rules' > "$HOME/.codex/AGENTS.md"
  echo 'Foreign Pi rules' > "$HOME/.pi/agent/AGENTS.md"
  for _ in 1 2; do
    run bash "$REPO_ROOT/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
    [ "$status" -eq 0 ]
  done
  [ -f "$XDG_CONFIG_HOME/opencode/skills/memory-bank/adapters/opencode_plugin.mjs" ]
  [ ! -e "$XDG_CONFIG_HOME/opencode/plugins" ]
  grep -q 'Foreign OpenCode rules' "$XDG_CONFIG_HOME/opencode/AGENTS.md"
  grep -q 'mb-key-rules:start' "$XDG_CONFIG_HOME/opencode/AGENTS.md"
  grep -q 'subagent({agent, description, prompt' "$XDG_CONFIG_HOME/opencode/AGENTS.md"
  [ "$(grep -c 'memory-bank-opencode:start' "$XDG_CONFIG_HOME/opencode/AGENTS.md")" -eq 1 ]
  jq -e '.plugins == ["foreign-plugin"] and .theme == "foreign"' "$XDG_CONFIG_HOME/opencode/opencode.json"
  grep -q 'Foreign Claude rules' "$HOME/.claude/CLAUDE.md"
  grep -q 'Foreign Codex rules' "$HOME/.codex/AGENTS.md"
  grep -q 'Foreign Pi rules' "$HOME/.pi/agent/AGENTS.md"
  [ -f "$HOME/.claude/agents/mb-backend.md" ]
  grep -q '^model = ' "$HOME/.codex/agents/mb-backend.toml" || grep -q '^developer_instructions = ' "$HOME/.codex/agents/mb-backend.toml"
  refute_grep -q 'OpenCode 2 host binding' "$HOME/.claude/CLAUDE.md"
  refute_grep -q 'OpenCode 2 host binding' "$HOME/.codex/AGENTS.md"
  refute_grep -q 'OpenCode 2 host binding' "$HOME/.pi/agent/AGENTS.md"
}

@test "opencode V2: XDG Key rules use the new default selection in the same install" {
  opencode_frozen_bundle
  export XDG_CONFIG_HOME="$SANDBOX_HOME/config space"
  export MB_MANIFEST_PATH="$SANDBOX_HOME/install-manifest.json" MB_SKIP_DEPS_CHECK=1
  mkdir -p "$HOME/.claude"
  echo 'Foreign Claude rules' > "$HOME/.claude/CLAUDE.md"
  run bash "$REPO_ROOT/scripts/mb-rules.sh" init --scope=user --disable=testing-trophy --custom='Existing custom rule sentinel'
  [ "$status" -eq 0 ]
  grep -q 'Existing custom rule sentinel' "$HOME/.claude/memory-bank/rules-profile.json"
  refute_grep -q 'Testing Trophy:' "$HOME/.claude/CLAUDE.md"
  mkdir -p "$XDG_CONFIG_HOME/opencode"
  echo 'Foreign OpenCode rules' > "$XDG_CONFIG_HOME/opencode/AGENTS.md"

  run bash "$REPO_ROOT/install.sh" --non-interactive --clients opencode --project-root "$PROJECT" --key-rules=default
  [ "$status" -eq 0 ]
  local file
  for file in "$XDG_CONFIG_HOME/opencode/AGENTS.md" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"; do
    grep -q 'Testing Trophy:' "$file"
    refute_grep -q 'Existing custom rule sentinel' "$file"
    [ "$(grep -c 'mb-key-rules:start' "$file")" -eq 1 ]
  done
  grep -q 'Foreign OpenCode rules' "$XDG_CONFIG_HOME/opencode/AGENTS.md"
  grep -qF "$XDG_CONFIG_HOME/opencode/skills/memory-bank/rules/RULES.md" "$XDG_CONFIG_HOME/opencode/AGENTS.md"
}

@test "opencode V2: native catalogs contain exactly the shared nonpartial roles and commands" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local src role_count=0 command_count=0
  for src in "$REPO_ROOT"/agents/*.md; do
    head -5 "$src" | grep -q '^partial: true' && continue
    [ -f "$PROJECT/.opencode/agent/$(basename "$src")" ]
    role_count=$((role_count + 1))
  done
  [ "$(find "$PROJECT/.opencode/agent" -name '*.md' | wc -l | tr -d ' ')" -eq "$role_count" ]
  for src in "$REPO_ROOT"/commands/*.md; do
    cmp "$src" "$PROJECT/.opencode/commands/$(basename "$src")"
    command_count=$((command_count + 1))
  done
  jq -e --argjson count "$((role_count + command_count + 1))" '.files | length == $count' "$PROJECT/.opencode/.mb-manifest.json"
}

@test "opencode V2: upgrade strips only owned references in both config formats" {
  printf '%s\n' '{"plugin":["foreign-v1","./.opencode/plugins/memory-bank.js"],"plugins":[{"package":"foreign-v2","options":{"keep":true}},{"package":"./.opencode/plugins/memory-bank.js"}],"model":"fixture/model"}' > "$PROJECT/opencode.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  jq -e '.plugin == ["foreign-v1"] and .plugins == [{"package":"foreign-v2","options":{"keep":true}}] and .model == "fixture/model"' "$PROJECT/opencode.json"
}

@test "opencode V2: bootstrap imports bundle runtime with spaces and shell metacharacters" {
  local bundle="$SANDBOX_HOME/bundle space \$literal"
  mkdir -p "$bundle"
  cp -R "$REPO_ROOT/adapters" "$REPO_ROOT/scripts" "$REPO_ROOT/hooks" "$REPO_ROOT/rules" "$REPO_ROOT/agents" "$REPO_ROOT/commands" "$REPO_ROOT/templates" "$REPO_ROOT/memory_bank_skill" "$REPO_ROOT/references" "$bundle/"
  cp "$REPO_ROOT/VERSION" "$REPO_ROOT/SKILL.md" "$bundle/"
  ADAPTER="$bundle/adapters/opencode.sh"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  v2_node <<'JS'
const plugin = await loadV2();
await plugin.hook('session.context', request());
await plugin.dispose();
JS
}

@test "opencode V2: generated plugin and roles preserve existing modes" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  chmod 640 "$PROJECT/.opencode/plugins/memory-bank.js"
  chmod 660 "$PROJECT/.opencode/agent/mb-backend.md"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local plugin_mode role_mode
  plugin_mode=$(stat -c '%a' "$PROJECT/.opencode/plugins/memory-bank.js" 2>/dev/null || stat -f '%Lp' "$PROJECT/.opencode/plugins/memory-bank.js")
  role_mode=$(stat -c '%a' "$PROJECT/.opencode/agent/mb-backend.md" 2>/dev/null || stat -f '%Lp' "$PROJECT/.opencode/agent/mb-backend.md")
  [ "$plugin_mode" = 640 ]
  [ "$role_mode" = 660 ]
}

teardown() {
  if [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ]; then rm -rf "$PROJECT"; fi
  if [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ]; then rm -rf "$SANDBOX_HOME"; fi
}

run_adapter() {
  local raw
  raw=$(bash "$ADAPTER" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
}

assert_opencode_agent_frontmatter() {
  local f="$1"
  [ -f "$f" ]
  refute_grep -q '^tools:' "$f"
  grep -Eq '^color: "#[0-9a-fA-F]{6}"$' "$f"
  grep -q '^mode: subagent$' "$f"
  grep -q '^permission:$' "$f"
  grep -q '^  read: allow$' "$f"
}

# ═══════════════════════════════════════════════════════════════
# Install
# ═══════════════════════════════════════════════════════════════

@test "opencode: install creates AGENTS.md with memory-bank markers" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "<!-- memory-bank:start -->" "$PROJECT/AGENTS.md"
  grep -q "<!-- memory-bank:end -->" "$PROJECT/AGENTS.md"
}

@test "opencode: install relies on plugin directory auto-discovery" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.opencode/plugins/memory-bank.js" ]
  [ ! -f "$PROJECT/opencode.json" ]
}

@test "opencode: install creates a thin V2 bootstrap loading the bundle runtime" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$plugin" ]
  [ "$(wc -l < "$plugin" | tr -d ' ')" -le 5 ]
  v2_node <<'JS'
const plugin = await loadV2();
assert(plugin.hooks.has('session.compaction'));
assert(plugin.hooks.has('session.prompt'));
await plugin.dispose();
JS
}

# B4 (F-4): the plugin only wrote a placeholder progress.md entry — it never
# invoked the CC-compatible summarize capture (mb-session-end.sh, the same
# script Cursor now wires — see B4 cursor test) on session end. Functional
# test: stub the summarize hook, fire a synthetic session.idle event through
# the REAL plugin module, and assert the stub was actually invoked with the
# expected JSON payload (proves wiring, not just source-text presence).
@test "opencode: plugin invokes the session-end summarize hook on session.idle (B4)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/memory-bank-plugin-under-test.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  local marker="$PROJECT/summarize-invoked.json"
  local stub="$PROJECT/stub-summarize.sh"
  cat > "$stub" <<STUB
#!/usr/bin/env bash
cat > "$marker"
STUB
  chmod +x "$stub"

  MB_SUMMARIZE_BIN="$stub" run v2_node <<'JS'
const plugin = await loadV2();
await plugin.emit('session.status', { sessionID: 'oc-summarize-test', status: { type: 'idle' } });
await plugin.dispose();
JS
  [ "$status" -eq 0 ]

  [ -f "$marker" ]
  grep -q "oc-summarize-test" "$marker"
  grep -q "$PROJECT" "$marker"
}

@test "opencode: a native child session's idle writes no progress.md auto-capture and no summary" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/memory-bank-plugin-child.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"
  mkdir -p "$PROJECT/.memory-bank"
  printf '# Progress\n' > "$PROJECT/.memory-bank/progress.md"
  local marker="$PROJECT/summarize-child.json"
  local stub="$PROJECT/stub-summarize-child.sh"
  printf '#!/usr/bin/env bash\ncat > "%s"\n' "$marker" > "$stub"
  chmod +x "$stub"

  MB_SUMMARIZE_BIN="$stub" run v2_node <<'JS'
const plugin = await loadV2({ 'child-1': { id: 'child-1', parentID: 'parent-1', location: { directory } } });
await plugin.emit('session.created', { sessionID: 'child-1', parentID: 'parent-1', location: { directory } });
await plugin.emit('session.status', { sessionID: 'child-1', status: { type: 'idle' } });
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [ ! -f "$marker" ]
  run grep -c 'Auto-capture' "$PROJECT/.memory-bank/progress.md"
  [ "$output" = "0" ]
}

@test "opencode S5: install preserves an unmanaged plugin collision in place" {
  mkdir -p "$PROJECT/.opencode/plugins"
  cat > "$PROJECT/.opencode/plugins/memory-bank.js" <<'EOF'
// USER_CUSTOM_PLUGIN_MARKER
export const MemoryBankPlugin = async () => ({});
EOF

  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  snapshot "$plugin" "$PROJECT/plugin.before"
  run_adapter install "$PROJECT"
  assert_opencode_preserved "$plugin" "$PROJECT/plugin.before"
}

@test "opencode: install does not leave a stray tmp file after writing the plugin (A16 atomic write)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local stray
  stray=$(find "$PROJECT/.opencode/plugins" -maxdepth 1 -type f ! -name 'memory-bank.js' ! -name '*.pre-mb-backup.*' | wc -l | tr -d ' ')
  [ "$stray" -eq 0 ]
}

@test "opencode: install creates project commands for slash menu" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/.opencode/commands/mb.md" ]
  [ -f "$PROJECT/.opencode/commands/start.md" ]
  [ -f "$PROJECT/.opencode/commands/done.md" ]
}

@test "opencode S5: install preserves an unmanaged command collision in place" {
  mkdir -p "$PROJECT/.opencode/commands"
  echo "# my own mb command" > "$PROJECT/.opencode/commands/mb.md"

  local cmd="$PROJECT/.opencode/commands/mb.md"
  snapshot "$cmd" "$PROJECT/command.before"
  run_adapter install "$PROJECT"
  assert_opencode_preserved "$cmd" "$PROJECT/command.before"
}

@test "opencode: install writes manifest" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.opencode/.mb-manifest.json"
  [ -f "$m" ]
  jq -e '.schema_version == 1' "$m" >/dev/null
  jq -e '.adapter == "opencode"' "$m" >/dev/null
  jq -e '.agents_md_owned == true' "$m" >/dev/null
}

@test "opencode: install idempotent — 2x run no duplicates" {
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # Exactly one start/end marker in AGENTS.md
  local start_count end_count
  start_count=$(grep -c "memory-bank:start" "$PROJECT/AGENTS.md")
  end_count=$(grep -c "memory-bank:end" "$PROJECT/AGENTS.md")
  [ "$start_count" -eq 1 ]
  [ "$end_count" -eq 1 ]
}

@test "opencode: install preserves existing AGENTS.md user content" {
  cat > "$PROJECT/AGENTS.md" <<'EOF'
# User's AGENTS.md

Custom user instructions here.
EOF
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # User content preserved
  grep -q "Custom user instructions" "$PROJECT/AGENTS.md"
  # Our section added
  grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
  # Manifest tracks that we did NOT own the file
  jq -e '.agents_md_owned == false' "$PROJECT/.opencode/.mb-manifest.json" >/dev/null
}

@test "opencode: install removes stale legacy plugin registration" {
  cat > "$PROJECT/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["./user/my-plugin.js", "./.opencode/plugins/memory-bank.js"],
  "share": "manual"
}
EOF
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # User entries preserved, stale Memory Bank registration removed.
  jq -e '.share == "manual"' "$PROJECT/opencode.json" >/dev/null
  jq -e '.plugin | map(.) | index("./user/my-plugin.js")' "$PROJECT/opencode.json" >/dev/null
  run jq -e '.plugin | map(.) | any(contains("memory-bank"))' "$PROJECT/opencode.json"
  [ "$status" -ne 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Uninstall
# ═══════════════════════════════════════════════════════════════

@test "opencode: uninstall removes plugin file and manifest" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.opencode/plugins/memory-bank.js" ]
  [ ! -f "$PROJECT/.opencode/commands/mb.md" ]
  [ ! -f "$PROJECT/.opencode/.mb-manifest.json" ]
}

@test "opencode: uninstall deletes AGENTS.md if we created it (sole owner)" {
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/AGENTS.md" ]
}

@test "opencode: uninstall preserves AGENTS.md user content, removes our section" {
  cat > "$PROJECT/AGENTS.md" <<'EOF'
# User's AGENTS.md

Custom user instructions here.
EOF
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/AGENTS.md" ]
  grep -q "Custom user instructions" "$PROJECT/AGENTS.md"
  refute_grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
}

@test "opencode: uninstall removes our plugin from opencode.json, preserves user entries" {
  cat > "$PROJECT/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["./user/my-plugin.js", "./.opencode/plugins/memory-bank.js"],
  "share": "manual"
}
EOF
  run_adapter install "$PROJECT"
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ -f "$PROJECT/opencode.json" ]
  jq -e '.share == "manual"' "$PROJECT/opencode.json" >/dev/null
  jq -e '.plugin | map(.) | index("./user/my-plugin.js")' "$PROJECT/opencode.json" >/dev/null
  # Our plugin reference gone
  run jq -e '.plugin | map(.) | any(contains("memory-bank"))' "$PROJECT/opencode.json"
  [ "$status" -ne 0 ]
}

@test "opencode: uninstall no-op if never installed" {
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# Global storage support (Stage 3 — MB_PATH resolver-aware)
# ═══════════════════════════════════════════════════════════════

@test "opencode: plugin JS honours MB_PATH env override (resolver-aware)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$plugin" ]
  mkdir -p "$PROJECT/global-bank"
  echo '# Global progress' > "$PROJECT/global-bank/progress.md"
  MB_PATH="$PROJECT/global-bank" run v2_node <<'JS'
const plugin = await loadV2();
await plugin.emit('session.idle', { sessionID: 'override' });
await plugin.dispose();
assert.match(fs.readFileSync(path.join(directory, 'global-bank/progress.md'), 'utf8'), /Auto-capture/);
assert.doesNotMatch(fs.readFileSync(path.join(directory, '.memory-bank/progress.md'), 'utf8'), /Auto-capture/);
JS
  [ "$status" -eq 0 ]
}

@test "opencode: plugin JS falls back to local .memory-bank when MB_PATH unset" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$plugin" ]
  run v2_node <<'JS'
const plugin = await loadV2();
await plugin.emit('session.idle', { sessionID: 'localbank' });
await plugin.dispose();
assert.match(fs.readFileSync(path.join(directory, '.memory-bank/progress.md'), 'utf8'), /Auto-capture/);
JS
  [ "$status" -eq 0 ]
}

# ═══════════════════════════════════════════════════════════════
# A5 (H-3): opencode.json backup + atomic + foreign-key safety
# ═══════════════════════════════════════════════════════════════

@test "opencode: install backs up existing opencode.json and preserves foreign keys" {
  echo '{"theme":"custom","plugin":["other"]}' > "$PROJECT/opencode.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  ls "$PROJECT"/opencode.json.pre-mb-backup.* >/dev/null 2>&1
  [ "$(jq -r '.theme' "$PROJECT/opencode.json")" = "custom" ]
  jq -e '.plugin | index("other")' "$PROJECT/opencode.json" >/dev/null
}

@test "opencode: install does NOT clobber a broken opencode.json (backs up, leaves intact)" {
  printf '{ broken json' > "$PROJECT/opencode.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  ls "$PROJECT"/opencode.json.pre-mb-backup.* >/dev/null 2>&1
  grep -q "broken json" "$PROJECT/opencode.json"
}

@test "opencode: install keeps a single true-original backup (idempotent)" {
  echo '{"theme":"custom"}' > "$PROJECT/opencode.json"
  run_adapter install "$PROJECT"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  n=$(find "$PROJECT" -maxdepth 1 -type f -name 'opencode.json.pre-mb-backup.*' | wc -l | tr -d ' ')
  [ "$n" = "1" ]
}

@test "opencode: install still makes a REAL backup when a non-file matches the backup glob" {
  echo '{"theme":"x"}' > "$PROJECT/opencode.json"
  mkdir -p "$PROJECT/opencode.json.pre-mb-backup.999"   # coincidental DIR match (not an MB backup)
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  found=0
  for b in "$PROJECT"/opencode.json.pre-mb-backup.*; do
    [ -f "$b" ] && grep -q '"theme"' "$b" && found=1
  done
  [ "$found" = "1" ]
}

@test "opencode: install preserves opencode.json file mode across atomic rewrite" {
  echo '{"theme":"x"}' > "$PROJECT/opencode.json"
  chmod 664 "$PROJECT/opencode.json"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  # GNU-first: on Linux `stat -f` means --file-system and prints a whole FS dump
  # to stdout before failing, so a BSD-first chain concatenates garbage + the mode.
  m=$(stat -c '%a' "$PROJECT/opencode.json" 2>/dev/null || stat -f '%Lp' "$PROJECT/opencode.json" 2>/dev/null)
  [ "$m" = "664" ]
}

# ═══════════════════════════════════════════════════════════════
# B3 (F-3): OpenCode natively supports .opencode/agent/*.md — dispatchable
# skill role-agents (agents/*.md, partials excluded) must land there so
# OpenCode users get the same subagents Claude Code does.
# ═══════════════════════════════════════════════════════════════

@test "opencode: install copies dispatchable agents to .opencode/agent/, excludes partials" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local agent_dir="$PROJECT/.opencode/agent"
  [ -f "$agent_dir/mb-developer.md" ]
  [ -f "$agent_dir/mb-backend.md" ]
  [ -f "$agent_dir/mb-reviewer.md" ]
  # Partials (prepended by /mb work, never dispatched standalone) must be excluded.
  [ ! -f "$agent_dir/mb-engineering-core.md" ]
  [ ! -f "$agent_dir/mb-tooling-core.md" ]
  [ ! -f "$agent_dir/mb-discipline-strict.md" ]
  # At least 5 dispatchable agents installed (DoD: "≥5 others").
  local n
  n=$(find "$agent_dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  [ "$n" -ge 6 ]
  # Content body is preserved, but frontmatter is normalized to OpenCode schema.
  grep -q '^# MB Developer' "$agent_dir/mb-developer.md"
}

@test "opencode: project agents use OpenCode-valid frontmatter" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local agent_dir="$PROJECT/.opencode/agent"
  assert_opencode_agent_frontmatter "$agent_dir/mb-developer.md"
  assert_opencode_agent_frontmatter "$agent_dir/mb-reviewer-tests.md"
  grep -q '^  edit: allow$' "$agent_dir/mb-developer.md"
}

@test "opencode: agents are registered in the manifest (uninstall removes them)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$PROJECT/.opencode/.mb-manifest.json"
  jq -e --arg p "$PROJECT/.opencode/agent/mb-developer.md" \
    '.files | index($p) != null' "$m" >/dev/null
  run_adapter uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  [ ! -f "$PROJECT/.opencode/agent/mb-developer.md" ]
  [ ! -d "$PROJECT/.opencode/agent" ]
}

@test "opencode S5: install preserves an unmanaged role collision in place" {
  mkdir -p "$PROJECT/.opencode/agent"
  echo "# my custom developer agent" > "$PROJECT/.opencode/agent/mb-developer.md"
  snapshot "$PROJECT/.opencode/agent/mb-developer.md" "$PROJECT/role.before"
  run_adapter install "$PROJECT"
  assert_opencode_preserved "$PROJECT/.opencode/agent/mb-developer.md" "$PROJECT/role.before"
}

# ═══════════════════════════════════════════════════════════════
# B9 (CDX-6): plugin registration is a SINGLE contract everywhere — code (this
# adapter) and tests (above: "relies on plugin directory auto-discovery",
# "removes stale legacy plugin registration") already commit to auto-discovery
# (.opencode/plugins/*, no opencode.json ref needed). The docs must say the
# same thing, not describe a contradictory project-opencode.json registration.
# ═══════════════════════════════════════════════════════════════

@test "opencode: docs do not promise opencode.json plugin registration (B9 grep-guard)" {
  local doc="$REPO_ROOT/docs/cross-agent-setup.md"
  [ -f "$doc" ]
  run grep -q "opencode.json.*plugin reference added" "$doc"
  [ "$status" -ne 0 ]
  run grep -q "plugin reference added to \`plugin\` array" "$doc"
  [ "$status" -ne 0 ]
  grep -qi "auto-discover" "$doc"
}

# ═══════════════════════════════════════════════════════════════
# adapter-parity Task 5 (REQ-011/012/013/019/020): plugin parity extend
# (session-start context injection + per-turn capture) is gated behind
# explicit opt-in (MB_OC_PARITY_ACCEPTED=1, set by install.sh's
# mb_install_host_extensions "opencode" branch on accept — see
# install_global_extensions() below for the sibling global-agents half of
# the same accept path). A plain/declined install must keep writing the
# BASE plugin variant (byte-for-byte the pre-T5 hook surface, extended with
# only the unconditional REQ-013 update-notify + REQ-020 nudge, both of
# which are read-only/no-capture and therefore safe on every host).
# ═══════════════════════════════════════════════════════════════

@test "opencode: plain install (no accept) writes the BASE plugin variant" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q 'extended: false' "$PROJECT/.opencode/plugins/memory-bank.js"
}

@test "opencode: MB_OC_PARITY_ACCEPTED=1 install writes the EXTENDED plugin variant" {
  MB_OC_PARITY_ACCEPTED=1 run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  grep -q 'extended: true' "$PROJECT/.opencode/plugins/memory-bank.js"
}

# REQ-013/REQ-020: session-start context injection via
# experimental.chat.system.transform — renders the update-notify notice
# (delegating to hooks/mb-update-notify.sh, stubbed here via
# MB_UPDATE_NOTIFY_BIN) on the BASE variant, PLUS the REQ-020 "extensions
# not installed" nudge (silent on the extended variant — see next test).
@test "opencode: base plugin's session-start hook renders update-notify AND the REQ-020 nudge" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-base.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  local stub="$PROJECT/stub-update-notify.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
echo "[memory-bank-skill] update available: 1.0.0 -> 2.0.0"
STUB
  chmod +x "$stub"

  MB_UPDATE_NOTIFY_BIN="$stub" run v2_node <<'JS'
const plugin = await loadV2();
const out = request('sess-base');
await plugin.hook('session.context', out);
console.log(JSON.stringify(out.system));
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [[ "$output" == *"update available: 1.0.0 -> 2.0.0"* ]]
  [[ "$output" == *"--with-extensions=opencode"* ]]
}

@test "opencode: extended plugin's session-start hook renders update-notify but stays silent on the nudge" {
  MB_OC_PARITY_ACCEPTED=1 run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-ext.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  local stub="$PROJECT/stub-update-notify.sh"
  cat > "$stub" <<'STUB'
#!/usr/bin/env bash
echo "[memory-bank-skill] update available: 1.0.0 -> 2.0.0"
STUB
  chmod +x "$stub"

  MB_UPDATE_NOTIFY_BIN="$stub" run v2_node <<'JS'
const plugin = await loadV2();
const out = request('sess-ext');
await plugin.hook('session.context', out);
console.log(JSON.stringify(out.system));
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [[ "$output" == *"update available: 1.0.0 -> 2.0.0"* ]]
  [[ "$output" != *"--with-extensions=opencode"* ]]
}

# REQ-013 render is once-per-session, not once-per-LLM-call.
@test "opencode: session-start hook renders update-notify only once per sessionID" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-once.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  local counter="$PROJECT/notify-call-count"
  local stub="$PROJECT/stub-update-notify-count.sh"
  cat > "$stub" <<STUB
#!/usr/bin/env bash
echo x >> "$counter"
echo "[memory-bank-skill] update available: 1.0.0 -> 2.0.0"
STUB
  chmod +x "$stub"

  MB_UPDATE_NOTIFY_BIN="$stub" run v2_node <<'JS'
const plugin = await loadV2();
for (let i = 0; i < 3; i++) await plugin.hook('session.context', request('same-sess'));
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [ -f "$counter" ]
  local calls
  calls=$(wc -l < "$counter" | tr -d ' ')
  [ "$calls" -eq 1 ]
}

# REQ-011/REQ-007-parity: per-turn capture on the EXTENDED variant only —
# chat.message writes session/*.md with the same v2 schema fields as the
# Claude Code / Pi captures, session.idle finalizes it.
@test "opencode: extended plugin captures per-turn session/*.md (v2 schema) and finalizes on session.idle" {
  MB_OC_PARITY_ACCEPTED=1 run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-capture.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  MB_SESSION_CAPTURE=on run v2_node <<'JS'
const history = { 'sess-cap': [] };
const plugin = await loadV2({}, history);
await plugin.hook('session.prompt', { sessionID: 'sess-cap', messageID: 'm1', prompt: { text: 'hello world' } });
assert(!fs.existsSync(path.join(directory, '.memory-bank/session')), 'admission is not a completed turn');
history['sess-cap'] = [...completedTurn('m1', 'a1', 'hello world'), ...completedTurn('m2', 'a2', 'second turn')];
await plugin.emit('session.status', { sessionID: 'sess-cap', status: { type: 'idle' } });
await plugin.dispose();
JS
  [ "$status" -eq 0 ]

  local sfile
  sfile=$(find "$PROJECT/.memory-bank/session" -maxdepth 1 -type f -name '*.md' ! -name '_recent*' -print -quit)
  [ -n "$sfile" ]
  grep -q "^session_id: sess-cap$" "$sfile"
  grep -q "^agent: opencode$" "$sfile"
  grep -q "^summary_schema: v2$" "$sfile"
  grep -q "^summarized: true$" "$sfile"
  grep -q "^turns: 2$" "$sfile"
  grep -q "hello world" "$sfile"
  grep -q "second turn" "$sfile"
  grep -q "^ended:" "$sfile"
  grep -q '^### Decisions$' "$sfile"
  grep -q '^### Open questions$' "$sfile"
}

@test "opencode: base (non-extended) plugin's native prompt hook is a no-op (no capture)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-nocap.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  MB_SESSION_CAPTURE=on run v2_node <<'JS'
const plugin = await loadV2({}, { 'sess-base-nocap': completedTurn('m1', 'a1', 'hello') });
await plugin.hook('session.prompt', { sessionID: 'sess-base-nocap', messageID: 'm1', prompt: { text: 'hello' } });
await plugin.emit('session.status', { sessionID: 'sess-base-nocap', status: { type: 'idle' } });
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT/.memory-bank/session" ]
}

@test "opencode: MB_SESSION_CAPTURE=off disables per-turn capture even on the extended plugin" {
  MB_OC_PARITY_ACCEPTED=1 run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-capoff.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  MB_SESSION_CAPTURE=off run v2_node <<'JS'
const plugin = await loadV2({}, { 'sess-capoff': completedTurn('m1', 'a1', 'hello') });
await plugin.hook('session.prompt', { sessionID: 'sess-capoff', messageID: 'm1', prompt: { text: 'hello' } });
await plugin.emit('session.status', { sessionID: 'sess-capoff', status: { type: 'idle' } });
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [ ! -d "$PROJECT/.memory-bank/session" ]
}

# REQ-019: every handler this task adds must be wrapped so a throw inside it
# never breaks OpenCode's session lifecycle. Forces an internal throw by
# monkey-patching a builtin the handler depends on (Array.isArray) BEFORE
# calling it — an unguarded handler would reject the outer promise (the
# node script's own .catch prints "CRASHED" and exits 1); a properly
# fail-open handler swallows it and the script completes normally.
@test "opencode: completed capture retries after I/O failure without marking the turn processed" {
  MB_OC_PARITY_ACCEPTED=1 run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-throw1.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  echo 'not a directory' > "$PROJECT/.memory-bank/session"
  run v2_node <<'JS'
const plugin = await loadV2({}, { 'sess-throw': completedTurn('m1', 'a1', 'x') });
await plugin.hook('session.prompt', { sessionID: 'sess-throw', messageID: 'm1', prompt: { text: 'x' } });
await plugin.emit('session.status', { sessionID: 'sess-throw', status: { type: 'idle' } });
assert.equal(fs.readFileSync(path.join(directory, '.memory-bank/session'), 'utf8').trim(), 'not a directory');
fs.unlinkSync(path.join(directory, '.memory-bank/session'));
await plugin.emit('session.status', { sessionID: 'sess-throw', status: { type: 'idle' } });
const files = fs.readdirSync(path.join(directory, '.memory-bank/session')).filter(f => f.endsWith('.md') && f !== '_recent.md');
assert.equal(files.length, 1);
assert.match(fs.readFileSync(path.join(directory, '.memory-bank/session', files[0]), 'utf8'), /^turns: 1$/m);
console.log('SURVIVED');
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED"* ]]
}

@test "opencode: optional native context helpers may fail without blocking a request (REQ-019)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-throw2.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  MB_UPDATE_NOTIFY_BIN=/nonexistent MB_AGENTS_LIB=/nonexistent run v2_node <<'JS'
const plugin = await loadV2();
await plugin.hook('session.context', request('sess-throw2'));
console.log('SURVIVED');
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED"* ]]
}

# Codex review fix (major #2): the event handler's session.idle/session.deleted
# branch called appendProgress()/runSummarize() with NO try/catch —
# appendProgress uses UNGUARDED synchronous fs.readFileSync/appendFileSync,
# so a real throw there used to reject the whole async event handler and
# escape into OpenCode's session lifecycle (the one hook that was not
# fail-open like every other T5 addition). Forces a REAL throw (not a
# monkey-patch): progress.md is replaced with a DIRECTORY, so
# fs.readFileSync(progress, 'utf8') inside appendProgress hits a genuine
# EISDIR.
@test "opencode: event handler (session.idle) throw never breaks the session (REQ-019)" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-throw3.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  rm -f "$PROJECT/.memory-bank/progress.md"
  mkdir -p "$PROJECT/.memory-bank/progress.md"

  run v2_node <<'JS'
const plugin = await loadV2();
await plugin.emit('session.idle', { sessionID: 'sess-throw3' });
console.log('SURVIVED');
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED"* ]]
}

# Codex review fix (minor): notifiedSessions (once-per-session nudge dedup)
# used to be cleared ONLY inside finalizeSessionCapture, which (a) only ran
# on the extended variant and (b) early-returned before the delete when no
# per-turn capture state existed — a base-variant session (added via
# system.transform, never reaching chat.message) leaked its entry forever.
# Observable proof: on the BASE variant, render the notice for a session,
# fire session.idle for that SAME sessionID, then request the notice again
# for the same sessionID — a cleared dedup entry re-renders it; a leaked one
# would stay silent forever.
@test "opencode: session.idle clears the per-session notify dedup even on the base (non-extended) plugin" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-dedup-leak.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"

  local counter="$PROJECT/notify-call-count-leak"
  local stub="$PROJECT/stub-update-notify-leak.sh"
  cat > "$stub" <<STUB
#!/usr/bin/env bash
echo x >> "$counter"
echo "[memory-bank-skill] update available: 1.0.0 -> 2.0.0"
STUB
  chmod +x "$stub"

  MB_UPDATE_NOTIFY_BIN="$stub" run v2_node <<'JS'
const plugin = await loadV2();
await plugin.hook('session.context', request('reused-sess'));
await plugin.emit('session.idle', { sessionID: 'reused-sess' });
await plugin.hook('session.context', request('reused-sess'));
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  [ -f "$counter" ]
  local calls
  calls=$(wc -l < "$counter" | tr -d ' ')
  [ "$calls" -eq 2 ]
}

# ═══════════════════════════════════════════════════════════════
# REQ-012: global-scope agents (~/.config/opencode/agent/*.md), gated
# behind the SAME accept-only path as REQ-011 (design.md's ASCII diagram
# nests "global ~/.config/opencode/agent/*.md" under the accept branch,
# mirroring Pi's install-global-extensions). Project scope
# (.opencode/agent/, exercised by the B3 tests above) is untouched by this
# action — it never even runs a project-scope install.
# ═══════════════════════════════════════════════════════════════

@test "opencode: install-global-agents installs the non-partial roster to ~/.config/opencode/agent/" {
  run_adapter install-global-agents "$PROJECT"
  [ "$status" -eq 0 ]
  local gdir="$SANDBOX_HOME/.config/opencode/agent"
  [ -f "$gdir/mb-developer.md" ]
  [ -f "$gdir/mb-backend.md" ]
  [ -f "$gdir/mb-reviewer.md" ]
  [ ! -f "$gdir/mb-engineering-core.md" ]
  [ ! -f "$gdir/mb-tooling-core.md" ]
  [ ! -f "$gdir/mb-discipline-strict.md" ]
  grep -q '^# MB Developer' "$gdir/mb-developer.md"
  # Project scope was never touched by this global-only action.
  [ ! -d "$PROJECT/.opencode/agent" ]
}

@test "opencode: install-global-agents writes OpenCode-valid frontmatter" {
  run_adapter install-global-agents "$PROJECT"
  [ "$status" -eq 0 ]
  local gdir="$SANDBOX_HOME/.config/opencode/agent"
  assert_opencode_agent_frontmatter "$gdir/mb-developer.md"
  assert_opencode_agent_frontmatter "$gdir/mb-reviewer-tests.md"
  grep -q '^  edit: allow$' "$gdir/mb-developer.md"
}

@test "opencode: install-global-agents writes a global manifest" {
  run_adapter install-global-agents "$PROJECT"
  [ "$status" -eq 0 ]
  local m="$SANDBOX_HOME/.config/opencode/.mb-global-extensions-manifest.json"
  [ -f "$m" ]
  jq -e '.schema_version == 1' "$m" >/dev/null
  jq -e '.adapter == "opencode"' "$m" >/dev/null
  jq -e '.agents_installed > 0' "$m" >/dev/null
  # adapter-parity T7 (REQ-015/017) fix: EVERY adapter manifest must declare
  # its limits — this second (global-scope) OpenCode manifest used to omit
  # platform_limited entirely (Codex review, T7 round). Same closed-vocab
  # values + reasons as the project-scope .opencode/.mb-manifest.json (same
  # adapter source file, same genuine ceilings).
  jq -e '.platform_limited == ["statusline","role-routing"]' "$m" >/dev/null
  jq -e '.platform_limited_notes.statusline | length > 0' "$m" >/dev/null
  jq -e '.platform_limited_notes["role-routing"] | length > 0' "$m" >/dev/null
  # Every declared file genuinely exists (adapter honesty contract).
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ -f "$p" ]
  done < <(jq -r '.files[]?' "$m")
}

@test "opencode S5: global install preserves an unmanaged role collision in place" {
  mkdir -p "$SANDBOX_HOME/.config/opencode/agent"
  echo "# my custom global developer agent" > "$SANDBOX_HOME/.config/opencode/agent/mb-developer.md"
  local role="$HOME/.config/opencode/agent/mb-developer.md"
  snapshot "$role" "$PROJECT/global-role.before"
  run_adapter install-global-agents "$PROJECT"
  assert_opencode_preserved "$role" "$PROJECT/global-role.before"
}

@test "opencode: install-global-agents 2x run stays safe — same roster, live files stay fresh" {
  run_adapter install-global-agents "$PROJECT"
  [ "$status" -eq 0 ]
  local gdir="$SANDBOX_HOME/.config/opencode/agent"
  local n1
  n1=$(find "$gdir" -maxdepth 1 -type f -name '*.md' ! -name '*.pre-mb-backup.*' | wc -l | tr -d ' ')

  # _opencode_backup_once (shared with the project-scope roster loop, same
  # convention as every re-run there) backs up whatever it finds each time —
  # a 2nd run is therefore not backup-free, but MUST stay non-fatal and MUST
  # NOT change the live (non-backup) roster's file count or content.
  run_adapter install-global-agents "$PROJECT"
  [ "$status" -eq 0 ]
  local n2
  n2=$(find "$gdir" -maxdepth 1 -type f -name '*.md' ! -name '*.pre-mb-backup.*' | wc -l | tr -d ' ')
  [ "$n1" -eq "$n2" ]
  grep -q '^# MB Developer' "$gdir/mb-developer.md"
}

# ═══ Stage 4b (AGR-074): the tier model lands in the installed agents ═══

@test "opencode: install renders the project profile model into .opencode/agent (provider/id)" {
  python3 -c 'import yaml' 2>/dev/null || skip "PyYAML required"
  printf 'roles:\n  developer: {agent: mb-developer}\n  reviewer: {agent: mb-reviewer}\nmodel_profiles:\n  opencode: {premium: openai/gpt-6-astra, mid: openai/gpt-6.1-sol}\n' \
    > "$PROJECT/.memory-bank/pipeline.yaml"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  assert_substring "$(cat "$PROJECT/.opencode/agent/mb-developer.md")" $'\nmodel: openai/gpt-6.1-sol\n'
  assert_substring "$(cat "$PROJECT/.opencode/agent/mb-reviewer.md")" $'\nmodel: openai/gpt-6-astra\n'
  refute_substring "$(cat "$PROJECT/.opencode/agent/mb-doctor.md")" $'\nmodel:'
}

@test "opencode: no profile → installed agents carry no model" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  refute_substring "$(cat "$PROJECT/.opencode/agent/mb-developer.md")" $'\nmodel:'
}

@test "opencode: install uses the shared host-bound named pipeline, not legacy" {
  mkdir -p "$PROJECT/.memory-bank/pipelines"
  printf 'roles:\n  developer: {agent: mb-developer, model: legacy/model}\n' > "$PROJECT/.memory-bank/pipeline.yaml"
  printf 'agents: [opencode]\nroles:\n  developer: {agent: mb-developer, model: local/team/coder#deep}\n' > "$PROJECT/.memory-bank/pipelines/native.yaml"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  assert_substring "$(cat "$PROJECT/.opencode/agent/mb-developer.md")" $'\nmodel: local/team/coder\nvariant: "deep"\n'
  [ ! -e "$PROJECT/.memory-bank/pipelines/opencode.yaml" ]
}

@test "opencode: explicit missing pipeline refuses before publishing resources" {
  export MB_PIPELINE=missing
  run_adapter install "$PROJECT"
  [ "$status" -ne 0 ]
  [ ! -e "$PROJECT/.opencode/agent/mb-developer.md" ]
  assert_substring "$output" "named pipeline not found"
}

@test "opencode S4-HOST-5: native guards ignore an ambient foreign host but honor an explicit pipeline" {
  mkdir -p "$PROJECT/.memory-bank/pipelines"
  printf 'agents: [opencode]\nprotected_paths: [sensitive.txt]\n' > "$PROJECT/.memory-bank/pipelines/native.yaml"
  printf 'agents: [codex]\nprotected_paths: []\n' > "$PROJECT/.memory-bank/pipelines/foreign.yaml"
  export MB_PIPELINE_HOST=codex MB_OC_PARITY_ACCEPTED=1
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  v2_node <<'JS'
const plugin = await loadV2();
const event = { tool: 'write', id: 'native-policy', sessionID: 'root', input: { path: path.join(directory, 'sensitive.txt'), content: 'Must remain protected' } };
await assert.rejects(plugin.hook('tool.execute.before', event), /BLOCKED/);
assert(!fs.existsSync(event.input.path));
process.env.MB_PIPELINE = 'foreign';
await plugin.hook('tool.execute.before', { ...event, id: 'explicit-policy' });
await plugin.dispose();
JS
}

@test "opencode: render-agents re-renders installed agents from a given pipeline, no backups" {
  python3 -c 'import yaml' 2>/dev/null || skip "PyYAML required"
  run_adapter install "$PROJECT"
  printf 'roles:\n  developer: {agent: mb-developer}\nmodel_profiles:\n  opencode: {premium: a/p, mid: a/m}\n' > "$PROJECT/p.yaml"
  run_adapter render-agents "$PROJECT" "$PROJECT/p.yaml"
  [ "$status" -eq 0 ]
  assert_substring "$output" "re-rendered"
  assert_substring "$(cat "$PROJECT/.opencode/agent/mb-developer.md")" $'\nmodel: a/m\n'
  run ls "$PROJECT/.opencode/agent"
  refute_substring "$output" "pre-mb-backup"
}

# upgrade-safe-install Stage 2: the plugin's session start also surfaces the
# stale-project-blocks hint (mb_project_blocks_hint, stubbed via MB_AGENTS_LIB),
# only when the project has a bank.
@test "opencode: session-start hook renders the stale project blocks hint only with a bank" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  command -v node >/dev/null || skip "node required"

  local plugin_mjs="$PROJECT/mb-plugin-hint.mjs"
  cp "$PROJECT/.opencode/plugins/memory-bank.js" "$plugin_mjs"
  local lib="$PROJECT/stub-agents-lib.sh"
  printf '%s\n' 'mb_project_blocks_hint() { echo "[memory-bank] Outdated managed blocks in AGENTS.md"; }' > "$lib"
  mkdir -p "$PROJECT/.memory-bank"
  MB_AGENTS_LIB="$lib" MB_UPDATE_NOTIFY_BIN=/nonexistent run v2_node <<'JS'
const plugin = await loadV2();
const out = request('s-hint');
await plugin.hook('session.context', out);
console.log(JSON.stringify(out.system));
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  assert_substring "$output" "Outdated managed blocks in AGENTS.md"

  rm -rf "$PROJECT/.memory-bank"
  MB_AGENTS_LIB="$lib" MB_UPDATE_NOTIFY_BIN=/nonexistent run v2_node <<'JS'
const plugin = await loadV2();
const out = request('s-hint');
await plugin.hook('session.context', out);
console.log(JSON.stringify(out.system));
await plugin.dispose();
JS
  [ "$status" -eq 0 ]
  refute_substring "$output" "Outdated managed blocks"
}
