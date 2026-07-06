#!/usr/bin/env bats
# Tests for scripts/mb-drive.sh — the drive-loop stateless decision function
# (drive-loop design.md §"The decision function"; Task 1 —
# REQ-DR-002/010/011/012/013/014/020/021).
#
# Contract under test — decision table (first match wins; ORDER IS THE
# SAFETY CONTRACT):
#   1. gate==2                                           -> stop_human check-broke:<name>
#   2. bud==exceeded                                      -> stop_budget
#   3. done_pct==100 AND gate==0                           -> stop_success
#   4. cyc_exhausted OR (stall AND last_pivot==architect)  -> stop_human max-cycle|stall
#   5. gate==1 AND pivot_mode != refine                    -> pivot <mode> <item>
#   6. gate==1                                             -> repair <item>
#   7. done_pct<100                                        -> implement <route> <item>
#
# Signal-injection mechanism (the ONE chosen seam, documented in the script
# header): `mb-drive.sh decide --gate ... --done-pct ...` calls the exact same
# pure core (`mbd_decide`) that `next` uses, with explicit values — no bank,
# no live goal.md/firewall required. This file drives the core directly
# through `decide` for the decision-table + ordering + negative-safety
# matrix, then exercises `next`'s real-signal wiring (incl. the fail-closed
# default) with a real isolated bank + a tiny stub script.

bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="$REPO_ROOT/scripts/mb-drive.sh"
  BANK="$BATS_TEST_TMPDIR/bank"
  mkdir -p "$BANK"
}

decide() {
  run bash "$RUN" decide "$@"
}

# ---- basics -----------------------------------------------------------------

@test "mb-drive.sh: script exists and is executable" {
  [ -f "$RUN" ]
  [ -x "$RUN" ]
}

@test "--help exits 0 and documents next/status/decide" {
  run bash "$RUN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"next"* ]]
  [[ "$output" == *"status"* ]]
  [[ "$output" == *"decide"* ]]
}

@test "unknown subcommand -> usage error, exit 2" {
  run bash "$RUN" bogus
  [ "$status" -eq 2 ]
}

@test "no subcommand -> usage error, exit 2" {
  run bash "$RUN"
  [ "$status" -eq 2 ]
}

@test "decide: missing --gate/--done-pct -> usage error, exit 2" {
  decide
  [ "$status" -eq 2 ]
}

@test "decide: --gate out of {0,1,2} -> usage error, exit 2" {
  decide --gate 3 --done-pct 0
  [ "$status" -eq 2 ]
}

@test "decide: --done-pct out of 0..100 -> usage error, exit 2" {
  decide --gate 0 --done-pct 101
  [ "$status" -eq 2 ]
}

# ---- one case per decision-table rule ---------------------------------------

@test "rule 1: gate==2 -> stop_human check-broke:<name>" {
  decide --gate 2 --done-pct 40 --broken-check tests
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:tests" ]
}

@test "rule 1: gate==2 with no --broken-check -> names 'unknown'" {
  decide --gate 2 --done-pct 40
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:unknown" ]
}

@test "rule 2: bud==exceeded -> stop_budget" {
  decide --gate 0 --done-pct 40 --bud exceeded
  [ "$status" -eq 0 ]
  [ "$output" = "stop_budget" ]
}

@test "rule 3: done_pct==100 AND gate==0 -> stop_success" {
  decide --gate 0 --done-pct 100
  [ "$status" -eq 0 ]
  [ "$output" = "stop_success" ]
}

@test "rule 4: cyc_exhausted -> stop_human max-cycle" {
  decide --gate 1 --done-pct 40 --cyc-exhausted 1
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human max-cycle" ]
}

@test "rule 4: stall AND last_pivot==via_architect -> stop_human stall" {
  decide --gate 1 --done-pct 40 --stall 1 --last-pivot via_architect
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human stall" ]
}

@test "rule 4: stall WITHOUT last_pivot==via_architect does NOT stop (falls through)" {
  decide --gate 1 --done-pct 40 --stall 1 --last-pivot in_role --current-item item-x
  [ "$status" -eq 0 ]
  [ "$output" = "repair item-x" ]
}

