#!/usr/bin/env bash
# mb-upgrade.sh — update the skill from GitHub.
#
# Usage:
#   mb-upgrade.sh              # check → prompt → pull + reinstall
#   mb-upgrade.sh --check      # check only: exit 0 = up to date, 1 = update available
#   mb-upgrade.sh --force      # apply without confirmation (for automation)
#   mb-upgrade.sh --language XX --clients a,b --project-root PATH
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
MB_PY="${MB_PYTHON:-python3}"
# shellcheck disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/_lib.sh"

CHECK_ONLY=0
FORCE=0
# A21 (CDX-I10): explicit overrides always win over the persisted manifest.
OVERRIDE_LANGUAGE=""
OVERRIDE_CLIENTS=""
OVERRIDE_PROJECT_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --language) OVERRIDE_LANGUAGE="${2:-}"; shift 2 ;;
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
# install.sh persists {language, clients_requested, project_root} into its own
# manifest (scripts/_lib.sh::mb_resolve_manifest_path — the same resolution
# uninstall.sh already uses). A plain re-run of install.sh used to silently
# reset the locale to en and drop the user's chosen --clients on every
# upgrade; this reapplies the previous choices non-interactively instead.
# Keep in sync with install.sh:VALID_CLIENTS / VALID_LANGUAGES.
UPGRADE_VALID_CLIENTS=(claude-code cursor windsurf cline kilo opencode pi codex)
UPGRADE_VALID_LANGUAGES=(en ru es zh)

_mb_upgrade_in_list() {
  local needle="$1"; shift
  local hay
  for hay in "$@"; do [ "$hay" = "$needle" ] && return 0; done
  return 1
}

# Drops any persisted client no longer recognized by this version of
# install.sh instead of letting install.sh hard-fail the whole re-install.
_mb_upgrade_sanitize_clients() {
  local input="$1" kept="" dropped="" part
  local IFS=','
  for part in $input; do
    part="${part// /}"
    [ -z "$part" ] && continue
    if _mb_upgrade_in_list "$part" "${UPGRADE_VALID_CLIENTS[@]}"; then
      kept="${kept:+$kept,}$part"
    else
      dropped="${dropped:+$dropped,}$part"
    fi
  done
  if [ -n "$dropped" ]; then
    echo "[warning] dropping clients no longer supported by this version: $dropped" >&2
  fi
  printf '%s' "$kept"
}

# Reads {language, clients_requested, project_root} from install.sh's
# manifest. Returns 1 (PERSISTED_* left unset) when the manifest is missing,
# unreadable, or predates A21 (no "language" key) — callers fall back to
# install.sh's own defaults and print a warning instead of failing the upgrade.
resolve_persisted_install_options() {
  local manifest raw
  manifest="$(mb_resolve_manifest_path "$SKILL_DIR")"
  [ -f "$manifest" ] || return 1
  raw="$(MANIFEST_PATH="$manifest" "$MB_PY" -c '
import json, os
try:
    with open(os.environ["MANIFEST_PATH"]) as fh:
        data = json.load(fh)
except Exception:
    raise SystemExit(1)
language = data.get("language") or ""
if not language:
    raise SystemExit(1)
print(language)
print(data.get("clients_requested") or "")
print(data.get("project_root") or "")
' 2>/dev/null)" || return 1
  PERSISTED_LANGUAGE="$(printf '%s\n' "$raw" | sed -n '1p')"
  PERSISTED_CLIENTS="$(printf '%s\n' "$raw" | sed -n '2p')"
  PERSISTED_PROJECT_ROOT="$(printf '%s\n' "$raw" | sed -n '3p')"
  return 0
}

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
  resolved_clients="$OVERRIDE_CLIENTS"
  resolved_project_root="$OVERRIDE_PROJECT_ROOT"

  if [ -z "$resolved_language" ] && [ -z "$resolved_clients" ]; then
    if resolve_persisted_install_options; then
      resolved_language="$PERSISTED_LANGUAGE"
      resolved_clients="$PERSISTED_CLIENTS"
      [ -z "$resolved_project_root" ] && resolved_project_root="$PERSISTED_PROJECT_ROOT"
    else
      echo "[warning] no persisted install options found (pre-upgrade-support manifest, or first install) — re-running install.sh with its own defaults" >&2
    fi
  fi

  if [ -n "$resolved_language" ] && ! _mb_upgrade_in_list "$resolved_language" "${UPGRADE_VALID_LANGUAGES[@]}"; then
    echo "[warning] persisted language '$resolved_language' is no longer supported — using en" >&2
    resolved_language="en"
  fi
  if [ -n "$resolved_clients" ]; then
    resolved_clients="$(_mb_upgrade_sanitize_clients "$resolved_clients")"
    [ -z "$resolved_clients" ] && resolved_clients="claude-code"
  fi

  [ -n "$resolved_language" ] && install_args+=(--language "$resolved_language")
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
