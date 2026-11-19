# Tasks: svp-adapt-escalation

> Slice S5 (ICE 294), rebased on ADaPT-lite (revision 4, 2026-11-19, master-completion Stage 18a).
> Task 1 is the delivered lite slice (waiver, ticked); Tasks 2-5 are the remainder on existing files.
> Order: 1 → 2 → 3 → 4 → 5, one writer at a time on `scripts/mb_work_adapt.py`, `commands/work.md`
> and `tests/pytest/test_mb_work_adapt*.py`. Eval first (red), then implementation (green).
> Budgets: Stage 1 = 210000, Stage 2 = 170000 (both ≤ 400000); every task ≤ 120000.
> `commands/work.md` is size-capped by the zone contract (`tests/pytest/test_s2_file_size_contract.py`):
> every edit to it is net-zero lines (compress the existing 5c1 text), and each task DoD re-checks it.
> `adapt.verify_fail_cycles` keeps its default 3 (AGR-082) in every task.
> Each `Eval:` carries an `output~:` anchor of a real failure (S2 REQ-054/055): a pytest run on a
> missing file exits non-zero without a `FAILED` line, so the anchor names a test that is written first.

<!-- mb-task:1 -->
## Task 1: ADaPT-lite baseline (delivered, waiver with commit link)

**Stage:** 1
**Covers:** REQ-001, REQ-005, REQ-006
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb_work_adapt.py, references/pipeline.default.yaml, references/adapt.md, commands/work.md, tests/pytest/test_mb_work_adapt.py, tests/pytest/test_adapt_lite_rules.py
**Budget:** 40000

**What to do:**
- Nothing to build: commit `190251c` (AGR-080, AGR-082) ships the `complexity_escalation` block parser (`scripts/mb_work_adapt.py:155`), the four HITL choices (`references/adapt.md` § Fork, `commands/work.md` step 5c1) and the in-run split with the parent gate (`mb_work_adapt.py:195/227/239`). This task records that mapping so REQ-001, REQ-005 and REQ-006 are covered by existing code and tests, not by a second implementation.
- The old Task 3 (`MB_WORK_RESULT_JSON` envelope in nine role agents) and the revision-3 `replan-gate` and child-spec registry are dropped: the lite block is the contract (`reason`, `estimate`, `proposed_subitems[]`, invalid → exit 3 → `BLOCKED`, ask once) and decomposition stays inside the run.

**Eval:** `pytest tests/pytest/test_mb_work_adapt.py tests/pytest/test_adapt_lite_rules.py` — red: retro-red observed on 190251c~1, where scripts/mb_work_adapt.py does not exist so every test errors on import, green since 190251c; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt\.py::test_escalation_block_parses_with_and_without_pyyaml

**Testing (TDD — tests BEFORE implementation):**
- Existing tests are the green evidence: `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_work_adapt.py tests/pytest/test_adapt_lite_rules.py` (23 passed on 2026-11-19). Retro-red: `git show 190251c~1:scripts/mb_work_adapt.py` fails, so the module and its tests do not exist before the commit.

**DoD:**
- [x] REQ-001, REQ-005, REQ-006 mapped to code at 190251c (waiver, no new code)
- [x] Existing lite tests green
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Remaining guards and thresholds in adapt-check

**Stage:** 1
**Covers:** REQ-002, REQ-003
**Role:** backend
**Blocked-by:** 1
**Scope:** scripts/mb_work_adapt.py, references/pipeline.default.yaml, commands/work.md, tests/pytest/test_mb_work_adapt.py
**Budget:** 70000

