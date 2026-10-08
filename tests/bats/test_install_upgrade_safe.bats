#!/usr/bin/env bats
# Installing `main` over an older install (plan 2026-10-07_fix_upgrade-safe-install, Stage 1):
#   - a re-run of install.sh with no flags restores the saved options (language,
#     comments language, clients, project root); an explicit flag wins;
#   - an upgrade from v5.3.1 ends in the same files as a clean install of the
#     current tree: no leftovers of the old version, user text around the
#     managed blocks intact;
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
  unset MB_CLIENTS MB_LANGUAGE MB_COMMENTS_LANGUAGE MB_WITH_EXTENSIONS MB_PATH MB_AGENT MB_MANIFEST_PATH XDG_DATA_HOME || true
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
    rsync -a --exclude='.git' --exclude='.index' --exclude='.memsearch' \
      --exclude='/tests' --exclude='node_modules' --exclude='.venv' --exclude='/.pi' \
      --exclude='/.memory-bank' --exclude='.installed-manifest.json' "$REPO_ROOT/" "$T/current/"
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

# _tree_listing <dir> — one line per path: type + content hash. Manifest
# timestamps and backup lists are dropped; project .git internals other than
# hooks are skipped (a fresh `git init` differs in nothing we manage).
_tree_listing() {
  /usr/bin/python3 - "$1" <<'PY'
import hashlib, json, os, sys
root = sys.argv[1]
VOLATILE = {"installed_at", "backups"}
def norm(v):
    if isinstance(v, dict):
        return {k: norm(x) for k, x in v.items() if k not in VOLATILE}
    if isinstance(v, list):
        return [norm(x) for x in v]
    return v
out = []
for d, dirs, files in os.walk(root):
    rel_d = os.path.relpath(d, root)
    if rel_d.split(os.sep)[:2] == ["project", ".git"] or rel_d == os.path.join("project", ".git"):
        keep = rel_d in (os.path.join("project", ".git"), os.path.join("project", ".git", "hooks"))
        if not keep:
            dirs[:] = []
            continue
        if rel_d == os.path.join("project", ".git"):
            dirs[:] = [x for x in dirs if x == "hooks"]
            files = [f for f in files if f.startswith("mb-")]
    for name in sorted(dirs + files):
        p = os.path.join(d, name)
        rel = os.path.relpath(p, root)
        if os.path.islink(p):
            out.append(f"{rel} -> {os.readlink(p)}")
            if name in dirs:
                dirs.remove(name)
            continue
        if os.path.isdir(p):
            out.append(f"{rel}/")
            continue
        data = open(p, "rb").read()
        if "manifest" in name and name.endswith(".json"):
            try:
                data = json.dumps(norm(json.loads(data)), sort_keys=True).encode()
            except ValueError:
                pass
        out.append(f"{rel} {hashlib.sha256(data).hexdigest()[:16]}")
print("\n".join(sorted(out)))
PY
}

_snapshot() {
  rm -rf "${T:?}/$1"
  mkdir -p "$T/$1"
  cp -a "$HOME" "$PROJECT" "$T/$1/"
}

@test "upgrade from $OLD_REF with no flags equals a clean install of the current tree" {
  git -C "$REPO_ROOT" rev-parse -q --verify "$OLD_REF^{commit}" >/dev/null || skip "$OLD_REF tag not available"

  # Reference: clean current install, user text added, plain re-run.
  _sync_current
  _install --non-interactive --language ru --clients "$CLIENTS_ALL" --project-root "$PROJECT"
  _add_user_text
  _install
  run _backups
  [ -z "$output" ]
  _snapshot clean

  # Upgrade: the old release installs, the user adds text, main is pulled over it.
  _fresh
  git -C "$REPO_ROOT" archive "$OLD_REF" | tar -x -C "$SRC"
  _install --non-interactive --language ru --clients "$CLIENTS_ALL" --project-root "$PROJECT"
  _add_user_text
  _sync_current
  _install
  run _backups
  [ -z "$output" ]
  _snapshot upgraded

  _tree_listing "$T/clean" > "$T/clean.list"
  _tree_listing "$T/upgraded" > "$T/upgraded.list"
  run diff "$T/clean.list" "$T/upgraded.list"
  if [ "$status" -ne 0 ]; then
    echo "$output" >&3
  fi
  [ "$status" -eq 0 ]

  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    assert_grep -qF "$USER_HEAD" "$f"
    assert_grep -qF "$USER_TAIL" "$f"
  done < <(_instruction_files)
  [ "$(_manifest .language)" = ru ]
  [ "$(_manifest .clients_requested)" = "$CLIENTS_ALL" ]
  [ "$(_manifest .project_root)" = "$PROJECT" ]
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
  mkdir -p "$HOME"
  _install
  [ "$(_manifest .language)" = en ]
  [ "$(_manifest .clients_requested)" = claude-code ]
}

