#!/usr/bin/env bats
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
# OpenCode plugins: TS/JS modules exporting a plugin function that returns
# hook callbacks directly. Files under .opencode/plugins/ are auto-discovered.
# Key events: session.created/idle/deleted, tool.execute.before/after,
#             experimental.session.compacting (PreCompact equivalent).

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ADAPTER="$REPO_ROOT/adapters/opencode.sh"
  PROJECT="$(mktemp -d)"
  mkdir -p "$PROJECT/.memory-bank"
  echo '# Progress' > "$PROJECT/.memory-bank/progress.md"
  command -v jq >/dev/null || skip "jq required"
}

teardown() {
  [ -n "${PROJECT:-}" ] && [ -d "$PROJECT" ] && rm -rf "$PROJECT"
}

run_adapter() {
  local raw
  raw=$(bash "$ADAPTER" "$@" 2>&1; printf '\n__EXIT__%s' "$?")
  status="${raw##*__EXIT__}"
  output="${raw%$'\n'__EXIT__*}"
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

@test "opencode: install creates plugin JS file with top-level hooks" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$plugin" ]
  # Current OpenCode plugin contract returns hook callbacks directly,
  # not nested under a stale { hooks: { ... } } wrapper.
  ! grep -q "hooks:" "$plugin"
  grep -q "event: async" "$plugin"
  # Plugin must reference key events.
  grep -q "session.idle\|session.deleted" "$plugin"
  grep -q "experimental.session.compacting\|tool.execute.before" "$plugin"
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

  run env MB_SUMMARIZE_BIN="$stub" node -e "
    import('file://$plugin_mjs').then(async (mod) => {
      const plugin = await mod.default({ directory: '$PROJECT' });
      await plugin.event({ event: { type: 'session.idle', properties: { info: { id: 'oc-summarize-test' } } } });
    }).catch((e) => { console.error(e); process.exitCode = 1; });
  "
  [ "$status" -eq 0 ]

  local i
  for i in $(seq 1 30); do
    [ -f "$marker" ] && break
    sleep 0.1
  done
  [ -f "$marker" ]
  grep -q "oc-summarize-test" "$marker"
  grep -q "$PROJECT" "$marker"
}

# A16 (M-8): plugins/memory-bank.js used to be clobbered with a plain `>`
# redirect — no backup of a user-modified copy, and non-atomic (a crash
# mid-write would leave a truncated/corrupt plugin file OpenCode then tries
# to load).
@test "opencode: install backs up an existing user-modified plugin file before overwriting (A16)" {
  mkdir -p "$PROJECT/.opencode/plugins"
  cat > "$PROJECT/.opencode/plugins/memory-bank.js" <<'EOF'
// USER_CUSTOM_PLUGIN_MARKER
export const MemoryBankPlugin = async () => ({});
EOF

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$plugin" ]
  # Freshly generated (the user's custom marker is gone from the live file)...
  ! grep -q "USER_CUSTOM_PLUGIN_MARKER" "$plugin"
  # ...but recoverable: a backup exists and holds the original content.
  local found=0
  for b in "$plugin".pre-mb-backup.*; do
    [ -f "$b" ] && grep -q "USER_CUSTOM_PLUGIN_MARKER" "$b" && found=1
  done
  [ "$found" -eq 1 ]
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

# A23 (CDX-I8): project commands are copied with a plain `cp "$f" "$COMMANDS_DIR/…"`
# — no backup, unlike the sibling agent-file copy loop right below it (which
# already calls _opencode_backup_once). A user's own same-named command file
# is silently clobbered.
@test "opencode: install backs up a pre-existing user command file with the same name (A23)" {
  mkdir -p "$PROJECT/.opencode/commands"
  echo "# my own mb command" > "$PROJECT/.opencode/commands/mb.md"

  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]

  local cmd="$PROJECT/.opencode/commands/mb.md"
  # Freshly generated (MB's own command content installed)...
  ! grep -q "my own mb command" "$cmd"
  # ...but the user's original is recoverable via a backup.
  local bk
  bk=$(ls "$cmd".pre-mb-backup.* 2>/dev/null | head -1)
  [ -n "$bk" ]
  grep -q "my own mb command" "$bk"
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
  ! jq -e '.plugin | map(.) | any(contains("memory-bank"))' "$PROJECT/opencode.json" >/dev/null
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
  ! grep -q "memory-bank:start" "$PROJECT/AGENTS.md"
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
  ! jq -e '.plugin | map(.) | any(contains("memory-bank"))' "$PROJECT/opencode.json" >/dev/null
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
  # Plugin must NOT use hard-coded path.join(app.path.cwd, '.memory-bank') as sole resolver
  ! grep -qF "path.join(app.path.cwd, '.memory-bank')" "$plugin"
  # Plugin must check MB_PATH env override
  grep -q "MB_PATH" "$plugin"
}

@test "opencode: plugin JS falls back to local .memory-bank when MB_PATH unset" {
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local plugin="$PROJECT/.opencode/plugins/memory-bank.js"
  [ -f "$plugin" ]
  # Fallback to local path must use current OpenCode plugin input.
  ! grep -q "app.path.cwd" "$plugin"
  grep -q "directory" "$plugin"
  grep -q '\.memory-bank' "$plugin"
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
  n=$(ls "$PROJECT"/opencode.json.pre-mb-backup.* 2>/dev/null | wc -l | tr -d ' ')
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
  # At least 5 dispatchable agents installed (DoD: "≥5 others").
  local n
  n=$(find "$agent_dir" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')
  [ "$n" -ge 6 ]
  # Content is copied as-is from the skill's agents/ (no rewriting).
  cmp -s "$REPO_ROOT/agents/mb-developer.md" "$agent_dir/mb-developer.md"
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

@test "opencode: install preserves an existing user agent file with the same name (backup)" {
  mkdir -p "$PROJECT/.opencode/agent"
  echo "# my custom developer agent" > "$PROJECT/.opencode/agent/mb-developer.md"
  run_adapter install "$PROJECT"
  [ "$status" -eq 0 ]
  local bk
  bk=$(ls "$PROJECT/.opencode/agent/mb-developer.md".pre-mb-backup.* 2>/dev/null | head -1)
  [ -n "$bk" ]
  grep -q "my custom developer agent" "$bk"
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
