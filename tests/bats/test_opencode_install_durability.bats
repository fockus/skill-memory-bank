#!/usr/bin/env bats
# Public ownership contract: one pending OpenCode mutation, committed predecessors,
# guarded recovery on handled I/O failure; no crash/replay or other-host rollback claim.
load lib/assert
load lib/opencode_install_fixture

_file_sha256() {
  python3 - "$1" <<'PY'
import hashlib, sys
with open(sys.argv[1], 'rb') as source:
    print(hashlib.sha256(source.read()).hexdigest())
PY
}

fault_fixture() {
  mkdir "$T/fault"
  cat > "$T/fault/sitecustomize.py" <<'PY'
import hashlib
import json
import os
import pathlib
import sys

record = os.environ.get('FAULT_RECORD', '')
target = pathlib.Path(os.environ.get('FAULT_TARGET', '/nonexistent'))
fired = pathlib.Path(os.environ.get('FAULT_FIRED', '/nonexistent/fired'))
original = os.environ.get('FAULT_ORIGINAL', '')
replace = os.replace

def fail(destination, candidate=None):
    if str(destination) != record or fired.exists():
        return
    dispatch = os.environ.get('FAULT_DISPATCH')
    if dispatch:
        if not candidate or 'opencode' not in json.loads(pathlib.Path(candidate).read_text()).get('adapters_failed', []):
            return
    elif os.environ.get('FAULT_FINAL'):
        if not candidate or 'opencode' not in json.loads(pathlib.Path(candidate).read_text()).get('clients', []):
            return
    else:
        if not target.exists() and not target.is_symlink():
            return
        if os.environ.get('FAULT_ALIAS') and not target.is_symlink():
            return
        if os.environ.get('FAULT_KEYRULES') and '<!-- mb-key-rules:start -->' not in target.read_text():
            return
        if original and target.is_file() and hashlib.sha256(target.read_bytes()).hexdigest() == original:
            return
    fired.write_text('Actual metadata I/O denied after the selected mutation.\n')
    if os.environ.get('FAULT_CHANGE'):
        target.write_text('User changed this postimage.\n')
    if os.environ.get('FAULT_ROLLBACK'):
        os.chmod(target.parent, 0o500)
    os.chmod(pathlib.Path(record).parent, 0o500)

def checked_replace(source, destination, *args, **kwargs):
    fail(destination, source)
    return replace(source, destination, *args, **kwargs)

os.replace = checked_replace
if pathlib.Path(sys.argv[0]).name == 'opencode_files.py' and sys.argv[1:2] == ['records']:
    fail(sys.argv[2])
if pathlib.Path(sys.argv[0]).name == 'opencode_files.py' and sys.argv[1:2] == ['write']:
    if sys.argv[2] == os.environ.get('FAULT_WRITE_TARGET'):
        fired.write_text('Actual target write denied after preparation.\n')
        os.chmod(pathlib.Path(sys.argv[2]).parent, 0o500)
PY
}

