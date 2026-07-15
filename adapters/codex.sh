#!/usr/bin/env bash
# adapters/codex.sh — OpenAI Codex CLI cross-agent adapter.
#
# Codex reads AGENTS.md for project instructions (shared format with OpenCode
# and Pi fallback). Project-level settings live in .codex/config.toml.
# Experimental hooks live in .codex/hooks.json (userpromptsubmit stable,
# lifecycle hooks under development).
#
# Usage:
#   adapters/codex.sh install [PROJECT_ROOT]
#   adapters/codex.sh uninstall [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[codex-adapter] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ADAPTERS_DIR="$SKILL_DIR/adapters"
GIT_FALLBACK="$ADAPTERS_DIR/git-hooks-fallback.sh"
CODEX_DIR="$PROJECT_ROOT/.codex"
CONFIG_TOML="$CODEX_DIR/config.toml"
HOOKS_JSON="$CODEX_DIR/hooks.json"
MANIFEST="$CODEX_DIR/.mb-manifest.json"

# shellcheck source=./_lib_agents_md.sh
. "$(dirname "$0")/_lib_agents_md.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

# Paired markers delimiting the MB-managed block inside a (possibly user-owned)
# config.toml. Detection + idempotent upsert keys off these — never the whole file.
CONFIG_MARKER_START="# >>> memory-bank >>>"
CONFIG_MARKER_END="# <<< memory-bank <<<"

# Backups captured during this install (registered in the manifest for uninstall).
MB_CODEX_BACKUPS=()

# ═══ config.toml template ═══
config_toml_body() {
  cat <<TOML_EOF
$CONFIG_MARKER_START
# Memory Bank — Codex project settings
# memory-bank: managed config (do not remove marker lines)

# Read up to this many bytes from AGENTS.md (project doc discovery)
project_doc_max_bytes = 65536

# Fallback filenames when AGENTS.md is missing at a directory level
project_doc_fallback_filenames = ["CLAUDE.md", "CURSOR.md"]

# Approval policy — MB recommends on-request for defense-in-depth
approval_policy = "on-request"
$CONFIG_MARKER_END
TOML_EOF
}

# ═══ hooks.json body (experimental — userpromptsubmit stable) ═══
hooks_json_body() {
  cat <<'JSON_EOF'
{
  "version": 1,
  "_mb_warning": "Codex hooks API is experimental. Schema may change; re-run `adapters/codex.sh install` after Codex CLI upgrades.",
  "hooks": {
    "userpromptsubmit": [
      {
        "command": "bash .codex/hooks/before-prompt.sh",
        "_mb_owned": true
      }
    ]
  }
}
JSON_EOF
}

# Pre-prompt guard script — danger-payload blocking (existing) + a TTL-gated
# update notice (Task 6, REQ-014/REQ-019). Codex has no session-start
# surface; userpromptsubmit is the only native hook, and it fires on EVERY
# prompt — so the notice logic below self-gates on a local marker file
# rather than rendering on every single prompt.
#
# Two heredocs, on purpose (same technique as
# adapters/git-hooks-fallback.sh's dynamic-flow gate): the first is a
# LITERAL ('HOOK_EOF') heredoc — none of its `$` references expand now, they
# are the hook's own runtime variables. The second is an UNQUOTED (HOOK_EOF2)
# heredoc so `$notify_sh_q`/`$marker_q` — resolved once, at install time, and
# pre-quoted with `printf '%q'` so spaces/`$`/quotes in the install path
# survive intact — expand NOW; every runtime variable inside it is `\$`-
# escaped so it only expands when the hook itself runs.
before_prompt_body() {
  local notify_sh_q marker_q
  notify_sh_q="$(printf '%q' "$SKILL_DIR/hooks/mb-update-notify.sh")"
  marker_q="$(printf '%q' "$CODEX_DIR/.mb-update-notified")"

  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# Codex userpromptsubmit — block dangerous payloads + TTL-gated update notice
# memory-bank: managed hook
set -u
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null || true)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // empty' 2>/dev/null || true)
HOOK_EOF

  cat <<HOOK_EOF2

