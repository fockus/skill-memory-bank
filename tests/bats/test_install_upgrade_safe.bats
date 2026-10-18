#!/usr/bin/env bats
# Installing `main` over an older install (plan 2026-10-07_fix_upgrade-safe-install, Stage 1):
#   - a re-run of install.sh with no flags restores the saved options (language,
#     comments language, clients, project root); an explicit flag wins;
#   - hashless v5.3.1 and deleted-manifest installs preserve candidate files
#     and refuse automatic OpenCode replacement; inference supplies options,
#     never ownership; established-ownership upgrades remain supported;
#   - I-250: files the previous install wrote are overwritten without a
#     `.pre-mb-backup.*` copy; a foreign file at a managed path still gets one;
#   - a file the old install wrote and the new one does not is removed when
#     unchanged, otherwise moved to a backup with a warning.
# Temp HOME + temp project + a copy of the skill (the real ~/ and the repo
# manifest are never touched).

load lib/assert

CLIENTS_ALL=claude-code,codex,cursor,opencode,pi,windsurf,cline,kilo
OLD_REF=v5.3.1

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  # PyYAML lives in the real user site; keep it importable under the temp HOME.
  PYTHONUSERBASE="$(/usr/bin/python3 -m site --user-base)"
  export PYTHONUSERBASE
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  PROJECT="$T/project"
  SRC="$T/skill"
  export MB_SKIP_DEPS_CHECK=1 MB_USER_RULES_AUTO_PROMPT=off
  unset MB_CLIENTS MB_LANGUAGE MB_COMMENTS_LANGUAGE MB_WITH_EXTENSIONS MB_PATH MB_AGENT MB_MANIFEST_PATH XDG_DATA_HOME CODEX_HOME || true
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"
  export XDG_RUNTIME_DIR="$HOME/run" XDG_CONFIG_DIRS="$HOME/config-dirs" XDG_DATA_DIRS="$HOME/data-dirs"
  export CODEX_HOME="$HOME/.codex" TMPDIR="$T/tmp"
  mkdir -p "$TMPDIR" "$XDG_RUNTIME_DIR"
  command -v jq >/dev/null || skip "jq required"
  command -v rsync >/dev/null || skip "rsync required"
  _fresh
}

_fresh() {
  rm -rf "$HOME" "$PROJECT" "$SRC"
  mkdir -p "$HOME" "$PROJECT" "$SRC"
  git -C "$PROJECT" init -q
}

# Same layout as a `git pull` of main into the existing skill checkout. The
# working tree is staged once per test, so both installs see the same files
# even while the repo is being edited.
_sync_current() {
  if [ ! -d "$T/current" ]; then
    mkdir -p "$T/current"
    rsync -a --exclude='.env*' --exclude='__pycache__' \
      "$REPO_ROOT/"{adapters,agents,commands,hooks,scripts,rules,references,templates,flow-templates,settings,memory_bank_skill} \
      "$REPO_ROOT/"{install.sh,uninstall.sh,VERSION,SKILL.md} "$T/current/"
  fi
  rsync -a --delete --exclude='.installed-manifest.json' "$T/current/" "$SRC/"
}

# _install <args...> — run the skill copy's installer from / (not the project).
_install() {
  (cd / && bash "$SRC/install.sh" "$@" </dev/null >>"$T/install.log" 2>&1)
}

_manifest() { jq -r "$1" "$SRC/.installed-manifest.json"; }

_backups() {
  find "$HOME" "$PROJECT" -name '*.pre-mb-backup.*' 2>/dev/null
}

USER_HEAD='USER_HEAD_LINE keep me above'
USER_TAIL='USER_TAIL_LINE keep me below'

# Instruction files that carry a managed block next to the user's own text.
_instruction_files() {
  printf '%s\n' "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/.pi/agent/AGENTS.md" \
    "$HOME/.config/opencode/AGENTS.md" "$PROJECT/AGENTS.md" "$PROJECT/CLAUDE.md"
}

