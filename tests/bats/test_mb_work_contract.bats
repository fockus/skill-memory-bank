#!/usr/bin/env bats
# Tests for scripts/mb-work-contract.sh — per-work-item sprint contract
# create/read/validate/path (work-loop-v2 design.md §4 "Sprint contract —
# format and lifecycle", REQ-110).
#
# Contract under test:
#   path convention: <bank>/contracts/<plan-topic>_stage-<N>.md
#   create: scaffolds the contract from the frontmatter + 6 body sections;
#           idempotent -- a second create for the same plan/stage never
#           clobbers the file.
#   read:   prints the contract file verbatim; missing -> clear non-zero.
#   validate: scope-lock check -- ALL frontmatter keys AND all 6 body
#           sections must be present; missing pieces are named on stderr.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-work-contract.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK/plans"
  PLAN="$BANK/plans/2026-07-04_feature_work-loop-v2.md"
  : >"$PLAN"
}

well_formed_contract() {
  # $1 = destination file path
  cat >"$1" <<'EOF'
---
plan: /p/plan.md
stage: 2
item_id: stage-2
generator_role: mb-architect
created: 2026-07-05T00:00:00Z
status: draft
contract_version: 1
---

# Contract: well-formed example

## In scope (what THIS item delivers)
- one concrete deliverable

## Plan of attack (ordered, mechanical)
1. do the thing

## Test plan
- Unit: unit coverage
- Integration: integration coverage
- E2E (if applicable): none

## DoD checkpoints (echoes plan, with how-to-verify)
- [ ] item 1 -> verified by test X

## Out of scope (explicit non-deliverables)
- not this

## Open risks (acknowledged at contract time)
- none
EOF
}

@test "mb-work-contract.sh: script exists and is executable" {
  [ -f "$RUN" ]
  [ -x "$RUN" ]
}

@test "--help exits 0 and documents create/read/validate/path" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"create"* ]]
  [[ "$output" == *"read"* ]]
  [[ "$output" == *"validate"* ]]
  [[ "$output" == *"path"* ]]
}

@test "unknown subcommand -> usage error, exit 2" {
  run bash "$RUN" bogus
  [ "$status" -eq 2 ]
}

@test "no subcommand -> usage error, exit 2" {
  run bash "$RUN"
  [ "$status" -eq 2 ]
}

# ---- path --------------------------------------------------------------

@test "path: deterministic -- <bank>/contracts/<plan-topic>_stage-<N>.md" {
  run bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage 2
  [ "$status" -eq 0 ]
  [ "$output" = "$BANK/contracts/work-loop-v2_stage-2.md" ]
}

@test "path: repeated calls with identical inputs return the identical path" {
  run bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage 2
  first="$output"
  run bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage 2
  [ "$status" -eq 0 ]
  [ "$first" = "$output" ]
}

@test "path: differs when stage differs (same plan)" {
  run bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage 2
  first="$output"
  run bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage 3
  [ "$status" -eq 0 ]
  [ "$first" != "$output" ]
}

@test "path: spec-style plan (specs/<topic>/tasks.md) derives topic from the directory name" {
  mkdir -p "$BANK/specs/reviewer-2.0"
  spec_plan="$BANK/specs/reviewer-2.0/tasks.md"
  : >"$spec_plan"
  run bash "$RUN" path --mb "$BANK" --plan "$spec_plan" --stage 5
  [ "$status" -eq 0 ]
  [ "$output" = "$BANK/contracts/reviewer-2.0_stage-5.md" ]
}

@test "path: missing --stage -> exit 2" {
  run bash "$RUN" path --mb "$BANK" --plan "$PLAN"
  [ "$status" -eq 2 ]
}

@test "path: missing --plan -> exit 2" {
  run bash "$RUN" path --mb "$BANK" --stage 1
  [ "$status" -eq 2 ]
}

@test "path: non-numeric --stage -> exit 2" {
  run bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage abc
  [ "$status" -eq 2 ]
}

# ---- create --------------------------------------------------------------

