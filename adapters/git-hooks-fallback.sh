#!/usr/bin/env bash
# adapters/git-hooks-fallback.sh
#
# Git-hooks fallback for Memory Bank in clients without a native hooks API.
# Primary consumer: Kilo (only target client without first-class hooks — FR #5827).
# Secondary: Pi Code (transitional, until Skills lifecycle API stabilizes).
#
# Installs:
#   .git/hooks/post-commit  — auto-capture: append placeholder to progress.md
#                             (respects .session-lock + MB_AUTO_CAPTURE env)
#   .git/hooks/pre-commit   — warn (stderr) on <private> blocks in staged changes
#
# Chains to existing user hooks via backup+wrap (never overwrites).
# Idempotent: 2x install does not duplicate chains.
#
# Usage:
#   adapters/git-hooks-fallback.sh install [PROJECT_ROOT]
#   adapters/git-hooks-fallback.sh uninstall [PROJECT_ROOT]

set -euo pipefail

ACTION="${1:-}"
PROJECT_ROOT_RAW="${2:-$(pwd)}"

# Absolute dir of THIS adapter, resolved at install time. The bundled check
# runners live in ../scripts; we bake the resolved, absolute firewall path and
# the _skill_root.sh path into the generated pre-commit hook so closure
# enforcement works from any cwd the git hook runs in (REQ-DF-062). Install
# runs with the skill present, so these resolve correctly; if scripts/ is ever
# absent the hook degrades to inert (fail-safe).
#
# Defect 2 fix: baked paths are shell-quoted with printf '%q' so a space or $
# in the install path cannot be re-interpreted at hook runtime. The quoted
# string is emitted UNQUOTED into the heredoc so bash evaluates it literally.
ADAPTER_DIR="$(cd "$(dirname "$0")" && pwd)"
MB_FLOW_VERIFY="$ADAPTER_DIR/../scripts/mb-flow-verify.sh"
if [ -f "$MB_FLOW_VERIFY" ]; then
  MB_FLOW_VERIFY="$(cd "$(dirname "$MB_FLOW_VERIFY")" && pwd)/mb-flow-verify.sh"
fi
# Shell-quote both baked paths for safe embedding in the unquoted heredoc.
MB_FLOW_VERIFY_Q="$(printf '%q' "$MB_FLOW_VERIFY")"
# The global-aware resolver (mb_hook_resolve_mb_path) lives in hooks/_skill_root.sh,
# a SIBLING of this adapter's dir (both adapters/ and hooks/ sit under the skill
# root, in the repo AND the installed bundle) — it is NOT in adapters/. Resolve +
# normalize it for the generated hook's global-storage bank lookup (Defect 1 fix).
# A baked adapters/_skill_root.sh path is dead and silently disables registry
# resolution, so a red global flow would commit freely.
MB_SKILL_ROOT_SH="$ADAPTER_DIR/../hooks/_skill_root.sh"
if [ -f "$MB_SKILL_ROOT_SH" ]; then
  MB_SKILL_ROOT_SH="$(cd "$(dirname "$MB_SKILL_ROOT_SH")" && pwd)/_skill_root.sh"
fi
MB_SKILL_ROOT_SH_Q="$(printf '%q' "$MB_SKILL_ROOT_SH")"

# Bake a DETERMINISTIC Memory Bank agent at install time. The global-aware
# resolver (mb_hook_resolve_mb_path) and the firewall both fall back to
# mb_hook_default_agent when MB_AGENT is unset, which GUESSES 'cursor' whenever
# ~/.cursor/skills/memory-bank exists (install.sh creates that alias) — so a
# claude-code global bank would be looked up in the wrong registry and a red
# global flow would commit freely. Capture the installing agent now (default
# claude-code) and seed MB_AGENT in the hook so commit-time resolution never
# guesses. A commit-time MB_AGENT still wins (`:=` only sets when unset).
MB_AGENT_BAKED="${MB_AGENT:-claude-code}"
MB_AGENT_BAKED_Q="$(printf '%q' "$MB_AGENT_BAKED")"

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[git-hooks] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

# True iff PROJECT_ROOT is itself a git repo ROOT (toplevel). rev-parse is
# worktree/submodule safe (there `.git` is a file pointer), but `--git-dir` alone
# walks up to an enclosing repo — so we also require `--show-toplevel` to canonically
# equal PROJECT_ROOT, else a nested non-root subdir would wrongly wire an enclosing
# repo's hooks.
_mb_is_repo_root() {
  local top
  top="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] && [ "$(cd "$PROJECT_ROOT" && pwd -P)" = "$(cd "$top" && pwd -P)" ]
}

