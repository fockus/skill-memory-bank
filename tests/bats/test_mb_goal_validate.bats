#!/usr/bin/env bats
# Tests for scripts/mb-goal-validate.sh — the goal precondition GATE.
#
# This is a PRECONDITION GATE (REQ-DF-004), so fail-loud exit 1 is correct
# (ADR-3's exit-0 rule applies only to the L5 check-runners, NOT to this
# validator). Behaviour under test:
#   - valid static goal (no adaptive fields) → exit 0, {"ok":true}   (REQ-DF-005)
#   - valid adaptive goal (mode+replan_with+source+acceptance) → exit 0
#   - missing acceptance criteria → exit 1, errors[]=acceptance-missing (REQ-DF-001)
#   - missing progress_source → exit 1, errors[]=progress_source-missing (REQ-DF-003)
#   - unresolvable/invalid progress_source → exit 1, errors[]=progress_source-unresolvable
#   - adaptive mode without replan_with → exit 1, errors[]=replan_with-missing (REQ-DF-004)
#
# All fixture tests pass "$BANK" as the second arg to mb-goal-validate.sh so
# mb_resolve_path uses the isolated temp bank, never the real repo bank.
# Linked paths in fixtures are chosen to NOT exist anywhere in the real repo.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-goal-validate.sh"
  command -v jq >/dev/null || skip "jq required"
  BANK="$(mktemp -d)/.memory-bank"
  mkdir -p "$BANK"
  GOAL="$BANK/goal.md"
}

teardown() {
  [ -n "${BANK:-}" ] && rm -rf "$(dirname "$BANK")"
}

# ---- helpers ----------------------------------------------------------------

# Assert a specific machine error code appears in errors[].
# bats captures stdout+stderr together in $output. The validator prints
# "[goal] …" fix-hints on stderr and JSON on stdout. We extract the JSON
# line (the one starting with '{') before feeding to jq.
assert_error_code() {
  local code="$1" output="$2"
  local json_line
  json_line="$(printf '%s\n' "$output" | grep '^{' | tail -n1)"
  printf '%s\n' "$json_line" | jq -e --arg code "$code" '.errors | map(. == $code) | any' >/dev/null
}

# ---- fixtures ---------------------------------------------------------------

write_static_goal() {
  # Uses checklist as bank-level source; create checklist.md so it resolves.
  mkdir -p "$BANK"
  touch "$BANK/checklist.md"
  cat >"$GOAL" <<'EOF'
---
id: G-001
status: active
progress_source: checklist
linked_plans: []
---

# Goal

## Description
Ship the firewall increment.

## Acceptance criteria
- [ ] mb-flow-verify.sh propagates 0/1/2
- [x] goal.md exists with deterministic acceptance
EOF
}

write_adaptive_goal() {
  mkdir -p "$BANK"
  touch "$BANK/checklist.md"
  cat >"$GOAL" <<'EOF'
---
id: G-002
status: active
mode: adaptive
progress_source: checklist
replan_with: analyze-task
linked_plans: []
---

# Goal

## Description
Adaptive route-picking flow.

## Acceptance criteria
- [ ] router names exactly one route
EOF
}

# ---- contract ---------------------------------------------------------------

@test "contract: mb-goal-validate.sh exists" {
  [ -f "$VALIDATE" ]
}

@test "contract: --help exits 0 and mentions goal validation" {
  run bash "$VALIDATE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"goal"* ]]
}

# ---- valid cases (exit 0) ---------------------------------------------------

@test "valid static goal with no adaptive fields exits 0 with ok:true (REQ-DF-005)" {
  write_static_goal
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
}

@test "valid static goal: defaults mode to static, requires no adaptive field (REQ-DF-005)" {
  mkdir -p "$BANK"; touch "$BANK/checklist.md"
  cat >"$GOAL" <<'EOF'
---
id: G-003
status: active
progress_source: checklist
---

# Goal

## Description
Minimal static goal.

## Acceptance criteria
- [ ] one criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
}

@test "valid adaptive goal (mode+replan_with+source+acceptance) exits 0" {
  write_adaptive_goal
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
}

@test "progress_source spec-tasks resolves when spec dir with tasks.md exists → exit 0" {
  mkdir -p "$BANK/specs/fixture-spec-zzz"
  printf '<!-- mb-task:1 -->\n' >"$BANK/specs/fixture-spec-zzz/tasks.md"
  cat >"$GOAL" <<'EOF'
---
id: G-004
status: active
progress_source: spec-tasks
linked_spec: specs/fixture-spec-zzz
---

# Goal

## Description
Source points at a real spec.

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.ok == true'
}

# Finding #2 (a): frontmatter with no closing fence — fields must be treated as missing
@test "frontmatter with no closing fence → fields empty → acceptance-missing + progress_source-missing" {
  cat >"$GOAL" <<'EOF'
---
id: G-020
status: active
progress_source: checklist

# Goal

## Description
No closing frontmatter fence.

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-missing" "$output"
}

