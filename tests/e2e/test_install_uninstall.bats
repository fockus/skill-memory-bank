#!/usr/bin/env bats
# End-to-end test: install.sh → verify files → uninstall.sh → verify clean.
#
# Runs against an isolated HOME directory — does not touch the real ~/.claude/.
# Works on macOS and Linux without Docker.

load ../bats/lib/assert

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SANDBOX_HOME="$(mktemp -d)"
  export HOME="$SANDBOX_HOME"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
  export XDG_RUNTIME_DIR="$HOME/run" XDG_CONFIG_DIRS="$HOME/config-dirs" XDG_DATA_DIRS="$HOME/data-dirs"
  export CODEX_HOME="$HOME/.codex" TMPDIR="$HOME/tmp"
  mkdir -p "$TMPDIR" "$XDG_RUNTIME_DIR"
  # Per-test manifest: never the repo's own (the owner's live install manifest).
  export MB_MANIFEST_PATH="$BATS_TEST_TMPDIR/installed-manifest.json"

  # Ensure Python 3 + jq-less mode. install.sh uses python3 for manifest + merge-hooks.
  command -v python3 >/dev/null || skip "python3 not installed"
}

teardown() {
  [ -n "${SANDBOX_HOME:-}" ] && [ -d "$SANDBOX_HOME" ] && rm -rf "$SANDBOX_HOME"
}

# Exercise the real broad installer only in a private, frozen runtime bundle.
s5_private_bundle() {
  local source="$REPO_ROOT"
  REPO_ROOT="$BATS_TEST_TMPDIR/frozen-bundle"
  mkdir -p "$REPO_ROOT"
  rsync -a --exclude='.env*' --exclude='__pycache__' \
    "$source/"{adapters,agents,commands,hooks,scripts,rules,references,templates,flow-templates,settings,memory_bank_skill} \
    "$source/"{install.sh,uninstall.sh,VERSION,SKILL.md} "$REPO_ROOT/"
  PROJECT="$BATS_TEST_TMPDIR/project"
  mkdir -p "$PROJECT" "$SANDBOX_HOME/tmp" "$SANDBOX_HOME/run"
}

s5_private_command() {
  env -i PATH="$PATH" HOME="$SANDBOX_HOME" TMPDIR="$SANDBOX_HOME/tmp" \
    XDG_CONFIG_HOME="${S5_CONFIG_HOME:-$SANDBOX_HOME/.config}" \
    XDG_DATA_HOME="$SANDBOX_HOME/.local/share" XDG_STATE_HOME="$SANDBOX_HOME/.local/state" \
    XDG_CACHE_HOME="$SANDBOX_HOME/.cache" XDG_RUNTIME_DIR="$SANDBOX_HOME/run" \
    XDG_CONFIG_DIRS="$SANDBOX_HOME/config-dirs" XDG_DATA_DIRS="$SANDBOX_HOME/data-dirs" \
    CODEX_HOME="$SANDBOX_HOME/.codex" MB_MANIFEST_PATH="$MB_MANIFEST_PATH" \
    MB_SKIP_DEPS_CHECK=1 MB_USER_RULES_AUTO_PROMPT=off PYTHONDONTWRITEBYTECODE=1 \
    bash "$REPO_ROOT/$1" "${@:2}"
}

s5_record_skill_directory() {
  local root="$1" directory="$1/skills/memory-bank" proof
  proof="$(python3 "$REPO_ROOT/adapters/opencode_files.py" backup-hash "$directory" "$MB_MANIFEST_PATH" "$root")" || return 1
  jq -n --arg h "$HOME" --arg p "${PROJECT:-$PWD}" --arg f "$directory" --arg proof "$proof" \
    '{home:$h,project_root:$p,clients:[],adapters_failed:[],backups:[],files:[$f],file_sha256:{($f):$proof}}' > "$MB_MANIFEST_PATH"
}

s5_global_cleanup_fixture() {
  s5_private_bundle
  local root="$HOME/.config/opencode"
  mkdir -p "$root/agent"
  printf 'User before\n<!-- memory-bank-opencode:start -->\nManaged block\n<!-- memory-bank-opencode:end -->\n' > "$root/AGENTS.md"
  chmod 660 "$root/AGENTS.md"
  printf 'Owned role\n' > "$root/agent/owned.md"
  jq -n --arg h "$HOME" --arg p "$PROJECT" --arg f "$root/AGENTS.md" \
    '{home:$h,project_root:$p,clients:[],adapters_failed:[],files:[$f],backups:[],file_sha256:{}}' > "$MB_MANIFEST_PATH"
  jq -n --arg f "$root/agent/owned.md" --arg h "$(shasum -a 256 "$root/agent/owned.md" | cut -d' ' -f1)" \
    '{files:[$f],file_sha256:{($f):$h}}' > "$root/.mb-global-extensions-manifest.json"
  printf 'User after\n' >> "$root/AGENTS.md"
  snapshot "$root/AGENTS.md" "$BATS_TEST_TMPDIR/global-agents.before"
  snapshot "$MB_MANIFEST_PATH" "$BATS_TEST_TMPDIR/global-top.before"
  snapshot "$root/.mb-global-extensions-manifest.json" "$BATS_TEST_TMPDIR/global-extensions.before"
}

@test "OpenCode global AGENTS: unreadable merged instructions retain exact retry metadata" {
  s5_global_cleanup_fixture
  local root="$HOME/.config/opencode" first
  chmod 000 "$root/AGENTS.md"
  [ ! -r "$root/AGENTS.md" ]
  run s5_private_command uninstall.sh -y
  first="$status"
  if [ -n "${S5_EVIDENCE_DIR:-}" ]; then printf '%s\n' "$output" > "$S5_EVIDENCE_DIR/global-read-refusal.log"; fi
  chmod 660 "$root/AGENTS.md"
  [ "$first" -ne 0 ]
  assert_unchanged "$root/AGENTS.md" "$BATS_TEST_TMPDIR/global-agents.before"
  assert_unchanged "$MB_MANIFEST_PATH" "$BATS_TEST_TMPDIR/global-top.before"
  assert_unchanged "$root/.mb-global-extensions-manifest.json" "$BATS_TEST_TMPDIR/global-extensions.before"
  [ -f "$root/agent/owned.md" ]
  run s5_private_command uninstall.sh -y
  [ "$status" -eq 0 ]
  grep -qx 'User before' "$root/AGENTS.md"
  if [ -n "${S5_EVIDENCE_DIR:-}" ]; then printf '%s\n' "$output" > "$S5_EVIDENCE_DIR/global-read-retry.log"; fi
  grep -qx 'User after' "$root/AGENTS.md"
  refute_grep -q 'memory-bank-opencode:start' "$root/AGENTS.md"
  [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$root/AGENTS.md")" = 660 ]
  refute_file "$MB_MANIFEST_PATH"
}