# ═══ update notice (REQ-014/REQ-019 — Codex honest tier) ═══
# The render itself is delegated to hooks/mb-update-notify.sh — that script
# already calls scripts/mb-version-check.sh --cache-only, is fail-open,
# honors MB_UPDATE_CHECK=off, and never touches the network in --cache-only
# mode (a stale/missing cache just answers "no update yet" and warms itself
# in the background for next time). Nothing here duplicates that logic —
# this block ONLY adds the "at most once per TTL window, not per prompt"
# gate a per-prompt hook needs that a per-session hook would not. Any
# failure (missing/unreadable notify script, unwritable marker dir, a
# non-zero/garbage resolver answer) degrades to silence — it NEVER blocks
# the prompt below.
if [ "\${MB_UPDATE_CHECK:-on}" != "off" ]; then
  _mb_notify_sh=$notify_sh_q
  _mb_marker=$marker_q
  if [ -n "\$_mb_notify_sh" ] && [ -r "\$_mb_notify_sh" ]; then
    _mb_ttl="\${MB_UPDATE_CHECK_TTL:-86400}"
    case "\$_mb_ttl" in ''|*[!0-9]*) _mb_ttl=86400 ;; esac
    _mb_fresh=0
    if [ -e "\$_mb_marker" ]; then
      _mb_mtime="\$(stat -c %Y "\$_mb_marker" 2>/dev/null || stat -f %m "\$_mb_marker" 2>/dev/null || echo 0)"
      case "\$_mb_mtime" in ''|*[!0-9]*) _mb_mtime=0 ;; esac
      _mb_now="\$(date +%s 2>/dev/null || echo 0)"
      case "\$_mb_now" in ''|*[!0-9]*) _mb_now=0 ;; esac
      _mb_age=\$(( _mb_now - _mb_mtime ))
      [ "\$_mb_age" -lt 0 ] && _mb_age=0
      [ "\$_mb_age" -lt "\$_mb_ttl" ] && _mb_fresh=1
    fi
    if [ "\$_mb_fresh" -ne 1 ]; then
      mkdir -p "\$(dirname "\$_mb_marker")" 2>/dev/null || true
      : > "\$_mb_marker" 2>/dev/null || true
      bash "\$_mb_notify_sh" 2>/dev/null || true
    fi
  fi
fi
HOOK_EOF2

  cat <<'HOOK_EOF3'

case "$PROMPT" in
  *"rm -rf /"*|*"rm -rf ~"*|*":(){ :|:& };:"*)
    printf '[MB-codex] BLOCKED dangerous prompt payload\n' >&2
    exit 2
    ;;
esac
exit 0
HOOK_EOF3
}

# ═══ Backup / merge helpers ═══
# Back up a user/foreign file exactly ONCE, before we first modify it. Skips when
# the file is already MB-managed (marker present) → idempotent, no backup creep,
# and the pristine first backup of the user's file is never overwritten.
codex_backup_if_exists() {
  local target="$1" marker="$2"
  [ -e "$target" ] || return 0
  if [ -n "$marker" ] && grep -qF "$marker" "$target" 2>/dev/null; then
    return 0
  fi
  local backup n
  backup="$target.pre-mb-backup.$(date +%s)"
  n=0
  while [ -e "$backup" ]; do
    n=$((n + 1))
    backup="$target.pre-mb-backup.$(date +%s).$n"
  done
  cp -p "$target" "$backup"
  MB_CODEX_BACKUPS+=("$backup")
}

# True (exit 0) iff the file carries a well-formed MB marker pair: exactly one
# start marker, exactly one end marker, start strictly before end. A corrupted or
# partial block (missing end marker from a manual edit / merge conflict /
# interrupted run) is NOT well-formed — callers must refuse to strip-to-EOF then,
# or they would silently truncate the user's content that follows the lone marker.
codex_markers_well_formed() {
  local target="$1"
  [ -f "$target" ] || return 1
  awk -v s="$CONFIG_MARKER_START" -v e="$CONFIG_MARKER_END" '
    index($0, s) { ns++; if (!sline) sline = NR }
    index($0, e) { ne++; if (!eline) eline = NR }
    END { exit !(ns == 1 && ne == 1 && sline < eline) }
  ' "$target"
}

