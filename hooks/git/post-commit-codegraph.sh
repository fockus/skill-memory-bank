#!/usr/bin/env bash
# OPT-IN git post-commit hook — keep the Memory Bank code graph fresh after each
# commit. NOT auto-installed (it mutates the tracked graph.json and lives outside
# the skill's Claude-Code hook system). Install manually per-repo:
#
#   ln -sf ~/.claude/skills/memory-bank/hooks/git/post-commit-codegraph.sh \
#          .git/hooks/post-commit
#
# post-commit (not pre-commit) is chosen so it never slows a commit. It only
# refreshes an ALREADY-BUILT graph, incrementally, in the background. Fail-safe:
# every path exits 0 — a broken graph refresh must never wedge git.
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
MB="$REPO_ROOT/.memory-bank"
GRAPH="$MB/codebase/graph.json"

# No graph yet → first build stays manual (nothing to refresh). No-op.
[ -f "$GRAPH" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

CG="$HOME/.claude/skills/memory-bank/scripts/mb-codegraph.py"
[ -f "$CG" ] || CG="$(cd "$(dirname "$0")/../.." 2>/dev/null && pwd)/scripts/mb-codegraph.py"
[ -f "$CG" ] || exit 0

if [ -n "${MB_GRAPH_AUTO_DRYRUN:-}" ]; then
  printf 'python3 %s --apply --docs %s %s\n' "$CG" "$MB" "$REPO_ROOT"
  exit 0
fi

# Incremental refresh in the background under an atomic lock; never block git.
# Build against $REPO_ROOT (git top-level), not the ambient cwd, so the graph
# always reflects the tree that was just committed.
LOCK="$MB/.index/.graph-rebuild.lock"
mkdir -p "$MB/.index" 2>/dev/null || true
if mkdir "$LOCK" 2>/dev/null; then
  ( trap 'rmdir "$LOCK" 2>/dev/null' EXIT
    python3 "$CG" --apply --docs "$MB" "$REPO_ROOT" >/dev/null 2>&1
  ) >/dev/null 2>&1 &
fi
exit 0
