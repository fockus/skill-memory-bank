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

if [ ! -d "$PROJECT_ROOT_RAW" ]; then
  echo "[git-hooks] project root not found: $PROJECT_ROOT_RAW" >&2
  exit 1
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT_RAW" && pwd)"

GIT_DIR="$PROJECT_ROOT/.git"
HOOKS_DIR="$GIT_DIR/hooks"
MANIFEST="$GIT_DIR/mb-hooks-manifest.json"

require_git_repo() {
  if [ ! -d "$GIT_DIR" ]; then
    echo "[git-hooks] not a git repository: $PROJECT_ROOT" >&2
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

# 2. Memory Bank auto-capture
_mb_repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
_mb_dir="$_mb_repo/.memory-bank"
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
  files_json=$(printf '%s\n' "$HOOKS_DIR/post-commit" "$HOOKS_DIR/pre-commit" | jq -R . | jq -s .)

  jq -n \
    --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson files "$files_json" \
    --argjson backup_post "$had_user_post" \
    --argjson backup_pre "$had_user_pre" \
    '{installed_at: $installed_at, adapter: "git-hooks-fallback", files: $files, had_user_post_commit: ($backup_post == 1), had_user_pre_commit: ($backup_pre == 1)}' \
    > "$MANIFEST"

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