**What to do:**
- Extend the `adapt:` block with `review_cycles: 3`, `judge_cycles: 2` and `cascade_stop: 3` (ints ≥ 1) in `DEFAULTS`, `validate()` and the default line of `references/pipeline.default.yaml`; `verify_fail_cycles: 3` is not touched. Update the pinned `DEFAULT_LINE` in `tests/pytest/test_mb_work_adapt.py`.
- `check()` counts the run-state steps `review_cycle` and `judge_cycle` against `review_cycles` / `judge_cycles`, and `eval_fail` against the state's own `max_cycles` (`eval_not_green`), using the same `@<sub-item>` suffix as `verify_fail`. Reasons: `review_cycles`, `judge_cycles`, `eval_not_green`.
- Scope guard, minimal: `adapt-check --declared "<Files csv>" --changed <path|->` marks `scope_violation` when a changed path matches no declared entry (exact path, `dir/**`, `*` inside one segment; the restricted-glob grammar of svp-sdd-core C1). With no declared list or no changed list the guard is not a trigger: it is listed in `degraded_guards` and the item's Files stay the only scope truth (S3's `mb-work-scope-check.sh` is out of scope).
- `commands/work.md` step 5c1 and the phase steps record `step eval_fail|review_cycle|judge_cycle` and pass `--declared`/`--changed` (changed list from `mb-work-diff.sh --name-only`); net-zero lines.

**Eval:** `pytest tests/pytest/test_mb_work_adapt.py` — red: adapt-check knows only the verify and token guards, so a changed path outside Files and a third review cycle are not triggers; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt\.py::test_adapt_check_scope_violation_triggers

**Testing (TDD — tests BEFORE implementation):**
- pytest: `test_adapt_check_scope_violation_triggers` (stray path → `scope_violation`; declared-only paths → none; `dir/**` and `*` matches); `test_adapt_check_scope_guard_degrades_without_inputs` (no list → `degraded_guards`, no trigger); `test_adapt_check_loop_thresholds` (review 3 / judge 2 boundary: `count == threshold` fires, `threshold - 1` does not; `eval_fail` against `max_cycles`; sub-item suffix); `test_adapt_config_new_keys_validated` (0, negative, bool, string, unknown key rejected, both PyYAML and stdlib branches); default block still has `verify_fail_cycles: 3`.
- Wiring: `wc -l < commands/work.md` ≤ 400 and `tests/pytest/test_s2_file_size_contract.py` green; `ruff check scripts/mb_work_adapt.py`.

**DoD:**
- [x] REQ-002 guards (scope, review, judge, eval-not-green) and REQ-003 keys implemented; pytest green (was red)
- [x] `adapt.verify_fail_cycles` default still 3; `commands/work.md` ≤ 400 lines
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Escalation journal, cascade stop and run summary

**Stage:** 1
**Covers:** REQ-007, REQ-008, REQ-010
**Role:** backend
**Blocked-by:** 2, svp-roadmap-backlog-db#2
**Scope:** scripts/mb_work_adapt.py, scripts/mb_work_adapt_journal.py, commands/work.md, tests/pytest/test_mb_work_adapt_journal.py
**Budget:** 100000

**What to do:**
- New sibling module `scripts/mb_work_adapt_journal.py` (SRP: `mb_work_adapt.py` is past 300 lines) holds the journal; `mb_work_adapt.py` only registers the subcommands `esc-open`, `esc-resolve`, `esc-clean`, `esc-summary` and dispatches to it.
- Journal `<bank>/tmp/escalations.jsonl`, three closed schemas (`opened`, `resolved`, `clean`; design C3), mandatory `ts`/`seq`, opaque `escalation_id`, invalid line on read → exit 1 without append.
- Concurrency: the whole read → validate → append path runs under `mb_lock_acquire "<bank>/tmp/.escalations.lock" 5 30` from `scripts/_lib.sh`, held by a bash holder subprocess that stays alive for the critical section and releases with `mb_lock_release`; no fifth lock implementation.
- `esc-open` computes `decision` (design C7): `stop_run` once `consecutive >= adapt.cascade_stop` (REQ-010), `fork_user` in HITL, `auto_split` in autonomous mode, `stub_continue` in autonomous mode when called with `--split-refused`.
- `esc-summary` prints every escalation of the run, corrections of a resolution, open skips and stubs with their backlog ids (REQ-008).
- `commands/work.md` step 5c1: call `esc-open` on a trigger, `esc-resolve` after the choice, `esc-clean` on a clean `done`, `stop_run` stops before the next dispatch with the recommendation, `esc-summary` in the final summary; net-zero lines.

