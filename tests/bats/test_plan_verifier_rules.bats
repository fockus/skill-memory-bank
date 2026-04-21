#!/usr/bin/env bats
# Contract tests for RULES.md enforcement checks in agents/plan-verifier.md.
#
# Stage 1 of plans/2026-04-21_refactor_agents-quality.md requires the
# plan-verifier prompt to contain Step 3.6 that instructs the sub-agent to:
#   1. Read RULES.md (project-local first, global fallback `~/.claude/RULES.md`).
#   2. Apply deterministic checks to changed files in the diff:
#        - SRP via a line-count threshold (>300 lines — flag)
#        - DIP / Clean Architecture direction (domain/ importing infrastructure/)
#        - TDD delta (source touched without matching test file)
#   3. Report violations in the final report under a `RULES violations:` row.
#
# These tests are contract-level: they grep the agent prompt for the exact
# markers a downstream orchestrator relies on. They do not execute the LLM.
#
# RED-phase target: agents/plan-verifier.md currently mentions none of these.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  PROMPT="$REPO_ROOT/agents/plan-verifier.md"
  [ -f "$PROMPT" ]
}

@test "rules: prompt references RULES.md with project-then-global precedence" {
  # Must mention both paths and imply precedence (project first).
  grep -Fq '.memory-bank/RULES.md' "$PROMPT"
  grep -Fq '~/.claude/RULES.md' "$PROMPT"
}

@test "rules: prompt instructs SRP check with a 300-line threshold" {
  # Either explicit number "300" or words "three hundred" — we pick literal 300.
  grep -Eq 'SRP.*300|300.*SRP|>300 lines' "$PROMPT"
}

@test "rules: prompt instructs Clean Architecture direction check" {
  # Must name 'domain' + 'infrastructure' + import direction.
  grep -Fq 'domain' "$PROMPT"
  grep -Fq 'infrastructure' "$PROMPT"
  grep -Eq 'import|depends on|direction' "$PROMPT"
}

@test "rules: prompt instructs TDD-delta check (source without matching test)" {
  # Some natural phrasing that couples 'source' + 'test' + 'missing|without'.
  grep -Eq 'source .*(without|no).*test|test.*missing|TDD delta|matching test' "$PROMPT"
}

@test "rules: response format declares RULES violations row" {
  # The report template must carry this literal row so callers can grep it.
  grep -Fq 'RULES violations' "$PROMPT"
}
