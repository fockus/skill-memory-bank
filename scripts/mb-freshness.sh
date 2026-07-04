#!/usr/bin/env bash
# mb-freshness.sh — deterministic Memory-Bank-vs-code freshness signal.
#
# Answers two questions with git only (no LLM, always exit 0, fail-safe):
#   behind = commits on HEAD since the last commit that touched the bank
#   dirty  = uncommitted tracked changes + untracked files under the bank prefix
#
# Modes (default = human report):
#   --porcelain   → `behind=<N> dirty=<M>`
#   --stop-nudge  → a one-line nudge ONLY when over threshold (silent when fresh)
#   --banner      → a `# Memory Bank freshness` block for SessionStart (empty when fresh)
#
# Thresholds: MB_DRIFT_WARN_COMMITS (default 5), MB_DRIFT_WARN_DIRTY_LINES (default 50).
# Not a git repo / no bank / any git failure → prints nothing, exit 0.
#
# Usage: mb-freshness.sh [--porcelain|--stop-nudge|--banner] [mb_path|repo_dir]
set -u

MODE="report"
MB_ARG=""
for a in "$@"; do
  case "$a" in
    --porcelain)  MODE="porcelain" ;;
    --stop-nudge) MODE="stop-nudge" ;;
    --banner)     MODE="banner" ;;
    -h|--help)    sed -n '2,18p' "$0"; exit 0 ;;
    *)            MB_ARG="$a" ;;
  esac
done

# Resolve the bank dir from an explicit repo/bank arg, else the CWD.
cand="${MB_ARG:-$PWD}"
BANK=""
if [ -d "$cand/.memory-bank" ]; then
  BANK="$cand/.memory-bank"
elif [ "$(basename "$cand" 2>/dev/null)" = ".memory-bank" ] && [ -d "$cand" ]; then
  BANK="$cand"
elif [ -d "$PWD/.memory-bank" ]; then
  BANK="$PWD/.memory-bank"
fi
[ -n "$BANK" ] || exit 0
BANK="$(cd "$BANK" 2>/dev/null && pwd)" || exit 0

REPO="$(git -C "$BANK" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$REPO" ] || exit 0            # not a git repo → silent
rel="${BANK#"$REPO"/}"              # bank path relative to repo root

# behind — commits since the last bank-touching commit (bank never committed → all commits)
last="$(git -C "$REPO" log -1 --format=%H -- "$rel" 2>/dev/null || true)"
if [ -n "$last" ]; then
  behind="$(git -C "$REPO" rev-list --count "$last"..HEAD 2>/dev/null || echo 0)"
else
  behind="$(git -C "$REPO" rev-list --count HEAD 2>/dev/null || echo 0)"
fi
case "$behind" in ''|*[!0-9]*) behind=0 ;; esac

# dirty — uncommitted tracked changes (staged+unstaged vs HEAD) + untracked, under the bank
num="$(git -C "$REPO" diff HEAD --numstat -- "$rel" 2>/dev/null | grep -c . || true)"
unt="$(git -C "$REPO" ls-files --others --exclude-standard -- "$rel" 2>/dev/null | grep -c . || true)"
case "$num" in ''|*[!0-9]*) num=0 ;; esac
case "$unt" in ''|*[!0-9]*) unt=0 ;; esac
dirty=$((num + unt))

warn_commits="${MB_DRIFT_WARN_COMMITS:-5}"
warn_dirty="${MB_DRIFT_WARN_DIRTY_LINES:-50}"
over=0
[ "$behind" -ge "$warn_commits" ] && over=1
[ "$dirty" -ge "$warn_dirty" ] && over=1

case "$MODE" in
  porcelain)
    printf 'behind=%s dirty=%s\n' "$behind" "$dirty"
    ;;
  stop-nudge)
    [ "$over" -eq 1 ] && printf '[MEMORY BANK] [memory-bank-skill] drift: %s commit(s) since the last .memory-bank commit, %s uncommitted bank change(s). Run: bash scripts/mb-auto-commit.sh --force  (or /mb done)\n' "$behind" "$dirty"
    ;;
  banner)
    # shellcheck disable=SC2016  # backticks are literal markdown code-spans in the banner text
    [ "$over" -eq 1 ] && printf '# Memory Bank freshness\n- drift: %s commit(s) behind the last bank commit, %s uncommitted bank change(s) — run `/mb done` or `bash scripts/mb-auto-commit.sh --force`\n' "$behind" "$dirty"
    ;;
  *)
    printf 'Memory Bank freshness: behind=%s dirty=%s (warn: commits>=%s dirty>=%s)\n' "$behind" "$dirty" "$warn_commits" "$warn_dirty"
    # shellcheck disable=SC2016  # backticks are literal markdown code-spans in the report text
    [ "$over" -eq 1 ] && printf 'DRIFT: bank is stale — run `/mb done` or `bash scripts/mb-auto-commit.sh --force`\n'
    ;;
esac
exit 0