@test "rule 5: gate==1 AND pivot_mode==pivot_in_role -> pivot in_role <item>" {
  decide --gate 1 --done-pct 40 --pivot-mode pivot_in_role --current-item item-x
  [ "$status" -eq 0 ]
  [ "$output" = "pivot in_role item-x" ]
}

@test "rule 5: gate==1 AND pivot_mode==pivot_via_architect -> pivot via_architect <item>" {
  decide --gate 1 --done-pct 40 --pivot-mode pivot_via_architect --current-item item-x
  [ "$status" -eq 0 ]
  [ "$output" = "pivot via_architect item-x" ]
}

@test "rule 6: gate==1 AND pivot_mode==refine -> repair <item>" {
  decide --gate 1 --done-pct 40 --pivot-mode refine --current-item item-x
  [ "$status" -eq 0 ]
  [ "$output" = "repair item-x" ]
}

@test "rule 7: done_pct<100 AND gate==0 -> implement <route> <item>" {
  decide --gate 0 --done-pct 40 --route bugfix --next-item item-y
  [ "$status" -eq 0 ]
  [ "$output" = "implement bugfix item-y" ]
}

# ---- ordering: stops beat progress ------------------------------------------

@test "ordering: gate==2 beats implement (done_pct<100 still stops)" {
  decide --gate 2 --done-pct 10 --broken-check lint --next-item item-y
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:lint" ]
}

@test "ordering: bud==exceeded beats implement (done_pct<100 still stops)" {
  decide --gate 0 --done-pct 10 --bud exceeded --next-item item-y
  [ "$status" -eq 0 ]
  [ "$output" = "stop_budget" ]
}

@test "ordering: gate==2 beats stop_budget (rule 1 before rule 2)" {
  decide --gate 2 --done-pct 10 --bud exceeded --broken-check tests
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:tests" ]
}

@test "ordering: bud==exceeded beats stop_success (rule 2 before rule 3, per design order)" {
  decide --gate 0 --done-pct 100 --bud exceeded
  [ "$status" -eq 0 ]
  [ "$output" = "stop_budget" ]
}

@test "ordering: cyc_exhausted beats repair (rule 4 before rule 6)" {
  decide --gate 1 --done-pct 10 --cyc-exhausted 1 --current-item item-x
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human max-cycle" ]
}

@test "ordering: pivot beats repair (rule 5 before rule 6, same gate==1 + item)" {
  decide --gate 1 --done-pct 10 --pivot-mode pivot_in_role --current-item item-x
  [ "$status" -eq 0 ]
  [ "$output" = "pivot in_role item-x" ]
}

# ---- negative safety (REQ-DR-014): no self-certified success ----------------

@test "negative safety: done_pct==100 WITH a red firewall (gate==1) NEVER yields stop_success (repair)" {
  decide --gate 1 --done-pct 100 --pivot-mode refine --current-item item-x
  [ "$status" -eq 0 ]
  [ "$output" != "stop_success" ]
  [ "$output" = "repair item-x" ]
}

@test "negative safety: done_pct==100 WITH a red firewall (gate==1) and a stagnant pivot still never stop_success (pivot)" {
  decide --gate 1 --done-pct 100 --pivot-mode pivot_via_architect --current-item item-x
  [ "$status" -eq 0 ]
  [ "$output" != "stop_success" ]
  [ "$output" = "pivot via_architect item-x" ]
}

@test "negative safety: done_pct==100 WITH a broken firewall (gate==2) NEVER yields stop_success" {
  decide --gate 2 --done-pct 100 --broken-check tests
  [ "$status" -eq 0 ]
  [ "$output" != "stop_success" ]
  [ "$output" = "stop_human check-broke:tests" ]
}

# ---- empty-operand guard (fix-cycle 1, #2): no malformed progress line ------

@test "empty-operand guard: implement with an empty --next-item -> check-broke:acceptance, never a malformed implement line" {
  decide --gate 0 --done-pct 40 --route bugfix --next-item ""
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:acceptance" ]
  [[ "$output" != implement* ]]
}

@test "empty-operand guard: implement with an empty --route -> stop_human undecidable, never a malformed implement line" {
  decide --gate 0 --done-pct 40 --route "" --next-item item-y
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human undecidable" ]
  [[ "$output" != implement* ]]
}

