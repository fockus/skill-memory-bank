#!/usr/bin/env bats
# Doc contract: the /mb work command contract describes Sprint 2 work-engine
# behavior.
#
# The contract spans commands/work.md plus its companion references (split for
# the 400-line limit, S2 review [26]), so assertions run over the DOC SET. If a
# test fails, the docs are out of date with the spec.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DOC="$REPO_ROOT/commands/work.md"
  [ -f "$DOC" ] || skip "commands/work.md missing"
  DOCS=(
    "$REPO_ROOT/commands/work.md"
    "$REPO_ROOT/references/work-reference.md"
    "$REPO_ROOT/references/work-loop-v2.md"
  )
}

@test "doc mentions specs/<topic>/tasks.md as executable" {
  run grep -E "specs/.*tasks\.md" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc mentions linked_spec frontmatter for plan-as-wrapper" {
  run grep -q "linked_spec" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc mentions mb-task marker format" {
  run grep -q "mb-task" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc documents the 5 target resolution forms" {
  run grep -qi "topic" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qiE "freeform|active plan|empty target" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc does not claim plan-only execution" {
  run grep -qi "plan-only execution" "${DOCS[@]}"
  [ "$status" -ne 0 ]
  run grep -qi "tasks.md is human-only" "${DOCS[@]}"
  [ "$status" -ne 0 ]
  run grep -qi "tasks.md is a scaffold" "${DOCS[@]}"
  [ "$status" -ne 0 ]
}