@test "OpenCode global AGENTS: unsafe symlink preservation remains warning-only" {
  s5_global_cleanup_fixture
  local root="$HOME/.config/opencode"
  mv "$root/AGENTS.md" "$BATS_TEST_TMPDIR/foreign-agents"
  ln -s "$BATS_TEST_TMPDIR/foreign-agents" "$root/AGENTS.md"
  run s5_private_command uninstall.sh -y
  if [ -n "${S5_EVIDENCE_DIR:-}" ]; then printf '%s\n' "$output" > "$S5_EVIDENCE_DIR/global-policy-preserve.log"; fi
  [ "$status" -eq 0 ]
  [ -L "$root/AGENTS.md" ]
  assert_unchanged "$BATS_TEST_TMPDIR/foreign-agents" "$BATS_TEST_TMPDIR/global-agents.before"
  refute_file "$root/agent/owned.md"
}

@test "OpenCode global AGENTS: conditional cleanup seam propagates a real strip write failure" {
  s5_global_cleanup_fixture
  local root="$HOME/.config/opencode"
  python3 - "$root/AGENTS.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text() + 'User instruction retained.\n' * 800)
PY
  snapshot "$root/AGENTS.md" "$BATS_TEST_TMPDIR/global-agents.before"
  run python3 - "$REPO_ROOT" "$root" "$MB_MANIFEST_PATH" <<'PY'
import resource
import signal
import subprocess
import sys
def limit_child():
    resource.setrlimit(resource.RLIMIT_FSIZE, (1024, 1024))
    signal.signal(signal.SIGXFSZ, signal.SIG_DFL)
script = '''
SKILL_DIR=$1; OPENCODE_DIR=$2; MANIFEST=$3; MB_PY=python3
source "$SKILL_DIR/adapters/_framework.sh"
run_texttool() {
  PYTHONPATH="$SKILL_DIR${PYTHONPATH:+:$PYTHONPATH}" "$MB_PY" -m memory_bank_skill._texttools "$@"
}
if source "$SKILL_DIR/adapters/opencode_uninstall.sh"; then exit 0; else exit $?; fi
'''
result = subprocess.run(['bash', '-c', script, '_', *sys.argv[1:]],
                        preexec_fn=limit_child, capture_output=True, timeout=30)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
raise SystemExit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
PY
  if [ -n "${S5_EVIDENCE_DIR:-}" ]; then printf '%s\n' "$output" > "$S5_EVIDENCE_DIR/global-strip-write.log"; fi
  [ "$status" -ne 0 ]
  assert_unchanged "$root/AGENTS.md" "$BATS_TEST_TMPDIR/global-agents.before"
  assert_unchanged "$MB_MANIFEST_PATH" "$BATS_TEST_TMPDIR/global-top.before"
  assert_unchanged "$root/.mb-global-extensions-manifest.json" "$BATS_TEST_TMPDIR/global-extensions.before"
  [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$root/AGENTS.md")" = 660 ]
  run s5_private_command uninstall.sh -y
  [ "$status" -eq 0 ]
  [ "$(grep -c '^User instruction retained.$' "$root/AGENTS.md")" -eq 800 ]
  refute_grep -q 'memory-bank-opencode:start' "$root/AGENTS.md"
}

@test "install S5: pristine default-root OpenCode roundtrip removes owned artifacts without a global plugin" {
  s5_private_bundle
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  local root="$HOME/.config/opencode"
  [ -f "$root/commands/mb.md" ]
  [ -f "$PROJECT/.opencode/plugins/memory-bank.js" ]
  grep -q 'extended: false' "$PROJECT/.opencode/plugins/memory-bank.js"
  refute_file "$root/plugins"
  refute_file "$root/agent"
  python3 - "$root/skills/memory-bank" "$REPO_ROOT" <<'PY'
import os, sys
assert os.path.realpath(sys.argv[1]) == sys.argv[2]
PY
  run s5_private_command uninstall.sh -y
  [ "$status" -eq 0 ]
  refute_file "$root/commands/mb.md"
  refute_file "$root/skills/memory-bank"
  refute_file "$PROJECT/.opencode/plugins/memory-bank.js"
}

@test "install S5: global command reinstall preserves edits without advancing ownership to unwritten bytes" {
  s5_private_bundle
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  local file="$HOME/.config/opencode/commands/mb.md"
  local installed_hash
  installed_hash="$(jq -r --arg p "$file" '.file_sha256[$p]' "$MB_MANIFEST_PATH")"
  cp -p "$file" "$BATS_TEST_TMPDIR/mtime"
  printf '\nUser global command edit\n' >> "$file"
  touch -r "$BATS_TEST_TMPDIR/mtime" "$file"
  snapshot "$file" "$BATS_TEST_TMPDIR/command.before"
  local edited_hash
  edited_hash="$(shasum -a 256 "$file" | cut -d' ' -f1)"
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  assert_unchanged "$file" "$BATS_TEST_TMPDIR/command.before"
  assert_substring "$output" "$file"
  printf '%s\n' "$output" | grep -Eiq 'preserv|refus|skip|modified'
  [ "$status" -ne 0 ]
  jq -e --arg p "$file" --arg h "$edited_hash" '.file_sha256[$p] != $h' "$MB_MANIFEST_PATH"
  jq -e --arg p "$file" --arg h "$installed_hash" '.file_sha256[$p] == $h' "$MB_MANIFEST_PATH"
  run s5_private_command uninstall.sh -y
  [ "$status" -eq 0 ]
  assert_unchanged "$file" "$BATS_TEST_TMPDIR/command.before"
  refute_file "$HOME/.config/opencode/commands/start.md"
  refute_file "$PROJECT/.opencode/plugins/memory-bank.js"
}