@test "empty-operand guard: repair with an empty --current-item -> stop_human undecidable, never a bare 'repair'" {
  decide --gate 1 --done-pct 40 --pivot-mode refine --current-item ""
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human undecidable" ]
  [[ "$output" != repair* ]]
}

@test "empty-operand guard: pivot with an empty --current-item -> stop_human undecidable, never a bare 'pivot'" {
  decide --gate 1 --done-pct 40 --pivot-mode pivot_in_role --current-item ""
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human undecidable" ]
  [[ "$output" != pivot* ]]
}

# ---- `next` real-signal wiring ----------------------------------------------

goal_with_pending_item() {
  cat > "$BANK/goal.md" <<'EOF'
---
id: g1
---
# Goal
## Acceptance criteria
- [ ] ship the thing
EOF
}

fake_bin() {
  # $1=filename $2=exit-code $3=stdout-body -> path to a chmod+x stub script
  local path="$BATS_TEST_TMPDIR/$1"
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$3'
exit $2
EOF
  chmod +x "$path"
  printf '%s' "$path"
}

fake_bin_stderr() {
  # $1=filename $2=exit-code $3=stderr-body -> path to a chmod+x stub script
  # (stdout stays empty, mirroring mb-work-budget.sh check's own contract)
  local path="$BATS_TEST_TMPDIR/$1"
  cat > "$path" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$3' >&2
exit $2
EOF
  chmod +x "$path"
  printf '%s' "$path"
}

fv_pass_stub() {
  # $1=filename -> a mb-flow-verify.sh replacement that always PASSES (gate=0)
  fake_bin "$1" 0 '{"checks":[],"totals":{"blocker":0,"major":0,"minor":0},"gate":"PASS","verdict":"pass"}'
}

@test "next: red acceptance (real scripts, no stub) -> repair" {
  goal_with_pending_item
  run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == repair* ]]
}

@test "next: stubbed all-green firewall + a pending item -> implement <route> <item>" {
  goal_with_pending_item
  local fv; fv=$(fake_bin fv-pass.sh 0 '{"checks":[],"totals":{"blocker":0,"major":0,"minor":0},"gate":"PASS","verdict":"pass"}')
  MB_FLOW_VERIFY_BIN="$fv" run bash "$RUN" next --bank "$BANK" --route bugfix
  [ "$status" -eq 0 ]
  [ "$output" = "implement bugfix ship the thing" ]
}

@test "next: fail-closed when mb-flow-verify.sh exits an unexpected code (127)" {
  goal_with_pending_item
  local fv; fv=$(fake_bin fv-broke.sh 127 '')
  MB_FLOW_VERIFY_BIN="$fv" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:mb-flow-verify" ]
}

@test "next: fail-closed when mb-goal-acceptance.sh emits unparseable output" {
  goal_with_pending_item
  local acc; acc=$(fake_bin acc-broke.sh 0 'not json at all')
  MB_GOAL_ACCEPTANCE_BIN="$acc" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:acceptance" ]
}

@test "next: fail-closed when mb-work-budget.sh check exits an unexpected code" {
  goal_with_pending_item
  local fv bud
  fv=$(fake_bin fv-pass2.sh 0 '{"checks":[],"totals":{"blocker":0,"major":0,"minor":0},"gate":"PASS","verdict":"pass"}')
  bud=$(fake_bin bud-broke.sh 9 '')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_BUDGET_BIN="$bud" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:work-budget" ]
}

# ---- fix-cycle 1 #1 (BLOCKER): acceptance `ok` extraction is type-strict ----
# Only a REAL JSON boolean true/false is a trustworthy done_pct signal. A
# malformed runner ({"ok":"true"} etc.) must check-broke, never coerce into
# the same token as a genuine boolean and reach stop_success (REQ-DR-014).

@test "acceptance type-strict: ok as a JSON STRING \"true\" -> check-broke:acceptance, never stop_success" {
  goal_with_pending_item
  local fv acc
  fv=$(fv_pass_stub fv-pass-str.sh)
  acc=$(fake_bin acc-str-true.sh 0 '{"name":"acceptance","ok":"true","findings":[]}')
  MB_FLOW_VERIFY_BIN="$fv" MB_GOAL_ACCEPTANCE_BIN="$acc" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:acceptance" ]
}

