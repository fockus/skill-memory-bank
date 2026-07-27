#!/usr/bin/env bats

# Task 3 (svp-contract-test-loop) — C3/C4 layer gates in mb-spec-validate.sh.
#
# The gates only exist for a spec that carries an explicit `layers` block. A
# spec WITHOUT the block is legacy (R3-001): no layer gate applies to it, so
# the whole existing corpus — including this slice's OWN spec, which has gated
# requirements, no `layers` block, and `**Layer:**` tasks at the END — keeps
# validating exactly as it did before S8.
#
# Every fixture below mutates exactly ONE thing away from a baseline that is
# green today, so a red run names its own cause. Fixtures carry no `**Eval:**`
# field on purpose: the v2/C8 battery activates on the Eval feature, and a
# dormant battery keeps every failure here attributable to the layer gate.

load 'lib/assert'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  VALIDATE="$REPO_ROOT/scripts/mb-spec-validate.sh"
  # A PRIVATE directory, never the shared TMPDIR: an assertion about a
  # directory other processes write to fails for reasons that have nothing to
  # do with the code under test, and passes when a real leak is masked (I-155).
  WORK="$(mktemp -d)"
  SPECS="$WORK/specs"
  mkdir -p "$SPECS"
}

teardown() {
  [ -n "${WORK:-}" ] && [ -d "$WORK" ] && rm -rf "$WORK"
}

# ── fixture builders ─────────────────────────────────────────────────────────

# write_req <dir> <layers-block|""> — the canonical owner of `layers` is this
# file's frontmatter; an empty second argument writes no frontmatter at all,
# which is precisely the legacy shape.
write_req() {
  local dir="$1" layers="$2"
  if [ -n "$layers" ]; then
    {
      printf -- '---\n'
      printf 'topic: %s\n' "$(basename "$dir")"
      printf '%s\n' "$layers"
      printf -- '---\n\n'
    } >"$dir/requirements.md"
  else
    : >"$dir/requirements.md"
  fi
  cat >>"$dir/requirements.md" <<'EOF'
# Requirements: demo

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall persist work items to disk.
- **REQ-002** (event-driven): When a work item is read, the system shall return it unchanged.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: persist round trip
**Covers:** REQ-001, REQ-002

- GIVEN a work item
- WHEN it is persisted
- THEN it round-trips
<!-- /mb-scenario:1 -->
EOF
}

write_design() {
  cat >"$1/design.md" <<'EOF'
# Design: demo

## Contract

**Seams:**
- the persistence boundary
EOF
}

# t_task <n> <title> <layer|""> <covers> <role> <checkbox> [extra body]
t_task() {
  local n="$1" title="$2" layer="$3" covers="$4" role="$5" box="$6" extra="${7:-}"
  printf -- '<!-- mb-task:%s -->\n## Task %s: %s\n\n' "$n" "$n" "$title"
  [ -n "$layer" ] && printf -- '**Layer:** %s\n' "$layer"
  printf -- '**Covers:** %s\n**Role:** %s\n\n' "$covers" "$role"
  printf -- '**What to do:**\n- do the work.\n'
  [ -n "$extra" ] && printf '%s\n' "$extra"
  printf -- '\n**Testing (TDD — tests BEFORE implementation):**\n- covered by tests.\n\n'
  printf -- '**DoD:**\n- [%s] %s\n' "$box" "${8:-the work is done.}"
  printf -- '<!-- /mb-task:%s -->\n\n' "$n"
}

# A CLOSED contract task must name the checker unit tests in its DoD, so this
# helper emits the compliant shape; the negative case builds its own.
t_contract()    { t_task "$1" "contract checkers" contract "REQ-001, REQ-002" backend "${2:- }" "${3:-}" \
                    'checker unit tests green: `bats tests/bats/test_persist_gate_checker.bats`'; }
t_impl()        { t_task "$1" "persist work items" "" "REQ-001, REQ-002" backend " "; }
t_integration() { t_task "$1" "integration tests" integration "REQ-001" qa " "; }
t_e2e()         { t_task "$1" "e2e tests" e2e "REQ-002" qa " "; }

ALL_ON='layers:
  contract_first: true
  integration_tests: true
  e2e_tests: true'

# mkspec <name> <layers-block|""> — tasks.md comes from stdin.
mkspec() {
  local dir="$SPECS/$1"
  mkdir -p "$dir"
  write_req "$dir" "$2"
  write_design "$dir"
  { printf '# Tasks: demo\n\n'; cat; } >"$dir/tasks.md"
  printf '%s\n' "$dir"
}

# ── baseline: the gates accept a correctly ordered spec ──────────────────────

