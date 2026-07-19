# Shared fixture helpers for the mb-spec-validate.sh v2 / C8 bats suites
# (svp-sdd-core Task 2). Loaded by test_mb_spec_validate_v2*.bats via `load`.
#
# The baseline triple is fully valid (has_eval → gates active); negative tests
# mutate exactly ONE thing so the failure is attributable.
#
# Consumers set $SPECS (specs root) and $VALIDATE in their own setup().

DASH=$'\xe2\x80\x94'  # em-dash used by the Eval grammar

write_req() {
  # $1 = spec dir
  cat >"$1/requirements.md" <<EOF
# Requirements: demo

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall persist work items to disk.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: persist round trip
**Covers:** REQ-001

- GIVEN a work item
- WHEN it is persisted
- THEN it round-trips
<!-- /mb-scenario:1 -->
EOF
}

write_tasks() {
  # $1 = spec dir
  cat >"$1/tasks.md" <<EOF
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: persist work items

**Covers:** REQ-001
**Role:** backend
**Eval:** \`bats tests/bats/test_demo.bats\` ${DASH} red: demo assertion fails; exit: 1; output~: \`not ok [0-9]+ demo_persist\`

**What to do:**
- persist to disk.

**Testing (TDD — tests BEFORE implementation):**
- round-trip test.

**DoD:**
- [ ] persist works.
<!-- /mb-task:1 -->
EOF
}

write_design() {
  # $1 = spec dir
  cat >"$1/design.md" <<EOF
# Design: demo

## Contract

**Seams:**
- the persistence boundary

## Eval declarations

- **T1** ${DASH} persist work items:
  **Eval:** \`bats tests/bats/test_demo.bats\` ${DASH} red: demo assertion fails; exit: 1; output~: \`not ok [0-9]+ demo_persist\`
EOF
}

mkbase() {
  # $1 = topic → returns spec dir on stdout
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  write_req "$dir"; write_tasks "$dir"; write_design "$dir"
  printf '%s\n' "$dir"
}
