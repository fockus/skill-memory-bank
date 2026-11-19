# F3b verify: master-completion Stage 18 (code half), svp-adapt-escalation T2-T5

## Plan Verification: master-completion Stage 18 + spec svp-adapt-escalation (T1 waiver, T2-T5 code)

### Status: PASS_WITH_NOTES

**Baseline commit:** HEAD e0a7ee0 (working tree; all F3b work is uncommitted, diff = `git diff` + untracked)
**Tests run:** pass (targeted only, per instruction; no full suite)
**RULES violations:** 0 CRITICAL, 6 WARNING (stack.python.type-hints, mb-rules-check.sh, project RULES.md)
**Agreement Compliance:** not run per agreement (track scope check only): AGR-082 verify_fail_cycles 3 kept, AGR-107 rebase respected

### Commands and results
- `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-adapt-escalation` -> `layers=legacy`, rc=0
- open DoD in tasks.md: `grep -c '- [ ]'` = 0
- `PYTHONPATH=. python3 -m pytest -q` (test_mb_work_adapt, _journal, _stub, _backlog, test_adapt_lite_rules, test_s2_file_size_contract, test_planning_qa_sources_scenarios, test_doc_counts) -> 99 passed
- same 5 adapt files under Python 3.11.11 (.venv, PATH so subprocess `python3` is 3.11) -> 75 passed; `ruff check --target-version py311` clean
- `bats tests/bats/test_mb_work_adapt_lite.bats` -> 13/13 ok
- doc pytest reading work.md / plan-verifier.md (16 files) -> 675 passed
- doc bats reading work.md / plan-verifier.md (16 files incl. hooks/tests/graph-discipline.bats; e2e install excluded) -> 207 ok, 0 not ok, 0 skip
- golden consumers `test_mb_workflow_qa.bats`, `test_planning_qa_default.bats` -> 32 ok, 0 not ok
- `tests/pytest/test_spec_corpus_battery.py` -> 5 passed (F3a stale-allowlist concern is resolved)
- `bash scripts/mb-pipeline-validate.sh references/pipeline.default.yaml` -> rc=0
- `ruff check` + `ruff format --check` on 4 modules + 4 test files -> clean
- end-to-end: `mb-work-state.sh init` -> 3x `step review_cycle` -> `adapt-check --declared src/a.py --changed -` -> reasons `[review_cycles, scope_violation]`, out_of_scope `[src/z.py]`; then `esc-open --mode autonomous` -> `auto_split`; `esc-summary` lists it.

### Task 2 (REQ-002, REQ-003)
- [x] keys `review_cycles 3`, `judge_cycles 2`, `cascade_stop 3` — scripts/mb_work_adapt.py:42-51, validate :77-79 (int >= 1, bool rejected), references/pipeline.default.yaml:288; tests test_bad_adapt_values_are_rejected (parametrized PyYAML/stdlib), test_adapt_config_new_keys_default_and_override
- [x] review/judge/eval_not_green counters with `@<sub-item>` suffix — mb_work_adapt.py:192-212; test_adapt_check_loop_thresholds (boundary pairs), test_adapt_check_loop_counters_use_the_sub_item_suffix
- [x] scope guard + degraded — mb_work_adapt.py:199-216, mb_work_adapt_block.py:97-114; test_adapt_check_scope_violation_triggers, test_adapt_check_scope_guard_degrades_without_inputs
- [x] verify_fail_cycles default 3 (mb_work_adapt.py:44, pipeline.default.yaml:288); work.md 377 lines

### Task 3 (REQ-007, REQ-008, REQ-010)
- [x] journal `<bank>/tmp/escalations.jsonl`, closed schemas — mb_work_adapt_journal.py:64-96; invalid line -> exit 1, file unchanged (test_invalid_journal_line_fails_loud_without_append)
- [x] under `mb_lock_acquire`: bash holder `source _lib.sh; mb_lock_acquire "$2" 30 30` (journal.py:37-41), Python yields only after the holder prints the token (journal.py:99-118). Token is `$$-RANDOM` of the `bash -c` holder (_lib.sh:1021-1033) and the holder stays alive on `read` until Python closes stdin, so liveness reclaim is correct. test_journal_concurrent_writers_keep_every_line: 8 real processes, 2 runs, `consecutive` exactly 1..4 per run (proves serialization), lock dir removed.
- [x] cascade stop `consecutive >= cascade_stop` -> stop_run; resolve after stop_run -> exit 2; esc-clean resets — journal.py:146-173; test_cascade_stop_after_three_consecutive_and_clean_resets
- [x] esc-summary with corrections and stub backlog ids — journal.py:238-251; tests ..._idempotent_and_corrections_append, test_esc_summary_lists_escalations_and_stub_backlog_ids
- [x] work.md 5c1 calls esc-open / esc-resolve / esc-clean / esc-summary (commands/work.md:227-231)

