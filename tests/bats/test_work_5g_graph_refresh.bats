#!/usr/bin/env bats
# Stage 5 (session-memory-graph-hardening) — 5g must document a background,
# lock-guarded, fail-open incremental graph refresh after the item's `flip`,
# mirroring hooks/git/post-commit-codegraph.sh, so the graph does not silently
# drift when the opt-in git hook is not installed.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WORK_MD="$REPO_ROOT/commands/work.md"
}

_5g_region() {
  # From the "### 5g. Item done" heading up to (not including) the next
  # top-level "6." section heading.
  awk '/^   ### 5g\. Item done/{flag=1} flag{print} /^6\. \*\*End-of-run summary/{exit}' "$WORK_MD"
}

@test "5g documents background graph refresh with all four guards" {
  region="$(_5g_region)"
  [ -n "$region" ]

  echo "$region" | grep -q "mb-codegraph.py --apply --docs"
  echo "$region" | grep -q "graph-rebuild.lock"
  echo "$region" | grep -Eq "\(.*&.*\)|background"
  echo "$region" | grep -Eiq "fail-open|exit 0"

  # exists-check guard for graph.json
  echo "$region" | grep -q "graph.json"
}

@test "5g documents refresh is skipped when graph.json is absent" {
  region="$(_5g_region)"
  [ -n "$region" ]

  echo "$region" | grep -Eiq "absent.*skip|skip.*absent|no.*graph.*(skip|no-op)|absent.*no-op"
}
