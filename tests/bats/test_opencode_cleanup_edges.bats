#!/usr/bin/env bats
# Remaining public cleanup boundaries before the same cycle-1 canonical gate.
load lib/assert
load lib/opencode_install_fixture

edge_call() {
  CALL_NUMBER=$((CALL_NUMBER + 1)); status=0
  public "$@" > "$T/stdout" 2> "$T/stderr" || status=$?
  output="$(cat "$T/stdout" "$T/stderr")"
  if [ -n "${S5_EVIDENCE_DIR:-}" ]; then
    cp "$T/stdout" "$S5_EVIDENCE_DIR/$BATS_TEST_NUMBER-$CALL_NUMBER.stdout"
    cp "$T/stderr" "$S5_EVIDENCE_DIR/$BATS_TEST_NUMBER-$CALL_NUMBER.stderr"
    printf '%s\n' "$status" > "$S5_EVIDENCE_DIR/$BATS_TEST_NUMBER-$CALL_NUMBER.exit"
  fi
}

receipt() {
  [ -z "${S5_EVIDENCE_DIR:-}" ] || cp "$2" "$S5_EVIDENCE_DIR/$BATS_TEST_NUMBER-$1"
}

tree_state() {
  python3 - "$1" <<'PY'
import hashlib, json, os, pathlib, stat, sys
root = pathlib.Path(sys.argv[1])
paths = {root}
if root.is_dir() and not root.is_symlink():
    for directory, folders, files in os.walk(root, followlinks=False):
        paths.update(pathlib.Path(directory) / name for name in folders + files)
result = {}
for path in sorted(paths):
    if not os.path.lexists(path):
        result[str(path.relative_to(root))] = None
        continue
    info = path.lstat()
    entry = {'device': info.st_dev, 'inode': info.st_ino, 'mode': info.st_mode, 'uid': info.st_uid, 'gid': info.st_gid, 'mtime_ns': info.st_mtime_ns}
    if stat.S_ISLNK(info.st_mode): entry['target'] = os.readlink(path)
    elif stat.S_ISREG(info.st_mode): entry['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    result[str(path.relative_to(root))] = entry
print(json.dumps(result, sort_keys=True, indent=2))
PY
}

route_alias() {
  local spelling="$1" intact=0
  mkdir -p "$OC/commands"
  printf 'Unmanaged command\n' > "$OC/commands/mb.md"
  printf '{"theme":"foreign-settings"}\n' > "$OC/opencode.json"
  snapshot "$OC/commands/mb.md" "$T/command.before"
  snapshot "$OC/opencode.json" "$T/settings.before"
  receipt command.before "$T/command.before"; receipt settings.before "$T/settings.before"
  minimal_manifest "$(jq -n --arg f "$spelling/mb.md" '[$f]')" \
    "$(jq -n --arg b "$spelling/restored.md|$OC/opencode.json" '[$b]')"
  receipt manifest.before "$MB_MANIFEST_PATH"
  edge_call bash "$SRC/uninstall.sh" -y
  cmp -s "$OC/commands/mb.md" "$T/command.before" || intact=1
  cmp -s "$OC/opencode.json" "$T/settings.before" || intact=1
  echo "remove_and_restore_preserved=$((1 - intact)); restored_exists=$([ -e "$OC/commands/restored.md" ] && echo yes || echo no)"
  [ "$intact" -eq 0 ]
  refute_file "$OC/commands/restored.md"
}

unknown_directory() {
  local variant="$1" directory="$OC/skills/memory-bank"
  mkdir -p "$directory"
  printf 'Private user notes\n' > "$directory/notes.md"
  printf 'Private external link target\n' > "$T/target"
  snapshot "$T/target" "$T/target.before"
  case "$variant" in
    skill) printf '%s\n' '---' 'name: unrelated-skill' '---' 'Not a Memory Bank installation.' > "$directory/SKILL.md" ;;
    linked) ln -s "$T/target" "$directory/linked-note" ;;
  esac
  chmod 750 "$directory"; chmod 660 "$directory/notes.md"
  tree_state "$directory" > "$T/tree.before"
  receipt tree.before "$T/tree.before"; receipt target.before "$T/target.before"
  edge_call bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  tree_state "$directory" > "$T/tree.after"
  receipt tree.after "$T/tree.after"
  echo "public_exit=$status; original_is_directory=$([ -d "$directory" ] && [ ! -L "$directory" ] && echo yes || echo no)"
  assert_unchanged "$T/tree.after" "$T/tree.before"
  assert_unchanged "$T/target" "$T/target.before"
  [ "$status" -ne 0 ]
  assert_substring "$output" "$directory"
  [ -z "$(find "$OC" -name 'memory-bank.pre-mb-backup.*' -print)" ]
}