durable_case() {
  local kind="$1" behavior="${2:-restore}" target record root committed="" original=""
  local -a command
  record="$MB_MANIFEST_PATH"; root="$OC"
  command=(bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT")
  case "$kind" in
    command) target="$OC/commands/adr.md"; committed="$OC/AGENTS.md" ;;
    alias) target="$OC/skills/memory-bank"; committed="$OC/commands/adr.md" ;;
    global-merged)
      target="$OC/AGENTS.md"; mkdir -p "$OC"
      printf 'Original user global instructions\n' > "$target" ;;
    project-pair)
      target="$PROJECT/.mb-agents-owners.json"; root="$PROJECT/.opencode"
      record="$root/.mb-manifest.json"
      printf 'Original user project instructions\n' > "$PROJECT/AGENTS.md"
      snapshot "$PROJECT/AGENTS.md" "$T/agents.before"
      command=(bash "$SRC/adapters/opencode.sh" install "$PROJECT") ;;
    plugin|role|rerender)
      root="$PROJECT/.opencode"; record="$root/.mb-manifest.json"
      command=(bash "$SRC/adapters/opencode.sh" install "$PROJECT")
      target="$root/plugins/memory-bank.js"
      if [ "$kind" != plugin ]; then target="$root/agent/mb-developer.md"; committed="$root/plugins/memory-bank.js"; fi
      if [ "$kind" = rerender ]; then
        call "${command[@]}"; [ "$status" -eq 0 ]
        mkdir -p "$PROJECT/.memory-bank"
        printf 'roles:\n  developer: {agent: mb-developer, model: fixture/durable}\n' > "$PROJECT/.memory-bank/pipeline.yaml"
        command=(bash "$SRC/adapters/opencode.sh" render-agents "$PROJECT")
      fi ;;
    global-role)
      record="$OC/.mb-global-extensions-manifest.json"; target="$OC/agent/mb-developer.md"
      committed="$OC/agent/mb-analyst.md"
      command=(bash "$SRC/adapters/opencode.sh" install-global-agents "$PROJECT")
      minimal_manifest '[]' '[]' ;;
  esac
  if [ -f "$target" ]; then
    snapshot "$target" "$T/target.before"
    original="$(_file_sha256 "$target")" || return 1
  fi
  fault_fixture
  local change='' rollback=''
  [ "$behavior" != changed ] || change=1
  [ "$behavior" != rollback ] || rollback=1
  call env PYTHONPATH="$T/fault" FAULT_RECORD="$record" FAULT_TARGET="$target" \
    FAULT_ORIGINAL="$original" FAULT_FIRED="$T/fault/fired" FAULT_CHANGE="$change" FAULT_ROLLBACK="$rollback" "${command[@]}"
  local first_exit="$status" first_output="$output"
  chmod u+w "$(dirname "$record")" "$(dirname "$target")"
  [ -f "$T/fault/fired" ]
  [ "$first_exit" -ne 0 ]
  refute_substring "$first_output" 'Manifest saved'
  if [ "$behavior" != restore ]; then
    [ -f "$target" ]
    [ "$behavior" != changed ] || assert_grep -qF 'User changed this postimage.' "$target"
    local recovery
    recovery="$(printf '%s\n' "$first_output" | sed -n 's/.*recovery: //p' | tail -1)"
    [ -d "$recovery" ]
    [ -n "$(find "$recovery" -type f -print -quit)" ]
    if [ -n "${S5_EVIDENCE_DIR:-}" ]; then
      tar -czf "$S5_EVIDENCE_DIR/$BATS_TEST_NUMBER-recovery.tar.gz" -C "$(dirname "$recovery")" "$(basename "$recovery")"
    fi
    call "${command[@]}"
    [ "$status" -ne 0 ]
    [ -d "$recovery" ]
    return
  fi
  if [ -n "$original" ]; then assert_unchanged "$target" "$T/target.before"; else refute_file "$target"; fi
  if [ "$kind" = project-pair ]; then assert_unchanged "$PROJECT/AGENTS.md" "$T/agents.before"; fi
  if [ -n "$committed" ]; then
    call python3 "$SRC/adapters/opencode_files.py" owned "$committed" "$record" "$root"
    [ "$status" -eq 0 ]
  fi
  call "${command[@]}"
  [ "$status" -eq 0 ]
  if [ "$root" = "$PROJECT/.opencode" ]; then
    call bash "$SRC/adapters/opencode.sh" uninstall "$PROJECT"
  else
    uninstall
  fi
  [ "$status" -eq 0 ]
  if [ "$kind" = global-merged ]; then assert_unchanged "$target" "$T/target.before"; else refute_file "$target"; fi
}

@test "RST10: a global command metadata fault restores only the pending command" { durable_case command; }
@test "RST10: alias metadata failure preserves preceding command ownership" { durable_case alias; }
@test "RST10: failed first global merged checkpoint restores user instructions" { durable_case global-merged; }
@test "RST10: project AGENTS and owners recover as one pending pair" { durable_case project-pair; }
@test "RST10: project plugin metadata failure permits retry and uninstall" { durable_case plugin; }
@test "RST10: local role metadata failure preserves the committed plugin" { durable_case role; }
@test "RST10: global role metadata failure preserves the committed roster prefix" { durable_case global-role; }
@test "RST10: rerender metadata failure restores the original owned role" { durable_case rerender; }
@test "RST10: changed postimage remains with reported recovery material" { durable_case command changed; }
@test "RST10: rollback I/O failure preserves the live command and recovery" { durable_case command rollback; }