s5_edited_global_roundtrip() {
  s5_private_bundle
  local root="${S5_CONFIG_HOME:-$HOME/.config}/opencode" host file
  mkdir -p "$root/skills/memory-bank" "$root/plugins" "$HOME/.claude" "$HOME/.codex" "$HOME/.pi/agent"
  printf 'Original local skill\n' > "$root/skills/memory-bank/SKILL.md"
  s5_record_skill_directory "$root"
  printf 'User OpenCode rules before install\n' > "$root/AGENTS.md"
  printf '{"plugins":["foreign-plugin"],"theme":"user"}\n' > "$root/opencode.json"
  printf '// Unrelated plugin\n' > "$root/plugins/user.js"
  snapshot "$root/opencode.json" "$BATS_TEST_TMPDIR/settings.before"
  snapshot "$root/plugins/user.js" "$BATS_TEST_TMPDIR/plugin.before"
  for host in .claude/CLAUDE.md .codex/AGENTS.md .pi/agent/AGENTS.md; do
    printf 'Other-host user instructions: %s\n' "$host" > "$HOME/$host"
  done
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT" --with-extensions=opencode
  [ "$status" -eq 0 ]
  [ -f "$root/agent/mb-developer.md" ]
  grep -q 'extended: true' "$PROJECT/.opencode/plugins/memory-bank.js"
  refute_file "$root/plugins/memory-bank.js"
  for file in "$root/commands/mb.md" "$root/agent/mb-developer.md"; do
    cp -p "$file" "$BATS_TEST_TMPDIR/mtime"
    printf '\nUser post-install edit\n' >> "$file"
    touch -r "$BATS_TEST_TMPDIR/mtime" "$file"
    snapshot "$file" "$BATS_TEST_TMPDIR/$(basename "$(dirname "$file")").before"
    chmod 640 "$file"
  done
  printf '\nUser OpenCode rules after install\n' >> "$root/AGENTS.md"
  chmod 640 "$root/AGENTS.md"
  printf 'User command target\n' > "$BATS_TEST_TMPDIR/target"
  snapshot "$BATS_TEST_TMPDIR/target" "$BATS_TEST_TMPDIR/target.before"
  rm "$root/commands/plan.md"
  ln -s "$BATS_TEST_TMPDIR/target" "$root/commands/plan.md"
  mkdir "$BATS_TEST_TMPDIR/user-skill"
  printf 'New user skill\n' > "$BATS_TEST_TMPDIR/user-skill/SKILL.md"
  rm "$root/skills/memory-bank"
  ln -s "$BATS_TEST_TMPDIR/user-skill" "$root/skills/memory-bank"

  run s5_private_command uninstall.sh -y
  refute_file "$root/commands/start.md"
  refute_file "$root/agent/mb-doctor.md"
  assert_unchanged "$root/commands/mb.md" "$BATS_TEST_TMPDIR/commands.before"
  assert_unchanged "$root/agent/mb-developer.md" "$BATS_TEST_TMPDIR/agent.before"
  [ -L "$root/commands/plan.md" ]
  [ "$(readlink "$root/commands/plan.md")" = "$BATS_TEST_TMPDIR/target" ]
  assert_unchanged "$BATS_TEST_TMPDIR/target" "$BATS_TEST_TMPDIR/target.before"
  [ -L "$root/skills/memory-bank" ]
  [ "$(readlink "$root/skills/memory-bank")" = "$BATS_TEST_TMPDIR/user-skill" ]
  grep -q 'New user skill' "$root/skills/memory-bank/SKILL.md"
  find "$root/.memory-bank-backups" -name SKILL.md -exec grep -l 'Original local skill' {} \; | grep -q .
  grep -q 'User OpenCode rules before install' "$root/AGENTS.md"
  grep -q 'User OpenCode rules after install' "$root/AGENTS.md"
  refute_grep -q 'memory-bank-opencode:start\|mb-key-rules:start' "$root/AGENTS.md"
  assert_unchanged "$root/opencode.json" "$BATS_TEST_TMPDIR/settings.before"
  assert_unchanged "$root/plugins/user.js" "$BATS_TEST_TMPDIR/plugin.before"
  for file in "$root/AGENTS.md" "$root/commands/mb.md" "$root/agent/mb-developer.md"; do
    [ "$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file")" = 640 ]
  done
  for host in .claude/CLAUDE.md .codex/AGENTS.md .pi/agent/AGENTS.md; do
    grep -qF "Other-host user instructions: $host" "$HOME/$host"
  done
  printf '%s\n' "$output" | grep -Eiq 'preserv|refus|skip|modified'
}

@test "OpenCode rollback: partial project refusal retains removable ownership without deleting edits" {
  s5_private_bundle
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  printf '\nUser plugin edit\n' >> "$PROJECT/.opencode/plugins/memory-bank.js"
  snapshot "$PROJECT/.opencode/plugins/memory-bank.js" "$BATS_TEST_TMPDIR/plugin.before"
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  assert_substring "$output" 'partially installed'
  run s5_private_command uninstall.sh -y
  [ "$status" -eq 0 ]
  assert_unchanged "$PROJECT/.opencode/plugins/memory-bank.js" "$BATS_TEST_TMPDIR/plugin.before"
  refute_file "$PROJECT/.opencode/commands/start.md"
}

@test "OpenCode rollback: a recreated same-target skill alias keeps its new identity" {
  s5_private_bundle
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  local alias="$HOME/.config/opencode/skills/memory-bank" target
  target="$(readlink "$alias")"
  mv "$alias" "$BATS_TEST_TMPDIR/original-alias"
  ln -s "$target" "$alias"
  run s5_private_command uninstall.sh -y
  [ "$status" -eq 0 ]
  [ -L "$alias" ]
  [ "$(readlink "$alias")" = "$target" ]
}

@test "OpenCode rollback: force does not hide a required backup-restore I/O failure" {
  s5_private_bundle
  local root="$HOME/.config/opencode" first retained=0
  mkdir -p "$root/skills/memory-bank"
  printf 'Original local skill\n' > "$root/skills/memory-bank/SKILL.md"
  s5_record_skill_directory "$root"
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  rm "$root/skills/memory-bank"
  chmod 500 "$root/skills"
  run s5_private_command uninstall.sh -y --force
  first="$status"
  [ -f "$MB_MANIFEST_PATH" ] || retained=1
  if [ -d "$root/skills" ]; then chmod 700 "$root/skills"; fi
  [ "$first" -ne 0 ]
  [ "$retained" -eq 0 ]
  run s5_private_command uninstall.sh -y
  [ "$status" -eq 0 ]
  grep -qx 'Original local skill' "$root/skills/memory-bank/SKILL.md"
}

@test "OpenCode rollback: replacing a managed skill alias with a directory is not adoption permission" {
  s5_private_bundle
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  local alias="$HOME/.config/opencode/skills/memory-bank"
  rm "$alias"
  mkdir "$alias"
  printf 'User replacement skill\n' > "$alias/SKILL.md"
  snapshot "$alias/SKILL.md" "$BATS_TEST_TMPDIR/skill.before"
  run s5_private_command install.sh --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -ne 0 ]
  [ ! -L "$alias" ]
  assert_unchanged "$alias/SKILL.md" "$BATS_TEST_TMPDIR/skill.before"
}

@test "uninstall S5: default-root lifecycle preserves edits symlinks merged instructions and backup collisions" {
  s5_edited_global_roundtrip
}

@test "uninstall S5: custom-XDG lifecycle cleans the actual install root while preserving user content" {
  S5_CONFIG_HOME="$HOME/custom config"
  s5_edited_global_roundtrip
}

# ═══════════════════════════════════════════════════════════════
# Install
# ═══════════════════════════════════════════════════════════════

@test "install: creates RULES, CLAUDE.md, commands, agents, hooks" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.claude/RULES.md" ]
  [ -f "$HOME/.claude/CLAUDE.md" ]
  [ -f "$HOME/.claude/memory-bank-config.json" ]
  [ -f "$HOME/.codex/AGENTS.md" ]
  [ -f "$HOME/.config/opencode/AGENTS.md" ]
  [ -f "$HOME/.pi/agent/AGENTS.md" ]
  [ -d "$HOME/.claude/commands" ]
  [ -d "$HOME/.config/opencode/commands" ]
  [ -d "$HOME/.claude/agents" ]
  [ -d "$HOME/.claude/hooks" ]
  [ -L "$HOME/.claude/skills/skill-memory-bank" ]
  [ -L "$HOME/.claude/skills/memory-bank" ]
  [ -L "$HOME/.codex/skills/memory-bank" ]
  [ -L "$HOME/.pi/agent/skills/memory-bank" ]
}

