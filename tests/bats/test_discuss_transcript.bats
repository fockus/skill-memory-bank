#!/usr/bin/env bats
# transcript: — svp-interview-upgrade Task 4 prompt contract.
# The Transcript step in `### Write & finalize` (candidate-first, secret-scan
# gate, <private>-is-not-a-bypass, block-on-finding, frontmatter) + the C4
# transcript template in references/templates.md.
#
# Name convention: every @test starts with `transcript: ` (Eval red-anchor).

load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DISCUSS="$REPO_ROOT/commands/discuss.md"
  TEMPLATES="$REPO_ROOT/references/templates.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("transcript-candidate-first|mb_section|Transcript|[Cc]andidate to.*before any git-tracked path|candidate|s/ before any git-tracked path//|REQ-005")
  MB_DISCUSS_CLAUSES+=("transcript-scan-gate|mb_section|Transcript|mb-secret-scan.*before publication|mb-secret-scan|s/before publication/after publication/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-private-not-clean|mb_section|Transcript|raw text including content inside|raw text|s/ including content inside .<private>.//|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-block-on-finding|mb_section|Transcript|git target is not created|finding|s/the git target is not created/the git target is overwritten/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-frontmatter|mb_section|Transcript|frontmatter records .interview_transcript:|frontmatter|s/ records .interview_transcript:.*//|REQ-005")
  MB_DISCUSS_CLAUSES+=("template-c4-grammar|mb_section|Interview transcript template|\\*\\*Финальный гейт|Interview transcript|/\\*\\*Финальный гейт/d|REQ-005")
}

_pair() {
  run assert_clause "$1" "$2"
  [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$1" "$2"
  [ "$status" -eq 0 ]
}

@test "transcript: candidate is written before any git-tracked path" { _pair "$DISCUSS" transcript-candidate-first; }
@test "transcript: secret-scan runs on the candidate before publication" { _pair "$DISCUSS" transcript-scan-gate; }
@test "transcript: <private> does not unblock a git write" { _pair "$DISCUSS" transcript-private-not-clean; }
@test "transcript: a finding blocks target creation" { _pair "$DISCUSS" transcript-block-on-finding; }
@test "transcript: context frontmatter records interview_transcript" { _pair "$DISCUSS" transcript-frontmatter; }
@test "transcript: templates.md carries the C4 grammar markers" { _pair "$TEMPLATES" template-c4-grammar; }

@test "transcript: harness rejects a vacuous transcript clause" {
  # Bare word `interview-transcript` matches exactly one line (the candidate
  # path); a real mutation of the normative tail leaves the word → vacuous.
  MB_DISCUSS_CLAUSES+=("bare-it|mb_section|Transcript|interview-transcript|interview-transcript|s/ before any git-tracked path//|REQ-005")
  run assert_clause_load_bearing "$DISCUSS" bare-it
  [ "$status" -ne 0 ]
  echo "$output" | grep -Eq 'reason=(vacuous|mutation_removed_topic)'
}
