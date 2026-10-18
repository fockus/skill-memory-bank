#!/usr/bin/env bats
# Public Stage 5 cycle-1 regressions; no native server or model boundary is used.
load lib/assert
load lib/opencode_install_fixture

io_retry() {
  local folder="$1" record="$2"
  [ "$(id -u)" -ne 0 ] || { echo 'Requires real non-root filesystem permissions'; return 1; }
  install
  [ "$status" -eq 0 ]
  chmod 500 "$folder"
  [ ! -w "$folder" ] || { echo 'Filesystem did not enforce the private permission boundary'; return 1; }
  uninstall
  local failed_status="$status" retained=0
  [ -f "$MB_MANIFEST_PATH" ] || retained=1
  [ -f "$record" ] || retained=1
  [ -f "$folder/mb.md" ] || retained=1
  chmod 700 "$folder"
  uninstall
  echo "first_exit=$failed_status ownership_lost=$retained retry_exit=$status"
  [ "$failed_status" -ne 0 ]
  [ "$retained" -eq 0 ]
  [ "$status" -eq 0 ]
  refute_file "$folder/mb.md"
}

@test "S5-ALIAS-1: public install refuses an unmanaged regular alias despite matching prior-install mtime" {
  mkdir -p "$HOME/.claude" "$OC/skills"
  printf '{"preferred_language":"en"}\n' > "$HOME/.claude/memory-bank-config.json"
  printf 'Unmanaged alias bytes\n' > "$OC/skills/memory-bank"
  touch -r "$HOME/.claude/memory-bank-config.json" "$OC/skills/memory-bank"
  snapshot "$OC/skills/memory-bank" "$T/before"
  local before_stat
  before_stat="$(python3 -c 'import os,stat,sys; s=os.stat(sys.argv[1]); print(stat.S_IMODE(s.st_mode), s.st_mtime_ns)' "$OC/skills/memory-bank")" || return 1
  install
  assert_unchanged "$OC/skills/memory-bank" "$T/before"
  [ ! -L "$OC/skills/memory-bank" ]
  python3 - "$OC/skills/memory-bank" "$before_stat" <<'PY'
import os, stat, sys
s = os.stat(sys.argv[1])
actual = f"{stat.S_IMODE(s.st_mode)} {s.st_mtime_ns}"
assert actual == sys.argv[2], (actual, sys.argv[2])
PY
  [ "$status" -ne 0 ]
  assert_substring "$output" "$OC/skills/memory-bank"
}

@test "S5-RESTORE-2: public uninstall refuses a forged legacy backup rename of unrelated settings" {
  mkdir -p "$OC/commands"
  printf '{"theme":"user-settings"}\n' > "$OC/opencode.json"
  snapshot "$OC/opencode.json" "$T/before"
  minimal_manifest '[]' "$(jq -n --arg b "$OC/commands/mb.md|$OC/opencode.json" '[$b]')"
  uninstall
  assert_unchanged "$OC/opencode.json" "$T/before"
  refute_file "$OC/commands/mb.md"
  assert_substring "$output" "$OC/commands/mb.md"
}

@test "S5-RESTORE-2: genuine unchanged skill backup restores through public uninstall" {
  mkdir -p "$OC/skills/memory-bank"
  printf 'Original local skill\n' > "$OC/skills/memory-bank/SKILL.md"
  record_skill_directory
  install
  [ "$status" -eq 0 ]
  uninstall
  [ "$status" -eq 0 ]
  [ ! -L "$OC/skills/memory-bank" ]
  grep -qx 'Original local skill' "$OC/skills/memory-bank/SKILL.md"
  refute_file "$PROJECT/.opencode/commands/mb.md"
}

@test "S5-RESTORE-2: public uninstall preserves a genuine backup edited after installation" {
  mkdir -p "$OC/skills/memory-bank"
  printf 'Original local skill\n' > "$OC/skills/memory-bank/SKILL.md"
  record_skill_directory
  install
  [ "$status" -eq 0 ]
  local backup
  backup="$(jq -r --arg p "$OC/skills/memory-bank|" '.backups[] | select(startswith($p)) | split("|")[1]' "$MB_MANIFEST_PATH")"
  printf 'User backup edit\n' >> "$backup/SKILL.md"
  snapshot "$backup/SKILL.md" "$T/before"
  uninstall
  assert_unchanged "$backup/SKILL.md" "$T/before"
  refute_file "$OC/skills/memory-bank"
}