read_failure_retry() {
  local scope="$1" file="$OC/commands/mb.md" record="$MB_MANIFEST_PATH" root="$OC" missing=0 bytes_lost=0
  [ "$(id -u)" -ne 0 ] || { echo 'Requires real non-root filesystem permissions'; return 1; }
  edge_call bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT"
  [ "$status" -eq 0 ]
  if [ "$scope" = project ]; then file="$PROJECT/.opencode/commands/mb.md"; record="$PROJECT/.opencode/.mb-manifest.json"; root="$PROJECT/.opencode"; fi
  edge_call python3 "$SRC/adapters/opencode_files.py" owned "$file" "$record" "$root"
  [ "$status" -eq 0 ]
  snapshot "$file" "$T/command.before"; receipt command.before "$T/command.before"
  receipt ownership.before "$record"; receipt discovery.before "$MB_MANIFEST_PATH"
  local mode first_exit
  mode="$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$file")"
  chmod 000 "$file"
  [ ! -r "$file" ] || { echo 'Filesystem did not enforce the private read boundary'; return 1; }
  edge_call bash "$SRC/uninstall.sh" -y
  first_exit="$status"
  [ -f "$record" ] && [ -f "$MB_MANIFEST_PATH" ] || missing=1
  if [ "$scope" = project ]; then [ -f "$PROJECT/.mb-agents-owners.json" ] || missing=1; fi
  if [ -f "$file" ]; then chmod "$mode" "$file"; cmp -s "$file" "$T/command.before" || bytes_lost=1; else bytes_lost=1; fi
  edge_call bash "$SRC/uninstall.sh" -y
  echo "read_fault_exit=$first_exit retry_records_lost=$missing bytes_lost=$bytes_lost retry_exit=$status"
  [ "$first_exit" -ne 0 ]
  [ "$missing" -eq 0 ]
  [ "$bytes_lost" -eq 0 ]
  [ "$status" -eq 0 ]
  refute_file "$file"
}

agents_fixture() {
  python3 - "$T/user-payload" "$PROJECT/AGENTS.md" <<'PY'
import pathlib, sys
payload = b'User instruction: preserve every byte.\n' * 750
for file in sys.argv[1:]: pathlib.Path(file).write_bytes(payload)
PY
  edge_call bash "$SRC/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  chmod 660 "$PROJECT/AGENTS.md"
  cp -p "$PROJECT/AGENTS.md" "$T/agents.before"
  snapshot "$PROJECT/.mb-agents-owners.json" "$T/owners.before"
  snapshot "$PROJECT/.opencode/.mb-manifest.json" "$T/manifest.before"
  receipt agents.before "$T/agents.before"; receipt owners.before "$T/owners.before"
  receipt manifest.before "$T/manifest.before"; receipt user-payload "$T/user-payload"
}

limited_cleanup() {
  edge_call python3 - "$SRC" "$PROJECT" "$1" <<'PY'
import pathlib, resource, signal, subprocess, sys
bundle, project, mode = sys.argv[1:]
if mode == 'adapter':
    argv = ['bash', str(pathlib.Path(bundle) / 'adapters/opencode.sh'), 'uninstall', project]
else:
    argv = ['bash', '-euo', 'pipefail', '-c', 'source "$1"; agents_md_uninstall "$2" opencode',
            '_', str(pathlib.Path(bundle) / 'adapters/_lib_agents_md.sh'), project]
def limit_child():
    resource.setrlimit(resource.RLIMIT_FSIZE, (1024, 1024))
    signal.signal(signal.SIGXFSZ, signal.SIG_DFL)
result = subprocess.run(argv, preexec_fn=limit_child, capture_output=True, timeout=30)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
raise SystemExit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
PY
}