**Eval:** `pytest tests/pytest/test_mb_work_adapt_journal.py` — red: the esc-* subcommands and the journal do not exist, no opened record is written; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt_journal\.py::test_esc_open_writes_opened_record

**Testing (TDD — tests BEFORE implementation):**
- pytest on a temp bank: `test_esc_open_writes_opened_record` (one valid `opened` line, `escalation_id` returned); `test_esc_resolve_correlates_by_escalation_id` (two lines, same id, fold gives the last); resolve matrix (backlog id required for `stub_continue`/`skip`, forbidden otherwise; `resolved_by` from the opened `decision`; resolve after `stop_run` → exit 2; unknown id → exit 2); tuple idempotency `(resolution, backlog_id)` no-op vs corrective line; `test_cascade_stop_after_three_consecutive` and `esc-clean` resets; invalid line (extra key, unknown event, wrong type) → exit 1 with the file unchanged; an `item_id` containing `:` still correlates; `test_journal_concurrent_writers_keep_every_line` (two real processes with different run ids, all lines valid, `seq` correct per run); `esc-summary` lists escalations, corrections and stub backlog ids.
- `wc -l < commands/work.md` ≤ 400; `ruff check` on the two modules.

**DoD:**
- [x] Journal written as JSONL under `mb_lock_acquire` (concurrency test green); cascade stop and summary implemented; pytest green (was red)
- [x] `commands/work.md` ≤ 400 lines
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Stub gate in verify (verify-stub)

**Stage:** 2
**Covers:** REQ-009
**Role:** qa
**Blocked-by:** 3
**Scope:** scripts/mb_work_adapt.py, scripts/mb_work_adapt_stub.py, agents/plan-verifier.md, commands/work.md, tests/pytest/test_mb_work_adapt_stub.py
**Budget:** 90000

**What to do:**
- New sibling module `scripts/mb_work_adapt_stub.py`; `mb_work_adapt.py` registers `verify-stub --repo <root> --diff-file <path> --backlog <path>` (design C4).
- Structural checks per changed file: marker → existing `I-NNN` in backlog.md; marker on a comment or docstring line; flag token elsewhere in the same file; bare `NotImplementedError`/`TODO`/`FIXME`/`...` without a marker → violation.
- Behavioural proof of fencing: run the `eval=<path>` driver twice from `--repo` with `subprocess.run(timeout=120)` in its own process group (killed on timeout): without `<NAME>` it must print `MB-ADAPT-STUB-PATH: baseline` and exit 0, with `<NAME>=1` it must print `MB-ADAPT-STUB-PATH: staged` and exit 0. Violation codes: `unknown_backlog_id`, `marker_not_in_docstring`, `flag_token_unused`, `bare_placeholder`, `missing_stub_eval`, `flag_default_on`, `flag_does_not_gate_stub`, `stub_eval_failed`, `stub_eval_timeout`; a driver that is missing or not executable → exit 2.
- Output JSON `{"stubs":[{"file","backlog_id","flag","eval"}],"violations":[{"file","line","reason"}]}`; exit 0 clean, 1 violations, 2 usage or broken tooling.
- `agents/plan-verifier.md` and the verify step of `commands/work.md` call `verify-stub` when the diff carries a stub marker and treat exit 1 and exit 2 as FAIL; docstring completeness stays a review judgment; net-zero lines in `commands/work.md`.

**Eval:** `pytest tests/pytest/test_mb_work_adapt_stub.py` — red: the verify-stub subcommand does not exist, so a default-on flag passes verification; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt_stub\.py::test_verify_stub_default_on_flag_fails