@test "S5-RESTORE-2: a replaced backup symlink and its private target survive public uninstall" {
  mkdir -p "$OC/skills/memory-bank" "$T/target"
  printf 'Original local skill\n' > "$OC/skills/memory-bank/SKILL.md"
  record_skill_directory
  install
  [ "$status" -eq 0 ]
  local backup
  backup="$(jq -r --arg p "$OC/skills/memory-bank|" '.backups[] | select(startswith($p)) | split("|")[1]' "$MB_MANIFEST_PATH")"
  mv "$backup" "$T/original-backup"
  cp "$T/original-backup/SKILL.md" "$T/target/SKILL.md"
  ln -s "$T/target" "$backup"
  uninstall
  [ -L "$backup" ]
  [ "$(readlink "$backup")" = "$T/target" ]
  assert_unchanged "$T/target/SKILL.md" "$T/original-backup/SKILL.md"
  refute_file "$OC/skills/memory-bank"
}

@test "S5-BACKUP-3: actual config-backup helper never follows a pre-existing dangling destination" {
  printf '{"theme":"user"}\n' > "$PROJECT/opencode.json"
  call bash -s -- "$SRC" "$PROJECT" "$T/outside-canary" <<'SH'
    SKILL_DIR=$1; PROJECT_ROOT=$2; MANIFEST=$2/.opencode/.mb-manifest.json
    source "$1/adapters/_framework.sh"
    eval "$(sed -n "/^opencode_backup_json()/,/^}/p" "$1/adapters/opencode.sh")"
    OC_JSON=$2/opencode.json
    ln -s "$3" "$OC_JSON.pre-mb-backup.$$"
    opencode_backup_json
    OC_JSON=$2/pristine.json; printf "original\n" > "$OC_JSON"
    opencode_backup_json; opencode_backup_json
    cmp "$OC_JSON" "$OC_JSON".pre-mb-backup.*
SH
  [ "$status" -eq 0 ]
  refute_file "$T/outside-canary"
  [ "$(find "$PROJECT" -type f -name 'pristine.json.pre-mb-backup.*' | wc -l | tr -d ' ')" -eq 1 ]
}

@test "S5-RULES-4: direct init implicit edit-sync and user-sync honor external XDG without following legacy links" {
  local action failed=0
  mkdir -p "$HOME/.config/opencode" "$HOME/.claude" "$HOME/.codex"
  printf 'Claude user text\n' > "$HOME/.codex/AGENTS.md"
  ln -s "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md"
  for action in init add sync; do
    configuration "$T/xdg-$action"
    mkdir -p "$XDG_CONFIG_HOME/opencode"
    printf 'Foreign legacy canary\n' > "$T/foreign-$action"
    snapshot "$T/foreign-$action" "$T/before-$action"
    ln -sf "$T/foreign-$action" "$HOME/.config/opencode/AGENTS.md"
    printf 'Selected OpenCode user text\n' > "$XDG_CONFIG_HOME/opencode/AGENTS.md"
    if [ "$action" = add ]; then call bash "$SRC/scripts/mb-rules.sh" add 'Cycle1 custom rule' --scope=user --project="$PROJECT"
    else call bash "$SRC/scripts/mb-rules.sh" "$action" --scope=user --project="$PROJECT"; fi
    [ "$status" -eq 0 ] || { echo "$action failed before completing user sync"; failed=1; }
    cmp -s "$T/foreign-$action" "$T/before-$action" || { echo "$action changed foreign legacy target"; failed=1; }
    grep -q 'mb-key-rules:start' "$XDG_CONFIG_HOME/opencode/AGENTS.md" || { echo "$action missed selected root"; failed=1; }
    grep -q 'Selected OpenCode user text' "$XDG_CONFIG_HOME/opencode/AGENTS.md" || failed=1
    grep -qF "$XDG_CONFIG_HOME/opencode/skills/memory-bank/rules/RULES.md" "$XDG_CONFIG_HOME/opencode/AGENTS.md" || failed=1
    grep -q 'Claude user text' "$HOME/.claude/CLAUDE.md"
    grep -q 'mb-key-rules:start' "$HOME/.codex/AGENTS.md"
    [ -L "$HOME/.claude/CLAUDE.md" ]
  done
  [ "$failed" -eq 0 ]
}

