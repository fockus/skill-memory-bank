# F3b report: svp-adapt-escalation T2-T5 (code)

STATUS: DONE

Concerns
- (resolved) work.md 5c1 (net-zero 5 lines, file still 377) and agents/plan-verifier.md (one verify-stub sentence) wired after B4 released the file. All DoD ticked, open DoD = 0, `mb-spec-validate.sh --require-scenarios` rc=0. Evidence: test_s2_file_size_contract + S5 + lite rules 77 passed; 15 pytest doc files that read work.md/plan-verifier.md: 670 passed; the 13 related bats files: no `not ok`.
- (Low) `mb_lock_acquire` has a TOCTOU (path vanishes between mkdir and -d check -> spurious lock_corrupt, _lib.sh): worked around in the bash holder (retry within a 30 s budget); real fix is a follow-up in _lib.sh.
- (Low) Pre-existing: mb_work_adapt.py failed under Python 3.11 (`split 1 --subitems` -> "unrecognized arguments"); fixed with parse_intermixed_args (bats test_mb_work_adapt_lite 13/13 ok under .venv 3.11).

## Files
scripts/mb_work_adapt.py (300 lines), NEW scripts/mb_work_adapt_block.py (129; extra sibling so the dispatcher fits 300: report + scope parsing), NEW scripts/mb_work_adapt_journal.py (300), NEW scripts/mb_work_adapt_stub.py (227), references/pipeline.default.yaml (adapt line + comment), references/adapt.md, references/scripts.md (3 rows), specs/svp-adapt-escalation/{tasks,design}.md, tests/bats/fixtures/qa-golden/workflow.json (golden gained the 3 keys), tests/bats/test_mb_work_adapt_lite.bats (pinned adapt JSON), tests/pytest/test_mb_work_adapt.py (+T2 tests, DEFAULT_LINE), test_mb_work_adapt_{journal,stub,backlog}.py (new).
Validator: `adapt.validate` is the hook already called by mb_pipeline_validate_core; new int keys rejected for 0/negative/bool/string in both PyYAML and stdlib branches (parametrized tests).

## Lock
Used `mb_lock_acquire` from scripts/_lib.sh via a bash holder subprocess (design C3, DoD names it). Not `_dir_lock` (mb_fs_atomic): it is best-effort and fails open without the lock, wrong for durable guard state. Wait budget 30 s (5 s too short: poll is 1 s, 8 contenders timed out).

## TDD evidence (red before code)
- T2: `pytest tests/pytest/test_mb_work_adapt.py` -> `26 failed, 7 passed` incl. FAILED ...::test_adapt_check_scope_violation_triggers; green after: `41 passed` (with lite rules).
- T3: `pytest tests/pytest/test_mb_work_adapt_journal.py` -> `13 failed` incl. test_esc_open_writes_opened_record; green: `13 passed` (concurrency test 14/14 reruns; 2 writers x 4 procs, all lines valid, lock dir gone).
- T4: `pytest tests/pytest/test_mb_work_adapt_stub.py` -> `13 failed, 2 passed` incl. test_verify_stub_default_on_flag_fails; green `15 passed`.
- T5: `pytest tests/pytest/test_mb_work_adapt_backlog.py` -> `5 failed, 1 passed` incl. test_stub_backlog_reaches_ready_before_code; green `6 passed`.
Final: all four files + test_adapt_lite_rules: 75 passed (3.13), 67 passed on 3.11 venv; bats adapt_lite 13 ok; test_s2_file_size_contract 10 passed (work.md 377 lines, untouched); test_planning_qa_sources_scenarios + test_doc_counts 22 passed; bats workflow_qa/planning_qa_default/work_source_bundle no failures; ruff check + format clean; `mb-pipeline-validate.sh references/pipeline.default.yaml` clean; verify_fail_cycles still 3.
Full-suite `-k` sweep and mb-test-run were started in background and had not reported when I stopped; not claimed.

Graph: 1 query (tests mb_work_adapt.py, catchup cooldown, then Read/grep).

## Fix cycle 1 (plan-verifier PASS_WITH_NOTES)
1. Scope guard false alarms. Red first: `test_adapt_check_scope_guard_ignores_free_text_entries` (exact Stage 18 Files line + change to design.md) and `test_adapt_check_scope_guard_expands_brace_groups` failed (2 failed). Fix in `scripts/mb_work_adapt_block.py`: `parse_declared` splits on top-level commas, expands `{a,b}` groups, and returns None when an entry contains whitespace (free text) -> `degraded_guards: ["scope"]`, no trigger. A real out-of-scope file still fires `scope_violation`. Green: 35 passed in test_mb_work_adapt.py.
2. work.md 5c1: every `esc-resolve` now carries `--bank <bank> --id <escalation_id>` (auto, stub path, HITL); the HITL `esc-open` is spelled out and the stub-path `esc-open` says "same flags plus --split-refused". Net-zero (377). Copy-paste walk against a scratch bank (open -> resolve decompose; open --split-refused -> stub-backlog I-001 -> resolve stub_continue; HITL skip with backlog id; clean; summary; verify-stub): every call rc=0 (note: a third unresolved-and-unclean open in one run correctly returns stop_run, so the walk cleans between items). New guard `test_work_md_esc_calls_carry_the_required_flags`.
Evidence: S5 tests + lite rules + size contract + doc tests (proportional_verification, graph_dispatch, cost_ladder, quality_dod, audit_command_contracts, tooling_core_wiring): 136 passed; bats work_command_doc/eval_first/plan_verifier_rules/adapt_lite: 0 not ok; ruff clean; modules 300/165/300/227 lines. Earlier sweeps: -k workflow/adapt 244 passed; 15 doc files 670 passed.
