#!/usr/bin/env bash
# mb-upgrade.sh — update the skill from GitHub.
#
# Usage:
#   mb-upgrade.sh              # check → prompt → pull + reinstall
#   mb-upgrade.sh --check      # check only: exit 0 = up to date, 1 = update available
#   mb-upgrade.sh --force      # apply without confirmation (for automation)
#   mb-upgrade.sh --language XX [--comments-language YY] --clients a,b --project-root PATH
#                              # override the persisted install options (A21)
#
# Env:
#   MB_SKILL_DIR — path to the cloned repo. Default: ~/.claude/skills/skill-memory-bank
#
# Requirements:
#   - skill installed via `git clone` (not ZIP)
#   - clean working tree (no local edits)
#   - network access for `git fetch`

set -euo pipefail

SKILL_DIR="${MB_SKILL_DIR:-$HOME/.claude/skills/skill-memory-bank}"
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/_lib.sh"

CHECK_ONLY=0
FORCE=0
# A21 (CDX-I10): explicit overrides always win over the persisted manifest.
OVERRIDE_LANGUAGE=""
OVERRIDE_COMMENTS_LANGUAGE=""
OVERRIDE_CLIENTS=""
OVERRIDE_PROJECT_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --language) OVERRIDE_LANGUAGE="${2:-}"; shift 2 ;;
    --comments-language) OVERRIDE_COMMENTS_LANGUAGE="${2:-}"; shift 2 ;;
    --clients) OVERRIDE_CLIENTS="${2:-}"; shift 2 ;;
    --project-root) OVERRIDE_PROJECT_ROOT="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,17p' "$0"
      exit 0
      ;;
    *) shift ;;
  esac
done

# ═══ A21 (CDX-I10): persist + reapply install options across upgrade ═══
# install.sh saves {language, comments_language, clients_requested,
# project_root} in its manifest and restores them itself on a plain re-run;
# scripts/_lib.sh::mb_saved_install_options is the one reader both use.

# ═══ Pre-flight: skill directory exists ═══
if [ ! -d "$SKILL_DIR" ]; then
  echo "[error] Skill directory not found: $SKILL_DIR" >&2
  echo "[hint] Install it with: git clone https://github.com/fockus/skill-memory-bank.git $SKILL_DIR" >&2
  exit 1
fi

# ═══ Detect install flavor when .git is missing ═══
# The skill ships through four channels: git clone, pipx, pip, and Homebrew.
# scripts/_lib.sh::mb_install_flavor is the single source of truth for this
# classification — mb-version-check.sh needs the exact same answer, so the
# pattern-matching lives there, not here (no second copy to drift).
#
# For non-git flavors this script can't self-update — the right answer is the
# packaging tool's own upgrade command. Print it and exit 0 so `--check`
# consumers see "nothing to do here" rather than a scary error.
if [ ! -d "$SKILL_DIR/.git" ]; then
  flavor="$(mb_install_flavor "$SKILL_DIR")"
  resolved="$(mb_resolve_install_alias "$SKILL_DIR")"

  case "$flavor" in
    pipx)
      echo "[info] memory-bank-skill is installed via pipx (bundle: $resolved)" >&2
      echo "[info] Git-based auto-upgrade is not applicable for pipx installs." >&2
      echo ""
      echo "To update, run:"
      echo "    $(mb_upgrade_command pipx "$SKILL_DIR")"
      echo ""
      echo "Or force-reinstall from GitHub (for release candidates):"
      echo "    pipx install --force 'git+https://github.com/fockus/skill-memory-bank.git'"
      # --check contract: exit 0 means "no action needed via THIS script".
      # The user has a clear next step, and CI pipelines don't fail.
      exit 0
      ;;
    pip)
      echo "[info] memory-bank-skill appears to be a pip install (bundle: $resolved)" >&2
      echo ""
      echo "To update, run:"
      echo "    $(mb_upgrade_command pip "$SKILL_DIR")"
      exit 0
      ;;
    brew)
      echo "[info] memory-bank-skill is installed via Homebrew (bundle: $resolved)" >&2
      echo ""
      echo "To update, run:"
      echo "    $(mb_upgrade_command brew "$SKILL_DIR")"
      exit 0
      ;;
    *)
      echo "[error] $SKILL_DIR is not a git repository and not a known package install" >&2
      echo "[hint] Reinstall options:" >&2
      echo "    git clone:  rm -rf $SKILL_DIR && git clone https://github.com/fockus/skill-memory-bank.git $SKILL_DIR" >&2
      echo "    pipx:       pipx install memory-bank-skill" >&2
      echo "    pip:        pip install memory-bank-skill" >&2
      exit 1
      ;;
  esac
fi

cd "$SKILL_DIR"

