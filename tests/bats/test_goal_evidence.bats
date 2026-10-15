#!/usr/bin/env bats
# goal_evidence: — drive-autopilot Task 1 (design C1, C5). Linked acceptance criteria
# are met only from evidence (closed plans + passing checks); hand ticks without it
# are reported as unbacked; --tick / --ticks-only; unlinked goals keep today's bytes.
# Name convention: every @test starts with `goal_evidence: ` (Eval red anchor).

load 'lib/discuss_contract'

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-goal-acceptance.sh"
  command -v jq >/dev/null || skip "jq required"
  PROJECT="$(mktemp -d)"
  BANK="$PROJECT/.memory-bank"
  mkdir -p "$BANK/plans/done" "$BANK/specs/demo"
  GOAL="$BANK/goal.md"
  GOAL_MD="$REPO_ROOT/commands/goal.md"
  MB_DISCUSS_CLAUSES=()
  MB_DISCUSS_CLAUSES+=("goal-plan|mb_section|Evidence links|.plan: <bank-relative path>. is closed only when every work item it resolves to is done|plan:|s/only when every work item/when any work item/|REQ-023")
  MB_DISCUSS_CLAUSES+=("goal-check|mb_section|Evidence links|.check: <command>. runs from the project root only after every linked plan of the criterion is closed|check:|s/only after every linked plan/before any linked plan/|REQ-023")
  MB_DISCUSS_CLAUSES+=("goal-unbacked|mb_section|Evidence links|a hand tick .\\[x\\]. without that evidence does not count and is listed under .unbacked.|unbacked|s/does not count and is listed/counts and is listed/|REQ-024")
  MB_DISCUSS_CLAUSES+=("goal-second|mb_section|Several drives in one bank|each drive owns its own goal file and passes it as the first argument of .mb-goal-acceptance.sh.|mb-goal-acceptance|s/owns its own goal file/shares the bank goal.md/|REQ-042")
  MB_DISCUSS_CLAUSES+=("goal-fence-skill|mb_section|Usage|SKILL_DIR=\"\\\$\\{MB_SKILLS_ROOT:-\\\$\\{SKILL_DIR:-\\\$HOME/.claude/skills/memory-bank\\}\\}\"|SKILL_DIR=|s/MB_SKILLS_ROOT:-//|REQ-046")
  MB_DISCUSS_CLAUSES+=("goal-fence-bank|mb_section|Usage|BANK=\"\\\$\\(mb_resolve_path |BANK=|s/mb_resolve_path /echo /|REQ-046")
}

teardown() { [ -n "${PROJECT:-}" ] && rm -rf "$PROJECT"; }

json_of() { printf '%s\n' "$1" | grep '^{' | tail -n1; }

# _plan <rel-path> <x-or-space>... — a plan with one stage per DoD state.
_plan() {
  local path="$BANK/$1" n=0 s; shift
  : > "$path"
  for s in "$@"; do
    n=$((n + 1))
    printf '<!-- mb-stage:%d -->\n### Stage %d: s%d\n\n**DoD:**\n- [%s] item\n\n' "$n" "$n" "$n" "$s" >> "$path"
  done
}

# _goal <criterion-block> — goal file with the given acceptance section body.
_goal() {
  printf -- '---\nid: g1\n---\n# Goal\n\n## Acceptance criteria\n\n%s\n' "$1" > "${2:-$GOAL}"
}

_accept() { run bash "$RUN" "${1:-$GOAL}" "$BANK" "${@:2}"; [ "$status" -eq 0 ]; J="$(json_of "$output")"; }

@test "goal_evidence: plan with a pending item is unmet" {
  _plan plans/p.md x " "
  _goal $'- [ ] pays\n  - plan: plans/p.md'
  _accept
  echo "$J" | jq -e '.ok == false and .criteria[0].met == false and .criteria[0].plans[0].closed == false'
  echo "$J" | jq -e '.findings[0] | test("pays")'
}

@test "goal_evidence: plan with all items done is met" {
  _plan plans/p.md x x
  _goal $'- [ ] pays\n  - plan: plans/p.md'
  _accept
  echo "$J" | jq -e '.ok == true and .criteria[0].met == true and (.findings | length == 0)'
}

@test "goal_evidence: wrapper over a spec with one undone task in range is unmet" {
  printf '<!-- mb-task:%d -->\n## Task %d: t\n\n**DoD:**\n- [%s] d\n\n' 1 1 x 2 2 " " 3 3 " " > "$BANK/specs/demo/tasks.md"
  printf -- '---\nlinked_spec: specs/demo\ntasks: 1-2\n---\n# W\n' > "$BANK/plans/w.md"
  printf -- '---\nlinked_spec: specs/demo\ntasks: 1\n---\n# W1\n' > "$BANK/plans/w1.md"
  _goal $'- [ ] wrapped\n  - plan: plans/w.md\n- [ ] first only\n  - plan: plans/w1.md'
  _accept
  echo "$J" | jq -e '.criteria[0].met == false and .criteria[1].met == true and .ok == false'
}

@test "goal_evidence: a plan moved to plans/done is found by basename" {
  _plan plans/done/p.md x
  _goal $'- [ ] pays\n  - plan: plans/p.md'
  _accept
  echo "$J" | jq -e '.ok == true and .criteria[0].plans[0].closed == true'
}