@test "S5-RULES-4: public install leaves a legacy instruction symlink target untouched with external XDG" {
  configuration "$T/external-config"
  mkdir -p "$HOME/.config/opencode"
  printf 'Foreign instruction canary\n' > "$T/foreign"
  snapshot "$T/foreign" "$T/before"
  ln -s "$T/foreign" "$HOME/.config/opencode/AGENTS.md"
  install --key-rules=default
  [ "$status" -eq 0 ]
  assert_unchanged "$T/foreign" "$T/before"
  [ -L "$HOME/.config/opencode/AGENTS.md" ]
  grep -qF "$XDG_CONFIG_HOME/opencode/skills/memory-bank/rules/RULES.md" "$XDG_CONFIG_HOME/opencode/AGENTS.md"
}

@test "S5-ROUTE-5: public removal and restore reject traversal-spelled OpenCode paths" {
  mkdir -p "$HOME/.claude" "$OC/commands"
  printf 'Edited unowned command\n' > "$OC/commands/mb.md"
  printf '{"theme":"private"}\n' > "$OC/opencode.json"
  snapshot "$OC/commands/mb.md" "$T/command.before"; snapshot "$OC/opencode.json" "$T/settings.before"
  local route="$HOME/.claude/../.config/opencode/commands"
  minimal_manifest "$(jq -n --arg f "$route/mb.md" '[$f]')" \
    "$(jq -n --arg b "$route/restored.md|$OC/opencode.json" '[$b]')"
  uninstall
  local intact=0
  cmp -s "$OC/commands/mb.md" "$T/command.before" || intact=1
  cmp -s "$OC/opencode.json" "$T/settings.before" || intact=1
  [ "$intact" -eq 0 ]
  refute_file "$OC/commands/restored.md"
}

@test "S5-XDG-6: identical public reinstall recognizes its recorded alias outside HOME" {
  configuration "$T/external-config"
  install
  [ "$status" -eq 0 ]
  local alias="$XDG_CONFIG_HOME/opencode/skills/memory-bank" identity
  identity="$(python3 -c 'import os,sys; print(os.lstat(sys.argv[1]).st_ino)' "$alias")"
  install
  [ "$status" -eq 0 ]
  [ "$(python3 -c 'import os,sys; print(os.lstat(sys.argv[1]).st_ino)' "$alias")" = "$identity" ]
  jq -e --arg h "$HOME" '.home == $h' "$MB_MANIFEST_PATH"
}

@test "S5-FAILURE-7: public extension refusal fails accounting without downgrading an extended plugin" {
  install --with-extensions=opencode
  [ "$status" -eq 0 ]
  grep -q 'extended: true' "$PROJECT/.opencode/plugins/memory-bank.js"
  printf '\nEdited global role\n' >> "$OC/agent/mb-developer.md"
  snapshot "$OC/agent/mb-developer.md" "$T/before"
  install --with-extensions=opencode
  printf 'exit=%s; plugin=%s; failures=%s\n' "$status" "$(tail -1 "$PROJECT/.opencode/plugins/memory-bank.js")" "$(jq -c .adapters_failed "$MB_MANIFEST_PATH")"
  assert_unchanged "$OC/agent/mb-developer.md" "$T/before"
  [ "$status" -ne 0 ]
  jq -e '.adapters_failed | index("opencode") != null' "$MB_MANIFEST_PATH"
  grep -q 'extended: true' "$PROJECT/.opencode/plugins/memory-bank.js"
}

@test "S5-DISCOVERY-8: consecutive public project and early-global refusals retain uninstall discovery" {
  install
  [ "$status" -eq 0 ]
  printf '\nEdited project command\n' >> "$PROJECT/.opencode/commands/mb.md"
  snapshot "$PROJECT/.opencode/commands/mb.md" "$T/before"
  install
  [ "$status" -ne 0 ]
  jq -e '.adapters_failed | index("opencode") != null' "$MB_MANIFEST_PATH"
  printf '\nEdited global command\n' >> "$OC/commands/mb.md"
  install
  [ "$status" -ne 0 ]
  local discovered=0
  jq -e '(.clients + .adapters_failed) | index("opencode") != null' "$MB_MANIFEST_PATH" >/dev/null || discovered=1
  uninstall
  echo "discovery_lost=$discovered"
  [ "$discovered" -eq 0 ]
  refute_file "$PROJECT/.opencode/commands/start.md"
  refute_file "$PROJECT/.opencode/.mb-manifest.json"
  refute_file "$PROJECT/.mb-agents-owners.json"
  assert_unchanged "$PROJECT/.opencode/commands/mb.md" "$T/before"
}