@test "install: creates Pi global skill, AGENTS.md, and prompt templates" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -L "$HOME/.pi/agent/skills/memory-bank" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/SKILL.md" ]
  [ -f "$HOME/.pi/agent/AGENTS.md" ]
  grep -q "<!-- memory-bank-pi:start -->" "$HOME/.pi/agent/AGENTS.md"
  grep -q "<!-- memory-bank-pi:end -->" "$HOME/.pi/agent/AGENTS.md"
  grep -q "~/.pi/agent/skills/memory-bank/SKILL.md" "$HOME/.pi/agent/AGENTS.md"
  [ -f "$HOME/.pi/agent/prompts/mb.md" ]
  [ -f "$HOME/.pi/agent/prompts/start.md" ]
  [ -f "$HOME/.pi/agent/prompts/done.md" ]
  [ -f "$HOME/.pi/agent/prompts/plan.md" ]
}

@test "install: backs up existing Pi skill outside skill discovery directory" {
  mkdir -p "$HOME/.pi/agent/skills/memory-bank"
  cat > "$HOME/.pi/agent/skills/memory-bank/SKILL.md" <<'EOF'
---
name: memory-bank
---
# old local Pi skill
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -L "$HOME/.pi/agent/skills/memory-bank" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/SKILL.md" ]
  [ -d "$HOME/.pi/agent/.memory-bank-backups" ]
  find "$HOME/.pi/agent/.memory-bank-backups" -maxdepth 2 -name SKILL.md | grep -q .
  ! find "$HOME/.pi/agent/skills" -maxdepth 2 -path '*pre-mb-backup*' -name SKILL.md | grep -q .
}

@test "install: backs up existing OpenCode skill outside skill discovery directory" {
  mkdir -p "$HOME/.config/opencode/skills/memory-bank"
  cat > "$HOME/.config/opencode/skills/memory-bank/SKILL.md" <<'EOF'
---
name: memory-bank
---
# old local OpenCode skill
EOF

  s5_record_skill_directory "$HOME/.config/opencode"

  bash "$REPO_ROOT/install.sh" --clients opencode --non-interactive >/dev/null

  [ -L "$HOME/.config/opencode/skills/memory-bank" ]
  [ -f "$HOME/.config/opencode/skills/memory-bank/SKILL.md" ]
  [ -d "$HOME/.config/opencode/.memory-bank-backups" ]
  find "$HOME/.config/opencode/.memory-bank-backups" -maxdepth 2 -name SKILL.md | grep -q .
  ! find "$HOME/.config/opencode/skills" -maxdepth 2 -path '*pre-mb-backup*' -name SKILL.md | grep -q .
}

@test "install: quarantines legacy ~/.opencode memory-bank backup skills outside discovery" {
  mkdir -p "$HOME/.opencode/skills/memory-bank.backup.20200101-000000"
  cat > "$HOME/.opencode/skills/memory-bank.backup.20200101-000000/SKILL.md" <<'EOF'
---
name: memory-bank
---
# stale legacy OpenCode backup skill
EOF

  bash "$REPO_ROOT/install.sh" --clients opencode --non-interactive >/dev/null

  [ ! -d "$HOME/.opencode/skills/memory-bank.backup.20200101-000000" ]
  [ -f "$HOME/.opencode/.memory-bank-backups/memory-bank.backup.20200101-000000/SKILL.md" ]
  ! find "$HOME/.opencode/skills" -maxdepth 2 -path '*memory-bank.backup*' -name SKILL.md | grep -q .
}

@test "install: quarantines legacy ~/.opencode managed plugin outside auto-discovery" {
  mkdir -p "$HOME/.opencode/plugins"
  cat > "$HOME/.opencode/plugins/memory-bank.js" <<'EOF'
// Memory Bank — OpenCode plugin
// memory-bank: managed plugin (do not remove marker line)
export default { id: 'memory-bank', async setup() {} };
EOF

  bash "$REPO_ROOT/install.sh" --clients opencode --non-interactive >/dev/null

  [ ! -f "$HOME/.opencode/plugins/memory-bank.js" ]
  [ -d "$HOME/.opencode/.memory-bank-backups/plugins" ]
  find "$HOME/.opencode/.memory-bank-backups/plugins" -maxdepth 1 -name 'memory-bank.js.pre-mb-backup.*' | grep -q .
  ! find "$HOME/.opencode/plugins" -maxdepth 1 -name 'memory-bank.js' | grep -q .
}

@test "install: default language is English in installed rules and config" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  grep -q '1. \*\*Language\*\*: English — responses and code comments' "$HOME/.claude/RULES.md"
  grep -q '\*\*Language\*\* — respond in English; technical terms may remain in English\.' "$HOME/.claude/CLAUDE.md"
  grep -q '"preferred_language": "en"' "$HOME/.claude/memory-bank-config.json"
}

@test "install: --language ru localizes global rules and settings" {
  bash "$REPO_ROOT/install.sh" --language ru >/dev/null

  grep -q '1. \*\*Language\*\*: Russian — responses and code comments' "$HOME/.claude/RULES.md"
  grep -q '\*\*Language\*\* — respond in Russian; technical terms may remain in English\.' "$HOME/.claude/CLAUDE.md"
  grep -q '"preferred_language": "ru"' "$HOME/.claude/memory-bank-config.json"
}

@test "install: copies expected commands" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  # Key commands must exist
  [ -f "$HOME/.claude/commands/mb.md" ]
  [ -f "$HOME/.config/opencode/commands/mb.md" ]
  [ -f "$HOME/.pi/agent/prompts/mb.md" ]
  [ -f "$HOME/.claude/commands/commit.md" ]
  [ -f "$HOME/.claude/commands/review.md" ]
  [ -f "$HOME/.claude/commands/plan.md" ]
  # Setup-project removed in v2
  [ ! -f "$HOME/.claude/commands/setup-project.md" ]
}

@test "install: copies 4 MB-native agents" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.claude/agents/mb-manager.md" ]
  [ -f "$HOME/.claude/agents/mb-doctor.md" ]
  [ -f "$HOME/.claude/agents/plan-verifier.md" ]
  [ -f "$HOME/.claude/agents/mb-codebase-mapper.md" ]
  # Orphan agent must be gone
  [ ! -f "$HOME/.claude/agents/codebase-mapper.md" ]
}

@test "install: creates settings.json with MB hooks" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.claude/settings.json" ]
  grep -q "memory-bank-skill" "$HOME/.claude/settings.json"
}

