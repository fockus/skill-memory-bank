#!/usr/bin/env bats
# Stage 7 — `mb-plan.sh` should *soft-warn* (stderr) when the topic uses a
# legacy Cyrillic planning term, but still create the plan. Hard-block was
# rejected explicitly: the user has the right to name plans freely.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PLAN="$REPO_ROOT/scripts/mb-plan.sh"
  TMP="$(mktemp -d)"
  cd "$TMP"
  mkdir -p .memory-bank/plans
  cat > .memory-bank/roadmap.md <<'EOF'
# Roadmap

## Active plans
EOF
  cat > .memory-bank/checklist.md <<'EOF'
# Checklist
EOF
}

teardown() {
  cd /
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

@test "mb-plan: cyrillic topic emits stderr WARN, plan is still created" {
  run bash "$PLAN" refactor "Этап 1 — auth migration"
  [ "$status" -eq 0 ]
  # The new plan file exists somewhere under .memory-bank/plans/
  count=$(find .memory-bank/plans -name '*.md' | wc -l | tr -d ' ')
  [ "$count" -ge 1 ]
  # Stderr (combined into $output by `run`) carries the WARN marker
  [[ "$output" =~ WARN.*legacy ]] || [[ "$output" =~ legacy.*WARN ]] || \
    [[ "$output" =~ WARN.*Cyrillic ]] || [[ "$output" =~ WARN.*Phase/Sprint/Stage ]]
}

@test "mb-plan: english topic does NOT trigger WARN" {
  run bash "$PLAN" refactor "phase-X-auth"
  [ "$status" -eq 0 ]
  ! [[ "$output" =~ WARN.*legacy ]]
  ! [[ "$output" =~ WARN.*Cyrillic ]]
}