@test "S5-IO-9: public unlink PermissionError retains ownership for a successful retry" {
  io_retry "$OC/commands" "$MB_MANIFEST_PATH"
}
@test "S5-IO-9: public project-adapter I/O failure retains both discovery and project manifest for retry" {
  io_retry "$PROJECT/.opencode/commands" "$PROJECT/.opencode/.mb-manifest.json"
}

@test "S5-IO-9: expected edited-file preservation still permits successful adapter cleanup" {
  call bash "$SRC/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  printf '\nUser project edit\n' >> "$PROJECT/.opencode/commands/mb.md"
  snapshot "$PROJECT/.opencode/commands/mb.md" "$T/before"
  call bash "$SRC/adapters/opencode.sh" uninstall "$PROJECT"
  [ "$status" -eq 0 ]
  assert_unchanged "$PROJECT/.opencode/commands/mb.md" "$T/before"
  refute_file "$PROJECT/.opencode/commands/start.md"
  refute_file "$PROJECT/.opencode/.mb-manifest.json"
}

@test "S5-RULES-4: direct user-sync refuses a selected OpenCode instruction symlink without changing its target" {
  mkdir -p "$OC"
  printf 'Selected foreign target\n' > "$T/foreign"
  snapshot "$T/foreign" "$T/before"
  ln -s "$T/foreign" "$OC/AGENTS.md"
  call bash "$SRC/scripts/mb-rules.sh" sync --scope=user --project="$PROJECT"
  assert_unchanged "$T/foreign" "$T/before"
  [ -L "$OC/AGENTS.md" ]
  assert_substring "$output" "$OC/AGENTS.md"
}

@test "S5-DISCOVERY-8: same HOME still removes the recorded failed project adapter" {
  call bash "$SRC/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  minimal_manifest '[]' '[]'
  jq '.adapters_failed=["opencode"]' "$MB_MANIFEST_PATH" > "$T/top.json"
  mv "$T/top.json" "$MB_MANIFEST_PATH"
  uninstall
  [ "$status" -eq 0 ]
  refute_file "$PROJECT/.opencode/commands/start.md"
  refute_file "$PROJECT/.mb-agents-owners.json"
  refute_file "$MB_MANIFEST_PATH"
}
@test "S5-DISCOVERY-8: legacy HOME-absent manifests retain project cleanup compatibility" {
  call bash "$SRC/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  minimal_manifest '[]' '[]'
  jq 'del(.home) | .clients=["opencode"]' "$MB_MANIFEST_PATH" > "$T/top.json"
  mv "$T/top.json" "$MB_MANIFEST_PATH"
  uninstall
  [ "$status" -eq 0 ]
  refute_file "$PROJECT/.opencode/commands/start.md"
  refute_file "$PROJECT/.mb-agents-owners.json"
}
@test "S5-DISCOVERY-8: force treats malformed JSON prefixes as no project authority" {
  call bash "$SRC/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  snapshot "$PROJECT/.opencode/commands/start.md" "$T/start.before"
  snapshot "$PROJECT/.mb-agents-owners.json" "$T/owners.before"
  minimal_manifest '[]' '[]'
  jq --arg h "$T/foreign-home" '.home=$h | .adapters_failed=["opencode"]' "$MB_MANIFEST_PATH" > "$T/top.json"
  cat "$T/top.json" > "$MB_MANIFEST_PATH"
  printf '\ninvalid-json-tail\n' >> "$MB_MANIFEST_PATH"
  call bash "$SRC/uninstall.sh" -y --force
  [ "$status" -eq 0 ]
  assert_unchanged "$PROJECT/.opencode/commands/start.md" "$T/start.before"
  assert_unchanged "$PROJECT/.mb-agents-owners.json" "$T/owners.before"
  refute_file "$MB_MANIFEST_PATH"
}