@test "install: skill scripts are executable" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  for s in mb-context.sh mb-metrics.sh mb-plan.sh mb-plan-sync.sh mb-plan-done.sh _lib.sh; do
    [ -x "$HOME/.claude/skills/memory-bank/scripts/$s" ]
  done
}

@test "install: v3.1 scripts are executable (idea, idea-promote, adr, migrate-structure)" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  for s in mb-idea.sh mb-idea-promote.sh mb-adr.sh mb-migrate-structure.sh mb-compact.sh; do
    [ -x "$HOME/.claude/skills/memory-bank/scripts/$s" ]
  done
}

@test "install: skill bundle is complete for Claude and Codex aliases" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  [ -f "$HOME/.claude/skills/memory-bank/SKILL.md" ]
  [ -d "$HOME/.claude/skills/memory-bank/commands" ]
  [ -d "$HOME/.claude/skills/memory-bank/agents" ]
  [ -d "$HOME/.claude/skills/memory-bank/hooks" ]
  [ -d "$HOME/.claude/skills/memory-bank/scripts" ]
  [ -d "$HOME/.claude/skills/memory-bank/references" ]
  [ -d "$HOME/.claude/skills/memory-bank/rules" ]
  [ -f "$HOME/.claude/skills/memory-bank/commands/mb.md" ]
  [ -f "$HOME/.claude/skills/memory-bank/agents/mb-manager.md" ]
  [ -f "$HOME/.claude/skills/memory-bank/hooks/session-end-autosave.sh" ]
  [ -f "$HOME/.codex/skills/memory-bank/commands/mb.md" ]
  [ -f "$HOME/.codex/skills/memory-bank/agents/mb-manager.md" ]
  [ -f "$HOME/.codex/skills/memory-bank/hooks/session-end-autosave.sh" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/commands/mb.md" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/agents/mb-manager.md" ]
  [ -f "$HOME/.pi/agent/skills/memory-bank/hooks/session-end-autosave.sh" ]
}

@test "install: ships the /mb team bundle; uninstall removes it" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  skill="$HOME/.claude/skills/memory-bank"
  for s in mb-team.sh mb-team-review.sh mb-team-checkpoint.sh mb-lock.sh mb_vcs.sh; do
    [ -x "$skill/scripts/$s" ]
  done
  for m in mb_team_config mb_team_ops mb_team_pipeline mb_team_render mb_team_review \
    mb_team_review_core mb_team_review_external mb_team_state mb_team_status mb_team_tracks \
    mb_team_vocab mb_lock_queue mb_lock_resource mb_pipeline_validate_team; do
    [ -f "$skill/scripts/$m.py" ]
  done
  for t in brief track-prompt external-review; do
    [ -f "$skill/templates/team/$t.md" ]
  done
  [ -f "$HOME/.claude/commands/team.md" ]
  [ -f "$HOME/.codex/prompts/team.md" ]

  bash "$REPO_ROOT/uninstall.sh" -y >/dev/null
  [ ! -e "$skill/scripts/mb-team.sh" ]
  [ ! -e "$skill/scripts/mb-lock.sh" ]
  [ ! -e "$skill/templates/team/brief.md" ]
  [ ! -e "$HOME/.claude/commands/team.md" ]
  [ ! -e "$HOME/.codex/prompts/team.md" ]
}

@test "install: Claude and Codex aliases resolve to canonical skill path" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  claude_canonical="$(python3 -c 'import os; print(os.path.realpath("'"$HOME"'/.claude/skills/skill-memory-bank"))')"
  claude_alias="$(python3 -c 'import os; print(os.path.realpath("'"$HOME"'/.claude/skills/memory-bank"))')"
  codex_alias="$(python3 -c 'import os; print(os.path.realpath("'"$HOME"'/.codex/skills/memory-bank"))')"

  [ "$claude_canonical" = "$REPO_ROOT" ]
  [ "$claude_alias" = "$claude_canonical" ]
  [ "$codex_alias" = "$claude_canonical" ]
}

@test "install: CLAUDE.md has MEMORY-BANK-SKILL marker" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  grep -q "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
}

@test "install: OpenCode AGENTS.md has memory-bank markers" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  grep -q "<!-- memory-bank-opencode:start -->" "$HOME/.config/opencode/AGENTS.md"
  grep -q "<!-- memory-bank-opencode:end -->" "$HOME/.config/opencode/AGENTS.md"
}

@test "install: Codex AGENTS.md has managed memory-bank block" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  grep -q "<!-- memory-bank-codex:start -->" "$HOME/.codex/AGENTS.md"
  grep -q "<!-- memory-bank-codex:end -->" "$HOME/.codex/AGENTS.md"
  grep -q "~/.codex/skills/memory-bank/SKILL.md" "$HOME/.codex/AGENTS.md"
}

@test "install: Pi AGENTS.md is localized with --language ru" {
  bash "$REPO_ROOT/install.sh" --language ru >/dev/null
  grep -q "<!-- memory-bank-pi:start -->" "$HOME/.pi/agent/AGENTS.md"
  grep -q '\*\*Language\*\* — respond in Russian; technical terms may remain in English\.' "$HOME/.pi/agent/AGENTS.md"
}

@test "install: writes manifest" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  [ -f "$MB_MANIFEST_PATH" ]
  python3 -c "import json; json.load(open('$MB_MANIFEST_PATH'))"
}

@test "install: manifest has schema_version=1" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  [ -f "$MB_MANIFEST_PATH" ]
  python3 - <<PY
import json

data = json.load(open("$MB_MANIFEST_PATH"))
assert data["schema_version"] == 1
PY
}

@test "install: global manifest does not own Cursor global files" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  python3 - <<PY
import json

data = json.load(open("$MB_MANIFEST_PATH"))
files = data["files"]
assert all("/.cursor/AGENTS.md" not in f for f in files)
assert all("/.cursor/hooks.json" not in f for f in files)
assert all("/.cursor/memory-bank-user-rules.md" not in f for f in files)
assert all("/.cursor/commands/mb.md" not in f for f in files)
assert any("/.pi/agent/prompts/mb.md" in f for f in files)
assert any("/.pi/agent/skills/memory-bank" in f for f in files)
PY
}

@test "install: refuses unsafe symlink target outside managed dirs" {
  mkdir -p "$HOME/.claude" "$HOME/outside"
  echo "keep me" > "$HOME/outside/victim.txt"
  ln -s "$HOME/outside/victim.txt" "$HOME/.claude/RULES.md"

  run bash "$REPO_ROOT/install.sh"
  [ "$status" -ne 0 ]
  grep -q "keep me" "$HOME/outside/victim.txt"
}

@test "install: idempotent — two runs yield no duplicate CLAUDE.md sections" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  count=$(grep -c "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md")
  [ "$count" -eq 1 ]
  python3 - <<PY