@test "spec_validate_layers_baseline_ok: contract → impl → integration → e2e passes" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1; t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

# ── C3: the contract task ────────────────────────────────────────────────────

@test "spec_validate_missing_contract_task_fails: contract_first + gated REQ with no contract task" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_impl 1; t_integration 2; t_e2e 3; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "contract"
}

@test "spec_validate_contract_task_after_impl_fails: a contract task behind an implementation task" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_impl 1; t_contract 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "contract"
}

@test "spec_validate_two_contract_tasks_fail: the gate demands exactly one" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1; t_contract 2; t_impl 3; t_integration 4; t_e2e 5; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "contract"
}

@test "spec_validate_no_gated_req_not_applicable: contract_first true without a SHALL/MUST criterion" {
  dir="$SPECS/nogated"
  mkdir -p "$dir"
  cat >"$dir/requirements.md" <<'EOF'
---
topic: nogated
layers:
  contract_first: true
  integration_tests: false
  integration_tests_reason: "no component seam in this slice"
  e2e_tests: false
  e2e_tests_reason: "library without an external surface"
---

# Requirements: nogated

## Requirements (EARS)

No normative criteria yet — this slice only records intent.
EOF
  write_design "$dir"
  { printf '# Tasks: nogated\n\n'; t_task 1 "sketch the module" "" "REQ-100" backend " "; } >"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" "contract_layer=not_applicable"
}

@test "spec_validate_should_may_is_not_gated: a SHOULD criterion demands no contract task" {
  # D-06: only a normative SHALL/MUST gates. Reachability is worth stating —
  # this repo's EARS check demands `shall` on every REQ bullet, so a SHOULD-only
  # spec is refused by check 1 regardless. What must NOT happen is a SECOND
  # refusal inventing a contract task for a requirement that never gated.
  dir="$SPECS/shoulds"
  mkdir -p "$dir"
  cat >"$dir/requirements.md" <<'EOF'
---
topic: shoulds
layers:
  contract_first: true
  integration_tests: false
  integration_tests_reason: "no component seam in this slice"
  e2e_tests: false
  e2e_tests_reason: "library without an external surface"
---

# Requirements: shoulds

## Requirements (EARS)

- **REQ-001** (ubiquitous): The system should prefer the cached value.
EOF
  write_design "$dir"
  { printf '# Tasks: shoulds\n\n'; t_task 1 "prefer the cache" "" "REQ-001" backend " "; } >"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  assert_substring "$output" "contract_layer=not_applicable"
  refute_substring "$output" "contract_first is on with gated requirements"
}

@test "spec_validate_contract_first_false_ok: the disabled layer is named and no task is demanded" {
  dir="$(mkspec demo 'layers:
  contract_first: false
  contract_first_reason: "checkers land in the parent slice"
  integration_tests: true
  e2e_tests: true')" || return 1
  { t_impl 1; t_integration 2; t_e2e 3; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" "contract_first"
}

@test "spec_validate_contract_task_while_disabled_fails: contract_first false but a contract task exists" {
  dir="$(mkspec demo 'layers:
  contract_first: false
  contract_first_reason: "checkers land in the parent slice"
  integration_tests: true
  e2e_tests: true')" || return 1
  { t_contract 1; t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "contract"
}

# ── C4: the layer matrix ─────────────────────────────────────────────────────

@test "spec_validate_e2e_before_integration_fails: e2e ahead of integration when both are on" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1; t_impl 2; t_e2e 3; t_integration 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "e2e"
}

@test "spec_validate_e2e_without_integration_ok: integration off, e2e straight after implementation" {
  dir="$(mkspec demo 'layers:
  contract_first: true
  integration_tests: false
  integration_tests_reason: "no component seam in this slice"
  e2e_tests: true')" || return 1
  { t_contract 1; t_impl 2; t_e2e 3; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" "integration_tests"
}

@test "spec_validate_integration_before_impl_fails: a layer task ahead of implementation" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1; t_integration 2; t_impl 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "integration"
}

@test "spec_validate_missing_integration_task_fails: integration on but no such task" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1; t_impl 2; t_e2e 3; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "integration"
}

@test "spec_validate_two_integration_tasks_fail: the matrix demands exactly one per layer" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1; t_impl 2; t_integration 3; t_integration 4; t_e2e 5; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "exactly one required"
}

@test "spec_validate_unknown_layer_value_fails: a Layer field outside the closed set" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1; t_impl 2; t_integration 3; t_e2e 4
    t_task 5 "smoke tests" smoke "REQ-001" qa " "; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "smoke"
}

# ── R3-001: legacy short-circuit ─────────────────────────────────────────────

