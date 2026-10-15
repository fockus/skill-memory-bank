#!/usr/bin/env bats
# End-to-end /mb drive runs (drive-autopilot Task 7) without model calls. The orchestrator's side is
# simulated through the real CLIs: mb-drive.sh for the brain, mb-team.sh for team actions, and
# mb-work-state.sh + mb-work-checkbox.sh (path-keyed claims, gated flips) for each /mb work run.
# The only mock is the firewall (MB_FLOW_VERIFY_BIN). Every test runs in a temp git project whose
# path contains spaces; the real repo's index is never touched.

bats_require_minimum_version 1.5.0

load ../bats/lib/team_fixture

setup() {
  team_fixture_setup
  unset MB_WORK_PARALLEL MB_WORK_RUN_ID MB_SESSION_ID CLAUDE_CODE_SESSION_ID MB_PATH MB_DRIVE_RESUME_GATE
  export MB_GRAPH_AUTOUPDATE=off
  BANK="$(cd "$BANK" && pwd -P)"  # canonical: the checkbox gate compares resolved paths
  mkdir -p "$BANK/plans"
  FV_LOG="$BATS_TEST_TMPDIR/fv.log"
  export FV_LOG
  export MB_FLOW_VERIFY_BIN="$BATS_TEST_TMPDIR/flow-verify-stub.sh"
  cat >"$MB_FLOW_VERIFY_BIN" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$FV_LOG"
case "${FV_RC:-0}" in
  1) echo '{"checks":[{"name":"tests","status":"fail"}]}' ;;
  2) echo '{"checks":[{"name":"qa","status":"broke"}]}' ;;
  *) echo '{"checks":[]}' ;;
esac
exit "${FV_RC:-0}"
SH
  chmod +x "$MB_FLOW_VERIFY_BIN"
}

drive() { (cd "$PROJ" && bash "$REPO/scripts/mb-drive.sh" "$@" --bank "$BANK"); }
gate() { # gate <session|""> — one Stop event through the resume gate
  local sid=""; [ -n "$1" ] && sid=",\"session_id\":\"$1\""
  run --separate-stderr bash -c 'printf "%s" "$1" | bash "$2"' _ \
    "{\"cwd\":\"$PROJ\",\"stop_hook_active\":false$sid}" "$REPO/hooks/mb-drive-resume-gate.sh"
}
field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$BANK/.drive/$1.json" "$2"; }

# mkplan <name> <files> [depends_on] [qa] → a one-stage plan; prints its bank-relative path
mkplan() {
  local fm="---\ntopic: $1\nqa: ${4:-off — no QA target}\n"
  [ -n "${3:-}" ] && fm="${fm}depends_on: [$3]\n"
  printf -- "$fm---\n# Plan: %s\n\n<!-- mb-stage:1 -->\n### Stage 1: Build %s\n**Files:** %s\n\n**DoD:**\n- [ ] %s works\n<!-- /mb-stage:1 -->\n" \
    "$1" "$1" "$2" "$1" >"$BANK/plans/$1.md"
  echo "plans/$1.md"
}

# mkgoal <file> "<label>|<link>|<link>…"… → an acceptance goal with indented link bullets
mkgoal() {
  local out="$BANK/$1" crit; shift
  mkdir -p "$(dirname "$out")"
  printf -- '---\nid: G-001\nstatus: active\nmode: static\nprogress_source: checklist\nprogress_target: 100\n---\n# Goal: g\n\n## Acceptance criteria\n\n' >"$out"
  for crit in "$@"; do
    printf -- '- [ ] %s\n' "${crit%%|*}" >>"$out"
    [ "$crit" = "${crit#*|}" ] || tr '|' '\n' <<<"${crit#*|}" | sed 's/^/  - /' >>"$out"
  done
}