_add_user_text() {
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    { printf '# My notes\n%s\n\n' "$USER_HEAD"; cat "$f"; printf '\n## My tail\n%s\n' "$USER_TAIL"; } > "$f.new"
    mv "$f.new" "$f"
  done < <(_instruction_files)
}

# _tree_listing <dir> — exact candidate bytes and file/link identities.
# Git internals other than hooks are not installer candidates.
_tree_listing() {
  /usr/bin/python3 - "$1" <<'PY'
import hashlib, os, stat, sys
root = sys.argv[1]
out = []
def failed(exc):
    raise exc
for d, dirs, files in os.walk(root, onerror=failed):
    rel_d = os.path.relpath(d, root)
    if rel_d == '.git' or rel_d.startswith('.git' + os.sep):
        if rel_d not in ('.git', os.path.join('.git', 'hooks')):
            dirs[:] = []
            continue
        if rel_d == '.git':
            dirs[:] = [x for x in dirs if x == "hooks"]
            files = [f for f in files if f.startswith("mb-")]
    for name in sorted(dirs + files):
        p = os.path.join(d, name)
        rel = os.path.relpath(p, root)
        info = os.lstat(p)
        identity = f'{info.st_dev}:{info.st_ino}:{stat.S_IMODE(info.st_mode):o}:{info.st_uid}:{info.st_gid}'
        if os.path.islink(p):
            out.append(f"{rel} {identity} -> {os.readlink(p)}")
            if name in dirs:
                dirs.remove(name)
            continue
        if os.path.isdir(p):
            out.append(f"{rel}/")
            continue
        data = open(p, "rb").read()
        out.append(f"{rel} {identity} {hashlib.sha256(data).hexdigest()}")
print("\n".join(sorted(out)))
PY
}

_snapshot() {
  _tree_listing "$HOME" > "$T/$1.home" || return 1
  _tree_listing "$PROJECT" > "$T/$1.project"
}

_assert_snapshot_unchanged() {
  _snapshot after || return 1
  cmp "$T/before.home" "$T/after.home" || return 1
  cmp "$T/before.project" "$T/after.project"
}

_sha256() {
  /usr/bin/python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
}

_inferred_options() {
  bash -c '
    source "$1/scripts/_lib.sh" || exit $?
    source "$1/scripts/_install_options.sh" || exit $?
    mb_inferred_install_options "$2" || exit $?
    printf "language=%s\ncomments=%s\nclients=%s\n" "$MB_SAVED_LANGUAGE" "$MB_SAVED_COMMENTS_LANGUAGE" "$MB_SAVED_CLIENTS"
  ' _ "$SRC" "$PROJECT"
}

@test "upgrade from genuine $OLD_REF without hashes refuses replacement and preserves every candidate" {
  git -C "$REPO_ROOT" rev-parse -q --verify "$OLD_REF^{commit}" >/dev/null || skip "$OLD_REF tag not available"

  # Authentic producer, not a current fixture retroactively granted hashes.
  git -C "$REPO_ROOT" archive "$OLD_REF" | tar -x -C "$SRC"
  _install --non-interactive --language ru --clients "$CLIENTS_ALL" --project-root "$PROJECT"
  _add_user_text
  jq -e '.file_sha256 == null' "$SRC/.installed-manifest.json"
  snapshot "$SRC/.installed-manifest.json" "$T/legacy-manifest.before"
  cp "$PROJECT/.codex/hooks.json" "$T/legacy-codex-hooks.json"
  _sync_current
  run _inferred_options
  [ "$status" -eq 0 ]
  assert_substring "$output" 'language=ru'
  _snapshot before
  mv "$T/install.log" "$T/producer-install.log"
  run _install
  [ "$status" -ne 0 ]
  assert_grep -qiE 'verifiable.*ownership' "$T/install.log"
  assert_grep -qF "$HOME/.config/opencode/commands/adr.md" "$T/install.log"
  refute_grep -qF 'Manifest saved' "$T/install.log"
  _assert_snapshot_unchanged
  assert_unchanged "$SRC/.installed-manifest.json" "$T/legacy-manifest.before"
  assert_unchanged "$PROJECT/.codex/hooks.json" "$T/legacy-codex-hooks.json"
  jq -e '.file_sha256 == null' "$SRC/.installed-manifest.json"

  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    assert_grep -qF "$USER_HEAD" "$f"
    assert_grep -qF "$USER_TAIL" "$f"
  done < <(_instruction_files)
}