@test "spec_validate_legacy_spec_without_layers_ok: no block, Layer tasks in any order, still valid" {
  # Deliberately the shape the gates would reject: the contract task sits LAST
  # and e2e precedes integration. A legacy spec is grandfathered whole.
  dir="$(mkspec legacy "")" || return 1
  { t_impl 1; t_e2e 2; t_integration 3; t_contract 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" "layers=legacy"
}

@test "spec_validate_s8_own_spec_stays_legacy: this slice's own spec gains no layer violation" {
  # The regression R3-001 was written for. The spec is COPIED into the private
  # work dir first: the checkout is shared with other sessions, and an
  # assertion that reads a file three agents may be editing proves nothing
  # about this gate.
  src="$REPO_ROOT/.memory-bank/specs/svp-contract-test-loop"
  dir="$SPECS/svp-contract-test-loop"
  mkdir -p "$dir"
  cp "$src/requirements.md" "$src/design.md" "$src/tasks.md" "$dir/"
  run bash "$VALIDATE" "$dir"
  assert_substring "$output" "layers=legacy"
  # Its own violations (CPR-D, seams) are pre-existing and not this gate's
  # business; what must hold is that NO violation mentions a layer.
  bash "$VALIDATE" --json "$dir" >"$WORK/viol.json" 2>/dev/null || true
  # writelines, not print(join(...)): an empty join still prints a newline, so
  # the file would never be empty and the assertion below could never pass.
  python3 -c "
import json, sys
v = json.load(open(sys.argv[1]))['violations']
sys.stdout.writelines(x + '\n' for x in v if 'layer' in x.lower())
" "$WORK/viol.json" >"$WORK/layer-violations.txt"
  [ ! -s "$WORK/layer-violations.txt" ] || {
    echo "layer violations on a legacy spec:"; cat "$WORK/layer-violations.txt"; false
  }
}

@test "spec_validate_json_mode_keeps_stderr_empty: the report never leaks into the machine channel" {
  # --json has a standing contract that stderr stays EMPTY, because a machine
  # caller reads that stream as the error channel. Writing the layer report
  # there turned a clean validation into an apparent failure for every legacy
  # spec — caught by tests/pytest/test_mb_spec_validate.py, locked down here.
  dir="$(mkspec legacy "")" || return 1
  { t_impl 1; t_e2e 2; t_integration 3; t_contract 4; } >>"$dir/tasks.md"
  bash "$VALIDATE" --json "$dir" >"$WORK/out.json" 2>"$WORK/err.txt"
  [ ! -s "$WORK/err.txt" ] || { echo "stderr leaked:"; cat "$WORK/err.txt"; false; }
  assert_grep -q '"violations"' "$WORK/out.json"
}

# ── the short-circuit must not swallow a broken block ────────────────────────

@test "spec_validate_layers_block_in_design_is_not_legacy: a misplaced block is a violation" {
  # The failure mode the legacy rule invites: `read_spec_layers` REFUSES this
  # spec, and a resolver error read as "no block → legacy" would delete every
  # gate exactly when the block is broken.
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1; t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  printf -- '---\nlayers:\n  contract_first: false\n---\n%s' "$(cat "$dir/design.md")" >"$dir/design.md.new"
  mv "$dir/design.md.new" "$dir/design.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "noncanonical_owner"
  refute_substring "$output" "layers=legacy"
}

@test "spec_validate_layers_false_without_reason_fails: an unexplained refusal is a violation" {
  dir="$(mkspec demo 'layers:
  contract_first: true
  integration_tests: false
  e2e_tests: true')" || return 1
  { t_contract 1; t_impl 2; t_e2e 3; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "missing_reason"
}

# ── C3a: the Contract-checkers registry ──────────────────────────────────────

REGISTRY='
```json Contract-checkers
{"checkers": [
  {"id": "persist_gate",
   "covers": ["REQ-001", "REQ-002"],
   "path": "tests/checkers/persist_gate.sh",
   "argv": ["bash", "tests/checkers/persist_gate.sh"],
   "evidence": "tmp/contract-gate/demo/persist_gate.{phase}.json",
   "output_ere": "persist_gate: FAIL"}
]}
```'

# mkreg <checkbox> <registry-body> — a spec whose contract task carries a
# registry and whose checkbox state decides whether the schema is checked.
mkreg() {
  local dir
  dir="$(mkspec demo "$ALL_ON")"
  { t_contract 1 "$1" "$2"; t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  printf '%s\n' "$dir"
}

@test "spec_validate_registry_valid_when_closed_ok: a conforming registry passes" {
  dir="$(mkreg x "$REGISTRY")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "spec_validate_registry_schema_checked_when_closed: evidence outside tmp/contract-gate/<topic>/" {
  dir="$(mkreg x "${REGISTRY/tmp\/contract-gate\/demo\//tmp\/elsewhere\/}")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "evidence"
}

@test "spec_validate_registry_unknown_key_fails: a key outside the closed schema" {
  dir="$(mkreg x "${REGISTRY/\"path\":/\"pathx\": \"x\", \"path\":}")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "pathx"
}

@test "spec_validate_registry_absolute_evidence_fails: an absolute path escapes the bank" {
  dir="$(mkreg x "${REGISTRY/tmp\/contract-gate\/demo\//\/tmp\/contract-gate\/demo\/}")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  # The DIAGNOSIS is asserted, not merely the refusal: an absolute path also
  # trips the prefix rule, so "it was rejected" would hold with the
  # bank-relative check deleted (mutation M14 survived on exactly that).
  assert_substring "$output" "bank-relative"
}

@test "spec_validate_registry_dotdot_evidence_fails: a traversal out of the topic directory" {
  dir="$(mkreg x "${REGISTRY/demo\/persist_gate/demo\/..\/persist_gate}")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "escape"
}

@test "spec_validate_registry_bad_ere_fails: an output_ere grep -E refuses" {
  dir="$(mkreg x "${REGISTRY/persist_gate: FAIL/persist_gate: [FAIL}")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "output_ere"
}

@test "spec_validate_registry_empty_argv_fails: argv must be a non-empty array of strings" {
  dir="$(mkreg x "${REGISTRY/\[\"bash\", \"tests\/checkers\/persist_gate.sh\"\]/[]}")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "argv"
}

@test "spec_validate_registry_uncovered_gated_req_fails: every gated REQ needs a checker" {
  dir="$(mkreg x "${REGISTRY/\[\"REQ-001\", \"REQ-002\"\]/[\"REQ-001\"]}")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "REQ-002"
}

@test "spec_validate_registry_missing_when_closed_fails: a closed contract task with no registry" {
  dir="$(mkreg x "")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "Contract-checkers"
}

@test "spec_validate_registry_not_demanded_while_open: an open contract task owes no registry" {
  dir="$(mkreg " " "")" || return 1
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "spec_validate_registry_ignored_on_legacy_spec: a malformed registry in a legacy spec is not read" {
  dir="$(mkspec legacy "")" || return 1
  { t_contract 1 x '
```json Contract-checkers
{"checkers": [{"nonsense": 1}]}
```'; t_impl 2; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  assert_substring "$output" "layers=legacy"
}

@test "spec_validate_registry_coverage_checked_while_open: a present registry is validated in full" {
  # The registry is written by the orchestrator after Dispatch A, while the
  # contract task is still OPEN — and Dispatch B, the red gate and every
  # business dispatch happen in that state. Gating coverage on closure meant
  # "every gated REQ has a checker" was first enforced after the work it was
  # supposed to govern. Absence stays excused while open; a registry that
  # EXISTS must be complete.
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1 " " "${REGISTRY/\[\"REQ-001\", \"REQ-002\"\]/[\"REQ-001\"]}"
    t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "REQ-002"
}

@test "spec_validate_open_task_without_registry_still_excused: absence is not incompleteness" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1 " " ""; t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "spec_validate_disabled_layer_task_present_fails: a recorded 'off' and a task are a contradiction" {
  # Symmetry with contract_first, which already refuses this. A spec that
  # records "no e2e, because <reason>" and then carries an e2e task states two
  # incompatible things, and a reader cannot tell which one is current.
  dir="$(mkspec demo 'layers:
  contract_first: true
  integration_tests: true
  e2e_tests: false
  e2e_tests_reason: "no external surface in this slice"')" || return 1
  { t_contract 1; t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "e2e_tests is off"
}

@test "spec_validate_closed_contract_task_names_its_checker_tests: step 4 must be readable" {
  # `commands/work.md` says "Once the checker unit tests are green" — prose no
  # code reads. Step 2 of the contract task demands unit tests proving each
  # checker REJECTS and ACCEPTS, and nothing anywhere observed whether they
  # exist. On closure the implementer knows the command, so the DoD has to
  # name it; an unnamed green is a self-report.
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_task 1 "contract checkers" contract "REQ-001, REQ-002" backend x "$REGISTRY" 'the work is done.'
    t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  assert_substring "$output" "checker unit tests"
}

@test "spec_validate_closed_contract_task_with_named_tests_ok: naming the command satisfies it" {
  dir="$(mkspec demo "$ALL_ON")" || return 1
  { t_contract 1 x "$REGISTRY"; t_impl 2; t_integration 3; t_e2e 4; } >>"$dir/tasks.md"
  run bash "$VALIDATE" "$dir"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