agents_fault() {
  agents_fixture
  limited_cleanup "$1"
  local first_exit="$status" lost=0
  [ -f "$PROJECT/.mb-agents-owners.json" ] && [ -f "$PROJECT/.opencode/.mb-manifest.json" ] || lost=1
  cmp -s "$PROJECT/.mb-agents-owners.json" "$T/owners.before" || lost=1
  cmp -s "$PROJECT/.opencode/.mb-manifest.json" "$T/manifest.before" || lost=1
  cmp -s "$PROJECT/AGENTS.md" "$T/agents.before" || lost=1
  if [ -f "$PROJECT/AGENTS.md" ]; then cp -p "$PROJECT/AGENTS.md" "$T/agents.after"; receipt agents.after "$T/agents.after"; fi
  tree_state "$PROJECT/AGENTS.md" > "$T/agents-state.after"; receipt agents-state.after "$T/agents-state.after"
  edge_call bash "$SRC/adapters/opencode.sh" uninstall "$PROJECT"
  echo "limited_exit=$first_exit original_or_records_lost=$lost retry_exit=$status"
  [ "$first_exit" -ne 0 ]
  [ "$lost" -eq 0 ]
  assert_unchanged "$T/agents.after" "$T/agents.before"
  [ "$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode))[2:])' "$T/agents.after")" = 660 ]
  [ "$status" -eq 0 ]
  python3 - "$T/user-payload" "$PROJECT/AGENTS.md" <<'PY'
import pathlib, sys
payload, agents = (pathlib.Path(p).read_bytes() for p in sys.argv[1:])
assert payload in agents
assert b'<!-- memory-bank:start -->' not in agents
PY
  refute_file "$PROJECT/.mb-agents-owners.json"
  refute_file "$PROJECT/.opencode/.mb-manifest.json"
}

@test "S5-ROUTE-5 pre-gate: dot-segment spelling cannot bypass public removal or restoration" {
  route_alias "$HOME/./.config/opencode/commands"
}
@test "S5-ROUTE-5 pre-gate: repeated separators cannot bypass public removal or restoration" {
  route_alias "$XDG_CONFIG_HOME//opencode/commands"
}
@test "S5-ROUTE-5 control: canonical hash-owned public removal still succeeds" {
  mkdir -p "$OC/commands"
  printf 'Pristine managed command\n' > "$OC/commands/mb.md"
  minimal_manifest "$(jq -n --arg p "$OC/commands/mb.md" '[$p]')" '[]'
  jq --arg p "$OC/commands/mb.md" --arg h "$(shasum -a 256 "$OC/commands/mb.md" | cut -d' ' -f1)" \
    '.file_sha256[$p] = $h' "$MB_MANIFEST_PATH" > "$T/manifest.new"
  mv "$T/manifest.new" "$MB_MANIFEST_PATH"
  edge_call bash "$SRC/uninstall.sh" -y
  [ "$status" -eq 0 ]
  refute_file "$OC/commands/mb.md"
}
@test "S5-ALIAS-1 pre-gate: unknown notes-only directory remains in place before public refusal" {
  unknown_directory notes
}
@test "S5-ALIAS-1 pre-gate: unrelated SKILL directory is not migration authority" {
  unknown_directory skill
}
@test "S5-ALIAS-1 pre-gate: directory with symlink member is refused before any quarantine move" {
  unknown_directory linked
}
@test "S5-IO-9 pre-gate: public global read PermissionError preserves retry ownership" {
  read_failure_retry global
}
@test "S5-IO-9 pre-gate: public project read PermissionError preserves both ownership and discovery" {
  read_failure_retry project
}
@test "S5-AGENTS-10 pre-gate: conditional adapter caller preserves original instructions on real write failure" {
  agents_fault adapter
}
@test "S5-AGENTS-10 control: standalone errexit helper preserves original instructions under the same resource limit" {
  agents_fault standalone
}