@test "create: produces a file with all frontmatter keys and all 6 body sections" {
  run bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 2 --role mb-architect --title "Contract script"
  [ "$status" -eq 0 ]
  contract="$output"
  [ -f "$contract" ]

  for key in plan: stage: item_id: generator_role: created: status: contract_version:; do
    grep -qE "^${key}" "$contract"
  done

  grep -qE '^# Contract:' "$contract"
  grep -qE '^## In scope' "$contract"
  grep -qE '^## Plan of attack' "$contract"
  grep -qE '^## Test plan' "$contract"
  grep -qE '^## DoD checkpoints' "$contract"
  grep -qE '^## Out of scope' "$contract"
  grep -qE '^## Open risks' "$contract"
}

@test "create: frontmatter echoes the plan, stage, role, and starts status:draft" {
  run bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 2 --role mb-architect
  [ "$status" -eq 0 ]
  contract="$output"

  run cat "$contract"
  [[ "$output" == *"plan: $PLAN"* ]]
  [[ "$output" == *"stage: 2"* ]]
  [[ "$output" == *"item_id: stage-2"* ]]
  [[ "$output" == *"generator_role: mb-architect"* ]]
  [[ "$output" == *"status: draft"* ]]
  [[ "$output" == *"contract_version: 1"* ]]
}

@test "create: defaults generator_role to 'unassigned' when --role is omitted" {
  run bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 4
  [ "$status" -eq 0 ]
  contract="$output"
  run cat "$contract"
  [[ "$output" == *"generator_role: unassigned"* ]]
}

@test "create: prints the same deterministic path 'path' would print" {
  run bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage 2
  expected="$output"
  run bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 2
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "create: idempotent -- second call does not clobber, same path, exit 0" {
  run bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 2 --title "Original title"
  [ "$status" -eq 0 ]
  contract="$output"

  # Simulate a hand-edit (e.g. reviewer approved it) between calls.
  printf '\nstatus: approved\n' >>"$contract"
  before_hash=$(cat "$contract")

  run bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 2 --title "A different title"
  [ "$status" -eq 0 ]
  [ "$output" = "$contract" ]

  after_hash=$(cat "$contract")
  [ "$before_hash" = "$after_hash" ]
}

@test "create: missing --stage -> exit 2" {
  run bash "$RUN" create --mb "$BANK" --plan "$PLAN"
  [ "$status" -eq 2 ]
}

# ---- read --------------------------------------------------------------

@test "read: rereads an existing contract identically to its on-disk content" {
  bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 2 --role mb-architect >/dev/null
  contract=$(bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage 2)

  run bash "$RUN" read --mb "$BANK" --plan "$PLAN" --stage 2
  [ "$status" -eq 0 ]
  expected=$(cat "$contract")
  [ "$output" = "$expected" ]
}

@test "read: idempotent -- two consecutive reads return identical output" {
  bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 2 >/dev/null

  run bash "$RUN" read --mb "$BANK" --plan "$PLAN" --stage 2
  first="$output"
  run bash "$RUN" read --mb "$BANK" --plan "$PLAN" --stage 2
  [ "$status" -eq 0 ]
  [ "$first" = "$output" ]
}

@test "read: missing contract -> clear non-zero exit, no stack trace" {
  run bash "$RUN" read --mb "$BANK" --plan "$PLAN" --stage 99
  [ "$status" -ne 0 ]
  [[ "$output" == *"no contract"* ]]
  [[ "$output" != *"Traceback"* ]]
}

# ---- validate --------------------------------------------------------------

@test "validate: PASSES a well-formed contract" {
  contract="$BATS_TEST_TMPDIR/good.md"
  well_formed_contract "$contract"

  run bash "$RUN" validate "$contract"
  [ "$status" -eq 0 ]
}

@test "validate: a real create-scaffolded contract also PASSES once frontmatter is intact" {
  # create leaves body bullets empty, but every heading is present -- the
  # scope-lock check is heading-presence, not bullet-content.
  run bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 2
  [ "$status" -eq 0 ]
  contract="$output"

  run bash "$RUN" validate "$contract"
  [ "$status" -eq 0 ]
}

@test "validate: FAILS and names 'in-scope' when In scope section is absent" {
  contract="$BATS_TEST_TMPDIR/no-in-scope.md"
  well_formed_contract "$contract"
  # Drop the "## In scope" section (and its one bullet) from the fixture.
  grep -v -E '^## In scope|^- one concrete deliverable$' "$contract" >"$contract.tmp"
  mv "$contract.tmp" "$contract"

  run bash "$RUN" validate "$contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"in-scope"* ]]
}

@test "validate: FAILS and names 'out-of-scope' when Out of scope section is absent" {
  contract="$BATS_TEST_TMPDIR/no-out-of-scope.md"
  well_formed_contract "$contract"
  grep -v -E '^## Out of scope|^- not this$' "$contract" >"$contract.tmp"
  mv "$contract.tmp" "$contract"

  run bash "$RUN" validate "$contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"out-of-scope"* ]]
}

@test "validate: FAILS and names 'test-plan' when Test plan section is absent" {
  contract="$BATS_TEST_TMPDIR/no-test-plan.md"
  well_formed_contract "$contract"
  grep -v -E '^## Test plan|Unit: unit coverage|Integration: integration coverage|E2E \(if applicable\): none' "$contract" >"$contract.tmp"
  mv "$contract.tmp" "$contract"

  run bash "$RUN" validate "$contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"test-plan"* ]]
}

@test "validate: FAILS and names 'dod-checkpoints' when DoD checkpoints section is absent" {
  contract="$BATS_TEST_TMPDIR/no-dod.md"
  well_formed_contract "$contract"
  grep -v -E '^## DoD checkpoints|item 1 -> verified by test X' "$contract" >"$contract.tmp"
  mv "$contract.tmp" "$contract"

  run bash "$RUN" validate "$contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"dod-checkpoints"* ]]
}

@test "validate: FAILS and names a missing frontmatter key" {
  contract="$BATS_TEST_TMPDIR/no-status-key.md"
  well_formed_contract "$contract"
  grep -v -E '^status: draft$' "$contract" >"$contract.tmp"
  mv "$contract.tmp" "$contract"

  run bash "$RUN" validate "$contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status"* ]]
}