# Emit the MB config block, dropping any top-level key the user's (post-strip)
# content already defines — TOML forbids duplicate top-level keys, so emitting a
# second `approval_policy`/`project_doc_max_bytes` would make strict parsers
# (tomllib, and Codex itself) reject the whole file. On collision we defer to the
# user's existing value. `$1` is the post-strip user content file (may be empty).
#
# Implemented in pure POSIX awk (no python/tomllib): a heredoc-parsed scan would
# add a hard python3 runtime dependency to config.toml install AND silently
# degrade to "no collisions" on any parse error — re-opening the dup-key bug
# exactly when the safety net matters. The awk scan collects genuine top-level
# keys (those before the first `[table]`/`[[array]]` header, outside any table),
# which is all the collision check needs, and never degrades.
codex_config_body_no_dupes() {
  local user_content="$1" skip_keys=""
  if [ -f "$user_content" ]; then
    skip_keys="$(awk '
      /^[[:space:]]*#/      { next }
      /^[[:space:]]*\[/     { intable = 1; next }
      !intable {
        if ($0 ~ /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/) {
          k = $0; sub(/[[:space:]]*=.*/, "", k); gsub(/[[:space:]]/, "", k)
          print k
        }
      }
    ' "$user_content" 2>/dev/null)"
  fi
  config_toml_body | MB_SKIP_KEYS="$skip_keys" awk '
    BEGIN {
      n = split(ENVIRON["MB_SKIP_KEYS"], arr, "\n")
      for (i = 1; i <= n; i++) if (arr[i] != "") skip[arr[i]] = 1
    }
    {
      line = $0
      if (line ~ /^[A-Za-z0-9_.-]+[[:space:]]*=/) {
        k = line; sub(/[[:space:]]*=.*/, "", k); gsub(/[[:space:]]/, "", k)
        if (k in skip) next
      }
      print
    }
  '
}

# Idempotent upsert of the MB block between paired markers. Any content outside
# the markers (user's own TOML keys) is preserved verbatim; a stale MB block is
# stripped before the fresh one is written, so repeat installs never duplicate.
# The MB block is emitted FIRST (before the user's content), because it carries
# top-level keys (project_doc_max_bytes, ...): in TOML every key after a `[table]`
# header belongs to that table, so appending MB after a user config that ends in
# a section (common: [history], [tui], [mcp_servers.*]) would silently nest MB's
# keys inside the user's last table. Leading = guaranteed genuine top level.
# Keys the user already defines at top level are omitted from the MB block so the
# merged file never carries a duplicate top-level key (invalid TOML).
codex_upsert_config_toml() {
  local target="$1" tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/mb-codex-cfg.XXXXXXXX")"
  if [ -f "$target" ]; then
    awk -v s="$CONFIG_MARKER_START" -v e="$CONFIG_MARKER_END" '
      BEGIN { inside = 0 }
      index($0, s) { inside = 1; next }
      index($0, e) { inside = 0; next }
      !inside { print }
    ' "$target" > "$tmp"
  else
    : > "$tmp"
  fi
  {
    codex_config_body_no_dupes "$tmp"
    cat "$tmp"
  } > "$tmp.body"
  mv "$tmp.body" "$target"
  rm -f "$tmp"
}

# Merge MB's userpromptsubmit hook into an existing hooks.json, preserving every
# user key + non-MB hook entry. Merge runs ONLY when the file is valid JSON AND
# has the expected shape (.hooks object-or-absent, .hooks.userpromptsubmit
# array-or-absent) — any other shape (still valid JSON but e.g. a string-valued
# .hooks) would make the merge jq filter abort under `set -euo pipefail` and kill
# the whole install mid-way, so it falls back to the fresh-MB-body branch (the
# original file is already backed up by the caller). MB's schema `version` is only
# set when the user hasn't already declared one (no silent downgrade); `_mb_warning`
# is MB's own namespaced-ish metadata. Atomic (tmp + mv).
codex_merge_hooks_json() {
  local target="$1" mb_body tmp
  mb_body="$(hooks_json_body)"
  tmp="$(mktemp "${TMPDIR:-/tmp}/mb-codex-hooks.XXXXXXXX")"
  if [ -f "$target" ] \
     && jq -e . "$target" >/dev/null 2>&1 \
     && jq -e '
          ((.hooks | type) as $h | $h == "null" or $h == "object")
          and ((.hooks.userpromptsubmit | type) as $u | $u == "null" or $u == "array")
        ' "$target" >/dev/null 2>&1; then
    jq --argjson mb "$mb_body" '
      . as $user
      | $user
      + { version: (if ($user | has("version")) then $user.version else $mb.version end),
          "_mb_warning": $mb._mb_warning }
      | .hooks = (($user.hooks // {}) + {
          userpromptsubmit: (
            (($user.hooks.userpromptsubmit // []) | map(select(._mb_owned != true)))
            + $mb.hooks.userpromptsubmit
          )
        })
    ' "$target" > "$tmp"
  else
    printf '%s\n' "$mb_body" > "$tmp"
  fi
  mv "$tmp" "$target"
}

# True (exit 0) iff MB created this file fresh at install — i.e. no pre-install
# user file existed, so codex_backup_if_exists took no `.pre-mb-backup.*`. This
# is the only safe signal for full-file removal on uninstall: a file the user
# already had (backup present) must never be deleted, only stripped — even if the
# strip leaves it looking MB-shaped (e.g. a user's own `{"version":N}`).
codex_mb_created_file() {
  local target="$1"
  ! ls "$target".pre-mb-backup.* >/dev/null 2>&1
}

# Inverse of codex_upsert_config_toml, used on uninstall: strip the MB block,
# preserving any foreign (user) content outside the markers verbatim. Remove the
# file entirely ONLY when it is MB-created AND nothing foreign remains; a file the
# user already had is kept even if it strips to whitespace.
codex_strip_config_toml_or_remove() {
  local target="$1" tmp
  [ -f "$target" ] || return 0
  # Refuse to strip a malformed/partial marker pair — the awk below would drop
  # everything from a lone start marker to EOF, silently truncating the user's
  # content. Leaving the file untouched (a cosmetic stray marker at worst) is
  # strictly safer than deleting real data on the "never lose foreign content" path.
  codex_markers_well_formed "$target" || return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/mb-codex-cfg-strip.XXXXXXXX")"
  awk -v s="$CONFIG_MARKER_START" -v e="$CONFIG_MARKER_END" '
    BEGIN { inside = 0 }
    index($0, s) { inside = 1; next }
    index($0, e) { inside = 0; next }
    !inside { print }
  ' "$target" > "$tmp"
  if grep -q '[^[:space:]]' "$tmp" 2>/dev/null; then
    mv "$tmp" "$target"           # foreign content remains → keep
  elif codex_mb_created_file "$target"; then
    rm -f "$tmp" "$target"        # MB-created and now empty → remove
  else
    mv "$tmp" "$target"           # user's pre-existing file → never delete
  fi
}

# Inverse of codex_merge_hooks_json, used on uninstall: drop only the MB-owned
# hook entries (and MB's `_mb_warning`), preserving every foreign key/hook
# untouched. A file that isn't valid JSON, OR is valid JSON but the wrong shape
# (e.g. a string-valued .hooks from a manual edit), is left untouched — we never
# guess at destructive surgery on data we can't safely parse/transform. The file
# is removed only when it is MB-created AND strips down to nothing user-owned.
codex_strip_hooks_json_or_remove() {
  local target="$1" tmp
  [ -f "$target" ] || return 0
  jq -e . "$target" >/dev/null 2>&1 || return 0
  # Shape guard mirroring the install side: a valid-JSON-but-wrong-shape file
  # would make the strip jq abort → empty tmp → truncation. Leave it untouched.
  jq -e '
    ((.hooks | type) as $h | $h == "null" or $h == "object")
    and ((.hooks.userpromptsubmit | type) as $u | $u == "null" or $u == "array")
  ' "$target" >/dev/null 2>&1 || return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/mb-codex-hooks-strip.XXXXXXXX")"
  jq '
    if (.hooks? and .hooks.userpromptsubmit?) then
      .hooks.userpromptsubmit |= map(select(._mb_owned != true))
    else . end
    | if (.hooks?.userpromptsubmit? and ((.hooks.userpromptsubmit | length) == 0)) then
        .hooks |= del(.userpromptsubmit)
      else . end
    | if (.hooks? and ((.hooks | length) == 0)) then
        del(.hooks)
      else . end
    | del(._mb_warning)
  ' "$target" > "$tmp" 2>/dev/null
  # Never mv an empty tmp (a jq failure) over the user's data.
  [ -s "$tmp" ] || { rm -f "$tmp"; return 0; }
  # `_mb_warning` (unambiguously MB's) is always removed above. A generic
  # top-level `version` may be the user's own → only delete the whole file when
  # it is MB-created AND nothing but (an MB-added) `version` / an empty object
  # would remain. A user's pre-existing file is kept, stripped, never removed.
  if jq -e '. == {} or (keys == ["version"])' "$tmp" >/dev/null 2>&1 \
     && codex_mb_created_file "$target"; then
    rm -f "$tmp" "$target"
  else
    mv "$tmp" "$target"
  fi
}

# ═══ Install ═══
install_codex() {
  adapter_require_jq "codex-adapter" || exit 1
  mkdir -p "$CODEX_DIR/hooks"

  # 1. AGENTS.md via shared lib (refcount aware)
  local owned
  owned=$(agents_md_install "$PROJECT_ROOT" "codex" "$SKILL_DIR")

  # 2. config.toml — back up any user file once, then idempotent MB-block upsert
  codex_backup_if_exists "$CONFIG_TOML" "$CONFIG_MARKER_START"
  codex_upsert_config_toml "$CONFIG_TOML"

  # 3. hooks.json (experimental) — back up once, then jq-merge preserving user keys
  codex_backup_if_exists "$HOOKS_JSON" '_mb_owned'
  codex_merge_hooks_json "$HOOKS_JSON"

  # 4. Pre-prompt script
  before_prompt_body > "$CODEX_DIR/hooks/before-prompt.sh"
  chmod +x "$CODEX_DIR/hooks/before-prompt.sh"

  # 4b. Session capture via git-hooks-fallback (B5 / F-5): Codex has no native
  # lifecycle hooks (only the experimental userpromptsubmit guard above) —
  # mirror pi.sh's wiring so Codex users still get post-commit auto-capture +
  # pre-commit <private> warnings in a git repo. `git rev-parse --git-dir`
  # (not `[ -d .git ]`) so a worktree (.git is a FILE there, per A9) is still
  # detected correctly. Wiring only — hook bodies live in git-hooks-fallback.sh.
  local git_hooks_installed=false
  if git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    MB_AGENT=codex bash "$GIT_FALLBACK" install "$PROJECT_ROOT" >/dev/null
    git_hooks_installed=true
  else
    echo "[codex-adapter] project is not a git repo; session-capture git hook skipped" >&2
  fi

  # 5. Manifest
  local files_json backups_json
  # Update-notice marker (Task 6) is written lazily by the hook at its FIRST
  # render, not at install time — still listed here so uninstall cleans it
  # up if it ever exists (the removal loop below is existence-guarded).
  files_json=$(printf '%s\n' "$CONFIG_TOML" "$HOOKS_JSON" "$CODEX_DIR/hooks/before-prompt.sh" "$CODEX_DIR/.mb-update-notified" | adapter_json_array_from_lines)
  if [ "${#MB_CODEX_BACKUPS[@]}" -gt 0 ]; then
    backups_json=$(printf '%s\n' "${MB_CODEX_BACKUPS[@]}" | adapter_json_array_from_lines)
  else
    backups_json='[]'
  fi

  adapter_write_manifest \
    "$MANIFEST" \
    "codex" \
    "$(cat "$SKILL_DIR/VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "$(jq -n --argjson owned "$owned" --argjson backups "$backups_json" --argjson git_hooks "$git_hooks_installed" \
      '{agents_md_owned: $owned, experimental_hooks: true, backups: $backups, git_hooks_installed: $git_hooks}')"

  echo "[codex-adapter] installed to $PROJECT_ROOT (hooks API: experimental)"
}

# ═══ Per-agent sub-invoke declaration (dynamic-flow Task 12, REQ-DF-082) ═══
# Codex's shell sub-invoke command for the explicit fan-out engine (mb-fanout.sh).
# The adapter DECLARES the command (DoD#1) by delegating to the single source of
# truth — scripts/mb-subinvoke-resolve.sh's codex TABLE entry (with the operator
# override env-u'd out, see below) — so what the adapter declares is byte-identical
# to the codex table command mb-fanout bakes when --cmd is omitted and no override
# is set (no duplicated template to drift). The branch prompt flows ONLY through the
# exported MB_FANOUT_PROMPT env var (never interpolated): the resolver emits the
# literal $MB_FANOUT_PROMPT token, preserving mb-fanout's security seam.
codex_subinvoke_cmd() {
  # `env -u MB_SUBINVOKE_CMD`: the adapter DECLARATION is a STABLE Codex contract —
  # always the resolver's codex TABLE entry, never an inherited operator override.
  # The MB_SUBINVOKE_CMD override belongs to mb-fanout's RESOLVE path (baking a
  # custom --cmd), NOT to what the adapter declares as the canonical Codex command.
  env -u MB_SUBINVOKE_CMD MB_AGENT=codex bash "$SKILL_DIR/scripts/mb-subinvoke-resolve.sh" --agent codex
}

# ═══ Uninstall ═══
uninstall_codex() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[codex-adapter] no manifest found, nothing to uninstall"
    return 0
  fi
  adapter_require_jq "codex-adapter" || exit 1

  # 1a. config.toml/hooks.json may carry foreign (user) content merged in at
  #     install time — strip only the MB-managed block/hook entries, and only
  #     rm -f the file outright if nothing foreign remains. This MUST run
  #     before the generic manifest-file removal below, which would otherwise
  #     blindly rm -f a file that still holds the user's own keys.
  codex_strip_config_toml_or_remove "$CONFIG_TOML"
  codex_strip_hooks_json_or_remove "$HOOKS_JSON"

  # 1b. Remove remaining tracked files (before-prompt.sh is always MB-only;
  #     config.toml/hooks.json are skipped here — already handled above, and
  #     if either still exists it carries foreign content that must survive).
  local file_path
  while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    case "$file_path" in
      "$CONFIG_TOML" | "$HOOKS_JSON") continue ;;
      *) [ -f "$file_path" ] && rm -f "$file_path" ;;
    esac
  done < <(jq -r '.files[]?' "$MANIFEST")

  # 2. Decrement AGENTS.md ownership
  agents_md_uninstall "$PROJECT_ROOT" "codex"

  # 2b. Remove git-hooks-fallback session capture, if this adapter installed it
  # (B5 / F-5). Read the flag BEFORE the manifest is deleted below.
  local installed_git
  installed_git=$(jq -r '.git_hooks_installed // false' "$MANIFEST")
  if [ "$installed_git" = "true" ]; then
    bash "$GIT_FALLBACK" uninstall "$PROJECT_ROOT" >/dev/null 2>&1 || true
  fi

  # 3. Remove manifest
  rm -f "$MANIFEST"

  # 4. Clean empty dirs
  rmdir "$CODEX_DIR/hooks" 2>/dev/null || true
  rmdir "$CODEX_DIR" 2>/dev/null || true

  echo "[codex-adapter] uninstalled from $PROJECT_ROOT"
}

case "$ACTION" in
  install)   install_codex ;;
  uninstall) uninstall_codex ;;
  subinvoke) codex_subinvoke_cmd ;;
  *)
    echo "Usage: $0 install|uninstall|subinvoke [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac

adapter_contract_require_functions install_codex uninstall_codex codex_subinvoke_cmd >/dev/null