**Testing (TDD — tests BEFORE implementation):**
- pytest on fixture repos: marker + flag + driver + existing `I-NNN` → clean; default-on (driver prints `staged` without the flag) → `flag_default_on`; marker outside a docstring → violation; flag token not steering the path (both runs print `baseline`) → `flag_does_not_gate_stub`; no `eval=` → `missing_stub_eval`; unknown backlog id; bare `NotImplementedError`/`TODO` without marker; flag only on the marker line; failing driver → `stub_eval_failed`; hanging driver → `stub_eval_timeout` (timeout patched short in the test); missing driver → exit 2; two valid stubs both listed; usage error → exit 2.
- `wc -l < commands/work.md` ≤ 400; `ruff check` on the two modules.

**DoD:**
- [x] verify-stub implemented and wired into plan-verifier and the verify step; default-on and unfenced stubs provably fail; pytest green (was red)
- [x] `commands/work.md` ≤ 400 lines
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Autonomous stub path and backlog chain

**Stage:** 2
**Covers:** REQ-004
**Role:** backend
**Blocked-by:** 4, svp-roadmap-backlog-db#2
**Scope:** scripts/mb_work_adapt.py, scripts/mb_work_adapt_stub.py, commands/work.md, tests/pytest/test_mb_work_adapt_backlog.py
**Budget:** 80000

**What to do:**
- `stub-backlog --bank <bank> --spec-topic <slug> --task-id <n> --reason <text> --flag <NAME> --capability <phrase>` in `scripts/mb_work_adapt_stub.py`, registered in `mb_work_adapt.py`: a thin sequencer over the existing S4 writers, never a second backlog mutator (design C5). It runs `mb-idea.sh "[ADAPT] <spec-topic>#<task-id>: <reason>" HIGH <bank>` without `--force`, reads the state with `mb-backlog-state.sh list`, takes the shortest valid path to `READY` (`NEW → NEEDS-INFO → TRIAGED → READY`, `annotate --brief` from the fixed template before `READY`), reuses an existing `READY`/`IN-PROGRESS` item, and halts on `DONE`/`WONTFIX`/`similar_out_of_scope` or any non-zero step. stdout `I-NNN`, exit 0; halt → exit 1; usage → exit 2.
- `commands/work.md` step 5c1, autonomous branch: when `split` exits 6 (refused at `adapt.max_depth`), `esc-open --split-refused` → decision `stub_continue` → `stub-backlog` before any code edit → re-dispatch the implementer with the stub protocol (marker, default-off flag, driver) → `esc-resolve --resolution stub_continue --backlog-id <I-NNN>`; any halt goes to the summary and stops the stub path before code; net-zero lines.

**Eval:** `pytest tests/pytest/test_mb_work_adapt_backlog.py` — red: the stub-backlog subcommand does not exist and no backlog item reaches READY before the stub; exit: 1; output~: FAILED tests/pytest/test_mb_work_adapt_backlog\.py::test_stub_backlog_reaches_ready_before_code

**Testing (TDD — tests BEFORE implementation):**
- pytest on a temp bank with the real S4 scripts: `test_stub_backlog_reaches_ready_before_code` (item ends `READY`, brief passes the READY gate, id printed); a repeated escalation with the same title reuses the existing `I-NNN` without an invalid transition; a `WONTFIX` item and a `similar_out_of_scope` hit halt with exit 1; the brief template carries `shall` and no path or line number; `PLANNED` is never assigned; usage error → exit 2.
- `wc -l < commands/work.md` ≤ 400; `ruff check` on the two modules.

**DoD:**
- [x] Autonomous stub path wired in work.md and `stub-backlog` implemented over the existing writers; pytest green (was red)
- [x] `commands/work.md` ≤ 400 lines; `adapt.verify_fail_cycles` default still 3
<!-- /mb-task:5 -->
