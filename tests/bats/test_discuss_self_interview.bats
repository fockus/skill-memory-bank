#!/usr/bin/env bats
# self_interview: — svp-interview-upgrade Task 6 prompt contract.
# The `### Self-interview` section: --self/--auto flag matrix + the
# `## Assumptions (self-answered)` block + usage-error and resume rules (C6).
# Every clause carries BOTH assert_clause and assert_clause_load_bearing.
#
# Name convention: every @test starts with `self_interview: ` (Eval red-anchor).

load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("self-answers-from-brief|mb_section|Self-interview|answers the interview questions itself from the brief|--self|s/ from the brief//|REQ-012")
  MB_DISCUSS_CLAUSES+=("self-assumptions-block|mb_section|Self-interview|Every self-answered decision is recorded in a .## Assumptions|Assumptions|s/Every self-answered decision/Important self-answered decisions/|REQ-012")
  MB_DISCUSS_CLAUSES+=("self-batch-confirm|mb_section|Self-interview|assumptions batch for confirmation before generation|assumptions batch|s/before generation/after generation/|REQ-013")
  MB_DISCUSS_CLAUSES+=("auto-non-blocking|mb_section|Self-interview|does not block on assumptions and offers their review after completion|--auto|s/ after completion//|REQ-014")
  MB_DISCUSS_CLAUSES+=("auto-requires-self|mb_section|Self-interview|without .--self. is a usage error raised before writing any files|--auto|s/ raised before writing any files//|REQ-014")
  MB_DISCUSS_CLAUSES+=("empty-brief-usage-error|mb_section|Self-interview|empty or whitespace-only brief is a usage error|brief|s/empty or whitespace-only brief/empty brief/|REQ-012")
  MB_DISCUSS_CLAUSES+=("batch-self-compatible|mb_section|Self-interview|is compatible with .--self. and changes only the frontier size|--batch|s/changes only the frontier size, not the answer mode/changes the answer mode/|REQ-015")
  MB_DISCUSS_CLAUSES+=("draft-resume|mb_section|Self-interview|draft. context resumes the saved interview plan|draft|s/resumes the saved interview plan rather than starting over/starts over/|REQ-012")
  MB_DISCUSS_CLAUSES+=("ready-context-choice|mb_section|Self-interview|edit / overwrite / cancel|ready|s# / cancel choice# choice#|REQ-012")
}

_pair() {
  run assert_clause "$DISCUSS" "$1"
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$DISCUSS" "$1"
  [ "$status" -eq 0 ]
}

@test "self_interview: --self answers the interview from the brief" { _pair self-answers-from-brief; }
@test "self_interview: every self-answered decision lands in the Assumptions block" { _pair self-assumptions-block; }
@test "self_interview: interactive self-interview confirms assumptions before generation" { _pair self-batch-confirm; }
@test "self_interview: --auto does not block and offers review after completion" { _pair auto-non-blocking; }
@test "self_interview: --auto without --self is a usage error before writing files" { _pair auto-requires-self; }
@test "self_interview: an empty/whitespace-only brief is a usage error before writing files" { _pair empty-brief-usage-error; }
@test "self_interview: --batch is orthogonal to --self (frontier size only)" { _pair batch-self-compatible; }
@test "self_interview: a draft context resumes the saved interview plan" { _pair draft-resume; }
@test "self_interview: a ready context keeps the edit/overwrite/cancel choice" { _pair ready-context-choice; }

@test "self_interview: harness rejects a vacuous self-interview clause" {
  MB_DISCUSS_CLAUSES+=("bare-citing|mb_section|Self-interview|citing|citing|s/ from the brief//|REQ-012")
  run assert_clause_load_bearing "$DISCUSS" bare-citing
  [ "$status" -ne 0 ]
  echo "$output" | grep -Eq 'reason=(vacuous|mutation_removed_topic)'
}