@test "acceptance type-strict: ok as a JSON NUMBER 1 -> check-broke:acceptance, never stop_success" {
  goal_with_pending_item
  local fv acc
  fv=$(fv_pass_stub fv-pass-num.sh)
  acc=$(fake_bin acc-num-one.sh 0 '{"name":"acceptance","ok":1,"findings":[]}')
  MB_FLOW_VERIFY_BIN="$fv" MB_GOAL_ACCEPTANCE_BIN="$acc" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:acceptance" ]
}

@test "acceptance type-strict: ok as JSON null -> check-broke:acceptance, never stop_success" {
  goal_with_pending_item
  local fv acc
  fv=$(fv_pass_stub fv-pass-null.sh)
  acc=$(fake_bin acc-null.sh 0 '{"name":"acceptance","ok":null,"findings":[]}')
  MB_FLOW_VERIFY_BIN="$fv" MB_GOAL_ACCEPTANCE_BIN="$acc" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:acceptance" ]
}

@test "acceptance type-strict: ok key MISSING entirely -> check-broke:acceptance, never stop_success" {
  goal_with_pending_item
  local fv acc
  fv=$(fv_pass_stub fv-pass-missing.sh)
  acc=$(fake_bin acc-missing.sh 0 '{"name":"acceptance","findings":[]}')
  MB_FLOW_VERIFY_BIN="$fv" MB_GOAL_ACCEPTANCE_BIN="$acc" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:acceptance" ]
}

# ---- fix-cycle 1 #3 (MAJOR): work-state cycle/max_cycles fail-closed -------

@test "work-state fail-closed: a present-but-non-numeric cycle -> check-broke:work-state (never masked to cycle=0)" {
  goal_with_pending_item
  local fv ws
  fv=$(fv_pass_stub fv-pass-ws1.sh)
  ws=$(fake_bin ws-corrupt.sh 0 '{"cycle":"banana","max_cycles":2,"heading":"x"}')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_STATE_BIN="$ws" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:work-state" ]
}

@test "work-state fail-closed: legit empty state {} (no active run yet) is NOT broken" {
  goal_with_pending_item
  local fv ws
  fv=$(fv_pass_stub fv-pass-ws2.sh)
  ws=$(fake_bin ws-empty.sh 0 '{}')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_STATE_BIN="$ws" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "implement auto ship the thing" ]
}

@test "work-state fail-closed: unparseable status output (exit 0) -> check-broke:work-state" {
  goal_with_pending_item
  local fv ws
  fv=$(fv_pass_stub fv-pass-ws3.sh)
  ws=$(fake_bin ws-junk.sh 0 'not json')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_STATE_BIN="$ws" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:work-state" ]
}

# ---- fix-cycle 1 #4 (MAJOR): budget exit-1 disambiguation ------------------
# mb-work-budget.sh check's exit 1 is ambiguous in the source (no-budget /
# stale run_id / WARN all share it with an uncaught-exception crash on a
# corrupt state file) but every DOCUMENTED path prefixes its stderr message
# `[budget] `; a crash (e.g. a Python traceback) does not. That prefix is
# the validated "output shape" fail-closed discriminator.

@test "budget exit-1 disambiguation: a legit WARN ([budget]-prefixed stderr) is NOT broken" {
  goal_with_pending_item
  local fv bud
  fv=$(fv_pass_stub fv-pass-b1.sh)
  bud=$(fake_bin_stderr bud-warn.sh 1 '[budget] WARN: spent 90/100 (90.0% >= 80%)')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_BUDGET_BIN="$bud" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "implement auto ship the thing" ]
}

@test "budget exit-1 disambiguation: legit no-active-budget ([budget]-prefixed stderr) is NOT broken" {
  goal_with_pending_item
  local fv bud
  fv=$(fv_pass_stub fv-pass-b2.sh)
  bud=$(fake_bin_stderr bud-none.sh 1 '[budget] no active budget')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_BUDGET_BIN="$bud" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "implement auto ship the thing" ]
}

@test "budget exit-1 disambiguation: exit 1 with a non-[budget] stderr (a crash) -> check-broke:work-budget" {
  goal_with_pending_item
  local fv bud
  fv=$(fv_pass_stub fv-pass-b3.sh)
  bud=$(fake_bin_stderr bud-crash.sh 1 'Traceback (most recent call last): boom')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_BUDGET_BIN="$bud" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:work-budget" ]
}

