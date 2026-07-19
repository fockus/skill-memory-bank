#!/usr/bin/env bats
# eval_first: — svp-sdd-core C6 Eval-first врезка in /mb work (REQ-008).
#
# Covers both halves: (1) the mb-work-state.sh eval-red/eval-green helper is the
# sole executor of the Eval command — a materialised red is accepted, a foreign
# failure / already-green command is rejected, and verify demands actual green;
# (2) commands/work.md documents the contract — materialise-before-implement,
# record via the subcommands (no direct JSON edit), foreign failure = FAIL that
# blocks implement, verify calls eval-green, waiver only for non-gated.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WS="$REPO_ROOT/scripts/mb-work-state.sh"
  WORK="$REPO_ROOT/commands/work.md"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK"
  IMPL="$TMP/impl"     # external product marker: absent = red, present = green
  GATE="$TMP/gate.sh"  # the product under test, named by the DECLARED Eval
  DECLARED="bash $GATE"
  # The eval gate is bound to the task's declared Eval (review [2]).
  mkdir -p "$BANK/specs/demo"
  printf '# Tasks: demo\n\n<!-- mb-task:1 -->\n## Task 1: the gate\n\n**Covers:** REQ-001\n**Role:** backend\n**Eval:** %s \xe2\x80\x94 red: gate fails; exit: 1; output~: not ok [0-9]+ foo_gate\n\n**DoD:**\n- [ ] gate works.\n<!-- /mb-task:1 -->\n' "$DECLARED" > "$BANK/specs/demo/tasks.md"
  bash "$WS" init demo 1 --mb "$BANK" >/dev/null
  DOC="$WORK"
}

# The cmd-file always carries exactly the DECLARED command; the GATE varies.
_cmd_file() { printf '#!/usr/bin/env bash\n%s\n' "$DECLARED" > "$1"; }

# eval command whose OUTCOME depends on external product state (not on editing
# the command) — models a real test that fails until the implementation lands.
_flip_cmd() {
  printf '#!/usr/bin/env bash\nif [ -f "%s" ]; then echo "ok 1 foo_gate"; exit 0; else echo "not ok 1 foo_gate"; exit 1; fi\n' "$IMPL" > "$GATE"
  _cmd_file "$1"
}

teardown() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}

# ── helper behaviour ─────────────────────────────────────────────────────────

@test "eval_first: eval_red on a materialised declared red → exit 0" {
  local c="$TMP/cmd.sh"; printf '#!/usr/bin/env bash\necho "not ok 1 foo_gate"\nexit 1\n' > "$GATE"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "eval_first: eval_red rejects a foreign failure (output mismatch) → exit 1" {
  local c="$TMP/cmd.sh"; printf '#!/usr/bin/env bash\necho "boom"\nexit 1\n' > "$GATE"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "eval_first: eval_red rejects an already-green command → exit 1 (fake red)" {
  local c="$TMP/cmd.sh"; printf '#!/usr/bin/env bash\necho "ok 1 foo_gate"\nexit 0\n' > "$GATE"; _cmd_file "$c"
  run bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  [ "$status" -eq 1 ]
}

@test "eval_first: eval_green demands actual green after a proven red → exit 0" {
  # legitimate red→green: red observed first, then the product turns it green
  # (cmd-file byte-identical throughout).
  local c="$TMP/cmd.sh"; _flip_cmd "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK"
  touch "$IMPL"
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 0 ]
}

@test "eval_first: eval_green REFUSES when eval_red never observed a red → exit 2" {
  # load-bearing: a failed/absent red must NOT let green through (contract-first).
  local c="$TMP/cmd.sh"; printf '#!/usr/bin/env bash\necho "ok 1 foo_gate"\nexit 0\n' > "$GATE"; _cmd_file "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --mb "$BANK" || true
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 2 ]
}

@test "eval_first: eval_green FAILs on a still-red command → exit 1" {
  local c="$TMP/cmd.sh"; printf '#!/usr/bin/env bash\necho "not ok 1 foo_gate"\nexit 1\n' > "$GATE"; _cmd_file "$c"
  bash "$WS" eval-red --cmd-file "$c" --output-re 'not ok [0-9]+ foo_gate' --expected-exit 1 --mb "$BANK" || true
  run bash "$WS" eval-green --cmd-file "$c" --mb "$BANK"
  [ "$status" -eq 1 ]
}

# ── commands/work.md contract ────────────────────────────────────────────────

@test "eval_first: work.md documents eval-red materialised before implement" {
  grep -q 'eval-red' "$WORK"
  grep -Eqi 'materiali[sz]e.*before.*implement|before implement.*eval' "$WORK"
}

@test "eval_first: work.md verify step calls eval-green" {
  grep -q 'eval-green' "$WORK"
}

@test "eval_first: work.md forbids direct state-JSON editing (record via subcommand)" {
  grep -Eqi 'direct.*json|do not edit.*json|never edit.*state|json.*forbidden' "$WORK"
}

@test "eval_first: work.md — foreign failure is a FAIL that blocks implement" {
  grep -Eqi 'foreign.*(fail|block)|(fail|block).*implement' "$WORK"
}

@test "eval_first: work.md — waiver only for non-gated" {
  grep -Eqi 'waiver.*non-gated|non-gated.*waiver' "$WORK"
}

@test "eval_first: work.md applies eval-first to ANY task carrying an Eval, not only gated ones (review [3])" {
  # REQ-008 (verbatim): "When /mb work starts a task carrying an Eval
  # declaration, the system shall materialize the eval into executable code
  # first, observe it fail before implementation and pass after." The trigger is
  # the DECLARATION, not gatedness — a non-gated docs task with a real
  # structural Eval must run the same red->green gate.
  run grep -n "For a gated task, \*\*materialise the eval code" "$DOC"
  [ "$status" -ne 0 ]
  grep -q "carrying an Eval declaration" "$DOC"
}
