# shellcheck shell=bash
# Private frozen installer fixture shared by the Stage 5 Bats contracts.
setup_file() {
  local repo
  repo="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  mkdir -p "$BATS_FILE_TMPDIR/assets"
  rsync -a --exclude='.env*' --exclude='__pycache__' \
    "$repo/"{adapters,agents,commands,hooks,scripts,rules,references,templates,flow-templates,settings,memory_bank_skill} \
    "$repo/"{install.sh,uninstall.sh,VERSION,SKILL.md} "$BATS_FILE_TMPDIR/assets/"
}

setup() {
  T="$BATS_TEST_TMPDIR"
  SRC="$T/bundle" PROJECT="$T/project"
  cp -R "$BATS_FILE_TMPDIR/assets" "$SRC"
  export HOME="$T/home" TMPDIR="$T/tmp"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/data" XDG_STATE_HOME="$HOME/state"
  export XDG_CACHE_HOME="$HOME/cache" XDG_RUNTIME_DIR="$HOME/run"
  export XDG_CONFIG_DIRS="$HOME/config-dirs" XDG_DATA_DIRS="$HOME/data-dirs" CODEX_HOME="$HOME/.codex"
  export MB_MANIFEST_PATH="$T/install-manifest.json"
  OC="$XDG_CONFIG_HOME/opencode" CALL_NUMBER=0
  mkdir -p "$HOME" "$PROJECT" "$TMPDIR" "$XDG_RUNTIME_DIR"
}

teardown() { chmod -R u+rwX "$T"; }

public() {
  env -i PATH="$PATH" HOME="$HOME" TMPDIR="$TMPDIR" CODEX_HOME="$CODEX_HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR" \
    XDG_CONFIG_DIRS="$XDG_CONFIG_DIRS" XDG_DATA_DIRS="$XDG_DATA_DIRS" \
    MB_MANIFEST_PATH="$MB_MANIFEST_PATH" MB_SKIP_DEPS_CHECK=1 MB_USER_RULES_AUTO_PROMPT=off \
    PYTHONDONTWRITEBYTECODE=1 "$@"
}

call() {
  CALL_NUMBER=$((CALL_NUMBER + 1)); status=0
  public "$@" > "$T/output" 2>&1 || status=$?
  output="$(cat "$T/output")"
  if [ -n "${S5_EVIDENCE_DIR:-}" ]; then
    cp "$T/output" "$S5_EVIDENCE_DIR/$BATS_TEST_NUMBER-$CALL_NUMBER.log"
    printf '%s\n' "$status" > "$S5_EVIDENCE_DIR/$BATS_TEST_NUMBER-$CALL_NUMBER.exit"
  fi
}

install() { call bash "$SRC/install.sh" --non-interactive --clients opencode --project-root "$PROJECT" "$@"; }
uninstall() { call bash "$SRC/uninstall.sh" -y; }
minimal_manifest() {
  jq -n --arg h "$HOME" --arg p "$PROJECT" --argjson f "$1" --argjson b "$2" \
    '{home:$h,project_root:$p,files:$f,backups:$b,clients:[],adapters_failed:[],file_sha256:{}}' > "$MB_MANIFEST_PATH"
}
configuration() { export XDG_CONFIG_HOME="$1"; OC="$XDG_CONFIG_HOME/opencode"; }

record_skill_directory() {
  local directory="$OC/skills/memory-bank" proof
  minimal_manifest "$(jq -n --arg p "$directory" '[$p]')" '[]'
  proof="$(public python3 "$SRC/adapters/opencode_files.py" backup-hash "$directory" "$MB_MANIFEST_PATH" "$OC")" || return 1
  jq --arg p "$directory" --arg h "$proof" '.file_sha256[$p] = $h' \
    "$MB_MANIFEST_PATH" > "$T/previous-manifest.json" || return 1
  mv "$T/previous-manifest.json" "$MB_MANIFEST_PATH"
}