@test "RST10: dispatch metadata failure prevents the project adapter mutation" {
  fault_fixture
  call env PYTHONPATH="$T/fault" FAULT_RECORD="$MB_MANIFEST_PATH" FAULT_DISPATCH=1 \
    FAULT_FIRED="$T/fault/fired" bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  local first_exit="$status"
  chmod u+w "$T"
  [ -f "$T/fault/fired" ]
  [ "$first_exit" -ne 0 ]
  refute_file "$PROJECT/.opencode/plugins/memory-bank.js"
  install; [ "$status" -eq 0 ]
  uninstall; [ "$status" -eq 0 ]
}

@test "RST10: an explicit foreign HOME manifest is preserved before installation" {
  minimal_manifest '[]' '[]'
  jq --arg h "$T/foreign-home" '.home=$h' "$MB_MANIFEST_PATH" > "$T/top.json"
  mv "$T/top.json" "$MB_MANIFEST_PATH"
  snapshot "$MB_MANIFEST_PATH" "$T/manifest.before"
  install
  [ "$status" -ne 0 ]
  assert_substring "$output" 'HOME'
  assert_unchanged "$MB_MANIFEST_PATH" "$T/manifest.before"
  refute_file "$OC/commands/adr.md"
}

@test "RST10: a different project cannot replace unresolved OpenCode dispatch ownership" {
  install; [ "$status" -eq 0 ]
  snapshot "$MB_MANIFEST_PATH" "$T/manifest.before"
  mkdir "$T/another-project"
  call bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$T/another-project"
  [ "$status" -ne 0 ]
  assert_unchanged "$MB_MANIFEST_PATH" "$T/manifest.before"
  refute_file "$T/another-project/.opencode/plugins/memory-bank.js"
}

@test "RST10: failed target replacement does not remove the untouched owned original" {
  install; [ "$status" -eq 0 ]
  local target="$OC/commands/adr.md"
  snapshot "$target" "$T/original"
  printf '\nNew revision\n' >> "$SRC/commands/adr.md"
  fault_fixture
  call env PYTHONPATH="$T/fault" FAULT_WRITE_TARGET="$target" FAULT_FIRED="$T/fault/fired" \
    bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  local first_exit="$status"
  chmod u+w "$OC/commands"
  [ "$first_exit" -ne 0 ]
  assert_unchanged "$target" "$T/original"
  call python3 "$SRC/adapters/opencode_files.py" owned "$target" "$MB_MANIFEST_PATH" "$OC"
  [ "$status" -eq 0 ]
}

@test "RST10: authorized directory migration restores original inode and backup lineage on failure" {
  local alias="$OC/skills/memory-bank"
  mkdir -p "$alias"
  printf 'Original skill contents\n' > "$alias/SKILL.md"
  record_skill_directory
  local inode
  inode="$(public python3 -c 'import os,sys; print(os.lstat(sys.argv[1]).st_ino)' "$alias")"
  fault_fixture
  call env PYTHONPATH="$T/fault" FAULT_ALIAS=1 FAULT_RECORD="$MB_MANIFEST_PATH" FAULT_TARGET="$alias" \
    FAULT_FIRED="$T/fault/fired" bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  local first_exit="$status"
  chmod u+w "$T"
  [ "$first_exit" -ne 0 ]
  [ -d "$alias" ] && [ ! -L "$alias" ]
  [ "$(public python3 -c 'import os,sys; print(os.lstat(sys.argv[1]).st_ino)' "$alias")" = "$inode" ]
  call python3 "$SRC/adapters/opencode_files.py" owned-directory "$alias" "$MB_MANIFEST_PATH" "$OC"
  [ "$status" -eq 0 ]
  install; [ "$status" -eq 0 ]
  uninstall; [ "$status" -eq 0 ]
  assert_grep -qF 'Original skill contents' "$alias/SKILL.md"
}