@test "I-250: re-install over the skill's own unedited files makes no backups; an edited one keeps a backup" {
  _sync_current
  _install --non-interactive --language ru --clients "$CLIENTS_ALL" --project-root "$PROJECT"
  # What an older version left behind: same paths, other content, recorded as
  # written by that install (sha256 in the main manifest; adapter files dated
  # no later than their adapter manifest).
  local f old_agent="$HOME/.claude/agents/mb-doctor.md" old_rules="$HOME/.claude/RULES.md"
  local old_prompt="$HOME/.codex/prompts/mb.md" oc_agent="$PROJECT/.opencode/agent/mb-doctor.md"
  printf 'old agent\n' > "$old_agent"
  printf 'old rules\n' > "$old_rules"
  printf 'old command\n' > "$old_prompt"
  printf 'old oc agent\n' > "$oc_agent"
  touch -r "$PROJECT/.opencode/.mb-manifest.json" "$oc_agent"
  local m="$SRC/.installed-manifest.json"
  for f in "$old_agent" "$old_rules" "$old_prompt"; do
    jq --arg f "$f" --arg s "$(shasum -a 256 "$f" | cut -d' ' -f1)" '.file_sha256[$f] = $s' "$m" > "$T/m.json"
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
  sha="$(printf 'shipped\n' | shasum -a 256 | cut -d' ' -f1)"
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
_install_here() {
  (cd "$PROJECT" && bash "$SRC/install.sh" "$@" </dev/null >>"$T/install.log" 2>"$T/err.log")
}

@test "no previous manifest (pipx --force): options are inferred from the config and client traces; only edited files get backups" {
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

  _install_here
  [ "$(_manifest .language)" = ru ]
  [ "$(_manifest .clients_requested)" = claude-code,cursor,codex ]
  [ "$(_manifest .project_root)" = "$PROJECT" ]
  assert_grep -qF 'inferred' "$T/err.log"
  assert_grep -qF 'memory-bank-config.json' "$T/err.log"
  run _backups
  [ "$output" = "$(ls "$HOME"/.claude/commands/mb.md.pre-mb-backup.*)" ]
  assert_grep -qF 'my tweak' "$HOME"/.claude/commands/mb.md.pre-mb-backup.*
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    assert_grep -qF "$USER_HEAD" "$f"
  done < <(_instruction_files)

  # An explicit flag still wins over what is inferred.
  rm -f "$SRC/.installed-manifest.json"
  _install_here --language en
  [ "$(_manifest .language)" = en ]
  [ "$(_manifest .clients_requested)" = claude-code,cursor,codex ]
}

@test "no previous manifest: the comments language is restored from the config" {
  _sync_current
  _install --non-interactive --language ru --comments-language en --clients claude-code --project-root "$PROJECT"
  rm -f "$SRC/.installed-manifest.json"
  _install_here
  [ "$(_manifest .language)" = ru ]
  [ "$(_manifest .comments_language)" = en ]
}

@test "fresh HOME without any previous install: defaults, nothing inferred" {
  _sync_current
  _install_here
  [ "$(_manifest .language)" = en ]
  [ "$(_manifest .clients_requested)" = claude-code ]
  refute_grep -qF 'inferred' "$T/err.log"
}