@test "validate: reports multiple missing sections in one pass" {
  contract="$BATS_TEST_TMPDIR/many-missing.md"
  well_formed_contract "$contract"
  grep -v -E '^## Out of scope|^- not this$|^## Test plan|Unit: unit coverage|Integration: integration coverage|E2E \(if applicable\): none' "$contract" >"$contract.tmp"
  mv "$contract.tmp" "$contract"

  run bash "$RUN" validate "$contract"
  [ "$status" -ne 0 ]
  [[ "$output" == *"out-of-scope"* ]]
  [[ "$output" == *"test-plan"* ]]
}

@test "validate: missing file -> clear non-zero, no stack trace" {
  run bash "$RUN" validate "$BATS_TEST_TMPDIR/does-not-exist.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" != *"Traceback"* ]]
}

@test "validate: missing <contract-file> argument -> usage error, exit 2" {
  run bash "$RUN" validate
  [ "$status" -eq 2 ]
}

@test "bash 3.2 (/bin/bash) clean: create, read, validate, path all run under macOS system bash" {
  run /bin/bash "$RUN" create --mb "$BANK" --plan "$PLAN" --stage 7
  [ "$status" -eq 0 ]
  contract="$output"

  run /bin/bash "$RUN" read --mb "$BANK" --plan "$PLAN" --stage 7
  [ "$status" -eq 0 ]

  run /bin/bash "$RUN" validate "$contract"
  [ "$status" -eq 0 ]

  run /bin/bash "$RUN" path --mb "$BANK" --plan "$PLAN" --stage 7
  [ "$status" -eq 0 ]
  [ "$output" = "$contract" ]
}