from pathlib import Path
text = Path('$HOME/.claude/CLAUDE.md').read_text(encoding='utf-8')
# The Key rules block (mb-rules.sh sync --scope=user) comes first, once.
assert text.startswith('<!-- mb-key-rules:start -->') and text.count('<!-- mb-key-rules:start -->') == 1
assert text.split('<!-- mb-key-rules:end -->\n', 1)[1].lstrip('\n').startswith('# [MEMORY-BANK-SKILL]')
PY
}

@test "install: idempotent — two runs yield no duplicate Pi sections or leading blanks" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  count=$(grep -c "memory-bank-pi:start" "$HOME/.pi/agent/AGENTS.md")
  [ "$count" -eq 1 ]
  python3 - <<PY
from pathlib import Path
text = Path('$HOME/.pi/agent/AGENTS.md').read_text(encoding='utf-8')
# The Key rules block (mb-rules.sh sync --scope=user) comes first, once.
assert text.startswith('<!-- mb-key-rules:start -->') and text.count('<!-- mb-key-rules:start -->') == 1
assert text.split('<!-- mb-key-rules:end -->\n', 1)[1].lstrip('\n').startswith('<!-- memory-bank-pi:start -->')
PY
}

@test "install: idempotent — settings.json has no duplicate hooks" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  # Each skill hook command should appear exactly once
  block_count=$(grep -c "block-dangerous.sh" "$HOME/.claude/settings.json")
  [ "$block_count" -eq 1 ]
}

@test "install: SessionEnd auto-capture hook registered and executable" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  # Hook copied
  [ -x "$HOME/.claude/hooks/session-end-autosave.sh" ]

  # Event is registered in settings.json
  grep -q "SessionEnd" "$HOME/.claude/settings.json"
  grep -q "session-end-autosave.sh" "$HOME/.claude/settings.json"
}

@test "install: SessionEnd idempotent — two runs = one entry" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  bash "$REPO_ROOT/install.sh" >/dev/null

  count=$(grep -c "session-end-autosave.sh" "$HOME/.claude/settings.json")
  [ "$count" -eq 1 ]
}

# ═══════════════════════════════════════════════════════════════
# Uninstall roundtrip
# ═══════════════════════════════════════════════════════════════

@test "uninstall: removes installed files" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.claude/RULES.md" ]
  [ ! -f "$HOME/.claude/commands/mb.md" ]
  [ ! -f "$HOME/.config/opencode/commands/mb.md" ]
  [ ! -f "$HOME/.claude/agents/mb-manager.md" ]
  [ ! -f "$HOME/.claude/hooks/block-dangerous.sh" ]
  [ ! -f "$HOME/.claude/hooks/session-end-autosave.sh" ]
  [ ! -e "$HOME/.claude/skills/skill-memory-bank" ]
  [ ! -e "$HOME/.claude/skills/memory-bank" ]
  [ ! -e "$HOME/.codex/skills/memory-bank" ]
  [ ! -e "$HOME/.pi/agent/skills/memory-bank" ]
  [ ! -f "$HOME/.pi/agent/prompts/mb.md" ]
}

@test "uninstall: calls per-adapter uninstall for install-time --clients (A10 refcount decrement)" {
  command -v jq >/dev/null || skip "jq required"
  PROJECT="$(mktemp -d)"

  bash "$REPO_ROOT/install.sh" --clients codex,opencode --project-root "$PROJECT" --non-interactive >/dev/null

  [ -f "$PROJECT/AGENTS.md" ]
  [ -f "$PROJECT/.opencode/commands/mb.md" ]
  [ -f "$PROJECT/.codex/config.toml" ]
  jq -e '.owners | contains(["opencode","codex"])' "$PROJECT/.mb-agents-owners.json" >/dev/null

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$PROJECT/.opencode/commands/mb.md" ]
  [ ! -f "$PROJECT/.codex/config.toml" ]
  # Both clients uninstalled → refcount reaches 0 → owners file + shared section removed.
  [ ! -f "$PROJECT/.mb-agents-owners.json" ]
  [ ! -f "$PROJECT/AGENTS.md" ]

  rm -rf "$PROJECT"
}

@test "uninstall: -y removes installed files without stdin prompt" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  run bash "$REPO_ROOT/uninstall.sh" -y

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/RULES.md" ]
  [ ! -e "$HOME/.claude/skills/memory-bank" ]
  [ ! -e "$HOME/.pi/agent/skills/memory-bank" ]
}

@test "uninstall: skips poisoned manifest paths outside managed dirs" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  mkdir -p "$HOME/victim-dir"
  echo "do not delete" > "$HOME/victim-dir/keep.txt"

  python3 - <<PY
import json
from pathlib import Path

manifest = Path("$MB_MANIFEST_PATH")
data = json.loads(manifest.read_text())
data["files"].append("$HOME/.claude/../victim-dir")
manifest.write_text(json.dumps(data, indent=2))
PY

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -d "$HOME/victim-dir" ]
  [ -f "$HOME/victim-dir/keep.txt" ]
}

@test "uninstall: removes Cursor global files even if global manifest lacks them" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  python3 - <<PY
import json
from pathlib import Path

manifest = Path("$MB_MANIFEST_PATH")
data = json.loads(manifest.read_text())
data["files"] = [
    f for f in data["files"]
    if "/.cursor/" not in f
]
manifest.write_text(json.dumps(data, indent=2))
PY

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.cursor/hooks.json" ]
  [ ! -f "$HOME/.cursor/AGENTS.md" ]
  [ ! -f "$HOME/.cursor/memory-bank-user-rules.md" ]
  [ ! -f "$HOME/.cursor/commands/mb.md" ]
  [ ! -f "$HOME/.cursor/.mb-manifest.json" ]
}

@test "uninstall: SessionEnd hook removed from settings.json" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  if [ -f "$HOME/.claude/settings.json" ]; then
    refute_grep -q "session-end-autosave.sh" "$HOME/.claude/settings.json"
  fi
}

@test "uninstall: strips MB hooks from settings.json" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  # settings.json may still exist, but must not contain memory-bank-skill markers
  if [ -f "$HOME/.claude/settings.json" ]; then
    refute_grep -q "memory-bank-skill" "$HOME/.claude/settings.json"
  fi
}

# I-147: these three assertions were CONDITIONALLY VACUOUS. With an empty
# sandbox HOME, install created a file containing ONLY our managed section and
# uninstall then removed the whole file — so `if [ -f ... ]` was false and the
# assertion inside never executed. The test passed identically with the
# assertion inverted, i.e. it proved nothing about the behaviour in its name.
# Seeding the user's own content makes the file survive, so the strip is
# actually exercised — and adds the half that matters more: the user's content
# must still be there afterwards.
@test "uninstall: strips Codex managed section from AGENTS.md, keeping user content" {
  mkdir -p "$HOME/.codex"
  printf '# my codex rules\nUSER_CODEX_CONTENT\n' > "$HOME/.codex/AGENTS.md"

  bash "$REPO_ROOT/install.sh" >/dev/null
  assert_grep -q "memory-bank-codex:start" "$HOME/.codex/AGENTS.md"
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -f "$HOME/.codex/AGENTS.md" ]
  refute_grep -q "memory-bank-codex:start" "$HOME/.codex/AGENTS.md"
  assert_grep -q "USER_CODEX_CONTENT" "$HOME/.codex/AGENTS.md"
}

