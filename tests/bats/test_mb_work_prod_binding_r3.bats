#!/usr/bin/env bats
# test_mb_work_prod_binding_r3.bats — svp-sdd-core round-3 review fixes, split out of
# test_mb_work_prod_binding.bats to keep every zone file within the 400-line
# contract (the same reason -lib/-eval and _r2 suites exist).
#
# Kept as a SEPARATE suite rather than trimmed: these are the regression tests
# for run-id threading under MB_WORK_PARALLEL, and deleting coverage to fit a line
# limit would be the wrong trade.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  WS="$REPO_ROOT/scripts/mb-work-state.sh"
  PLAN="$REPO_ROOT/scripts/mb-work-plan.sh"
  export LC_ALL=C
  TMP="$(mktemp -d)"
  BANK="$TMP/.memory-bank"
  mkdir -p "$BANK"
  TOPIC="binding-demo"
  GATE="$TMP/gate.sh"
  DECLARED="bash $GATE"
  _spec_with_eval "$TOPIC" 1 "$DECLARED"
}

teardown() {
  rm -rf "$TMP"
}

# A minimal but REAL v2 spec triple: mb-work-plan.sh parses tasks.md through
# mb_work_items.py, so the fixture must satisfy that parser, not a stub.
_spec_with_eval() {
  local topic="$1" no="$2" cmd="$3"
  local dir="$BANK/specs/$topic"
  mkdir -p "$dir"
  cat >"$dir/tasks.md" <<TASKS
# Tasks: $topic

<!-- mb-task:$no -->
## Task $no: the gate

**Covers:** REQ-001
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/**
**Budget:** 100000

**What to do:**
- wire the gate

**Eval:** \`$cmd\` — red: not implemented; exit: 1; output~: \`GATE-RED\`

**DoD:**
- [ ] gate wired
TASKS
}

# The product under test: red until the marker file exists, green after.
_write_gate() {
  cat >"$GATE" <<GATESH
#!/usr/bin/env bash
if [ -f "$TMP/impl" ]; then echo GATE-GREEN; exit 0; fi
echo GATE-RED
exit 1
GATESH
}

_cmd_file() {
  printf '%s\n' "$DECLARED" > "$TMP/cmd.sh"
  printf '%s' "$TMP/cmd.sh"
}

# ── [9] the plan → init → eval binding must resolve end to end ──────────────

# ═══ r3 [8]: MB_WORK_PARALLEL loses the run_id at completion ═══════════════
#
# Under MB_WORK_PARALLEL the state lives in a per-run slot
# <bank>/.work-state/<run_id>.json, but the documented `done` / `flip` / `clear`
# blocks omit `--run-id`, so they read the singleton and fail with exit 2
# ("no active work-state") — the run can be started but never completed through
# the documented sequence.

_wmd() { printf '%s' "$REPO_ROOT/commands/work.md"; }

@test "prod_binding: the documented parallel done carries --run-id" {
  # Behavioural half: a per-run init followed by a singleton `done` fails.
  export MB_WORK_PARALLEL=1
  local rid; rid="$(bash "$WS" new-run-id)"
  bash "$WS" init spec 1 --run-id "$rid" --source-topic "$TOPIC" --mb "$BANK" >/dev/null
  [ -f "$BANK/.work-state/$rid.json" ] || { echo "per-run slot not created"; false; }

  run bash "$WS" done --mb "$BANK"
  [ "$status" -ne 0 ] || { echo "singleton done succeeded under MB_WORK_PARALLEL"; false; }

  run bash "$WS" done --run-id "$rid" --mb "$BANK"
  [ "$status" -ne 2 ] || { echo "run-id done still could not find the state: $output"; false; }
  unset MB_WORK_PARALLEL
}

@test "prod_binding: work.md threads --run-id through done" {
  # Contract half: the documented block must carry it, else the loop above is
  # unreachable through the documented sequence.
  local md; md="$(_wmd)"
  grep -Eq 'mb-work-state\.sh done \$\{RUN_ID:\+--run-id' "$md" \
    || { echo "work.md 'done' block does not thread --run-id"; false; }
}

@test "prod_binding: work.md threads --run-id through the checkbox flip" {
  grep -Eq 'mb-work-checkbox\.sh flip <source> <item_no> \$\{RUN_ID:\+--run-id' "$(_wmd)" \
    || { echo "work.md 'flip' block does not thread --run-id"; false; }
}

@test "prod_binding: work.md threads --run-id through the final clears" {
  # Both clears live on ONE line, so `... clear .*run-id` matched the OTHER
  # command's flag and stayed green with this one's removed. The flag must
  # follow its own command IMMEDIATELY.
  local md; md="$(_wmd)"
  grep -Eq 'mb-work-state\.sh clear \$\{RUN_ID:\+--run-id' "$md" \
    || { echo "work.md 'state clear' does not thread --run-id"; false; }
  grep -Eq 'mb-work-budget\.sh clear \$\{RUN_ID:\+--run-id' "$md" \
    || { echo "work.md 'budget clear' does not thread --run-id"; false; }
}

@test "prod_binding: the threaded form is a no-op for a single run" {
  # The single-run default must stay byte-identical in behaviour: the documented
  # form has to degrade to no flag at all when RUN_ID is unset.
  grep -Eq '\$\{RUN_ID:\+--run-id "\$RUN_ID"\}' "$(_wmd)" \
    || { echo "work.md does not use the unset-safe \${RUN_ID:+...} form"; false; }
}