@test "doc includes source and kind fields in JSON schema" {
  run grep -q '"source"' "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q '"kind"' "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc includes covers field in JSON schema" {
  run grep -q '"covers"' "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc includes item_no as alias for stage_no" {
  run grep -q '"item_no"' "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── I-093 S3: durable loop-state + budget run_id wiring ────────────────────

@test "doc mentions mb-work-state.sh and .work-state.json" {
  run grep -q "mb-work-state.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q ".work-state.json" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc states 5f calls mb-work-state.sh cycle and halts on exit 3" {
  run grep -q "mb-work-state.sh cycle" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "exit 3" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "cycle budget exhausted" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's Hard-stops table lists the cycle-exhausted trigger via mb-work-state.sh cycle" {
  run grep -qi "cycle-exhausted" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-state.sh cycle" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc threads budget init/check with --run-id from mb-work-state.sh init" {
  run grep -q -- "--run-id" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "RUN_ID=\$(bash scripts/mb-work-state.sh init" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc describes resume path trusting work-state phase over checkboxes" {
  run grep -q "mb-work-state.sh status" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "phase.*in-progress" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "mid-flight" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── I-093 S5: checkbox flip discipline ──────────────────────────────────────

@test "doc's implement prompt bans agents from editing DoD checkboxes" {
  run grep -qi "do not edit dod checkboxes" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-checkbox.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's 5g sequences mb-work-state.sh done then mb-work-checkbox.sh flip, refusal means gate not passed" {
  run grep -q "mb-work-checkbox.sh flip" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  # ordering is a within-file property — both anchors live in work.md's step 5g
  done_line=$(grep -n "mb-work-state.sh done" "$DOC" | head -1 | cut -d: -f1)
  flip_line=$(grep -n "mb-work-checkbox.sh flip" "$DOC" | head -1 | cut -d: -f1)
  [ -n "$done_line" ]
  [ -n "$flip_line" ]
  [ "$done_line" -lt "$flip_line" ]
  run grep -qi "refused flip\|refused.*exit 1\|exit 1.*refus" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's resume note names .work-state.json phase as the source of truth for completion" {
  run grep -qi "source of truth" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q ".work-state.json" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── I-093 S7: --external reviewer parse + one bounded auto-retry ───────────

@test "doc's 5d uses --external parse for a cross-model/codex reviewer" {
  run grep -q -- "mb-work-review-parse.sh --external" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "cross-model\|codex" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's 5d performs exactly one bounded auto-retry on parse failure carrying parser stderr" {
  run grep -qi "exactly one\|one automatic retry\|one bounded.*retry\|single automatic retry" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "parser.*stderr\|stderr.*parser" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "second failure\|halts the review step\|halt.*review step" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── I-093 S9: codex preflight + loud cross-model degradation ───────────────

@test "doc's 5d runs mb-work-codex-preflight.sh before a cross-model review wave" {
  run grep -q "mb-work-codex-preflight.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "before.*cross-model review wave\|before dispatching an external review wave" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc mandates a loud cross-model review SKIPPED record in stage report and progress.md NOTE" {
  run grep -qi "cross-model review SKIPPED" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "NOTE.*progress.md\|progress.md.*NOTE" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "never silent\|never silently" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc says the loop consumes a SKIPPED verdict/status as a degraded cross-model gate" {
  run grep -qi 'verdict.*SKIPPED\|"SKIPPED"' "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "degraded gate\|degraded review\|degrades.*gate\|treat the gate as.*degraded" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's Hard-stops table requires explicit --auto confirmation when cross-model review is skipped" {
  run grep -qi "cross-model review SKIPPED.*--auto\|skipped cross-model gate" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "explicit user confirmation\|explicit confirmation" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── I-094 S7: parallel state+budget+claim wired into commands/work.md ─────

@test "doc mentions MB_WORK_PARALLEL and per-run state/budget slot paths" {
  run grep -q "MB_WORK_PARALLEL" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q ".work-state/<run_id>.json" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q ".work-budget/<run_id>.json" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc says a parallel run mints its id via new-run-id and threads --run-id" {
  run grep -q "mb-work-state.sh new-run-id" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "--run-id" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "thread.*--run-id\|--run-id.*to (state|budget|checkbox)\|--run-id.*budget.*checkbox" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc states mb-work-state.sh init returns exit 4 when claimed, halting unless --takeover" {
  run grep -qi "exit 4" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "--takeover" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "claimed" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's Hard-stops table lists the claim-refused (exit 4) trigger" {
  run grep -qi "claim.refused\|claim refused" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "exit 4" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's resume section reads status --all to enumerate live parallel runs" {
  run grep -q "mb-work-state.sh status --all" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "parallel run" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── I-094 S8: baseline diff + claim-aware resolve + worktree rule ─────────

@test "doc's 5c/5d build the verify/review diff with mb-work-diff.sh --run-id and --files" {
  run grep -q -- "mb-work-diff.sh --run-id" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "--files" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "bare.*git diff\|not a bare" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc says the diff file list is the stage's Files: intersected with changed-since-baseline, single-arg fallback" {
  run grep -qi "changed.since.baseline\|changed since baseline" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "git diff <baseline>" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "git diff <baseline>..HEAD" "${DOCS[@]}"
  [ "$status" -ne 0 ]
}

@test "doc's resolve step passes --skip-claimed under MB_WORK_PARALLEL for empty-target" {
  run grep -q -- "mb-work-resolve.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "--skip-claimed" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "MB_WORK_PARALLEL" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc states the inter-plan-worktree / intra-plan-single-owner rule" {
  run grep -qi "separate git worktrees\|separate worktrees" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "single owner\|single-owner" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "intra-plan" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "inter-plan" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── I-094 S9: concurrent core-file write contract ─────────────────────────

@test "doc says progress.md appends go through the locked append-only helper under parallel runs" {
  run grep -q "mb-work-progress-append.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "locked\|lock" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "append-only" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc says checklist.md is flipped only by mb-work-checkbox.sh (single-writer)" {
  run grep -q "mb-work-checkbox.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "single.writer\|single writer" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "checklist.md" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc states durable progress is checkboxes+.work-state, TaskUpdate is ephemeral" {
  run grep -qi "ephemeral" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "TaskUpdate" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "durable" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q ".work-state" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── I-094 S10: "Parallel runs" section (T5) ───────────────────────────────

@test "doc has a Parallel runs section naming intra-plan waves and inter-plan worktrees" {
  run grep -qi "^## Parallel runs" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "intra-plan wave" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "inter-plan worktree" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's spawn rule: sync when the next step depends on the result, async only for independent waves" {
  run grep -qi "\bsync\b" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "\basync\b" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "depends on the result\|next step depends" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "truly independent" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc mandates background report delivery via SendMessage or .reports/ else only idle notification reaches lead" {
  run grep -q "SendMessage" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- ".reports/" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "idle notification" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc describes optional self-claim pull mode: publish before spawn, self-claim via init exit-4, single-writer" {
  run grep -qi "self-claim" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "publish.*before spawn\|publish all tasks before spawn" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-state.sh init" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "single.writer\|single owner" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── reviewer-2.0 Task 5: mb-review.sh payload + --require-tests-blocker ────

@test "doc's 5d assembles the review payload via mb-review.sh before dispatching a reviewer" {
  run grep -q -- "mb-review.sh --emit-payload" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "deterministic" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's 5d dispatches the pipeline-resolved reviewer, not a hard-coded Task to mb-reviewer" {
  run grep -q "mb-reviewer-resolve.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "never a hard-coded \`Task(mb-reviewer)\`\|not a hard-coded \`Task" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc wires --require-tests-blocker into mb-work-review-parse.sh before the severity gate" {
  run grep -q -- "--require-tests-blocker" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "cannot drop" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "BEFORE the severity gate" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc says --require-tests-blocker is opt-in and byte-identical when omitted" {
  run grep -qi -- "opt-in.*omit the flag\|omit the flag when touched-file tests were passing" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "byte-identical" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── Fix-cycle 1 (governed review NO_GO on Task 5): MINOR #3 ────────────────

@test "doc's 5d names an unambiguous, greppable marker for touched-file test status" {
  run grep -q -- "## Auto-generated findings" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "tests_pass: False" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "grep -q" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

# ── work-loop-v2 Task 5: contract phase + trend + pivot + max-cycle wiring ──

@test "doc has a work-loop-v2 section naming mb-work-contract.sh, mb-work-trend.sh, and mb-work-pivot.sh" {
  run grep -qi "^## Sprint contracts, progress trend, and strategic pivoting" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-contract.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-trend.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-pivot.sh" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc describes the sprint-contract phase as opt-in via --contract or require_contract, capped at 3 cycles" {
  run grep -q -- "--contract" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "require_contract" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "review_mode:" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "3 contract.review cycles\|3 contract cycles" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc describes progress trend computed via mb-work-trend.sh key/compute with all four outcomes" {
  run grep -q -- "mb-work-trend.sh key" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "mb-work-trend.sh compute" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "improving" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "stagnant" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "regressing" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc's pivot section names both pivot_in_role and pivot_via_architect routes plus telemetry" {
  run grep -q "pivot_in_role" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q "pivot_via_architect" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "mb-work-pivot.sh decide" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "mb-work-pivot.sh prompt-prefix" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -q -- "pivot-log.jsonl" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}

@test "doc states the max-cycle policy default is on_max_cycles: stop_for_human" {
  run grep -q -- "on_max_cycles: stop_for_human" "${DOCS[@]}"
  [ "$status" -eq 0 ]
  run grep -qi "stop_for_human" "${DOCS[@]}"
  [ "$status" -eq 0 ]
}