@test "re-run without flags keeps the saved options; an explicit flag overrides one of them" {
  _sync_current
  _install --non-interactive --language ru --comments-language en --clients claude-code,codex --project-root "$PROJECT"
  rm -rf "$PROJECT/.codex"

  _install
  [ "$(_manifest .language)" = ru ]
  [ "$(_manifest .comments_language)" = en ]
  [ "$(_manifest .clients_requested)" = claude-code,codex ]
  [ "$(_manifest .project_root)" = "$PROJECT" ]
  [ -d "$PROJECT/.codex" ]
  assert_grep -qF '"preferred_language": "ru"' "$HOME/.claude/memory-bank-config.json"

  _install --language en
  [ "$(_manifest .language)" = en ]
  [ "$(_manifest .clients_requested)" = claude-code,codex ]
  [ "$(_manifest .project_root)" = "$PROJECT" ]
}

@test "saved options of another HOME are ignored" {
  _sync_current
  _install --non-interactive --language ru --clients claude-code,codex --project-root "$PROJECT"
  export HOME="$T/other-home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"
  export XDG_RUNTIME_DIR="$HOME/run" XDG_CONFIG_DIRS="$HOME/config-dirs" XDG_DATA_DIRS="$HOME/data-dirs"
  export CODEX_HOME="$HOME/.codex" TMPDIR="$HOME/tmp"
  mkdir -p "$TMPDIR" "$XDG_RUNTIME_DIR"
  _install
  [ "$(_manifest .language)" = en ]
  [ "$(_manifest .clients_requested)" = claude-code ]
}

@test "I-250: re-install over the skill's own unedited files makes no backups; an edited one keeps a backup" {
  _sync_current
  _install --non-interactive --language ru --clients "$CLIENTS_ALL" --project-root "$PROJECT"
  # What an older version left behind: same paths, other content, recorded as
  # written by that install, with the actual installed hashes in both manifests.
  local f sha old_agent="$HOME/.claude/agents/mb-doctor.md" old_rules="$HOME/.claude/RULES.md"
  local old_prompt="$HOME/.codex/prompts/mb.md" oc_agent="$PROJECT/.opencode/agent/mb-doctor.md"
  printf 'old agent\n' > "$old_agent"
  printf 'old rules\n' > "$old_rules"
  printf 'old command\n' > "$old_prompt"
  printf 'old oc agent\n' > "$oc_agent"
  local oc_manifest="$PROJECT/.opencode/.mb-manifest.json"
  sha="$(_sha256 < "$oc_agent")" || return 1
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]]
  jq --arg f "$oc_agent" --arg s "$sha" \
    '.file_sha256[$f] = $s' "$oc_manifest" > "$T/oc-m.json"
  mv "$T/oc-m.json" "$oc_manifest"
  local m="$SRC/.installed-manifest.json"
  for f in "$old_agent" "$old_rules" "$old_prompt"; do
    sha="$(_sha256 < "$f")" || return 1
    [[ "$sha" =~ ^[0-9a-f]{64}$ ]]
    jq --arg f "$f" --arg s "$sha" '.file_sha256[$f] = $s' "$m" > "$T/m.json"
    mv "$T/m.json" "$m"
  done
  # A file of ours the user edited after the install.
  printf 'my tweak\n' >> "$HOME/.claude/commands/mb.md"

  _install
  run _backups
  [ "$output" = "$(ls "$HOME"/.claude/commands/mb.md.pre-mb-backup.*)" ]
  assert_grep -qF 'my tweak' "$HOME"/.claude/commands/mb.md.pre-mb-backup.*
  refute_grep -qF 'old agent' "$old_agent"
  refute_grep -qF 'old rules' "$old_rules"
  refute_grep -qF 'old command' "$old_prompt"
  refute_grep -qF 'old oc agent' "$oc_agent"
}

