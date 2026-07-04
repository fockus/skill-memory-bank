#!/usr/bin/env bats
# Doc contract: commands/work.md describes Sprint 2 work-engine behavior.
#
# Every assertion here must be satisfied by the current state of commands/work.md.
# If a test fails, the doc is out of date with the spec.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  DOC="$REPO_ROOT/commands/work.md"
  [ -f "$DOC" ] || skip "commands/work.md missing"
}

@test "doc mentions specs/<topic>/tasks.md as executable" {
  run grep -E "specs/.*tasks\.md" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc mentions linked_spec frontmatter for plan-as-wrapper" {
  run grep -q "linked_spec" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc mentions mb-task marker format" {
  run grep -q "mb-task" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc documents the 5 target resolution forms" {
  run grep -qi "topic" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qiE "freeform|active plan|empty target" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc does not claim plan-only execution" {
  run grep -qi "plan-only execution" "$DOC"
  [ "$status" -ne 0 ]
  run grep -qi "tasks.md is human-only" "$DOC"
  [ "$status" -ne 0 ]
  run grep -qi "tasks.md is a scaffold" "$DOC"
  [ "$status" -ne 0 ]
}

@test "doc includes source and kind fields in JSON schema" {
  run grep -q '"source"' "$DOC"
  [ "$status" -eq 0 ]
  run grep -q '"kind"' "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc includes covers field in JSON schema" {
  run grep -q '"covers"' "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc includes item_no as alias for stage_no" {
  run grep -q '"item_no"' "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-093 S3: durable loop-state + budget run_id wiring ────────────────────

@test "doc mentions mb-work-state.sh and .work-state.json" {
  run grep -q "mb-work-state.sh" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q ".work-state.json" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc states 5f calls mb-work-state.sh cycle and halts on exit 3" {
  run grep -q "mb-work-state.sh cycle" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "exit 3" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "cycle budget exhausted" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's Hard-stops table lists the cycle-exhausted trigger via mb-work-state.sh cycle" {
  run grep -qi "cycle-exhausted" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-state.sh cycle" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc threads budget init/check with --run-id from mb-work-state.sh init" {
  run grep -q -- "--run-id" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "RUN_ID=\$(bash scripts/mb-work-state.sh init" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc describes resume path trusting work-state phase over checkboxes" {
  run grep -q "mb-work-state.sh status" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "phase.*in-progress" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "mid-flight" "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-093 S5: checkbox flip discipline ──────────────────────────────────────

@test "doc's implement prompt bans agents from editing DoD checkboxes" {
  run grep -qi "do not edit dod checkboxes" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-checkbox.sh" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's 5g sequences mb-work-state.sh done then mb-work-checkbox.sh flip, refusal means gate not passed" {
  run grep -q "mb-work-checkbox.sh flip" "$DOC"
  [ "$status" -eq 0 ]
  done_line=$(grep -n "mb-work-state.sh done" "$DOC" | head -1 | cut -d: -f1)
  flip_line=$(grep -n "mb-work-checkbox.sh flip" "$DOC" | head -1 | cut -d: -f1)
  [ -n "$done_line" ]
  [ -n "$flip_line" ]
  [ "$done_line" -lt "$flip_line" ]
  run grep -qi "refused flip\|refused.*exit 1\|exit 1.*refus" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's resume note names .work-state.json phase as the source of truth for completion" {
  run grep -qi "source of truth" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q ".work-state.json" "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-093 S7: --external reviewer parse + one bounded auto-retry ───────────

@test "doc's 5d uses --external parse for a cross-model/codex reviewer" {
  run grep -q -- "mb-work-review-parse.sh --external" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "cross-model\|codex" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's 5d performs exactly one bounded auto-retry on parse failure carrying parser stderr" {
  run grep -qi "exactly one\|one automatic retry\|one bounded.*retry\|single automatic retry" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "parser.*stderr\|stderr.*parser" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "second failure\|halts the review step\|halt.*review step" "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-093 S9: codex preflight + loud cross-model degradation ───────────────

@test "doc's 5d runs mb-work-codex-preflight.sh before a cross-model review wave" {
  run grep -q "mb-work-codex-preflight.sh" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "before.*cross-model review wave\|before dispatching an external review wave" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc mandates a loud cross-model review SKIPPED record in stage report and progress.md NOTE" {
  run grep -qi "cross-model review SKIPPED" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "NOTE.*progress.md\|progress.md.*NOTE" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "never silent\|never silently" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc says the loop consumes a SKIPPED verdict/status as a degraded cross-model gate" {
  run grep -qi 'verdict.*SKIPPED\|"SKIPPED"' "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "degraded gate\|degraded review\|degrades.*gate\|treat the gate as.*degraded" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's Hard-stops table requires explicit --auto confirmation when cross-model review is skipped" {
  run grep -qi "cross-model review SKIPPED.*--auto\|skipped cross-model gate" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "explicit user confirmation\|explicit confirmation" "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-094 S7: parallel state+budget+claim wired into commands/work.md ─────

@test "doc mentions MB_WORK_PARALLEL and per-run state/budget slot paths" {
  run grep -q "MB_WORK_PARALLEL" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q ".work-state/<run_id>.json" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q ".work-budget/<run_id>.json" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc says a parallel run mints its id via new-run-id and threads --run-id" {
  run grep -q "mb-work-state.sh new-run-id" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q -- "--run-id" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "thread.*--run-id\|--run-id.*to (state|budget|checkbox)\|--run-id.*budget.*checkbox" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc states mb-work-state.sh init returns exit 4 when claimed, halting unless --takeover" {
  run grep -qi "exit 4" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q -- "--takeover" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "claimed" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's Hard-stops table lists the claim-refused (exit 4) trigger" {
  run grep -qi "claim.refused\|claim refused" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "exit 4" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's resume section reads status --all to enumerate live parallel runs" {
  run grep -q "mb-work-state.sh status --all" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "parallel run" "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-094 S8: baseline diff + claim-aware resolve + worktree rule ─────────

@test "doc's 5c/5d build the verify/review diff with mb-work-diff.sh --run-id and --files" {
  run grep -q -- "mb-work-diff.sh --run-id" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q -- "--files" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "bare.*git diff\|not a bare" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc says the diff file list is the stage's Files: intersected with changed-since-baseline, single-arg fallback" {
  run grep -qi "changed.since.baseline\|changed since baseline" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q -- "git diff <baseline>" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q -- "git diff <baseline>..HEAD" "$DOC"
  [ "$status" -ne 0 ]
}

@test "doc's resolve step passes --skip-claimed under MB_WORK_PARALLEL for empty-target" {
  run grep -q -- "mb-work-resolve.sh" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q -- "--skip-claimed" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "MB_WORK_PARALLEL" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc states the inter-plan-worktree / intra-plan-single-owner rule" {
  run grep -qi "separate git worktrees\|separate worktrees" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "single owner\|single-owner" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "intra-plan" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "inter-plan" "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-094 S9: concurrent core-file write contract ─────────────────────────

@test "doc says progress.md appends go through the locked append-only helper under parallel runs" {
  run grep -q "mb-work-progress-append.sh" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "locked\|lock" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "append-only" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc says checklist.md is flipped only by mb-work-checkbox.sh (single-writer)" {
  run grep -q "mb-work-checkbox.sh" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "single.writer\|single writer" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "checklist.md" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc states durable progress is checkboxes+.work-state, TaskUpdate is ephemeral" {
  run grep -qi "ephemeral" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "TaskUpdate" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "durable" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q ".work-state" "$DOC"
  [ "$status" -eq 0 ]
}

# ── I-094 S10: "Parallel runs" section (T5) ───────────────────────────────

@test "doc has a Parallel runs section naming intra-plan waves and inter-plan worktrees" {
  run grep -qi "^## Parallel runs" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "intra-plan wave" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "inter-plan worktree" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc's spawn rule: sync when the next step depends on the result, async only for independent waves" {
  run grep -qi "\bsync\b" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "\basync\b" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "depends on the result\|next step depends" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "truly independent" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc mandates background report delivery via SendMessage or .reports/ else only idle notification reaches lead" {
  run grep -q "SendMessage" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q -- ".reports/" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "idle notification" "$DOC"
  [ "$status" -eq 0 ]
}

@test "doc describes optional self-claim pull mode: publish before spawn, self-claim via init exit-4, single-writer" {
  run grep -qi "self-claim" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "publish.*before spawn\|publish all tasks before spawn" "$DOC"
  [ "$status" -eq 0 ]
  run grep -q "mb-work-state.sh init" "$DOC"
  [ "$status" -eq 0 ]
  run grep -qi "single.writer\|single owner" "$DOC"
  [ "$status" -eq 0 ]
}