# ═══ Pre-flight: working tree clean ═══
if ! git diff --quiet 2>/dev/null; then
  echo "[error] Skill repo has unstaged local changes" >&2
  git status --short >&2
  echo "[hint] Save or revert changes: git stash OR git checkout -- ." >&2
  exit 1
fi
if ! git diff --cached --quiet 2>/dev/null; then
  echo "[error] Skill repo has staged local changes" >&2
  git status --short >&2
  exit 1
fi

# ═══ Read local version ═══
local_version="unknown"
[ -f VERSION ] && local_version=$(tr -d '[:space:]' < VERSION)
local_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

echo "Local:  $local_version ($local_commit)"

# ═══ Fetch from remote ═══
echo "[info] Fetching from origin..."
if ! git fetch origin 2>&1 | grep -v "^$" | head -5; then
  : # may be a no-op if already up to date
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
remote_branch="origin/$branch"

# If the remote branch does not exist — error
if ! git rev-parse --verify "$remote_branch" >/dev/null 2>&1; then
  echo "[error] Remote branch $remote_branch not found. The remote may be configured incorrectly." >&2
  exit 2
fi

remote_commit=$(git rev-parse --short "$remote_branch")

# ═══ Compare ═══
behind=$(git rev-list --count "HEAD..$remote_branch" 2>/dev/null || echo 0)
ahead=$(git rev-list --count "$remote_branch..HEAD" 2>/dev/null || echo 0)

echo "Remote: $remote_commit ($branch)"
echo "Status: $behind behind, $ahead ahead"
echo ""

if [ "$behind" -eq 0 ]; then
  echo "[✓] Up to date"
  exit 0
fi

# ═══ Update available ═══
echo "=== $behind new commits ==="
git --no-pager log --oneline "HEAD..$remote_branch" | head -10
echo ""

if [ "$CHECK_ONLY" -eq 1 ]; then
  exit 1  # signal that an update is available
fi

# ═══ Prompt ═══
if [ "$FORCE" -eq 0 ]; then
  if [ ! -t 0 ]; then
    echo "[error] Non-interactive mode requires the --force flag" >&2
    exit 3
  fi
  read -r -p "Apply $behind updates (git pull + re-install)? (y/n): " answer
  if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
    echo "Cancelled by user"
    exit 0
  fi
fi

# ═══ Apply ═══
echo "[info] git pull --ff-only origin $branch..."
if ! git pull --ff-only origin "$branch"; then
  echo "[error] git pull failed (possibly divergent branches)" >&2
  echo "[hint] Manually: cd $SKILL_DIR && git pull" >&2
  exit 4
fi

if [ -x "$SKILL_DIR/install.sh" ]; then
  # A21: reapply the previous install's language/clients/project-root
  # non-interactively instead of resetting to install.sh's bare defaults.
  install_args=(--non-interactive)
  resolved_language="$OVERRIDE_LANGUAGE"
  resolved_comments_language="$OVERRIDE_COMMENTS_LANGUAGE"
  resolved_clients="$OVERRIDE_CLIENTS"
  resolved_project_root="$OVERRIDE_PROJECT_ROOT"

  if [ -z "$resolved_language" ] && [ -z "$resolved_clients" ]; then
    if mb_saved_install_options "$(mb_resolve_manifest_path "$SKILL_DIR")"; then
      resolved_language="$MB_SAVED_LANGUAGE"
      resolved_clients="$MB_SAVED_CLIENTS"
      [ -z "$resolved_comments_language" ] && resolved_comments_language="$MB_SAVED_COMMENTS_LANGUAGE"
      [ -z "$resolved_project_root" ] && resolved_project_root="$MB_SAVED_PROJECT_ROOT"
    else
      echo "[warning] no persisted install options found (pre-upgrade-support manifest, or first install) — re-running install.sh with its own defaults" >&2
    fi
  fi

  [ -n "$resolved_language" ] && install_args+=(--language "$resolved_language")
  [ -n "$resolved_comments_language" ] && install_args+=(--comments-language "$resolved_comments_language")
  [ -n "$resolved_clients" ] && install_args+=(--clients "$resolved_clients")
  [ -n "$resolved_project_root" ] && install_args+=(--project-root "$resolved_project_root")

  echo "[info] Re-running install.sh${resolved_language:+ (language=$resolved_language)}${resolved_clients:+ (clients=$resolved_clients)}..."
  bash "$SKILL_DIR/install.sh" "${install_args[@]}"
else
  echo "[warning] install.sh is missing or not executable — skipping re-install" >&2
fi

new_version="unknown"
[ -f VERSION ] && new_version=$(tr -d '[:space:]' < VERSION)
new_commit=$(git rev-parse --short HEAD)

echo ""
echo "[✓] Skill updated: $local_version → $new_version ($local_commit → $new_commit)"
