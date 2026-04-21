#!/usr/bin/env bash
# mb-upgrade.sh — update the skill from GitHub.
#
# Usage:
#   mb-upgrade.sh              # check → prompt → pull + reinstall
#   mb-upgrade.sh --check      # check only: exit 0 = up to date, 1 = update available
#   mb-upgrade.sh --force      # apply without confirmation (for automation)
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

CHECK_ONLY=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=1 ;;
    --force) FORCE=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
  esac
done

# ═══ Pre-flight: skill directory exists ═══
if [ ! -d "$SKILL_DIR" ]; then
  echo "[error] Skill directory not found: $SKILL_DIR" >&2
  echo "[hint] Install it with: git clone https://github.com/fockus/skill-memory-bank.git $SKILL_DIR" >&2
  exit 1
fi

# ═══ Detect install flavor when .git is missing ═══
# The skill ships through three channels:
#   1. git clone  — target has .git, this script drives it (git pull + re-install)
#   2. pipx       — target is (or resolves into) ~/.local/pipx/venvs/.../share/memory-bank-skill
#   3. pip / other — target is installed data in a site-packages share directory
#
# For 2/3 this script can't self-update — the right answer is the packaging
# tool's own upgrade command. Print the exact command and exit 0 so `--check`
# consumers see "nothing to do here" rather than a scary error.
if [ ! -d "$SKILL_DIR/.git" ]; then
  resolved="$SKILL_DIR"
  # Follow symlinks to the real location; pipx installs always sit under
  # .../pipx/venvs/memory-bank-skill/share/memory-bank-skill, so a readlink
  # reveals the install flavor even when $SKILL_DIR is an alias symlink.
  if [ -L "$SKILL_DIR" ]; then
    if command -v readlink >/dev/null 2>&1; then
      # -f for chain resolution; fall back to single-hop readlink on BSD builds
      # that lack -f (older macOS). realpath is a last resort.
      resolved="$(readlink -f "$SKILL_DIR" 2>/dev/null || readlink "$SKILL_DIR" || echo "$SKILL_DIR")"
    fi
  fi

  case "$resolved" in
    *pipx/venvs/memory-bank-skill*)
      echo "[info] memory-bank-skill is installed via pipx (bundle: $resolved)" >&2
      echo "[info] Git-based auto-upgrade is not applicable for pipx installs." >&2
      echo ""
      echo "To update, run:"
      echo "    pipx upgrade memory-bank-skill"
      echo ""
      echo "Or force-reinstall from GitHub (for release candidates):"
      echo "    pipx install --force 'git+https://github.com/fockus/skill-memory-bank.git'"
      # --check contract: exit 0 means "no action needed via THIS script".
      # The user has a clear next step, and CI pipelines don't fail.
      exit 0
      ;;
    *site-packages*|*dist-packages*)
      echo "[info] memory-bank-skill appears to be a pip install (bundle: $resolved)" >&2
      echo ""
      echo "To update, run:"
      echo "    pip install --upgrade memory-bank-skill"
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
  echo "[info] Re-running install.sh..."
  bash "$SKILL_DIR/install.sh"
else
  echo "[warning] install.sh is missing or not executable — skipping re-install" >&2
fi

new_version="unknown"
[ -f VERSION ] && new_version=$(tr -d '[:space:]' < VERSION)
new_commit=$(git rev-parse --short HEAD)

echo ""
echo "[✓] Skill updated: $local_version → $new_version ($local_commit → $new_commit)"