# Finding #2 (b): body horizontal-rule `---` + progress_source below it must NOT be read as frontmatter
@test "body horizontal-rule + progress_source below it is NOT read as frontmatter" {
  cat >"$GOAL" <<'EOF'
---
id: G-021
status: active
---

# Goal

## Description
The rule below is a body rule.

---
progress_source: checklist

## Acceptance criteria
- [ ] criterion
EOF
  # progress_source is in the body, NOT frontmatter → must fail with progress_source-missing
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-missing" "$output"
}

# ---- invalid cases (exit 1 + machine error codes) ---------------------------

@test "missing acceptance criteria → exit 1, errors contains acceptance-missing (REQ-DF-001)" {
  mkdir -p "$BANK"; touch "$BANK/checklist.md"
  cat >"$GOAL" <<'EOF'
---
id: G-005
status: active
progress_source: checklist
---

# Goal

## Description
No acceptance section at all.
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "acceptance-missing" "$output"
}

@test "empty acceptance criteria (no checkbox items) → exit 1, errors contains acceptance-missing" {
  mkdir -p "$BANK"; touch "$BANK/checklist.md"
  cat >"$GOAL" <<'EOF'
---
id: G-006
status: active
progress_source: checklist
---

# Goal

## Acceptance criteria
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "acceptance-missing" "$output"
}

# Finding #1: checkbox inside a code fence must NOT count as acceptance item
@test "checkbox only inside a code block does NOT satisfy acceptance criteria → exit 1" {
  mkdir -p "$BANK"; touch "$BANK/checklist.md"
  cat >"$GOAL" <<'EOF'
---
id: G-011
status: active
progress_source: checklist
---

# Goal

## Acceptance criteria

This section shows an example (inside code — NOT real criteria):

```
- [ ] this checkbox is inside a fenced code block and must be ignored
```

~~~
- [x] this one too (tilde fence)
~~~
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "acceptance-missing" "$output"
}

@test "missing progress_source → exit 1, errors contains progress_source-missing (REQ-DF-003)" {
  cat >"$GOAL" <<'EOF'
---
id: G-007
status: active
---

# Goal

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-missing" "$output"
}

@test "progress_source value outside the allowed set → exit 1, errors contains progress_source-invalid" {
  cat >"$GOAL" <<'EOF'
---
id: G-008
status: active
progress_source: vibes
---

# Goal

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-invalid" "$output"
}

@test "progress_source spec-tasks pointing at MISSING spec → exit 1, errors contains progress_source-unresolvable" {
  cat >"$GOAL" <<'EOF'
---
id: G-009
status: active
progress_source: spec-tasks
linked_spec: specs/fixture-no-such-spec-xyzzy
---

# Goal

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-unresolvable" "$output"
}

# Finding #3: spec-tasks with linked_spec pointing at a plain FILE (not a dir with tasks.md)
@test "progress_source spec-tasks with linked_spec pointing at a plain file → exit 1 (not a spec dir)" {
  mkdir -p "$BANK"
  # Create a plain file (not a dir containing tasks.md)
  printf 'not a tasks.md\n' >"$BANK/not-a-spec-dir.md"
  cat >"$GOAL" <<'EOF'
---
id: G-030
status: active
progress_source: spec-tasks
linked_spec: not-a-spec-dir.md
---

# Goal

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-unresolvable" "$output"
}

# Finding #3: spec-tasks with linked_spec pointing at a dir WITHOUT tasks.md
@test "progress_source spec-tasks with spec dir that has no tasks.md → exit 1" {
  mkdir -p "$BANK/specs/fixture-no-tasks-zzz"
  # The dir exists but no tasks.md inside it
  cat >"$GOAL" <<'EOF'
---
id: G-031
status: active
progress_source: spec-tasks
linked_spec: specs/fixture-no-tasks-zzz
---

# Goal

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-unresolvable" "$output"
}

# Finding #3: plan-stages with linked_plan pointing at a directory (not a .md file)
@test "progress_source plan-stages with linked_plan pointing at a directory → exit 1" {
  mkdir -p "$BANK/fixture-plan-dir-zzz"
  cat >"$GOAL" <<'EOF'
---
id: G-032
status: active
progress_source: plan-stages
linked_plan: fixture-plan-dir-zzz
---

# Goal

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-unresolvable" "$output"
}

# Finding #4: checklist source with no checklist.md in bank → exit 1
@test "progress_source checklist with no checklist.md in bank → exit 1" {
  mkdir -p "$BANK"
  # Intentionally do NOT create checklist.md
  cat >"$GOAL" <<'EOF'
---
id: G-040
status: active
progress_source: checklist
---

# Goal

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "progress_source-unresolvable" "$output"
}

@test "adaptive mode without replan_with → exit 1, errors contains replan_with-missing (REQ-DF-004)" {
  mkdir -p "$BANK"; touch "$BANK/checklist.md"
  cat >"$GOAL" <<'EOF'
---
id: G-010
status: active
mode: adaptive
progress_source: checklist
---

# Goal

## Acceptance criteria
- [ ] criterion
EOF
  run bash "$VALIDATE" "$GOAL" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "replan_with-missing" "$output"
}

@test "missing goal file → exit 1, errors contains goal-missing" {
  run bash "$VALIDATE" "$BANK/nonexistent-goal.md" "$BANK"
  [ "$status" -eq 1 ]
  assert_error_code "goal-missing" "$output"
}
