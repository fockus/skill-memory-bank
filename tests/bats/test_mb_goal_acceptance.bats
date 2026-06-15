#!/usr/bin/env bats
# Tests for scripts/mb-goal-acceptance.sh — the L5 goal-acceptance aggregator.
#
# Contract (REQ-DF-042, ADR-3):
#   - emits a JSON object {"name":"acceptance","ok":true|false|null,"findings":[...]}
#   - ALWAYS exits 0 — pass/fail/skip is carried ONLY by the `ok` field.
#   - ok=true   only when N>=1 acceptance items AND all are [x].
#   - ok=false  when >=1 unchecked item remains (findings list them).
#   - ok=null   when goal.md is missing OR has zero acceptance criteria.
#   - code-fence-aware: checkbox lines inside ``` / ~~~ fences are ignored,
#     exactly like scripts/mb-goal-validate.sh's acceptance_item_count.
#
# Fixtures pass "$BANK" as the second arg so mb_resolve_path uses the isolated
# temp bank, never the real repo bank.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-goal-acceptance.sh"
  command -v jq >/dev/null || skip "jq required"
  BANK="$(mktemp -d)/.memory-bank"
  mkdir -p "$BANK"
  GOAL="$BANK/goal.md"
}

teardown() {
  [ -n "${BANK:-}" ] && rm -rf "$(dirname "$BANK")"
}

# Extract the single JSON line from combined stdout+stderr.
json_of() {
  printf '%s\n' "$1" | grep '^{' | tail -n1
}

@test "acceptance: script exists" {
  [ -f "$RUN" ]
}

@test "acceptance: --help exits 0 and mentions goal" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"goal"* ]]
}

# ---- PASS case --------------------------------------------------------------

@test "acceptance: all items checked → ok=true, exit 0, no findings" {
  cat >"$GOAL" <<'EOF'
---
id: g1
---
# Goal
## Acceptance criteria
- [x] first done
- [x] second done
EOF
  run bash "$RUN" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.name == "acceptance"'
  echo "$j" | jq -e '.ok == true'
  echo "$j" | jq -e '.findings | length == 0'
}

# ---- FAIL case --------------------------------------------------------------

@test "acceptance: an unchecked item → ok=false, exit 0, finding lists it" {
  cat >"$GOAL" <<'EOF'
---
id: g1
---
# Goal
## Acceptance criteria
- [x] first done
- [ ] second not done
EOF
  run bash "$RUN" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  echo "$j" | jq -e '.ok == false'
  echo "$j" | jq -e '.findings | length == 1'
  echo "$j" | jq -e '.findings[0] | test("second not done")'
}

@test "acceptance: FAIL case STILL exits 0 (ADR-3 — no fail-loud in runner)" {
  cat >"$GOAL" <<'EOF'
---
id: g1
---
# Goal
## Acceptance criteria
- [ ] not done
EOF
  run bash "$RUN" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == false'
}

# ---- NULL / skip case -------------------------------------------------------

@test "acceptance: no goal.md → ok=null, exit 0" {
  run bash "$RUN" "$BANK/nonexistent-goal.md" "$BANK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == null'
}

@test "acceptance: goal with zero criteria → ok=null, exit 0" {
  cat >"$GOAL" <<'EOF'
---
id: g1
---
# Goal
## Description
No acceptance section here.
EOF
  run bash "$RUN" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == null'
}

# ---- code-fence awareness (parity with mb-goal-validate.sh) -----------------

@test "acceptance: checkboxes inside a code fence are ignored" {
  cat >"$GOAL" <<'EOF'
---
id: g1
---
# Goal
## Acceptance criteria
- [x] real done item
```markdown
- [ ] this is an example inside a fence, not a real criterion
```
EOF
  run bash "$RUN" "$GOAL" "$BANK"
  [ "$status" -eq 0 ]
  local j; j="$(json_of "$output")"
  # Only the one real (outside-fence) item counts; it is checked → ok=true.
  echo "$j" | jq -e '.ok == true'
  echo "$j" | jq -e '.findings | length == 0'
}

@test "acceptance: default goal path resolves via bank when no goal arg given" {
  cat >"$GOAL" <<'EOF'
---
id: g1
---
# Goal
## Acceptance criteria
- [x] done
EOF
  run bash "$RUN" "" "$BANK"
  [ "$status" -eq 0 ]
  echo "$(json_of "$output")" | jq -e '.ok == true'
}