@test "RST10: JSON transformation failure restores user bytes and removes only its new backup" {
  printf '{"plugins":["foreign-plugin","./.opencode/plugins/memory-bank.js"]}\n' > "$PROJECT/opencode.json"
  snapshot "$PROJECT/opencode.json" "$T/json.before"
  local original
  original="$(_file_sha256 "$PROJECT/opencode.json")" || return 1
  fault_fixture
  call env PYTHONPATH="$T/fault" FAULT_RECORD="$PROJECT/.opencode/.mb-manifest.json" \
    FAULT_TARGET="$PROJECT/opencode.json" FAULT_ORIGINAL="$original" FAULT_FIRED="$T/fault/fired" \
    bash "$SRC/adapters/opencode.sh" install "$PROJECT"
  local first_exit="$status"
  chmod u+w "$PROJECT/.opencode"
  [ "$first_exit" -ne 0 ]
  assert_unchanged "$PROJECT/opencode.json" "$T/json.before"
  [ -z "$(find "$PROJECT" -name 'opencode.json.pre-mb-backup.*' -print)" ]
}

# This public path reaches the implicit rewrite in mb_rules_sync_lib.sh, not just the initial block writer.
@test "RST10: late Key rules failure restores the preceding committed global block" {
  mkdir -p "$OC"; printf 'User global instructions\n' > "$OC/AGENTS.md"
  fault_fixture
  call env PYTHONPATH="$T/fault" FAULT_KEYRULES=1 FAULT_RECORD="$MB_MANIFEST_PATH" \
    FAULT_TARGET="$OC/AGENTS.md" FAULT_FIRED="$T/fault/fired" \
    bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  local first_exit="$status"
  chmod u+w "$T"
  [ "$first_exit" -ne 0 ]
  assert_grep -qF 'User global instructions' "$OC/AGENTS.md"
  refute_grep -qF '<!-- mb-key-rules:start -->' "$OC/AGENTS.md"
  call python3 "$SRC/adapters/opencode_files.py" owned "$OC/AGENTS.md" "$MB_MANIFEST_PATH" "$OC"
  [ "$status" -eq 0 ]
}

@test "RST10: final summary failure retains durable failed-project discoverability" {
  fault_fixture
  call env PYTHONPATH="$T/fault" FAULT_FINAL=1 FAULT_RECORD="$MB_MANIFEST_PATH" \
    FAULT_FIRED="$T/fault/fired" bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  local first_exit="$status" first_output="$output"
  chmod u+w "$T"
  [ "$first_exit" -ne 0 ]
  refute_substring "$first_output" 'Manifest saved'
  [ -f "$PROJECT/.opencode/plugins/memory-bank.js" ]
  jq -e '.adapters_failed | index("opencode") != null' "$MB_MANIFEST_PATH"
  uninstall; [ "$status" -eq 0 ]
  refute_file "$PROJECT/.opencode/plugins/memory-bank.js"
}

@test "RST10: early ownership preflight retains the previous good record and owned bytes" {
  mkdir "$T/ownership"; export MB_MANIFEST_PATH="$T/ownership/top.json"
  mkdir -p "$OC/commands"; printf 'Previously owned command\n' > "$OC/commands/adr.md"
  minimal_manifest "$(jq -n --arg p "$OC/commands/adr.md" '[$p]')" '[]'
  local digest
  digest="$(_file_sha256 "$OC/commands/adr.md")" || return 1
  jq --arg p "$OC/commands/adr.md" --arg h "$digest" \
    '.file_sha256[$p]=$h' "$MB_MANIFEST_PATH" > "$T/record.json"
  mv "$T/record.json" "$MB_MANIFEST_PATH"
  snapshot "$MB_MANIFEST_PATH" "$T/record.before"
  snapshot "$OC/commands/adr.md" "$T/command.before"
  chmod a-w "$T/ownership"
  install
  local first_exit="$status"
  chmod u+w "$T/ownership"
  [ "$first_exit" -ne 0 ]
  assert_unchanged "$MB_MANIFEST_PATH" "$T/record.before"
  assert_unchanged "$OC/commands/adr.md" "$T/command.before"
  refute_substring "$output" 'Manifest saved'
}