# work_run <plan rel> [close] — one simulated /mb work run on a plan: a path-keyed claim, and with
# `close` the gate pass (done) and the gated checkbox flip. Prints the work run id.
work_run() {
  local wid
  wid="$(MB_WORK_PARALLEL=1 bash "$REPO/scripts/mb-work-state.sh" init "$1" 1 --source-path "$BANK/$1" --mb "$BANK")"
  if [ "${2:-}" = close ]; then
    MB_WORK_PARALLEL=1 bash "$REPO/scripts/mb-work-state.sh" done --mb "$BANK" --run-id "$wid" >/dev/null 2>&1
    MB_WORK_PARALLEL=1 bash "$REPO/scripts/mb-work-checkbox.sh" flip "$BANK/$1" 1 --mb "$BANK" --run-id "$wid" >/dev/null 2>&1
  fi
  echo "$wid"
}

# executing <goal-flags…> → start + phase execution; sets RID
executing() {
  RID="$(drive start "$@")"
  drive phase execution --run-id "$RID"
}

@test "test_REQ_021__independent_items_go_to_team_and_dependent_ones_to_work" {
  a="$(mkplan a 'a/x.txt')"; b="$(mkplan b 'b/y.txt')"; c="$(mkplan c 'shared/z.txt' "$a")"
  mkgoal goal.md "A done|plan: $a|check: grep -q a2 a/x.txt" "B done|plan: $b" "C done|plan: $c"

  run drive start --budget 500000
  [ "$status" -eq 0 ]; RID="$output"
  run drive next --run-id "$RID"
  [ "$output" = "plan" ]
  run drive phase execution --run-id "$RID"
  [ "$status" -eq 0 ]
  [ "$(field "$RID" phase)" = execution ]

  run drive next --run-id "$RID"
  [ "$output" = "team $a $b" ]
  [ -z "$(grep -E 'implement|repair|review' <<<"$output")" ]

  # team action: one track per plan, --no-goal, every track runs /mb work on its plan.
  topic="drive-${RID:0:8}"
  team init "$topic" --no-goal --tree "$PROJ" >/dev/null
  team track add A --source "$a" --files "a/**" --task "Stage 1: Build a" --dod "$a closed" --size small >/dev/null
  team track add B --source "$b" --files "b/**" --task "Stage 1: Build b" --dod "$b closed" --size small >/dev/null
  team_fill_brief "$topic"
  run team next
  [ "$output" = "$(printf 'dispatch A\ndispatch B')" ]
  echo a2 >>"$PROJ/a/x.txt"; echo b2 >>"$PROJ/b/y.txt"
  wa="$(work_run "$a" close)"; wb="$(work_run "$b" close)"
  for t in A B; do
    printf 'STATUS: DONE\n\n## Files\n- %s\n' "$t" >"$BANK/reports/$topic/$t.md"
    team track set "$t" --status dispatched >/dev/null
    team track set "$t" --status returned >/dev/null
  done
  run team next
  [ "$output" = collect ]
  run team collect
  [ "$status" -eq 0 ]
  run team next
  [ "$output" = stop_success ]
  run team close
  [ "$status" -eq 0 ]
  run drive returned --run-id "$RID" --action "team $a $b" --tokens 30000 --work-run "$wa" --work-run "$wb"
  [ "$status" -eq 0 ]
  grep -qF -- '- [x] A done' "$BANK/goal.md"
  grep -qF -- '- [x] B done' "$BANK/goal.md"
  grep -qF -- '- [ ] C done' "$BANK/goal.md"

  run drive next --run-id "$RID"
  [ "$output" = "work $c" ]
  echo z2 >>"$PROJ/shared/z.txt"
  wc_="$(work_run "$c" close)"
  run drive returned --run-id "$RID" --action "work $c" --tokens 20000 --work-run "$wc_"
  [ "$status" -eq 0 ]

  # No plan declares qa: on and there is no qa/README.md → final QA does not apply; the firewall decides.
  run drive next --run-id "$RID"
  [ "$output" = stop_success ]
  [ "$(cat "$FV_LOG")" = "$BANK --skip acceptance" ]
  run bash "$REPO/scripts/mb-goal-acceptance.sh" "$BANK/goal.md" "$BANK" --tick
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["ok"] is True and not d["unbacked"], d' "$output"
  [ "$(grep -c -- '- \[x\]' "$BANK/goal.md")" -eq 3 ]

  run bash "$REPO/scripts/mb-drive-stop.sh" record --bank "$BANK" --run-id "$RID" --action stop_success
  [ "$status" -eq 0 ]
  [ "$(field "$RID" phase)" = stopped ]
  [ "$(field "$RID" stop_reason)" = success ]
  grep -q "run=\`$RID\`" "$BANK/progress.md"
  [ "$(field "$RID" steps)" = 2 ]
  gate ""
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
  run drive next --run-id "$RID"
  [ "$status" -eq 1 ]
}

