#!/usr/bin/env bash
# OPT-IN git post-commit hook — keep the Memory Bank code graph fresh after each
# commit. NOT auto-installed (it concerns the tracked graph.json and lives outside
# the skill's Claude-Code hook system). Install manually per-repo:
#
#   ln -sf ~/.claude/skills/memory-bank/hooks/git/post-commit-codegraph.sh \
#          .git/hooks/post-commit
#
# I-133 discipline: this hook does NOT rebuild anything (the old detached
# background builder spawn is gone) — it only marks `.graph-dirty`.
# The next graph query or SessionEnd catchup rebuilds inline, bounded by
# MB_GRAPH_CATCHUP_BUDGET, under a non-blocking flock. post-commit therefore
# never slows a commit by more than a file touch. Fail-safe: every path exits 0.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
MB="$REPO_ROOT/.memory-bank"
GRAPH="$MB/codebase/graph.json"

# No graph yet → first build stays manual (nothing to refresh). No-op.
[ -f "$GRAPH" ] || exit 0

if [ -n "${MB_GRAPH_AUTO_DRYRUN:-}" ]; then
  printf 'mark-dirty %s/codebase/.graph-dirty\n' "$MB"
  exit 0
fi

: >> "$MB/codebase/.graph-dirty" 2>/dev/null || true
exit 0