@test "I-250: a foreign file at a managed path is backed up" {
  _sync_current
  mkdir -p "$HOME/.claude/agents"
  printf 'MY OWN AGENT\n' > "$HOME/.claude/agents/mb-doctor.md"
  _install --non-interactive --clients claude-code --project-root "$PROJECT"
  run _backups
  assert_substring "$output" "mb-doctor.md.pre-mb-backup."
  assert_grep -qF 'MY OWN AGENT' "$HOME"/.claude/agents/mb-doctor.md.pre-mb-backup.*
}

@test "orphan of the previous install: removed when unchanged, backed up with a warning when edited" {
  _sync_current
  _install --non-interactive --clients claude-code --project-root "$PROJECT"
  local kept="$HOME/.claude/commands/retired-same.md" edited="$HOME/.claude/commands/retired-edited.md"
  local foreign="$HOME/.claude/commands/my-own.md"
  printf 'shipped\n' > "$kept"
  printf 'shipped\n' > "$edited"
  printf 'mine\n' > "$foreign"
  local sha
  sha="$(printf 'shipped\n' | _sha256)" || return 1
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]]
  jq --arg a "$kept" --arg b "$edited" --arg s "$sha" \
    '.files += [$a, $b] | .file_sha256[$a] = $s | .file_sha256[$b] = $s' \
    "$SRC/.installed-manifest.json" > "$T/m.json"
  mv "$T/m.json" "$SRC/.installed-manifest.json"
  printf 'user edit\n' >> "$edited"

  _install
  refute_file "$kept"
  refute_file "$edited"
  assert_grep -qF 'user edit' "$edited".pre-mb-backup.*
  assert_grep -qF 'retired-edited.md' "$T/install.log"
  [ -f "$foreign" ]
}

@test "Homebrew keg: the manifest lives outside the versioned keg so saved options survive brew upgrade" {
  # shellcheck disable=SC1091
  . "$REPO_ROOT/scripts/_lib.sh"
  local old="$T/opt/homebrew/Cellar/memory-bank/5.3.1/share/memory-bank-skill"
  local new="$T/opt/homebrew/Cellar/memory-bank/5.4.0/share/memory-bank-skill"
  mkdir -p "$old" "$new"
  [ "$(mb_resolve_manifest_path "$new")" = "$HOME/.local/share/memory-bank/.installed-manifest.json" ]
  # An install made before this change keeps finding its own manifest (uninstall).
  printf '{}' > "$old/.installed-manifest.json"
  [ "$(mb_resolve_manifest_path "$old")" = "$old/.installed-manifest.json" ]
}

@test "Homebrew upgrade: saved options are read from the previous keg when the user dir has none" {
  local cellar="$T/opt/homebrew/Cellar/memory-bank" rel="share/memory-bank-skill"
  # Two older kegs, each with a co-located manifest (pre-fix brew installs); the newest wins.
  _sync_current
  mkdir -p "$cellar/5.2.0/$rel" "$cellar/5.3.1/$rel"
  rsync -a "$SRC/" "$cellar/5.3.1/$rel/"
  MB_MANIFEST_PATH="$cellar/5.3.1/$rel/.installed-manifest.json" \
    bash "$cellar/5.3.1/$rel/install.sh" --non-interactive --language ru --clients claude-code,codex \
    --project-root "$PROJECT" </dev/null >>"$T/install.log" 2>&1
  jq '.language = "es"' "$cellar/5.3.1/$rel/.installed-manifest.json" > "$cellar/5.2.0/$rel/.installed-manifest.json"
  touch -t 202001010000 "$cellar/5.2.0/$rel/.installed-manifest.json"

  # brew upgrade: a new keg; the old ones may still be there until cleanup.
  mkdir -p "$cellar/5.4.0/$rel"
  rsync -a "$SRC/" "$cellar/5.4.0/$rel/"
  (cd / && bash "$cellar/5.4.0/$rel/install.sh" </dev/null >>"$T/install.log" 2>&1)

  local m="$HOME/.local/share/memory-bank/.installed-manifest.json"
  [ "$(jq -r .language "$m")" = ru ]
  [ "$(jq -r .clients_requested "$m")" = claude-code,codex ]
  [ "$(jq -r .project_root "$m")" = "$PROJECT" ]
  run _backups
  [ -z "$output" ]
}