@test "test_REQ_019__planning_gate_refuses_an_unlinked_goal" {
  a="$(mkplan a 'a/x.txt')"
  printf -- '---\ntopic: n\n---\n# Plan: n\n\n<!-- mb-stage:1 -->\n### Stage 1: N\n- [ ] n\n<!-- /mb-stage:1 -->\n' >"$BANK/plans/n.md"
  mkdir -p "$BANK/specs/big"
  printf -- '---\nstatus: draft\n---\n# R\n' >"$BANK/specs/big/requirements.md"
  printf -- '<!-- mb-task:1 -->\n## Task 1: T\n\n- [ ] t\n<!-- /mb-task:1 -->\n' >"$BANK/specs/big/tasks.md"
  printf -- '---\ntopic: big\nqa: on\nlinked_spec: specs/big\n---\n# W\n' >"$BANK/plans/w.md"
  mkgoal goal.md "A done|plan: $a" "unlinked thing" "W done|plan: plans/w.md"
  RID="$(drive start)"
  run --separate-stderr drive phase execution --run-id "$RID"
  [ "$status" -eq 1 ]
  grep -qF "unlinked thing" <<<"$stderr"
  grep -qF "big" <<<"$stderr"  # the draft spec behind the wrapper needs an approval
  [ "$(field "$RID" phase)" = planning ]

  mkgoal goal.md "A done|plan: $a" "N done|plan: plans/n.md" "W done|plan: plans/w.md"
  run --separate-stderr drive phase execution --run-id "$RID" --approve big
  [ "$status" -eq 1 ]
  grep -qF "plans/n.md" <<<"$stderr"
  [ "$(field "$RID" phase)" = planning ]

  # The approval batch given with the refused call stands; only the qa gap had to be fixed.
  mkgoal goal.md "A done|plan: $a" "W done|plan: plans/w.md"
  run drive phase execution --run-id "$RID"
  [ "$status" -eq 0 ]
  [ "$(field "$RID" phase)" = execution ]
}

@test "test_REQ_023__acceptance_counts_evidence_and_reports_unbacked_ticks" {
  a="$(mkplan a 'a/x.txt')"
  mkgoal goal.md "A done|plan: $a" "probe passes|check: touch probe-ran"
  sed -i.bak 's/^- \[ \] A done/- [x] A done/' "$BANK/goal.md"
  run bash "$REPO/scripts/mb-goal-acceptance.sh" "$BANK/goal.md" "$BANK" --ticks-only
  [ ! -e "$PROJ/probe-ran" ]
  run bash "$REPO/scripts/mb-goal-acceptance.sh" "$BANK/goal.md" "$BANK" --tick
  python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["ok"] is False and d["unbacked"]==["A done"], d; assert [c["met"] for c in d["criteria"]]==[False, True], d' "$output"
  [ -e "$PROJ/probe-ran" ]
  grep -qF -- '- [ ] A done' "$BANK/goal.md"
  grep -qF -- '- [x] probe passes' "$BANK/goal.md"

  # Closing the plan through a gated /mb work flip is the evidence that ticks A.
  work_run "$a" close >/dev/null
  run bash "$REPO/scripts/mb-goal-acceptance.sh" "$BANK/goal.md" "$BANK" --tick
  python3 -c 'import json,sys; assert json.loads(sys.argv[1])["ok"] is True' "$output"
  grep -qF -- '- [x] A done' "$BANK/goal.md"
}

