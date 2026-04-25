#!/usr/bin/env bash
# mb-auto-commit.sh — opt-in auto-commit of .memory-bank/ changes after /mb done.
#
# Usage:
#   MB_AUTO_COMMIT=1 bash mb-auto-commit.sh [--mb <path>]
#   bash mb-auto-commit.sh --force [--mb <path>]
#
# Triggers only when MB_AUTO_COMMIT=1 (env) OR --force flag.
#
# Safety gates (each emits a warning to stderr and exits 0 — never fatal):
#   1. .memory-bank/ has no changes               → no-op.
#   2. Working tree dirty OUTSIDE .memory-bank/   → skip (won't sweep source code).
#   3. Repo in rebase / merge / cherry-pick       → skip.
#   4. Detached HEAD                              → skip.
#
# Commit subject:
#   `chore(mb): <last ### heading from progress.md>` (truncated to 60 chars)
# Fallback when no `###` heading:
#   `chore(mb): session-end <YYYY-MM-DD>`
#
# Never pushes. Push remains an explicit user action.

set -euo pipefail

# shellcheck source=_lib.sh
source "$(dirname "$0")/_lib.sh"

MAX_SUBJECT_LEN=60

MB_ARG=""
FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --mb) MB_ARG="${2:-}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --help|-h)
      cat <<'USAGE'
Usage: mb-auto-commit.sh [--mb <path>] [--force]

Opt-in auto-commit of .memory-bank/ changes. Triggers only when
MB_AUTO_COMMIT=1 (env) OR --force flag. Refuses to commit when source
files outside .memory-bank/ are dirty, or during rebase/merge/cherry-pick,
or on detached HEAD. Never pushes.

Subject: chore(mb): <last ### heading from progress.md> (≤60 chars)
Fallback: chore(mb): session-end <YYYY-MM-DD>
USAGE
      exit 0 ;;
    --*)
      echo "[error] unknown flag: $1" >&2
      exit 2 ;;
    *)
      [ -z "$MB_ARG" ] && MB_ARG="$1"
      shift ;;
  esac
done

# Trigger gate.
if [ "$FORCE" -ne 1 ] && [ "${MB_AUTO_COMMIT:-}" != "1" ]; then
  exit 0
fi

MB_PATH_RAW=$(mb_resolve_path "$MB_ARG")
if [ ! -d "$MB_PATH_RAW" ]; then
  echo "[mb-auto-commit] skip: .memory-bank not found at $MB_PATH_RAW" >&2
  exit 0
fi
MB_PATH=$(cd "$MB_PATH_RAW" && pwd)

REPO_ROOT=$(git -C "$MB_PATH" rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$REPO_ROOT" ]; then
  echo "[mb-auto-commit] skip: not inside a git repo" >&2
  exit 0
fi

# Path of MB relative to repo root for porcelain matching.
MB_REL=$(python3 - "$REPO_ROOT" "$MB_PATH" <<'PY'
import os, sys
print(os.path.relpath(sys.argv[2], sys.argv[1]))
PY
)
case "$MB_REL" in
  ""|"."|..*) MB_REL=".memory-bank" ;;
esac
MB_REL_PREFIX="${MB_REL%/}/"

# Gate 3: rebase / merge / cherry-pick / bisect.
GIT_DIR=$(git -C "$REPO_ROOT" rev-parse --git-dir)
for marker in REBASE_HEAD MERGE_HEAD CHERRY_PICK_HEAD BISECT_LOG rebase-merge rebase-apply; do
  if [ -e "$GIT_DIR/$marker" ]; then
    echo "[mb-auto-commit] skip: repo is in the middle of rebase/merge/cherry-pick ($marker present)" >&2
    exit 0
  fi
done

# Gate 4: detached HEAD.
if ! git -C "$REPO_ROOT" symbolic-ref -q HEAD >/dev/null 2>&1; then
  echo "[mb-auto-commit] skip: HEAD is detached — refusing to commit" >&2
  exit 0
fi

# Inspect porcelain.
porcelain=$(git -C "$REPO_ROOT" status --porcelain=v1 2>/dev/null || true)

if [ -z "$porcelain" ]; then
  exit 0  # Gate 1: nothing to commit.
fi

bank_dirty=0
outside_dirty=0
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # Format: XY <path>  (or XY <oldpath> -> <newpath> for renames)
  rel="${line:3}"
  case "$rel" in
    *' -> '*) rel="${rel##* -> }" ;;
  esac
  # Strip surrounding quotes git emits when the path contains spaces.
  rel="${rel#\"}"
  rel="${rel%\"}"
  case "$rel" in
    "$MB_REL_PREFIX"*|"$MB_REL")
      bank_dirty=1 ;;
    *)
      outside_dirty=1 ;;
  esac
done <<< "$porcelain"

if [ "$bank_dirty" -eq 0 ]; then
  exit 0  # Gate 1 (no bank changes among the dirty files).
fi

if [ "$outside_dirty" -eq 1 ]; then
  echo "[mb-auto-commit] skip: dirty files outside .memory-bank/ — refusing to bundle source changes into a chore(mb) commit" >&2
  exit 0
fi

# Build commit subject from progress.md last `### ` heading.
PROGRESS_FILE="$MB_PATH/progress.md"
heading=""
if [ -f "$PROGRESS_FILE" ]; then
  heading=$(awk '
    /^### / {
      sub(/^### +/, "")
      last = $0
    }
    END {
      if (last != "") print last
    }
  ' "$PROGRESS_FILE")
fi

if [ -n "$heading" ]; then
  subject="chore(mb): $heading"
else
  subject="chore(mb): session-end $(date +%Y-%m-%d)"
fi

# Truncate subject to MAX_SUBJECT_LEN runes (UTF-8 aware via python).
subject=$(SUBJ="$subject" MAX="$MAX_SUBJECT_LEN" python3 - <<'PY'
import os
s = os.environ["SUBJ"]
n = int(os.environ["MAX"])
if len(s) > n:
    s = s[:n - 1].rstrip() + "…"
print(s)
PY
)

# Stage only .memory-bank/ and commit.
git -C "$REPO_ROOT" add -- "$MB_REL" >/dev/null
COMMIT_MSG=$(printf '%s\n\nCo-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>\n' "$subject")
if git -C "$REPO_ROOT" commit -q -m "$COMMIT_MSG" >/dev/null 2>&1; then
  sha=$(git -C "$REPO_ROOT" rev-parse --short HEAD)
  echo "[mb-auto-commit] committed $sha — $subject"
else
  echo "[mb-auto-commit] skip: nothing to commit after staging" >&2
fi

exit 0