# Resolve the effective git dir + hooks dir via rev-parse (honors core.hooksPath).
# Falls back to the literal .git layout for a non-repo / non-root path (require_git_repo
# then reports it). `git -C` runs in PROJECT_ROOT so relative paths resolve there.
if _mb_is_repo_root && _mb_gd="$(git -C "$PROJECT_ROOT" rev-parse --git-dir 2>/dev/null)"; then
  case "$_mb_gd" in /*) GIT_DIR="$_mb_gd" ;; *) GIT_DIR="$PROJECT_ROOT/$_mb_gd" ;; esac
  if _mb_hp="$(git -C "$PROJECT_ROOT" rev-parse --git-path hooks 2>/dev/null)"; then
    case "$_mb_hp" in /*) HOOKS_DIR="$_mb_hp" ;; *) HOOKS_DIR="$PROJECT_ROOT/$_mb_hp" ;; esac
  else
    HOOKS_DIR="$GIT_DIR/hooks"
  fi
else
  GIT_DIR="$PROJECT_ROOT/.git"
  HOOKS_DIR="$GIT_DIR/hooks"
fi
MANIFEST="$GIT_DIR/mb-hooks-manifest.json"

# shellcheck disable=SC1091
. "$(dirname "$0")/_framework.sh"
# shellcheck disable=SC1091
. "$(dirname "$0")/_contract.sh"

require_git_repo() {
  if ! _mb_is_repo_root; then
    echo "[git-hooks] not a git repository root: $PROJECT_ROOT" >&2
    exit 1
  fi
}

# ═══ post-commit hook body ═══
post_commit_body() {
  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# memory-bank: managed hook (do not remove marker line)
set -u

# 1. Chain to user's original hook if we backed one up
_mb_backup="$(dirname "$0")/post-commit.pre-mb-backup"
[ -x "$_mb_backup" ] && "$_mb_backup" "$@"

# 2. Memory Bank auto-capture — honour MB_PATH env override for global mode.
_mb_repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
if [ -n "${MB_PATH:-}" ]; then
  _mb_dir="$MB_PATH"
else
  _mb_dir="$_mb_repo/.memory-bank"
fi
[ -d "$_mb_dir" ] || exit 0

# Respect MB_AUTO_CAPTURE env
case "${MB_AUTO_CAPTURE:-auto}" in
  off)    exit 0 ;;
  strict) printf '[MB strict] git post-commit: expected /mb done, skipping\n' >&2; exit 0 ;;
  auto|*) ;;
esac

# Respect fresh .session-lock (manual /mb done happened recently)
_mb_lock="$_mb_dir/.session-lock"
if [ -f "$_mb_lock" ]; then
  _age=$(($(date +%s) - $(stat -f%m "$_mb_lock" 2>/dev/null || stat -c%Y "$_mb_lock" 2>/dev/null || echo 0)))
  if [ "$_age" -lt 3600 ]; then
    rm -f "$_mb_lock"
    exit 0
  fi
  rm -f "$_mb_lock"
fi

_mb_progress="$_mb_dir/progress.md"
[ -f "$_mb_progress" ] || exit 0

_sha=$(git rev-parse HEAD 2>/dev/null | cut -c1-8)
_today=$(date +%Y-%m-%d)

# Idempotency: same commit SHA + day already recorded → skip
if grep -q "Auto-capture.*git-${_sha}" "$_mb_progress" 2>/dev/null; then
  exit 0
fi

{
  printf '\n## %s\n\n' "$_today"
  printf '### Auto-capture %s (git-%s)\n' "$_today" "$_sha"
  printf -- '- Session ended without an explicit /mb done (git post-commit fallback)\n'
  printf -- '- Commit SHA: %s\n' "$_sha"
  printf -- '- Details will be restored during the next /mb start\n'
} >> "$_mb_progress"
exit 0
HOOK_EOF
}

# ═══ pre-commit hook body ═══
pre_commit_body() {
  cat <<'HOOK_EOF'
#!/usr/bin/env bash
# memory-bank: managed hook (do not remove marker line)
set -u

# 1. Chain to user's original hook if we backed one up
_mb_backup="$(dirname "$0")/pre-commit.pre-mb-backup"
if [ -x "$_mb_backup" ]; then
  "$_mb_backup" "$@" || exit $?
fi

# 2. Warn on staged <private> blocks
_mb_repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$_mb_repo" || exit 0

_staged=$(git diff --cached --name-only 2>/dev/null || true)
_hits=0
if [ -n "$_staged" ]; then
  while IFS= read -r _f; do
    [ -z "$_f" ] && continue
    [ -f "$_f" ] || continue
    if grep -q '<private>' "$_f" 2>/dev/null; then
      printf '[MB WARNING] staged file contains <private> block: %s\n' "$_f" >&2
      _hits=$((_hits + 1))
    fi
  done <<< "$_staged"
fi

# Also scan .memory-bank files directly (including unstaged for awareness)
if [ -d "$_mb_repo/.memory-bank" ]; then
  while IFS= read -r -d '' _f; do
    if grep -q '<private>' "$_f" 2>/dev/null; then
      _rel="${_f#"$_mb_repo"/}"
      if printf '%s\n' "$_staged" | grep -qF "$_rel"; then
        :  # already reported above
      else
        printf '[MB INFO] unstaged private content: %s (review before future commits)\n' "$_rel" >&2
      fi
    fi
  done < <(find "$_mb_repo/.memory-bank" -type f -name '*.md' -print0 2>/dev/null)
fi

[ "$_hits" -gt 0 ] && printf '[MB WARNING] review %d file(s) with <private> blocks before committing\n' "$_hits" >&2
HOOK_EOF

  # --- dynamic-flow closure enforcement (Task 6, REQ-DF-062) ---------------
  # Paths baked at install time are shell-quoted with printf '%q' (Defect 2 fix)
  # so spaces, $, backticks, and " in the install path cannot be re-interpreted
  # at hook runtime. The quoted strings are emitted UNQUOTED into this heredoc
  # so they expand NOW (at install); every runtime variable below uses \$ so it
  # expands later inside the hook.
  # _skill_root.sh is sourced in the hook for the global-aware bank resolver
  # (mb_hook_resolve_mb_path) so global-storage banks are visible (Defect 1 fix).
  cat <<HOOK_EOF

# ═══ dynamic-flow closure gate (memory-bank: managed) ═══
# Emergency bypass: MB_FLOW_CLOSURE=off skips the gate entirely.
if [ "\${MB_FLOW_CLOSURE:-on}" != "off" ]; then
  # Baked paths (shell-quoted at install time — safe for spaces and metacharacters).
  _mb_verify=$MB_FLOW_VERIFY_Q
  _mb_skill_root_sh=$MB_SKILL_ROOT_SH_Q

  # Seed a DETERMINISTIC agent so registry resolution is not guessed (cursor
  # misdetect). A commit-time MB_AGENT still wins (:= only sets when unset).
  : "\${MB_AGENT:=$MB_AGENT_BAKED_Q}"
  export MB_AGENT

  # Resolve the bank via the global-aware resolver when available (Defect 1),
  # otherwise fall back to MB_PATH → <repo>/.memory-bank.
  _mb_flow_dir=""
  if [ -f "\$_mb_skill_root_sh" ]; then
    # shellcheck source=/dev/null
    . "\$_mb_skill_root_sh"
    if command -v mb_hook_resolve_mb_path >/dev/null 2>&1; then
      _mb_flow_dir="\$(mb_hook_resolve_mb_path "\$_mb_repo" 2>/dev/null || true)"
    fi
  fi
  if [ -z "\$_mb_flow_dir" ]; then
    if [ -n "\${MB_PATH:-}" ]; then
      _mb_flow_dir="\$MB_PATH"
    else
      _mb_flow_dir="\$_mb_repo/.memory-bank"
    fi
  fi

  # Flow-active predicate: only gate when goal.md exists AND the firewall is present.
  if [ -f "\$_mb_flow_dir/goal.md" ] && [ -f "\$_mb_verify" ]; then
    bash "\$_mb_verify" "\$_mb_flow_dir" >/dev/null 2>&1
    _mb_fw_rc=\$?
    if [ "\$_mb_fw_rc" -eq 1 ]; then
      printf '[MB BLOCK] dynamic-flow is RED — mb-flow-verify exited 1.\n' >&2
      printf '[MB BLOCK] The flow is NOT finished; repair the breach and re-run mb-flow-verify before committing.\n' >&2
      printf '[MB BLOCK] (emergency bypass: MB_FLOW_CLOSURE=off git commit ...)\n' >&2
      exit 1
    elif [ "\$_mb_fw_rc" -eq 2 ]; then
      printf '[MB BLOCK] a check script broke (mb-flow-verify exit 2) — cannot certify closure.\n' >&2
      printf '[MB BLOCK] Fix the broken check, then re-run mb-flow-verify before committing.\n' >&2
      printf '[MB BLOCK] (emergency bypass: MB_FLOW_CLOSURE=off git commit ...)\n' >&2
      exit 1
    fi
    # rc 0 (certified) or any unexpected code (firewall itself unrunnable → fail
    # safe) falls through: a broken toolchain must not wedge every commit.
  fi
fi

exit 0
HOOK_EOF
}

# ═══ Install ═══
install_one_hook() {
  local name="$1" body_fn="$2"
  local target="$HOOKS_DIR/$name"
  local backup="$HOOKS_DIR/$name.pre-mb-backup"

  # If target exists and is NOT our managed hook, back it up (unless backup already exists)
  if [ -f "$target" ] && ! grep -q "memory-bank: managed hook" "$target" 2>/dev/null; then
    if [ ! -f "$backup" ]; then
      mv "$target" "$backup"
      chmod +x "$backup"
    fi
  fi

  # Write our hook
  $body_fn > "$target"
  chmod +x "$target"
}

install_git_hooks() {
  require_git_repo
  mkdir -p "$HOOKS_DIR"

  local had_user_post=0 had_user_pre=0
  [ -f "$HOOKS_DIR/post-commit.pre-mb-backup" ] && had_user_post=1
  [ -f "$HOOKS_DIR/pre-commit.pre-mb-backup" ] && had_user_pre=1

  install_one_hook post-commit post_commit_body
  install_one_hook pre-commit  pre_commit_body

  # Track backups that now exist (either from this run or previous)
  [ -f "$HOOKS_DIR/post-commit.pre-mb-backup" ] && had_user_post=1
  [ -f "$HOOKS_DIR/pre-commit.pre-mb-backup" ] && had_user_pre=1

  # Manifest
  local files_json
  files_json=$(printf '%s\n' "$HOOKS_DIR/post-commit" "$HOOKS_DIR/pre-commit" | adapter_json_array_from_lines)

  adapter_write_manifest \
    "$MANIFEST" \
    "git-hooks-fallback" \
    "$(cat "$(dirname "$0")/../VERSION" 2>/dev/null || echo unknown)" \
    "$files_json" \
    "{\"had_user_post_commit\": $([ "$had_user_post" -eq 1 ] && printf true || printf false), \"had_user_pre_commit\": $([ "$had_user_pre" -eq 1 ] && printf true || printf false)}"

  echo "[git-hooks] installed to $PROJECT_ROOT/.git/hooks/"
}

# ═══ Uninstall ═══
uninstall_git_hooks() {
  if [ ! -f "$MANIFEST" ]; then
    echo "[git-hooks] no manifest found, nothing to uninstall"
    return 0
  fi
  require_git_repo

  local had_user_post had_user_pre
  had_user_post=$(jq -r '.had_user_post_commit // false' "$MANIFEST")
  had_user_pre=$(jq -r '.had_user_pre_commit // false' "$MANIFEST")

  # post-commit: if user had one, restore from backup; else just remove
  if [ -f "$HOOKS_DIR/post-commit" ] && grep -q "memory-bank: managed hook" "$HOOKS_DIR/post-commit" 2>/dev/null; then
    rm -f "$HOOKS_DIR/post-commit"
  fi
  if [ "$had_user_post" = "true" ] && [ -f "$HOOKS_DIR/post-commit.pre-mb-backup" ]; then
    mv "$HOOKS_DIR/post-commit.pre-mb-backup" "$HOOKS_DIR/post-commit"
  fi

  # pre-commit: same pattern
  if [ -f "$HOOKS_DIR/pre-commit" ] && grep -q "memory-bank: managed hook" "$HOOKS_DIR/pre-commit" 2>/dev/null; then
    rm -f "$HOOKS_DIR/pre-commit"
  fi
  if [ "$had_user_pre" = "true" ] && [ -f "$HOOKS_DIR/pre-commit.pre-mb-backup" ]; then
    mv "$HOOKS_DIR/pre-commit.pre-mb-backup" "$HOOKS_DIR/pre-commit"
  fi

  rm -f "$MANIFEST"
  echo "[git-hooks] uninstalled from $PROJECT_ROOT/.git/hooks/"
}

case "$ACTION" in
  install)   install_git_hooks ;;
  uninstall) uninstall_git_hooks ;;
  *)
    echo "Usage: $0 install|uninstall [PROJECT_ROOT]" >&2
    exit 1
    ;;
esac

adapter_contract_require_functions install_git_hooks uninstall_git_hooks >/dev/null