@test "uninstall: strips Pi managed section from AGENTS.md and removes prompts" {
  mkdir -p "$HOME/.pi/agent"
  printf '# my pi rules\nUSER_PI_CONTENT\n' > "$HOME/.pi/agent/AGENTS.md"

  bash "$REPO_ROOT/install.sh" >/dev/null
  assert_grep -q "memory-bank-pi:start" "$HOME/.pi/agent/AGENTS.md"
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.pi/agent/prompts/mb.md" ]
  [ -f "$HOME/.pi/agent/AGENTS.md" ]
  refute_grep -q "memory-bank-pi:start" "$HOME/.pi/agent/AGENTS.md"
  assert_grep -q "USER_PI_CONTENT" "$HOME/.pi/agent/AGENTS.md"
}

@test "uninstall: restores pre-existing Pi skill from hidden backup" {
  mkdir -p "$HOME/.pi/agent/skills/memory-bank"
  cat > "$HOME/.pi/agent/skills/memory-bank/SKILL.md" <<'EOF'
---
name: memory-bank
---
# old local Pi skill
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -d "$HOME/.pi/agent/skills/memory-bank" ]
  [ ! -L "$HOME/.pi/agent/skills/memory-bank" ]
  grep -q "old local Pi skill" "$HOME/.pi/agent/skills/memory-bank/SKILL.md"
  [ ! -d "$HOME/.pi/agent/.memory-bank-backups" ]
}

@test "uninstall: strips MEMORY-BANK-SKILL section from CLAUDE.md, keeping user content" {
  mkdir -p "$HOME/.claude"
  printf '# my claude rules\nUSER_CLAUDE_CONTENT\n' > "$HOME/.claude/CLAUDE.md"

  bash "$REPO_ROOT/install.sh" >/dev/null
  assert_grep -q "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -f "$HOME/.claude/CLAUDE.md" ]
  refute_grep -q "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
  assert_grep -q "USER_CLAUDE_CONTENT" "$HOME/.claude/CLAUDE.md"
}

@test "uninstall: preserves user CLAUDE.md content above skill section" {
  # User has their own CLAUDE.md before install
  mkdir -p "$HOME/.claude"
  echo "# User's own preferences" > "$HOME/.claude/CLAUDE.md"
  echo "Important project rules" >> "$HOME/.claude/CLAUDE.md"

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "User's own preferences" "$HOME/.claude/CLAUDE.md"
  grep -q "Important project rules" "$HOME/.claude/CLAUDE.md"
}

@test "uninstall: preserves CLAUDE.md edits the user made AFTER install (A20 / CDX-I9)" {
  # Regression for CDX-I9: a backup only gets recorded when CLAUDE.md already
  # existed pre-install (backup_if_exists is a no-op otherwise) — this is the
  # scenario where uninstall.sh used to `mv` that PRE-install backup straight
  # back over CLAUDE.md, discarding both the pre-existing content AND anything
  # the user added after install ran. The managed block must instead be
  # stripped surgically (paired A13 markers), leaving everything else intact.
  mkdir -p "$HOME/.claude"
  echo "# Pre-existing user content" > "$HOME/.claude/CLAUDE.md"

  bash "$REPO_ROOT/install.sh" >/dev/null

  echo "" >> "$HOME/.claude/CLAUDE.md"
  echo "USER_POST_INSTALL_EDIT: keep me" >> "$HOME/.claude/CLAUDE.md"

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ -f "$HOME/.claude/CLAUDE.md" ]
  grep -q "Pre-existing user content" "$HOME/.claude/CLAUDE.md"
  grep -q "USER_POST_INSTALL_EDIT: keep me" "$HOME/.claude/CLAUDE.md"
  ! grep -q "\[MEMORY-BANK-SKILL\]" "$HOME/.claude/CLAUDE.md"
}

@test "uninstall: preserves user OpenCode AGENTS.md content above skill section" {
  mkdir -p "$HOME/.config/opencode"
  cat > "$HOME/.config/opencode/AGENTS.md" <<'EOF'
# User OpenCode rules

Keep answers concise.
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "User OpenCode rules" "$HOME/.config/opencode/AGENTS.md"
  grep -q "Keep answers concise" "$HOME/.config/opencode/AGENTS.md"
  refute_grep -q "memory-bank-opencode:start" "$HOME/.config/opencode/AGENTS.md"
  refute_grep -q "memory-bank:start" "$HOME/.config/opencode/AGENTS.md"
}

@test "uninstall: preserves user Codex AGENTS.md content above skill section" {
  mkdir -p "$HOME/.codex"
  cat > "$HOME/.codex/AGENTS.md" <<'EOF'
# User Codex rules

Respect existing workflows.
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "User Codex rules" "$HOME/.codex/AGENTS.md"
  grep -q "Respect existing workflows." "$HOME/.codex/AGENTS.md"
  ! grep -q "memory-bank-codex:start" "$HOME/.codex/AGENTS.md"
}

@test "uninstall: preserves user Pi AGENTS.md content above skill section" {
  mkdir -p "$HOME/.pi/agent"
  cat > "$HOME/.pi/agent/AGENTS.md" <<'EOF'
# User Pi rules

Keep Pi concise.
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  grep -q "User Pi rules" "$HOME/.pi/agent/AGENTS.md"
  grep -q "Keep Pi concise." "$HOME/.pi/agent/AGENTS.md"
  ! grep -q "memory-bank-pi:start" "$HOME/.pi/agent/AGENTS.md"
}

@test "uninstall: preserves user hooks in settings.json" {
  # User has their own settings before install
  mkdir -p "$HOME/.claude"
  cat > "$HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit", "hooks": [{"type": "command", "command": "echo user-edit-hook"}]}
    ]
  }
}
EOF

  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  # User hook survives both install and uninstall
  grep -q "user-edit-hook" "$HOME/.claude/settings.json"
}

@test "uninstall: removes manifest after cleanup" {
  bash "$REPO_ROOT/install.sh" >/dev/null
  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$MB_MANIFEST_PATH" ]
}

# ═══════════════════════════════════════════════════════════════
# A22 (CDX-I11): fail loudly on a corrupt manifest instead of
# silently treating it as empty (uninstall.sh used to `|| true` past a
# JSON-parse failure and just... remove nothing).
# ═══════════════════════════════════════════════════════════════

@test "uninstall: exits nonzero on a corrupt manifest without --force" {
  export MB_MANIFEST_PATH="$HOME/.mb-a22-corrupt-manifest.json"
  printf '{"schema_version": 1, "files": [' > "$MB_MANIFEST_PATH"   # truncated JSON

  run bash "$REPO_ROOT/uninstall.sh" -y
  [ "$status" -ne 0 ]
  [[ "$output" == *"corrupt"* ]] || [[ "$output" == *"invalid"* ]]
  # It must not have been silently treated as an empty/no-op manifest.
  [ -f "$MB_MANIFEST_PATH" ]
}