### Task 4 (REQ-009)
- [x] verify-stub, codes, exit 0/1/2, process-group kill on timeout — mb_work_adapt_stub.py:38-145; 15 tests incl. test_verify_stub_default_on_flag_fails, ..._flag_that_does_not_gate_fails, ..._hanging_driver_times_out, ..._missing_or_unrunnable_driver_is_a_tooling_error
- [x] wired: agents/plan-verifier.md:119 (`verify-stub --repo . --diff-file <name-only list> --backlog <bank>/backlog.md`; exit 1 or 2 = FAIL) and commands/work.md:229 — flags match `verify-stub --help`

### Task 5 (REQ-004)
- [x] stub-backlog over real mb-idea.sh / mb-backlog-state.sh, no --force, NEW->NEEDS-INFO->TRIAGED->(annotate --brief)->READY, reuse READY/IN-PROGRESS, halt otherwise — mb_work_adapt_stub.py:148-227; 6 tests on the real S4 scripts (READY, reuse, resume mid-chain, WONTFIX halt, similar_out_of_scope halt, usage exit 2)
- [x] autonomous branch in work.md:228 (split exit 6 -> esc-open --split-refused -> stub-backlog before code -> stub protocol -> esc-resolve stub_continue)

### Item 3: work.md / CLI coherence
- work.md 377 lines (net-zero); every subcommand and flag named in 5c1 exists (`--help` of the dispatcher, esc-*, verify-stub, stub-backlog). `mb-work-state.sh adapt-check` forwards `--declared/--changed` through REST_ARGS (mb-work-state.sh:222-227) — confirmed end to end.

### Item 4
- verify_fail_cycles default 3: yes. Journal under mb_lock_acquire: yes (holder read, see T3). Module sizes: 300 / 129 / 300 / 227 — none over 300 (two exactly at the cap). Python 3.11: tests green on 3.11.11; `datetime.UTC` (3.11+), `zip(strict=)` (3.10+) fine.

### Item 5: changes outside the planned list
- tests/bats/fixtures/qa-golden/workflow.json and test_mb_work_adapt_lite.bats:157: the pinned adapt JSON only gains the three new keys; strict equality kept, nothing weakened. Necessary consequence of T2's keys.
- parse_intermixed_args (mb_work_adapt.py:265): justified. Reproduced: `parse_args(["split","--state","s","1",...])` fails on 3.11.11 ("unrecognized arguments: 1") and passes on 3.13; HEAD used `parse_args`, so it was a pre-existing 3.11 bug that `mb-work-state.sh` hits (it puts the item after `--state`).
- scripts/mb_work_adapt_block.py (new, not in Scope): pure move of the report parser out of the dispatcher plus the scope matcher, to stay at 300 lines; documented in design.md:252 and references/scripts.md.
- test_mb_work_adapt.py: the only removed line is the old pinned DEFAULT_LINE.

### WARNING (non-blocking)
1. Scope guard false positive on brace or free-text Files entries. Plan stages use brace Files (this very Stage 18: `.memory-bank/specs/svp-adapt-escalation/{requirements,design,tasks}.md`). The CSV split breaks the braces apart, and the entry never matches. Reproduced: `adapt-check --declared '.memory-bank/specs/svp-adapt-escalation/{requirements,design,tasks}.md,scripts/mb_work_adapt.py' --changed -` with `design.md` changed -> `trigger: true, reasons: [scope_violation]`. This matches the C1 grammar, which rejects braces, but plan-sourced items will fire spurious escalations. Recommendation: when any declared entry is malformed per C1 (brace, space or other free text), put `scope` in `degraded_guards` instead of firing; or expand braces. Follow-up item.
2. Lock args deviate from the spec text: `mb_lock_acquire … 30 30` instead of `5 30` (journal.py:39), with a retry loop that also retries on `lock_corrupt`. This is justified and documented in design.md:252 (library TOCTOU, follow-up in _lib.sh), but the design.md:135 body text still says `5 30`.
3. work.md 5c1 shows `esc-resolve --id … --resolution …` without the required `--bank`, and the stub-path resolve also has no `--id`. This is shorthand next to a full esc-open line. An orchestrator copying it literally gets an argparse exit 2. Consider spelling out `--bank <bank> --id <escalation_id>` once (net-zero).
4. RULES (warn strictness): 6 `stack.python.type-hints` warnings (mb_work_adapt.py:60, block.py:19/24 (moved code), journal.py:56/92/204).

### INFO
- Plan Stage 18 DoD boxes (plan lines 382-383) are still `[ ]`. Both items are met by evidence; the orchestrator should tick them.
- The tasks.md T1 waiver cites `mb_work_adapt.py:155/195/227/239` at commit 190251c. The code has since moved: the parser is now in mb_work_adapt_block.py, and split/sub_done/gate are at :129/:161/:173. The references are correct as commit references.
- verify-stub flags a bare `...` line in any file of the diff when that file has no marker, so Protocol bodies in the same diff would be reported. This follows the spec, but watch for noise.
- Retro-red cannot be checked from git (new tests untracked), but it is structurally certain. HEAD's CLI choices (`parse, config, split, sub-done, adapt-check, gate, carry`) have no esc-*/verify-stub/stub-backlog/--declared, so every new test fails on HEAD.

### Gate
Stage 18 DoD: open DoD = 0, validate rc=0, the JSONL journal under the lock is proven by a concurrency test, and work.md is 377 lines (≤ 400). Met.