@test "budget exit-1 disambiguation: exit 1 with EMPTY stderr (a silent crash) -> check-broke:work-budget" {
  goal_with_pending_item
  local fv bud
  fv=$(fv_pass_stub fv-pass-b4.sh)
  bud=$(fake_bin_stderr bud-silent.sh 1 '')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_BUDGET_BIN="$bud" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:work-budget" ]
}

# ---- plan-verifier add: MB_WORK_PIVOT_BIN fail-closed (mirrors the 3 above) -

@test "next: fail-closed when mb-work-pivot.sh decide emits an out-of-enum value" {
  goal_with_pending_item
  local fv pv
  fv=$(fv_pass_stub fv-pass-pv1.sh)
  pv=$(fake_bin pivot-garbage.sh 0 'not-a-real-mode')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_PIVOT_BIN="$pv" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:work-pivot" ]
}

@test "next: fail-closed when mb-work-pivot.sh decide exits an unexpected code" {
  goal_with_pending_item
  local fv pv
  fv=$(fv_pass_stub fv-pass-pv2.sh)
  pv=$(fake_bin pivot-crash.sh 9 '')
  MB_FLOW_VERIFY_BIN="$fv" MB_WORK_PIVOT_BIN="$pv" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:work-pivot" ]
}

# ---- fix-cycle 1 #5 (MAJOR): a hung sub-script must not hang the loop ------

@test "timeout: wraps sub-script calls when a timeout binary is on PATH (deterministic fake stub)" {
  # A fake 'timeout' proves mb-drive.sh actually invokes the wrapper and
  # fail-closes on ITS non-zero exit -- independent of whether this host has
  # a real timeout/gtimeout (this dev box may have neither).
  mkdir -p "$BATS_TEST_TMPDIR/faketo"
  cat > "$BATS_TEST_TMPDIR/faketo/timeout" <<'EOF'
#!/usr/bin/env bash
# Ignores the wrapped command entirely: proves mb-drive.sh maps a
# timeout-style non-zero exit to the fail-closed check-broke path.
exit 124
EOF
  chmod +x "$BATS_TEST_TMPDIR/faketo/timeout"
  goal_with_pending_item
  PATH="$BATS_TEST_TMPDIR/faketo:$PATH" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == "stop_human check-broke:"* ]]
}

@test "timeout: a real timeout/gtimeout kills a hanging sub-script and fail-closes (skip if unavailable)" {
  if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
    skip "no timeout/gtimeout on PATH"
  fi
  goal_with_pending_item
  local slow="$BATS_TEST_TMPDIR/fv-slow.sh"
  cat > "$slow" <<'EOF'
#!/usr/bin/env bash
sleep 5
printf '%s\n' '{"checks":[],"totals":{"blocker":0,"major":0,"minor":0},"gate":"PASS","verdict":"pass"}'
exit 0
EOF
  chmod +x "$slow"
  MB_DRIVE_TIMEOUT=1 MB_FLOW_VERIFY_BIN="$slow" run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:mb-flow-verify" ]
}

# ---- fix-cycle 1 #6: tighten the no-goal.md assertion ----------------------

@test "next: no goal.md at all -> ok=null is not a boolean -> check-broke:acceptance, never a malformed implement line" {
  run bash "$RUN" next --bank "$BANK"
  [ "$status" -eq 0 ]
  [ "$output" = "stop_human check-broke:acceptance" ]
  [[ "$output" != implement* ]]
  [[ "$output" != *"  "* ]]
}

@test "status: prints a JSON object with the gathered signals and the resulting action" {
  goal_with_pending_item
  run bash "$RUN" status --bank "$BANK"
  [ "$status" -eq 0 ]
  [[ "$output" == \{*\} ]]
  [[ "$output" == *'"gate"'* ]]
  [[ "$output" == *'"action"'* ]]
  [[ "$output" == *'"next_item": "ship the thing"'* ]]
}

@test "status: is read-only (running it twice yields the same action)" {
  goal_with_pending_item
  run bash "$RUN" status --bank "$BANK"
  local first="$output"
  run bash "$RUN" status --bank "$BANK"
  [ "$output" = "$first" ]
}