@test "uninstall: --force proceeds past a corrupt manifest" {
  export MB_MANIFEST_PATH="$HOME/.mb-a22-corrupt-manifest-force.json"
  printf '{"schema_version": 1, "files": [' > "$MB_MANIFEST_PATH"   # truncated JSON

  run bash "$REPO_ROOT/uninstall.sh" -y --force
  [ "$status" -eq 0 ]
}

@test "uninstall: no-tty without -y exits nonzero with a hint instead of hanging (A24)" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  run bash "$REPO_ROOT/uninstall.sh" < /dev/null

  [ "$status" -ne 0 ]
  [[ "$output" == *"-y"* ]]
  # Files must still be present — no half-applied removal happened.
  [ -f "$HOME/.claude/RULES.md" ]
}

@test "uninstall: -y still works with no tty on stdin (A24)" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  run bash "$REPO_ROOT/uninstall.sh" -y < /dev/null

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/RULES.md" ]
}

@test "uninstall: pipe with real y answers the prompt normally (A24 no regression)" {
  bash "$REPO_ROOT/install.sh" >/dev/null

  echo "y" | bash "$REPO_ROOT/uninstall.sh" >/dev/null

  [ ! -f "$HOME/.claude/RULES.md" ]
}

# ═══════════════════════════════════════════════════════════════
# A6 (H-4): backup rotation preserves the user's TRUE original
# A7 (H-5): incremental/trap manifest survives partial failure
# ═══════════════════════════════════════════════════════════════

@test "install: upgrade preserves the user's TRUE original backup across two installs (A6)" {
  mkdir -p "$HOME/.claude"
  printf 'USER_RULES_ORIGINAL\n' > "$HOME/.claude/RULES.md"
  bash "$REPO_ROOT/install.sh" >/dev/null 2>&1            # #1: backs up user RULES.md → T1 (true original)
  printf '\nlocal_edit\n' >> "$HOME/.claude/RULES.md"     # make the installed file differ so #2 re-backs-up
  bash "$REPO_ROOT/install.sh" >/dev/null 2>&1            # #2: rotation must NOT delete the true original
  found=0
  for b in "$HOME/.claude/RULES.md.pre-mb-backup."*; do
    [ -f "$b" ] && grep -q "USER_RULES_ORIGINAL" "$b" && found=1
  done
  [ "$found" = "1" ]
}

@test "install: partial failure still writes a manifest for rollback (A7 trap flush)" {
  mkdir -p "$HOME/.claude"
  : > "$HOME/.claude/agents"          # poison Step 2: mkdir .claude/agents/ fails mid-install
  export MB_MANIFEST_PATH="$HOME/.mb-test-manifest.json"
  run bash "$REPO_ROOT/install.sh"
  [ "$status" -ne 0 ]                 # install aborted mid-way
  [ -f "$MB_MANIFEST_PATH" ]          # trap flushed a manifest anyway
  python3 -c "import json; m=json.load(open('$MB_MANIFEST_PATH')); assert len(m.get('files',[]))>=1, 'manifest has no files'"
}

# ═══════════════════════════════════════════════════════════════
# A12 (M-4): user-writable manifest path for pip/sudo installs
# ═══════════════════════════════════════════════════════════════

setup_readonly_skill_sandbox() {
  command -v rsync >/dev/null || skip "rsync required"
  unset MB_MANIFEST_PATH   # these tests exercise the resolver's own default, on a copy
  RO_SKILL_PARENT="$(mktemp -d)"
  RO_SKILL_SRC="$RO_SKILL_PARENT/skill"
  mkdir -p "$RO_SKILL_SRC"
  rsync -a \
    --exclude='.git' \
    --exclude='*.pre-mb-backup.*' \
    --exclude='.index' \
    --exclude='node_modules' \
    --exclude='.installed-manifest.json' \
    "$REPO_ROOT/" "$RO_SKILL_SRC/"
  # Simulate a pip/sudo install tree: readable+executable, not writable by us.
  chmod -R a-w "$RO_SKILL_SRC"
}

teardown_readonly_skill_sandbox() {
  [ -n "${RO_SKILL_SRC:-}" ] && [ -d "$RO_SKILL_SRC" ] && chmod -R u+w "$RO_SKILL_SRC"
  [ -n "${RO_SKILL_PARENT:-}" ] && [ -d "$RO_SKILL_PARENT" ] && rm -rf "$RO_SKILL_PARENT"
}

@test "install: manifest falls back to XDG data dir when skill dir is read-only (A12)" {
  setup_readonly_skill_sandbox
  unset XDG_DATA_HOME

  run env MB_SKIP_DEPS_CHECK=1 bash "$RO_SKILL_SRC/install.sh" --non-interactive
  [ "$status" -eq 0 ]

  # Not silently lost inside the unwritable tree...
  [ ! -f "$RO_SKILL_SRC/.installed-manifest.json" ]
  # ...but present at the user-writable fallback, and valid JSON.
  local fallback="$HOME/.local/share/memory-bank/.installed-manifest.json"
  [ -f "$fallback" ]
  python3 -c "import json; json.load(open('$fallback'))"

  teardown_readonly_skill_sandbox
}

@test "install: manifest write failure is logged, not silently swallowed (A12)" {
  setup_readonly_skill_sandbox
  # Fallback dir itself unwritable too — both candidate paths fail.
  mkdir -p "$HOME/.local/share/memory-bank"
  chmod a-w "$HOME/.local/share/memory-bank"

  run env MB_SKIP_DEPS_CHECK=1 bash "$RO_SKILL_SRC/install.sh" --non-interactive
  # Install still completes (manifest is a rollback aid, not a hard blocker)...
  [ "$status" -eq 0 ]
  # ...but the failure is reported, not hidden behind a bare generic string.
  [[ "$output" == *"Manifest write failed"* ]]
  [[ "$output" == *"Permission denied"* ]] || [[ "$output" == *"Errno 13"* ]]

  chmod u+w "$HOME/.local/share/memory-bank"
  teardown_readonly_skill_sandbox
}

@test "uninstall: finds manifest at the same XDG fallback install.sh used (A12)" {
  setup_readonly_skill_sandbox
  unset XDG_DATA_HOME

  bash "$RO_SKILL_SRC/install.sh" --non-interactive >/dev/null 2>&1

  local fallback="$HOME/.local/share/memory-bank/.installed-manifest.json"
  [ -f "$fallback" ]

  echo "y" | bash "$RO_SKILL_SRC/uninstall.sh" >/dev/null
  [ ! -f "$fallback" ]
  [ ! -f "$HOME/.claude/RULES.md" ]

  teardown_readonly_skill_sandbox
}
