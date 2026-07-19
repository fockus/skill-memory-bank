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
  # REQ-007 candidate hygiene: verify-then-publish ordering and the guarantee
  # that the raw credential never lingers on disk.
  MB_DISCUSS_CLAUSES+=("transcript-verify-then-publish|mb_section|Transcript|order is .*verify, then publish.* — never publish, then verify|order|s/never publish, then verify/either order works/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-candidate-gitignored|mb_section|Transcript|tmp/. is gitignored|candidate|s/is gitignored/is a normal tracked directory/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-no-inplace-edit|mb_section|Transcript|[Nn]ever edit the candidate in place after a finding|candidate|s/Never edit the candidate in place/Edit the candidate in place/|REQ-007")
  MB_DISCUSS_CLAUSES+=("transcript-candidate-consumed|mb_section|Transcript|removes the candidate on every exit path|candidate|s/on every exit path/on success/|REQ-007")
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

# ─── candidate hygiene (review [5], REQ-007) ───

@test "transcript: the order is verify-then-publish, never the reverse" { _pair "$DISCUSS" transcript-verify-then-publish; }
@test "transcript: the candidate lives only in the gitignored scratch dir" { _pair "$DISCUSS" transcript-candidate-gitignored; }
@test "transcript: a finding forbids in-place editing of the candidate" { _pair "$DISCUSS" transcript-no-inplace-edit; }
@test "transcript: the candidate is consumed on every exit path" { _pair "$DISCUSS" transcript-candidate-consumed; }

@test "transcript: the gitignore claim in the prompt is actually true" {
  # A prompt clause asserting `<bank>/tmp/` is ignored is only safe if the repo
  # really ignores it — otherwise the candidate reaches git after all.
  run git -C "$REPO_ROOT" check-ignore -q .memory-bank/tmp/interview-transcript-x.candidate.md
  [ "$status" -eq 0 ]
}

@test "transcript: the writer really scrubs the candidate (prompt matches code)" {
  # Binds the prompt promise to the implementation: the claim "removed on every
  # exit path" must be backed by a trap in the writer, not just asserted.
  local w="$REPO_ROOT/scripts/mb-interview-artifact-write.sh"
  grep -q '_scrub_candidate' "$w"
  grep -Eq 'trap .*_scrub_candidate.* EXIT' "$w"
  grep -Eq "trap .*_on_signal 15.* TERM" "$w"
}

@test "transcript: harness rejects a vacuous transcript clause" {
  # Bare word `interview-transcript` matches exactly one line (the candidate
  # path); a real mutation of the normative tail leaves the word → vacuous.
  MB_DISCUSS_CLAUSES+=("bare-it|mb_section|Transcript|interview-transcript|interview-transcript|s/ before any git-tracked path//|REQ-005")
  run assert_clause_load_bearing "$DISCUSS" bare-it
  [ "$status" -ne 0 ]
  echo "$output" | grep -Eq 'reason=(vacuous|mutation_removed_topic)'
}