@test "goal_evidence: check true meets, check false does not" {
  _plan plans/p.md x
  _goal $'- [ ] ok check\n  - plan: plans/p.md\n  - check: true\n- [ ] bad check\n  - check: false'
  _accept
  echo "$J" | jq -e '.criteria[0].met == true and .criteria[0].checks[0].exit == 0'
  echo "$J" | jq -e '.criteria[1].met == false and .criteria[1].checks[0].exit == 1 and .ok == false'
}

@test "goal_evidence: checks do not run while a linked plan is open" {
  _plan plans/p.md " "
  _goal $'- [ ] gated\n  - plan: plans/p.md\n  - check: touch ran.marker'
  _accept
  [ ! -e "$PROJECT/ran.marker" ]
  echo "$J" | jq -e '.criteria[0].met == false'
  _plan plans/p.md x
  _accept
  [ -e "$PROJECT/ran.marker" ]
  echo "$J" | jq -e '.criteria[0].met == true'
}

@test "goal_evidence: a hand-ticked unmet criterion is listed under unbacked" {
  _plan plans/p.md " "
  _goal $'- [x] claimed\n  - plan: plans/p.md\n- [x] unlinked tick'
  _accept
  echo "$J" | jq -e '.ok == false and (.unbacked | length == 2) and (.unbacked[0] | test("claimed"))'
  echo "$J" | jq -e '.findings | map(select(test("no evidence link"))) | length == 1'
}

@test "goal_evidence: --tick sets boxes to evidence on a goal file outside the bank goal.md" {
  _plan plans/p.md x
  _plan plans/q.md " "
  local other="$PROJECT/other-goal.md"
  _goal $'- [ ] met one\n  - plan: plans/p.md\n- [x] unmet one\n  - plan: plans/q.md' "$other"
  _accept "$other" --tick
  grep -qx -- '- \[x\] met one' "$other"
  grep -qx -- '- \[ \] unmet one' "$other"
  grep -qx -- '  - plan: plans/q.md' "$other"
  [ ! -e "$GOAL" ]
  echo "$J" | jq -e '.unbacked == ["unmet one"]'
}

@test "goal_evidence: default mode writes nothing" {
  _plan plans/p.md x
  _goal $'- [ ] met one\n  - plan: plans/p.md'
  local before; before="$(cat "$GOAL")"
  _accept
  [ "$(cat "$GOAL")" = "$before" ]
}

@test "goal_evidence: --ticks-only counts boxes and runs no check" {
  _goal $'- [x] ticked\n  - check: touch ran.marker'
  _accept "$GOAL" --ticks-only
  [ ! -e "$PROJECT/ran.marker" ]
  [ "$J" = '{"name":"acceptance","ok":true,"findings":[]}' ]
}

@test "goal_evidence: a malformed link is a finding, not a crash" {
  _goal $'- [ ] broken\n  - plan:'
  _accept
  echo "$J" | jq -e '.ok == false and (.findings[0] | test("malformed"))'
}

@test "goal_evidence: a goal without links keeps byte-identical output" {
  _goal $'- [x] first done\n- [ ] second not done'
  run bash "$RUN" "$GOAL" "$BANK" 2>/dev/null
  [ "$output" = '{"name":"acceptance","ok":false,"findings":["second not done"]}' ]
  _goal $'- [x] first done\n- [x] second done'
  run bash "$RUN" "$GOAL" "$BANK" 2>/dev/null
  [ "$output" = '{"name":"acceptance","ok":true,"findings":[]}' ]
  _goal $'- [x] real\n```markdown\n- [ ] fenced\n  - plan: plans/none.md\n```'
  run bash "$RUN" "$GOAL" "$BANK" 2>/dev/null
  [ "$output" = '{"name":"acceptance","ok":true,"findings":[]}' ]
  run bash -c 'bash "$1" "$2" "$3" 2>/dev/null' _ "$RUN" "$BANK/missing.md" "$BANK"
  [ "$output" = '{"name":"acceptance","ok":null,"findings":[]}' ]
}

# ── prompt clauses ──
_pair() {
  run assert_clause "$1" "$2"; [ "$status" -eq 0 ]
  run assert_clause_load_bearing "$1" "$2"; [ "$status" -eq 0 ]
}

@test "goal_evidence: goal.md states the link grammar" {
  _pair "$GOAL_MD" goal-plan
  _pair "$GOAL_MD" goal-check
  _pair "$GOAL_MD" goal-unbacked
}

@test "goal_evidence: goal.md covers a second goal file" {
  _pair "$GOAL_MD" goal-second
}

@test "goal_evidence: goal.md resolves bundle and bank through the fence" {
  _pair "$GOAL_MD" goal-fence-skill
  _pair "$GOAL_MD" goal-fence-bank
  run grep -cF -e "\$(dirname \"\$0\")" -e 'BANK=".memory-bank"' "$GOAL_MD"
  [ "$output" = 0 ]
}

@test "goal_evidence: the goal template carries one linked example criterion" {
  [ "$(grep -cE '^ +- plan: plans/' "$REPO_ROOT/templates/goal.md")" -eq 1 ]
}

@test "goal_evidence: --tick keeps the goal file's mode" {
  _plan plans/p.md x
  _goal $'- [ ] met one\n  - plan: plans/p.md'
  chmod 0644 "$GOAL"
  _accept "$GOAL" --tick
  grep -qx -- '- \[x\] met one' "$GOAL"
  [ "$(stat -f %Lp "$GOAL" 2>/dev/null || stat -c %a "$GOAL")" = 644 ]
}