@test "re-run inside another project installs there; from a non-project directory the saved project is kept" {
  _sync_current
  _install --non-interactive --clients claude-code,cursor --project-root "$PROJECT"
  local other="$T/other-project" plain="$T/plain-dir"
  mkdir -p "$other" "$plain"
  git -C "$other" init -q

  (cd "$other" && bash "$SRC/install.sh" </dev/null >>"$T/install.log" 2>"$T/err.log")
  [ "$(_manifest .project_root)" = "$other" ]
  [ -d "$other/.cursor" ]
  assert_grep -qF "current project $other" "$T/err.log"

  (cd "$plain" && bash "$SRC/install.sh" </dev/null >>"$T/install.log" 2>&1)
  [ "$(_manifest .project_root)" = "$other" ]
  refute_file "$plain/.cursor"

  # The skill checkout itself (mb-upgrade.sh, `bash install.sh` from the clone) is not a target.
  git -C "$SRC" init -q && rm -rf "$SRC/.cursor"
  (cd "$SRC" && bash "$SRC/install.sh" </dev/null >>"$T/install.log" 2>&1)
  [ "$(_manifest .project_root)" = "$other" ]
  refute_file "$SRC/.cursor"
}

@test "windsurf: a re-install does not back up its own hooks.json; a user-edited one is backed up and keeps the user's hook" {
  _sync_current
  local hj="$PROJECT/.windsurf/hooks.json"
  _install --non-interactive --clients windsurf --project-root "$PROJECT"
  _install
  _install
  run _backups
  [ -z "$output" ]

  jq '.hooks["user-prompt-submit"] += [{command: "bash my-own-hook.sh"}]' "$hj" > "$T/h.json"
  mv "$T/h.json" "$hj"
  _install
  run _backups
  assert_substring "$output" "hooks.json.pre-mb-backup."
  assert_grep -qF 'my-own-hook.sh' "$hj"
  assert_grep -qF 'before-prompt.sh' "$hj"
}

# _install_here <args...> — run the skill copy's installer from the project dir.
# shellcheck disable=SC2120 # Bats run forwards the explicit --language argument.
_install_here() {
  (cd "$PROJECT" && bash "$SRC/install.sh" "$@" </dev/null >>"$T/install.log" 2>"$T/err.log")
}

@test "no previous manifest (pipx --force): inferred options do not authorize replacement of genuine legacy files" {
  git -C "$REPO_ROOT" rev-parse -q --verify "$OLD_REF^{commit}" >/dev/null || skip "$OLD_REF tag not available"
  git -C "$REPO_ROOT" archive "$OLD_REF" | tar -x -C "$SRC"
  _install --non-interactive --language ru --clients claude-code,codex,cursor --project-root "$PROJECT"
  _add_user_text
  # A file of ours the user edited later than that install.
  printf 'my tweak\n' >> "$HOME/.claude/commands/mb.md"
  /usr/bin/python3 -c 'import os, sys; t = os.path.getmtime(sys.argv[1]) + 3600; os.utime(sys.argv[2], (t, t))' \
    "$HOME/.claude/memory-bank-config.json" "$HOME/.claude/commands/mb.md"
  _sync_current
  rm -f "$SRC/.installed-manifest.json"

  run _inferred_options
  [ "$status" -eq 0 ]
  assert_substring "$output" 'language=ru'
  assert_substring "$output" 'clients=claude-code,cursor,codex'
  _snapshot before
  mv "$T/install.log" "$T/producer-install.log"
  run _install_here
  [ "$status" -ne 0 ]
  assert_grep -qF 'inferred' "$T/err.log"
  assert_grep -qF 'memory-bank-config.json' "$T/err.log"
  assert_grep -qiE 'verifiable.*ownership' "$T/err.log" "$T/install.log"
  refute_grep -qF 'Manifest saved' "$T/install.log"
  [ ! -e "$SRC/.installed-manifest.json" ]
  _assert_snapshot_unchanged
  assert_grep -qF 'my tweak' "$HOME/.claude/commands/mb.md"
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    assert_grep -qF "$USER_HEAD" "$f"
  done < <(_instruction_files)

  # An explicit option wins, but still supplies no ownership authority.
  run _install_here --language en
  [ "$status" -ne 0 ]
  assert_grep -qF 'Preferred language: en' "$T/install.log"
  [ ! -e "$SRC/.installed-manifest.json" ]
  _assert_snapshot_unchanged
}

