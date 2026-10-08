# shellcheck shell=bash
# adapters/_lib_project_stamp.sh — freshness stamp of the managed project blocks (I-251).
#
# Sourced by _lib_agents_md.sh (callers source that one); uses its markers
# (MB_START_MARKER, MB_KR_START, MB_RULE_FILE_TITLE), _MB_AGENTS_LIB_DIR and
# _mb_skill_version.
#
# Every managed project unit — the Key rules block, the AGENTS.md MB block, a per-host
# rule file body — carries `mb-stamp: <VERSION>-<crc>`: the skill VERSION plus a
# checksum of the render inputs (templates, Key rules catalog, architecture presets,
# user + project rules profiles, the saved language, which RULES.md exists). The
# install path is left out on purpose: a source checkout and the installed copy stamp
# alike. Pure bash + cksum — the session-start hook runs it on every session.
MB_PROJECT_BLOCK_FILES="CLAUDE.md AGENTS.md .cursor/rules/memory-bank.mdc .windsurf/rules/memory-bank.md .clinerules/memory-bank.md .clinerules .kilocode/rules/memory-bank.md"

# $1 = project_root (its bank is <project_root>/.memory-bank).
mb_project_stamp() {
  local project="$1" root="$_MB_AGENTS_LIB_DIR/.." crc
  crc="$(
    {
      (cd "$root" && cat VERSION rules/key-rules.json scripts/mb-rules.sh scripts/mb_rules_sync_lib.sh \
        adapters/_lib_agents_md.sh \
        memory_bank_skill/key_rules.py memory_bank_skill/quality.py memory_bank_skill/_texttools.py \
        references/rules-presets/architecture/*.json)
      cat "$HOME/.claude/memory-bank/rules-profile.json" "$HOME/.claude/memory-bank-config.json" \
        "$project/.memory-bank/rules-profile.json"
      [ -f "$project/RULES.md" ] && echo R
      [ -f "$project/.memory-bank/RULES.md" ] && echo B
    } 2>/dev/null | cksum
  )"
  printf 'mb-stamp: %s-%08x\n' "$(_mb_skill_version "$root")" "${crc%% *}"
}

# $1 = project_root. Prints the stale files (relative, space-separated): a file with a
# managed unit (Key rules / MB block start marker, rule-file title) that lacks the
# current stamp. Nothing when every unit is fresh or the project has none.
mb_project_stale_files() {
  local project="$1" token f extra units fresh out=""
  token="$(mb_project_stamp "$project")"
  for f in $MB_PROJECT_BLOCK_FILES; do
    [ -f "$project/$f" ] || continue
    # The rule-file title counts only in the per-host rule files.
    case "$f" in CLAUDE.md|AGENTS.md) extra="$MB_KR_START" ;; *) extra="$MB_RULE_FILE_TITLE" ;; esac
    units="$(grep -cxF -e "$MB_KR_START" -e "$MB_START_MARKER" -e "$extra" "$project/$f" 2>/dev/null)" || true
    [ "${units:-0}" -gt 0 ] || continue
    fresh="$(grep -cF -- "$token" "$project/$f" 2>/dev/null)" || true
    [ "${fresh:-0}" -ge "$units" ] || out="$out $f"
  done
  printf '%s' "${out# }"
}

# $1 = project_root. Session-start check: stale blocks → one hint line naming the
# refresh command; MB_AUTO_REFRESH=on → refresh in place (the hint only if that fails).
mb_project_blocks_hint() {
  local project="$1" stale rules_sh
  stale="$(mb_project_stale_files "$project")"
  [ -n "$stale" ] || return 0
  rules_sh="$(cd "$_MB_AGENTS_LIB_DIR/../scripts" && pwd)/mb-rules.sh"
  if [ "${MB_AUTO_REFRESH:-off}" = on ] \
    && bash "$rules_sh" sync --scope=project --project="$project" >/dev/null 2>&1; then
    return 0
  fi
  printf "[memory-bank] Outdated managed blocks in %s — refresh: bash '%s' sync --scope=project (MB_AUTO_REFRESH=on does it at session start)\n" \
    "$stale" "$rules_sh"
}
