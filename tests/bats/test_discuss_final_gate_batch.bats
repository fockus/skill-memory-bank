#!/usr/bin/env bats
# final_gate_batch: — svp-interview-upgrade Task 2 prompt contract.
# Grilling rule 12 (final "anything to add?" gate) + Batch mode section (frontier
# rounds, tool limit, degradation, partial answers, parallel fact-finding,
# citation, honest sequential degradation, default-off, rule-6 override).
# Every clause carries BOTH assert_clause and assert_clause_load_bearing.
#
# Name convention: every @test starts with `final_gate_batch: ` (Eval red-anchor
# `not ok [0-9]+ final_gate_batch: `).

load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  MB_DISCUSS_CLAUSES=()
  # rule 12
  MB_DISCUSS_CLAUSES+=("rule12-gate-after-close|mb_rule|12|anything to add.*before generation|anything to add|s/before generation/after generation/|REQ-003")
  MB_DISCUSS_CLAUSES+=("rule12-reopen-on-addition|mb_rule|12|non-empty answer reopens.*ledger|non-empty answer reopens|s/ on the decision ledger//|REQ-004")
  MB_DISCUSS_CLAUSES+=("rule12-explicit-no|mb_rule|12|only an explicit .no. lets generation proceed|generation proceed|s/only an explicit .no./the absence of an answer/|REQ-003")
  # batch mode
  MB_DISCUSS_CLAUSES+=("batch-overrides-rule6|mb_section|Batch mode|overrides grilling rule 6|overrides grilling rule|s/grilling rule 6/grilling rule 9/|REQ-015")
  MB_DISCUSS_CLAUSES+=("batch-frontier-round|mb_section|Batch mode|whole current frontier.*recommendation on each|frontier|s/, with a recommendation on each question//|REQ-015")
  MB_DISCUSS_CLAUSES+=("batch-tool-limit|mb_section|Batch mode|up to 4 questions per call.*several calls|AskUserQuestion|s/ and issue several calls in one round when the frontier exceeds four//|REQ-015")
  MB_DISCUSS_CLAUSES+=("batch-degradation|mb_section|Batch mode|degrades to a numbered plain-text list.*never skipped|interactive question tool|s/degrades to a numbered plain-text list — it is never skipped/is skipped/|REQ-016")
  MB_DISCUSS_CLAUSES+=("partial-answer-keeps-open|mb_section|Batch mode|unanswered question stays.*next frontier|partially answered|s/ and returns in the next frontier//|REQ-022")
  # fact-finding
  MB_DISCUSS_CLAUSES+=("factfind-parallel|mb_section|Batch mode|parallel subagents, one per frontier question|fact-find|s/parallel subagents, one per frontier question/the main agent/|REQ-055")
  MB_DISCUSS_CLAUSES+=("factfind-cites|mb_section|Batch mode|must cite the found fact|recommendation|s/must cite the found fact/may guess/|REQ-015")
  MB_DISCUSS_CLAUSES+=("factfind-degrade-sequential|mb_section|Batch mode|sequentially in the main agent — never skipped|platform_limited|s/run the same fact-finding sequentially in the main agent — never skipped/skip the fact-finding/|REQ-056")
  MB_DISCUSS_CLAUSES+=("factfind-degrade-announced|mb_section|Batch mode|report the degradation to the user|platform_limited|s/ — and report the degradation to the user in one line//|REQ-056")
  MB_DISCUSS_CLAUSES+=("factfind-default-off|mb_section|Batch mode|[Ww]ithout .--batch. the default is unchanged|subagent dispatch|s/Without .--batch. the default is unchanged/Even in batch mode/|REQ-055")
}

_clause_pair() {
  run assert_clause "$DISCUSS" "$1"
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" "$1"
  [ "$status" -eq 0 ]
}

@test "final_gate_batch: rule 12 asks the final gate before generation" { _clause_pair rule12-gate-after-close; }
@test "final_gate_batch: rule 12 reopens the iteration and updates the ledger on an addition" { _clause_pair rule12-reopen-on-addition; }
@test "final_gate_batch: rule 12 lets generation proceed only on an explicit no" { _clause_pair rule12-explicit-no; }
@test "final_gate_batch: --batch overrides only grilling rule 6" { _clause_pair batch-overrides-rule6; }
@test "final_gate_batch: batch asks the whole frontier with a recommendation on each" { _clause_pair batch-frontier-round; }
@test "final_gate_batch: batch respects the 4-question tool limit with multiple calls" { _clause_pair batch-tool-limit; }
@test "final_gate_batch: batch degrades to numbered plain text, never skipped" { _clause_pair batch-degradation; }
@test "final_gate_batch: partial answers keep unanswered questions in the next frontier" { _clause_pair partial-answer-keeps-open; }
@test "final_gate_batch: fact-finding runs in parallel subagents per frontier question" { _clause_pair factfind-parallel; }
@test "final_gate_batch: each recommendation cites the found fact" { _clause_pair factfind-cites; }
@test "final_gate_batch: fact-finding degrades to sequential main-agent work, not skip" { _clause_pair factfind-degrade-sequential; }
@test "final_gate_batch: the sequential degradation is announced to the user" { _clause_pair factfind-degrade-announced; }
@test "final_gate_batch: without --batch the one-question default is unchanged" { _clause_pair factfind-default-off; }

@test "final_gate_batch: mandatory subagent dispatch requires Task in allowed-tools (REQ-055)" {
  # The batch fact-finding clauses mandate Task-based subagent dispatch; on a
  # host that enforces allowed-tools this is impossible unless Task is granted.
  # Bind the mandatory clause to the allowlist capability so a green clause
  # text can never mask a missing permission.
  _clause_pair factfind-parallel
  _clause_pair factfind-default-off
  run assert_tool_allowed "$DISCUSS" Task
  [ "$status" -eq 0 ]
}

@test "final_gate_batch: harness rejects a vacuous rule-12 clause" {
  # Bare clause: clause-ERE == topic-anchor == `generation` on the single-line
  # rule 12; a real mutation leaves the word, so the assertion is vacuous.
  MB_DISCUSS_CLAUSES+=("bare-generation|mb_rule|12|generation|generation|s/before generation/after generation/|REQ-003")
  run assert_clause_load_bearing "$DISCUSS" bare-generation
  [ "$status" -ne 0 ]
  echo "$output" | grep -Eq 'reason=(vacuous|mutation_removed_topic)'
}