@test "no previous manifest: comments language inference survives a preservation-safe refusal" {
  _sync_current
  _install --non-interactive --language ru --comments-language en --clients claude-code --project-root "$PROJECT"
  rm -f "$SRC/.installed-manifest.json"
  run _inferred_options
  [ "$status" -eq 0 ]
  assert_substring "$output" 'language=ru'
  assert_substring "$output" 'comments=en'
  _snapshot before
  mv "$T/install.log" "$T/producer-install.log"
  run _install_here
  [ "$status" -ne 0 ]
  assert_grep -qiE 'verifiable.*ownership' "$T/err.log" "$T/install.log"
  [ ! -e "$SRC/.installed-manifest.json" ]
  refute_grep -qF 'Manifest saved' "$T/install.log"
  _assert_snapshot_unchanged
}

@test "fresh HOME without any previous install: defaults, nothing inferred" {
  _sync_current
  _install_here
  [ "$(_manifest .language)" = en ]
  [ "$(_manifest .clients_requested)" = claude-code ]
  refute_grep -qF 'inferred' "$T/err.log"
}

@test "S5-DISCOVERY-8: an early refusal never adopts a failed project from another HOME" {
  _sync_current
  bash "$SRC/adapters/opencode.sh" install "$PROJECT" >/dev/null
  local previous="$PROJECT" current="$T/new-project"
  snapshot "$previous/.opencode/commands/start.md" "$T/project.before"
  mkdir "$current"
  jq -n --arg h "$T/foreign-home" --arg p "$previous" \
    '{home:$h,project_root:$p,files:[],backups:[],file_sha256:{},clients:[],adapters_failed:["opencode"]}' \
    > "$SRC/.installed-manifest.json"
  mkdir -p "$T/home/.config/opencode/commands"
  printf 'Unmanaged global command\n' > "$T/home/.config/opencode/commands/mb.md"
  _snapshot before
  snapshot "$SRC/.installed-manifest.json" "$T/manifest.before"
  _tree_listing "$current" > "$T/current.before"
  run _install --non-interactive --clients opencode --project-root "$current"
  [ "$status" -ne 0 ]
  assert_grep -qF 'manifest HOME does not match current HOME' "$T/install.log"
  assert_grep -qF 'recovery: ' "$T/install.log"
  _assert_snapshot_unchanged
  assert_unchanged "$SRC/.installed-manifest.json" "$T/manifest.before"
  _tree_listing "$current" > "$T/current.after"
  cmp "$T/current.before" "$T/current.after"
  run bash "$SRC/uninstall.sh" -y
  [ "$status" -ne 0 ]
  assert_substring "$output" 'manifest HOME does not match current HOME'
  assert_substring "$output" 'inspect the path before retrying'
  _assert_snapshot_unchanged
  assert_unchanged "$SRC/.installed-manifest.json" "$T/manifest.before"
  _tree_listing "$current" > "$T/current.after"
  cmp "$T/current.before" "$T/current.after"
  assert_unchanged "$previous/.opencode/commands/start.md" "$T/project.before"
  [ -f "$previous/.mb-agents-owners.json" ]
}
