#!/usr/bin/env bats
# Docs/rules/verifier wiring for the "Running List of Agreements" feature
# (tasks 6-7 of specs/agreements/tasks.md). The CLI (scripts/mb-agree.sh) is
# implemented separately; this suite only asserts the documentation
# invariants — same style as test_agent_report_delivery.bats.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

@test "rules/CLAUDE-GLOBAL.md carries the agreements trigger" {
  run command grep -F 'AGR-NNN записано' "$REPO_ROOT/rules/CLAUDE-GLOBAL.md"
  [ "$status" -eq 0 ]
  run command grep -F 'mb-agree.sh' "$REPO_ROOT/rules/CLAUDE-GLOBAL.md"
  [ "$status" -eq 0 ]
  run command grep -F -- '--supersedes' "$REPO_ROOT/rules/CLAUDE-GLOBAL.md"
  [ "$status" -eq 0 ]
}

@test "rules/RULES.md carries the agreements trigger" {
  run command grep -F 'AGR-NNN записано' "$REPO_ROOT/rules/RULES.md"
  [ "$status" -eq 0 ]
  run command grep -F 'mb-agree.sh' "$REPO_ROOT/rules/RULES.md"
  [ "$status" -eq 0 ]
  run command grep -F -- '--supersedes' "$REPO_ROOT/rules/RULES.md"
  [ "$status" -eq 0 ]
}

@test "both rules files point to references/agreements.md" {
  run command grep -F 'references/agreements.md' "$REPO_ROOT/rules/CLAUDE-GLOBAL.md"
  [ "$status" -eq 0 ]
  run command grep -F 'references/agreements.md' "$REPO_ROOT/rules/RULES.md"
  [ "$status" -eq 0 ]
}

@test "commands/mb.md has the agree router row" {
  run command grep -E '\| .agree <subcommand>. +\|' "$REPO_ROOT/commands/mb.md"
  [ "$status" -eq 0 ]
}

@test "commands/mb.md router row does not list a bare 'supersede' subcommand" {
  run command grep -F 'agree <subcommand>' "$REPO_ROOT/commands/mb.md"
  [ "$status" -eq 0 ]
  line="$output"
  echo "$line" | command grep -qF -- '--supersedes'
  stripped="${line//--supersedes/}"
  ! echo "$stripped" | command grep -qi 'supersede'
}

@test "commands/mb.md has a ### agree implementation section" {
  run command grep -E '^### agree' "$REPO_ROOT/commands/mb.md"
  [ "$status" -eq 0 ]
}

@test "commands/mb.md verify section mentions agreement compliance" {
  run command awk '/^### verify/,/^### map/' "$REPO_ROOT/commands/mb.md"
  [ "$status" -eq 0 ]
  echo "$output" | command grep -qi 'agreement'
}

@test "commands/agree.md exists with the CLI contract table" {
  [ -f "$REPO_ROOT/commands/agree.md" ]
  run command grep -F 'add' "$REPO_ROOT/commands/agree.md"
  [ "$status" -eq 0 ]
  run command grep -F 'supersede' "$REPO_ROOT/commands/agree.md"
  [ "$status" -eq 0 ]
  run command grep -F 'defer' "$REPO_ROOT/commands/agree.md"
  [ "$status" -eq 0 ]
  run command grep -F 'reject' "$REPO_ROOT/commands/agree.md"
  [ "$status" -eq 0 ]
  run command grep -F 'question' "$REPO_ROOT/commands/agree.md"
  [ "$status" -eq 0 ]
  run command grep -F 'resolve' "$REPO_ROOT/commands/agree.md"
  [ "$status" -eq 0 ]
  run command grep -F 'list' "$REPO_ROOT/commands/agree.md"
  [ "$status" -eq 0 ]
  run command grep -F 'sync' "$REPO_ROOT/commands/agree.md"
  [ "$status" -eq 0 ]
}

@test "references/agreements.md contains the announce format" {
  run command grep -F '→ AGR-NNN записано' "$REPO_ROOT/references/agreements.md"
  [ "$status" -eq 0 ]
}

@test "references/agreements.md has an anti-example section" {
  run command grep -iE '^#+ .*(NOT an agreement|anti-example)' "$REPO_ROOT/references/agreements.md"
  [ "$status" -eq 0 ]
}

@test "references/agreements.md documents the 4 statuses" {
  for s in active deferred superseded rejected; do
    run command grep -Fi "$s" "$REPO_ROOT/references/agreements.md"
    [ "$status" -eq 0 ]
  done
}

@test "references/agreements.md documents ADR routing and lazy activation" {
  run command grep -F '→ ADR-' "$REPO_ROOT/references/agreements.md"
  [ "$status" -eq 0 ]
  run command grep -Fi 'lazy' "$REPO_ROOT/references/agreements.md"
  [ "$status" -eq 0 ]
  run command grep -F 'MB_AGREEMENTS=off' "$REPO_ROOT/references/agreements.md"
  [ "$status" -eq 0 ]
}

@test "SKILL.md registers the agreements feature" {
  run command grep -Fi 'agreements.md' "$REPO_ROOT/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "agents/plan-verifier.md carries the Agreement Compliance step" {
  run command grep -F 'Agreement Compliance' "$REPO_ROOT/agents/plan-verifier.md"
  [ "$status" -eq 0 ]
}

@test "agents/plan-verifier.md documents the three classifications" {
  for c in satisfied violated 'not-applicable'; do
    run command grep -Fi "$c" "$REPO_ROOT/agents/plan-verifier.md"
    [ "$status" -eq 0 ]
  done
}

@test "agents/plan-verifier.md documents fix-or-supersede on violation" {
  run command grep -Fi 'supersede' "$REPO_ROOT/agents/plan-verifier.md"
  [ "$status" -eq 0 ]
}

@test "agents/plan-verifier.md skips silently when agreements.md is absent" {
  run command grep -Fi 'no agreements' "$REPO_ROOT/agents/plan-verifier.md"
  [ "$status" -eq 0 ] || run command grep -Fi 'skip' "$REPO_ROOT/agents/plan-verifier.md"
  [ "$status" -eq 0 ]
}