@test "test_REQ_025__stalled_item_pivots_once_then_stops" {
  a="$(mkplan a 'a/x.txt')"
  mkgoal goal.md "A done|plan: $a"
  executing
  [ "$(drive next --run-id "$RID")" = "work $a" ]
  w1="$(work_run "$a")"
  drive returned --run-id "$RID" --action "work $a" --tokens 100 --work-run "$w1" --outcome "stop_human:claim:1"
  run drive next --run-id "$RID"
  [ "$output" = "pivot $a" ]
  drive returned --run-id "$RID" --action "pivot $a" --tokens 100
  # The item's own live work run is not a foreign claim: drive resumes it, never waits on it.
  run drive next --run-id "$RID"
  [ "$output" = "work $a" ]
  drive returned --run-id "$RID" --action "work $a" --tokens 100 --work-run "$w1"
  run drive next --run-id "$RID"
  [ "$output" = "stop_human stall" ]
  run bash "$REPO/scripts/mb-drive-stop.sh" record --bank "$BANK" --run-id "$RID" --action "stop_human stall"
  [ "$status" -eq 0 ]
  [ "$(field "$RID" stop_reason)" = "human:stall" ]
  grep -q 'human:stall' "$BANK/progress.md"
}

@test "test_REQ_026__token_usage_is_recorded_and_stops_the_run_early" {
  a="$(mkplan a 'a/x.txt')"
  mkgoal goal.md "A done|plan: $a"
  executing --budget 100000
  w="$(work_run "$a")"
  for _ in 1 2; do
    drive returned --run-id "$RID" --action "work $a" --tokens 40000 --work-run "$w" --outcome owned-elsewhere
  done
  run env MB_WORK_PARALLEL=1 bash "$REPO/scripts/mb-work-budget.sh" status --run-id "$RID" --mb "$BANK"
  grep -q 'spent=80000' <<<"$output"
  run drive next --run-id "$RID"
  [ "$output" = stop_budget ]
  bash "$REPO/scripts/mb-drive-stop.sh" record --bank "$BANK" --run-id "$RID" --action stop_budget
  [ "$(field "$RID" stop_reason)" = budget ]
}

@test "test_REQ_028__resume_and_the_stop_gate_read_the_drive_file" {
  a="$(mkplan a 'a/x.txt')"
  mkgoal goal.md "A done|plan: $a"
  executing --session S1
  R1="$RID"
  run drive resume
  [ "$status" -eq 0 ]
  [ "$output" = "run_id=$R1 goal=$BANK/goal.md phase=execution" ]
  MB_WORK_RUN_ID=unrelated gate S1
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"$R1"* ]]

  mkgoal goals/second.md "A done|plan: $a"; mkgoal goals/third.md "A done|plan: $a"
  executing --goal goals/second.md; R2="$RID"
  executing --goal goals/third.md; R3="$RID"
  run drive resume
  [ "$status" -ne 0 ]
  grep -qF "$R1" <<<"$output"; grep -qF "$R2" <<<"$output"
  gate ""
  [[ "$output" != *'"decision":"block"'* ]]
  grep -qF "$R2" <<<"$stderr"; grep -qF "$R3" <<<"$stderr"

  run drive status --run-id "$R1"
  python3 -c 'import json,sys; s=json.loads(sys.argv[1]); assert [(i["path"], i["heading"]) for i in s["items"]]==[(sys.argv[2], "Stage 1: Build a")], s' "$output" "$a"

  bash "$REPO/scripts/mb-drive-stop.sh" record --bank "$BANK" --run-id "$R1" --action "stop_human stall"
  gate S1
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