@test "S5-IO-9: operational manifest read failure is not a force waiver" {
  minimal_manifest '[]' '[]'
  snapshot "$MB_MANIFEST_PATH" "$T/manifest.before"
  chmod 000 "$MB_MANIFEST_PATH"
  edge_call bash "$SRC/uninstall.sh" -y --force
  local first_exit="$status"
  chmod 600 "$MB_MANIFEST_PATH"
  [ "$first_exit" -ne 0 ]
  assert_unchanged "$MB_MANIFEST_PATH" "$T/manifest.before"
  edge_call bash "$SRC/uninstall.sh" -y
  [ "$status" -eq 0 ]
}

@test "S5-ROUTE-5: a legacy restore destination link cannot route a foreign file into OpenCode" {
  mkdir -p "$HOME/.claude" "$OC/commands"
  printf 'Foreign backup source\n' > "$HOME/.claude/source.md"
  snapshot "$HOME/.claude/source.md" "$T/source.before"
  ln -s "$OC/commands" "$HOME/.claude/restored"
  minimal_manifest '[]' "$(jq -n --arg b "$HOME/.claude/restored|$HOME/.claude/source.md" '[$b]')"
  edge_call bash "$SRC/uninstall.sh" -y
  assert_unchanged "$HOME/.claude/source.md" "$T/source.before"
  [ -L "$HOME/.claude/restored" ]
  refute_file "$OC/commands/source.md"
}

foreign_manifest_refusal() {
  local recorded_home="$1"; shift
  edge_call bash "$SRC/adapters/opencode.sh" install "$PROJECT"
  [ "$status" -eq 0 ]
  mkdir -p "$HOME/.claude"
  printf 'User text\n<!-- mb-key-rules:start -->\nKeep these bytes\n<!-- mb-key-rules:end -->\n' > "$HOME/.claude/CLAUDE.md"
  printf 'Foreign user notes\n' > "$PROJECT/user-notes.md"
  chmod 640 "$PROJECT/user-notes.md"; chmod 660 "$PROJECT/.mb-agents-owners.json"
  minimal_manifest '[]' '[]'
  jq --arg h "$recorded_home" '.home=$h | .adapters_failed=["opencode"]' "$MB_MANIFEST_PATH" > "$T/top.json"
  mv "$T/top.json" "$MB_MANIFEST_PATH"
  tree_state "$PROJECT" > "$T/project.before"; tree_state "$HOME" > "$T/home.before"
  tree_state "$MB_MANIFEST_PATH" > "$T/manifest.before"
  edge_call bash "$SRC/uninstall.sh" -y "$@"
  tree_state "$PROJECT" > "$T/project.after"; tree_state "$HOME" > "$T/home.after"
  tree_state "$MB_MANIFEST_PATH" > "$T/manifest.after"
  local label
  for label in project home manifest; do
    receipt "$label.before" "$T/$label.before"; receipt "$label.after" "$T/$label.after"
  done
  [ -f "$PROJECT/.opencode/commands/start.md" ]
  [ -f "$PROJECT/.mb-agents-owners.json" ]
  cmp -s "$T/project.before" "$T/project.after"
  cmp -s "$T/home.before" "$T/home.after"
  cmp -s "$T/manifest.before" "$T/manifest.after"
  [ "$status" -ne 0 ]
  assert_substring "$output" 'HOME'
}

@test "S5-DISCOVERY-8: direct public uninstall refuses foreign HOME before any cleanup" {
  foreign_manifest_refusal "$T/foreign-home"
}
@test "S5-DISCOVERY-8: force cannot grant a foreign HOME manifest project ownership" {
  foreign_manifest_refusal "$T/foreign-home" --force
}
@test "S5-DISCOVERY-8: a HOME symlink alias is not uninstall ownership" {
  ln -s "$HOME" "$T/home-alias"
  foreign_manifest_refusal "$T/home-alias"
}