@test "test_REQ_030__blocked_qa_is_retried_deferred_and_reported" {
  a="$(mkplan a 'a/x.txt')"; b="$(mkplan b 'b/y.txt')"
  mkgoal goal.md "A done|plan: $a" "B done|plan: $b"
  executing --serial
  w=""
  for _ in 1 2; do
    [ "$(drive next --run-id "$RID")" = "work $a" ]
    [ -n "$w" ] || w="$(work_run "$a")"  # the second run resumes the recorded work run
    drive returned --run-id "$RID" --action "work $a" --tokens 10 --work-run "$w" --outcome qa-blocked:no-browser
  done
  [ "$(drive next --run-id "$RID")" = "work $b" ]
  wb="$(work_run "$b" close)"
  drive returned --run-id "$RID" --action "work $b" --tokens 10 --work-run "$wb"
  run drive next --run-id "$RID"
  [ "$output" = "qa $a" ]
  run drive status --run-id "$RID"
  python3 -c 'import json,sys; assert [c["waiting_qa"] for c in json.loads(sys.argv[1])["criteria"]]==[True, False]' "$output"
  drive returned --run-id "$RID" --action "qa $a" --tokens 10 --work-run "$w" --outcome qa-blocked:no-browser
  run drive next --run-id "$RID"
  [ "$output" = "stop_human qa-blocked:no-browser" ]
  bash "$REPO/scripts/mb-drive-stop.sh" record --bank "$BANK" --run-id "$RID" --action "$output"
  [ "$(field "$RID" stop_reason)" = "human:qa-blocked:no-browser" ]
}

@test "test_REQ_032__final_qa_and_the_firewall_gate_success" {
  mkdir -p "$BANK/qa/test_cases/checkout"
  printf '# QA target\n' >"$BANK/qa/README.md"
  a="$(mkplan checkout 'a/x.txt' '' on)"
  mkgoal goal.md "Pay works|plan: $a"
  executing
  [ "$(drive next --run-id "$RID")" = "work $a" ]
  w="$(work_run "$a" close)"
  drive returned --run-id "$RID" --action "work $a" --tokens 10 --work-run "$w"
  run drive next --run-id "$RID"
  [ "$output" = final_qa ]
  [ ! -e "$FV_LOG" ]
  run python3 "$REPO/scripts/mb_drive_qa.py" selection --bank "$BANK" --run-id "$RID"
  [ "$output" = "$RID-final0 @checkout" ]
  drive returned --run-id "$RID" --action final_qa --tokens 10
  [ "$(field "$RID" final_qa)" = pass ]
  run env FV_RC=1 bash "$REPO/scripts/mb-drive.sh" next --run-id "$RID" --bank "$BANK"
  [ "$output" = "stop_human flow-red:tests" ]
  run env FV_RC=2 bash "$REPO/scripts/mb-drive.sh" next --run-id "$RID" --bank "$BANK"
  [ "$output" = "stop_human check-broke:qa" ]
  run drive next --run-id "$RID"
  [ "$output" = stop_success ]
  [ "$(sort -u "$FV_LOG")" = "$BANK --skip acceptance" ]
}

@test "test_REQ_053__final_qa_bugs_go_through_a_fix_plan" {
  mkdir -p "$BANK/qa/test_cases/checkout"
  printf '# QA target\n' >"$BANK/qa/README.md"
  printf -- '---\nid: c\ntags: [x]\n---\n# Case\n' >"$BANK/qa/test_cases/checkout/pay.md"
  printf 'qa:\n  gate: {critical: 0, major: 0}\n  max_cycles: 2\n' >>"$BANK/pipeline.yaml"
  a="$(mkplan checkout 'a/x.txt' '' on)"
  mkgoal goal.md "Pay works|plan: $a"
  executing
  w="$(work_run "$a" close)"
  drive returned --run-id "$RID" --action "work $a" --tokens 10 --work-run "$w"
  [ "$(drive next --run-id "$RID")" = final_qa ]

  add_bug() {
    printf -- '- Scenario: qa/test_cases/checkout/pay.md, step 2\n- Run: %s\n- Steps: open the page\n- Expected: ok\n- Actual: 500\n- Evidence: logs/pay.txt\n' "$1" |
      bash "$REPO/scripts/mb-qa-bug.sh" --mb "$BANK" add major "Pay returns 500" --run "$1"
  }
  bid="$(add_bug "$RID-final0")"
  drive returned --run-id "$RID" --action final_qa --tokens 10
  fix="$(cd "$BANK" && ls plans/*_fix_drive-qa-checkout-*.md)"
  grep -q '^topic: checkout$' "$BANK/$fix"; grep -q '^qa: on$' "$BANK/$fix"; grep -qF "$bid" "$BANK/$fix"
  run drive next --run-id "$RID"
  [ "$output" = "work $fix" ]

  # The fix plan runs through an ordinary /mb work item; once it closes, final QA runs again.
  wf="$(work_run "$fix" close)"
  bash "$REPO/scripts/mb-qa-bug.sh" --mb "$BANK" set "$bid" fixed >/dev/null
  drive returned --run-id "$RID" --action "work $fix" --tokens 10 --work-run "$wf"
  run drive next --run-id "$RID"
  [ "$output" = final_qa ]
  # Bounded by qa.max_cycles (REQ-054): a second red final QA is fix cycle 2, the third is qa-red.
  bid2="$(add_bug "$RID-final1")"
  drive returned --run-id "$RID" --action final_qa --tokens 10
  fix2="$(cd "$BANK" && ls plans/*_fix_drive-qa-checkout-*-2.md)"
  grep -qF "$bid2" "$BANK/$fix2"
  run drive next --run-id "$RID"
  [ "$output" = "work $fix2" ]
  wf2="$(work_run "$fix2" close)"
  drive returned --run-id "$RID" --action "work $fix2" --tokens 10 --work-run "$wf2"
  [ "$(drive next --run-id "$RID")" = final_qa ]
  add_bug "$RID-final2" >/dev/null
  drive returned --run-id "$RID" --action final_qa --tokens 10
  [ "$(field "$RID" final_qa)" = red ]
  run drive next --run-id "$RID"
  [ "$output" = "stop_human qa-red" ]
  bash "$REPO/scripts/mb-drive-stop.sh" record --bank "$BANK" --run-id "$RID" --action "$output"
  [ "$(field "$RID" stop_reason)" = "human:qa-red" ]
}

@test "test_REQ_051__two_drives_in_one_bank_stay_apart" {
  p="$(mkplan p 'a/x.txt')"
  mkgoal goal.md "P done|plan: $p"
  executing; R1="$RID"
  run --separate-stderr drive start
  [ "$status" -eq 1 ]
  grep -qF "$R1" <<<"$stderr"

  mkgoal goals/second.md "P done|plan: $p"
  wid="$(work_run "$p")"  # a live work run R2 never recorded owns P
  executing --goal "$BANK/goals/second.md"; R2="$RID"
  [ "$R2" != "$R1" ]
  [ -f "$BANK/.drive/$R2.json" ]
  for _ in 1 2 3; do
    run drive next --run-id "$R2"
    [ "$output" = "wait $p" ]
    drive returned --run-id "$R2" --action "wait $p" --tokens 0
  done
  run drive status --run-id "$R2"
  python3 -c 'import json,sys; s=json.loads(sys.argv[1]); assert s["items"][0]["stalls"]==0 and s["items"][0]["owned_by"]==sys.argv[2], s' "$output" "$wid"
  run drive next --run-id "$R2"
  [ "$output" = "stop_human owned-elsewhere:$wid" ]
  [ "$(field "$R1" phase)" = execution ]
  [ "$(field "$R1" waits)" = 0 ]
}

@test "test_REQ_046__drive_commands_resolve_paths_and_match_the_scripts" {
  for cmd in drive goal; do
    fences="$(awk '/^```bash/{f=1;next} /^```/{f=0} f' "$REPO/commands/$cmd.md")"
    [ -z "$(grep -E 'dirname "\$0"|BANK=\.memory-bank' <<<"$fences")" ]
  done
  usage="$(bash "$REPO/scripts/mb-drive.sh" --help)"
  for action in plan work team pivot qa wait final_qa stop_success stop_budget stop_human; do
    grep -qw -- "$action" <<<"$usage"
    grep -qw -- "$action" "$REPO/commands/drive.md"
  done
  # Every flag drive.md documents for start is accepted by the script.
  mkgoal goal.md "A done|plan: $(mkplan a 'a/x.txt')"
  run --separate-stderr drive start --goal goal.md --budget 1000 --serial --host-serial --session S1
  [ "$status" -eq 0 ]
  for f in mb-drive.sh mb_drive_state.py mb_drive_decide.py mb_drive_qa.py mb_goal_evidence.py mb-drive-stop.sh; do
    [ "$(wc -l <"$REPO/scripts/$f")" -lt 400 ]
  done
}
