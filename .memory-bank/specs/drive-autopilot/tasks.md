# Tasks: drive-autopilot

> Slice S3 of `[SPEC:autopilot]`. Five coarse implementation tasks cut at owner and dependency boundaries
> (AGR-078, NFR-001), then the two rendered test layers. Order: Task 1 (goal evidence) → Task 2 (drive brain,
> reads Task 1) → Task 3 (stop record and resume gate) and Task 4 (final-QA fix cycle) in parallel on disjoint
> files → Task 5 (commands, docs and the removal of the last old callers). Every task replaces the old tests of
> the files it owns; the full suite runs once at the end of the spec. Prompt clauses are asserted through
> `tests/bats/lib/discuss_contract.bash` (`assert_clause` + `assert_clause_load_bearing`), never by a bare
> `grep -q`. Roles are bare. Requires S1 `planning-qa-sources` (plan `qa:` line, `--tier`, wrapper, regression
> cases) and S2 `team-completion` (tracks through `/mb work`, `--skip acceptance` in team's flow call) first.

<!-- mb-task:1 -->
## Task 1: Goal acceptance from evidence

**Stage:** 1
**Covers:** REQ-023, REQ-024, REQ-042, REQ-043, REQ-046
**Role:** developer
**Blocked-by:** none
**Scope:** scripts/mb-goal-acceptance.sh, scripts/mb_goal_evidence.py, templates/goal.md, commands/goal.md, tests/bats/test_goal_evidence.bats, tests/bats/test_mb_goal_acceptance.bats
**Budget:** 60000
**Eval:** bats tests/bats/test_goal_evidence.bats tests/bats/test_mb_goal_acceptance.bats — red: bats file materialised, mb-goal-acceptance.sh reads no plan or check links, has no tick modes and reports no unbacked ticks, so every named case goal_evidence fails; exit: 1; output~: not ok [0-9]+ goal_evidence:

**What to do:**
- `scripts/mb_goal_evidence.py` per design C1: parse `plan:` / `check:` sub-bullets under each criterion (fence-aware, same section rule as today); resolve a plan (with the `plans/done/<basename>` fallback) and, for a wrapper, its spec tasks in the `tasks:` range through `mb_work_items.parse_work_items` + `mb_work_plan_wrapper.fm_value`; closed = every resolved item `done`; run a criterion's checks only once its plans are closed, from the project root, under `MB_GOAL_CHECK_TIMEOUT`; `tick` rewrites linked boxes of the given goal file atomically.
- `scripts/mb-goal-acceptance.sh`: a goal with no link keeps today's code path and bytes; with ≥ 1 link delegate to the module (`ok`, `findings`, `unbacked`, `criteria`); `--tick` writes, `--ticks-only` forces today's count; exit 0 always; the explicit goal-path argument works for any goal file.
- `templates/goal.md`: one linked example criterion in the comment block. `commands/goal.md`: the link grammar, goal files other than `<bank>/goal.md` for a second drive, and the resolution fence of design C5 (no `$(dirname "$0")`, no `BANK=".memory-bank"`).

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_goal_evidence.bats`, every case named `goal_evidence: …`, on a temp bank: plan with a pending item → unmet; all items done → met; wrapper over a spec with one undone task in range → unmet; `plans/done/` fallback; `check: true` / `check: false`; checks not run while a plan is open (a check that writes a marker file); hand-ticked unmet criterion listed under `unbacked`; `--tick` sets boxes to evidence on a goal file outside `<bank>/goal.md`; `--ticks-only` runs no check (marker absent); a goal without links gives byte-identical output to the pre-change script for the fixtures of `tests/bats/test_mb_goal_acceptance.bats`, which stays green unchanged.
- Prompt clauses through the harness: goal.md link grammar, second goal file, and the resolution fence.

**DoD:**
- [x] linked criteria are met only from evidence; unbacked ticks are reported; `--tick` and `--ticks-only` behave as in design C1
- [x] a goal without links keeps byte-identical output; `tests/bats/test_mb_goal_acceptance.bats` green unchanged
- [x] `scripts/mb_goal_evidence.py` ≤ 250 lines, `scripts/mb-goal-acceptance.sh` < 400 lines
- [x] tests pass (were red); shellcheck and ruff clean on touched files
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: Drive brain — run files, run selection, planning gate, next and returned

**Stage:** 2
**Covers:** REQ-019, REQ-039, REQ-021, REQ-022, REQ-033, REQ-040, REQ-041, REQ-025, REQ-044, REQ-026, REQ-027, REQ-028, REQ-029, REQ-047, REQ-030, REQ-031, REQ-032, REQ-048, REQ-042, REQ-051, REQ-052, REQ-055, REQ-056, REQ-049
**Role:** developer
**Blocked-by:** 1
**Scope:** scripts/mb-drive.sh, scripts/mb_drive_state.py, scripts/mb_drive_decide.py, scripts/mb-work-slots.sh, references/pipeline.default.yaml, docs/pipeline-yaml.md, .gitignore, tests/pytest/test_mb_drive_brain.py, tests/bats/test_mb_drive.bats, tests/pytest/test_s2_file_size_contract.py
**Budget:** 115000
**Eval:** python3 -m pytest -q tests/pytest/test_mb_drive_brain.py tests/pytest/test_s2_file_size_contract.py — red: test file materialised, mb-drive.sh has no start, resume, phase or returned subcommand, keeps no run file per drive and next still prints implement, so the brain tests fail; exit: 1; output~: FAILED tests/pytest/test_mb_drive_brain.py

**What to do:**
- `scripts/mb_drive_state.py` per design C2/C3.1/C3.2/C3.4: atomic run-file IO at `mbw_drive_slot` (retargeted in `scripts/mb-work-slots.sh` to `<bank>/.drive/<run_id>.json`); run selection (`--run-id`, the only live run, several → exit 2 with the list); `start` (bank, `--goal` with the `<bank>/goal.md` default, scaffold/validate refusal, same-goal live-run refusal naming the run, run id, session, parallel mode and reason with the host notice line, per-run budget init), `resume`, `phase execution` (the gap rules, `--approve`), `returned` (budget add, `--work-run`, waits, per-item stall/QA/owned-elsewhere accounting, pivot, final-QA blocked/pass, `mb-goal-acceptance.sh <goal> --tick`), `stop` (phase `stopped`, `stop_reason` — called by Task 3). Leave a single call site for the final-QA gate that Task 4 fills.
- `scripts/mb_drive_decide.py` per design C3.3/C3.5: items from goal links, deps from `depends_on:`, files from `mb_work_waves.declared_files`, waves from `mb_work_waves.assign_waves`, owned-elsewhere from `MB_WORK_PARALLEL=1 mb-work-state.sh status --all` against the item's recorded work runs; the pure `decide(facts)` with the fifteen rules in order; checks only from rule 13, `mb-flow-verify.sh --skip acceptance` only at rule 15; `status` JSON.
- `scripts/mb-drive.sh`: rewrite as a thin dispatcher (≤ 120 lines) for `start`, `resume`, `phase`, `next`, `returned`, `status`; the old `decide` seam, `implement`/`repair`/cycle/pivot-mode signals and `--route/--phase/--max-cycles` go.
- `references/pipeline.default.yaml` + `docs/pipeline-yaml.md`: `drive: {parallel: true}`; only a literal `false` turns it off. `.gitignore`: `.memory-bank/.drive/`. `tests/pytest/test_s2_file_size_contract.py`: list `scripts/mb-drive.sh`, both modules and the new test file.
- Delete `tests/bats/test_mb_drive.bats` (it pins the removed decision table); its still-valid cases (help, unknown subcommand exit 2, fail-closed on a broken input) move into the new test file.

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_mb_drive_brain.py`: the `decide` table row by row on fact dicts (each rule wins over the next); through the CLI on a temp bank with a stub `mb-flow-verify.sh` (`MB_FLOW_VERIFY_BIN`, the only mock): planning gate gaps and `--approve`; `team A B` for disjoint independent plans, `work C` for the dependent one, `work` only under `--serial`, `drive.parallel: false` and `--host-serial` (notice line); stall → `pivot` → `stop_human stall`; a `stop_human:` outcome counts as a stall, `owned-elsewhere` does not; a live foreign work claim on P → `wait P`, three waits → `stop_human owned-elsewhere:<id>`, a claim recorded through `--work-run` is not foreign; budget 100000 with two 40000 returns → `stop_budget`, spent visible through `mb-work-budget.sh status` under the run id; QA blocked twice → deferred → `qa <A>` after B closes → `stop_human qa-blocked:<r>`; `final_qa` then firewall with `--skip acceptance` exit 0/1/2; two runs on two goal files coexist, a second start on the same goal (also by another path spelling) exits 1 naming the first; `resume` with one live run and no `MB_WORK_RUN_ID`, with two live runs → exit 2 and the list; `status` names items by path and first pending heading and marks `waiting_qa`.

**DoD:**
- [x] `next` follows the fifteen rules of design C3.3 and never prints `implement`, `repair` or a review action
- [x] `start`/`resume`/`phase`/`returned`/`status` behave as in design C3, state only in `<bank>/.drive/<run_id>.json`, several runs per bank on distinct goal files
- [x] `scripts/mb-drive.sh` ≤ 120 lines, both modules ≤ 300 lines, listed in the zone size contract (green)
- [x] tests pass (were red); shellcheck and ruff clean on touched files
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: Stop record and resume gate on the drive run files

**Stage:** 3
**Covers:** REQ-045, REQ-028, REQ-043, REQ-050
**Role:** developer
**Blocked-by:** 2
**Scope:** scripts/mb-drive-stop.sh, hooks/mb-drive-resume-gate.sh, references/hooks.md, tests/bats/test_drive_stop_gate.bats, tests/bats/test_mb_drive_stop.bats, tests/bats/test_mb_drive_resume_gate.bats
**Budget:** 55000
**Eval:** bats tests/bats/test_drive_stop_gate.bats tests/bats/test_mb_drive_stop.bats tests/bats/test_mb_drive_resume_gate.bats — red: bats file materialised, the stop record writes no run file and the resume gate still keys on MB_WORK_RUN_ID and ignores the hook session, so every named case drive_gate fails; exit: 1; output~: not ok [0-9]+ drive_gate:

**What to do:**
- `scripts/mb-drive-stop.sh` per design C4: `record [--run-id R]` selects the run like design C2 and calls `mb_drive_state.py stop` (phase `stopped`, `stop_reason`), then the fence and progress sinks; the vocabulary gains `human:stall`, `human:acceptance-red:<n>`, `human:flow-red:<checks>`, `human:qa-blocked:<reason>`, `human:qa-red`, `human:owned-elsewhere:<id>`; `state`/`path` print the run file. `arm` stays until Task 5 removes its last caller.
- `hooks/mb-drive-resume-gate.sh` per design C4: candidates are execution-phase run files; match on the hook input's `session_id`, else runs without a session; one candidate with an unmet goal (`--ticks-only` on its goal file) → block naming the run; several → allow with one stderr warning; the singleton slot, `MB_WORK_RUN_ID`, fence and work-state branches go; the header names the hosts that call it (Claude Code, Codex). `references/hooks.md` row updated.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_drive_stop_gate.bats`, every case named `drive_gate: …`: record writes phase `stopped` and the reason into the selected run file, the fence and one progress line; each new reason accepted, an unknown one exit 2; record without `--run-id` and two live runs → exit 2; the gate blocks in phase execution with an unmet goal for the run of its session and no `MB_WORK_RUN_ID`, allows for another session's run, allows with a warning when two sessionless runs are live, allows in planning, after a record, with a met goal, without run files, on `stop_hook_active`; a poisoned `check:` command and a poisoned firewall prove the gate runs neither.
- Rework `tests/bats/test_mb_drive_stop.bats` and `tests/bats/test_mb_drive_resume_gate.bats` to the run files; drop their singleton and cycle cases.

**DoD:**
- [x] a recorded stop is visible in the run file, the fence and `progress.md`
- [x] the gate decides from run files, the hook session and ticks only, never from the environment, a check or the firewall
- [x] tests pass (were red); shellcheck clean; touched files < 400 lines
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: Final QA fix cycle through ordinary work items

**Stage:** 3
**Covers:** REQ-032, REQ-053, REQ-054
**Role:** developer
**Blocked-by:** 2
**Scope:** scripts/mb_drive_qa.py, scripts/mb_drive_state.py, tests/pytest/test_mb_drive_final_qa.py, tests/pytest/test_s2_file_size_contract.py
**Budget:** 45000
**Eval:** python3 -m pytest -q tests/pytest/test_mb_drive_final_qa.py tests/pytest/test_s2_file_size_contract.py — red: test file materialised, a final QA with a blocking bug writes no fix plan and returned never sets final_qa red, so the final QA tests fail; exit: 1; output~: FAILED tests/pytest/test_mb_drive_final_qa.py

**What to do:**
- `scripts/mb_drive_qa.py` per design C3.6: the final QA run id and `@<topic>` selection of the run's plans; `mb-qa-bug.sh gate` on that run with `qa.gate`; blocking bugs grouped by the topic of their `- Scenario:` case path; one fix plan per topic (`topic:`, `qa: on`, `drive_run:`, one stage quoting each bug, the §5c2 regression-test-first instruction, one DoD line per bug naming `mb:case reg-bug-nnn` and `mb-qa-bug.sh set … fixed`); bugs without a case → a `qa: off — no case` plan; `qa.max_cycles` bound.
- `scripts/mb_drive_state.py`: the final-QA call site of `returned` calls the module; fix plans join `items` with `fix: true`, `final_qa` back to `pending`, or `red` past the bound. `tests/pytest/test_s2_file_size_contract.py`: list `scripts/mb_drive_qa.py` and the new test file.

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_mb_drive_final_qa.py` on a temp bank with a real `qa/bugs.md` written through `mb-qa-bug.sh add`: a major bug on `qa/test_cases/checkout/pay.md` → one fix plan with `topic: checkout`, `qa: on`, the bug id in its body and DoD, and `next` prints `work <fix plan>`; bugs on two topics → two plans; a medium bug alone → `final_qa: pass`; the fix plan closed → `final_qa` again; past `qa.max_cycles` → `stop_human qa-red`; selection lists only the run's topics.

**DoD:**
- [x] blocking final-QA bugs become fix plans executed by `/mb work`; drive adds no fix chain and no check
- [x] the cycle is bounded by `qa.max_cycles` and ends in `stop_human qa-red`
- [x] `scripts/mb_drive_qa.py` ≤ 150 lines, `scripts/mb_drive_state.py` ≤ 300 lines
- [x] tests pass (were red); ruff clean on touched files
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: Drive and goal commands, docs, and the last old callers

**Stage:** 3
**Covers:** REQ-020, REQ-041, REQ-033, REQ-046, REQ-050, REQ-029, REQ-052, REQ-055
**Role:** developer
**Blocked-by:** 2, 3, 4
**Scope:** commands/drive.md, commands/mb.md, adapters/_lib_agents_md.sh, scripts/mb-drive-preflight.sh, scripts/mb-drive-stop.sh, CHANGELOG.md, tests/bats/test_drive_command_contract.bats, tests/bats/test_mb_drive_command.bats, tests/pytest/test_audit_drive.py
**Budget:** 75000
**Eval:** bats tests/bats/test_drive_command_contract.bats tests/bats/test_mb_drive_command.bats — red: bats file materialised, drive.md still documents implement, repair and max cycles, resolves the bundle through dirname and calls the preflight script, so every named case drive_cmd fails; exit: 1; output~: not ok [0-9]+ drive_cmd:

**What to do:**
- `commands/drive.md` rewritten per design C5 §1–§8 (start/resume with several live runs; planning phase with tier routing, `/mb sdd --auto` + wrapper, QA target, links, one approval batch, `phase execution`; the execution action table with `--run-id`; executing `work` with per-run work slots, the plan path as claim key, resuming the item's own work run, exit 4 → `owned-elsewhere`, never `--takeover`; executing `team`, `wait` and `final_qa`; tokens, work run ids and `returned`; stop recording and the final report; hosts via `SKILL.md` § Invocation with `--host-serial`; resume and `--goal` for a second drive). One `<!-- mb-drive:start -->` fence calling `mb-drive.sh start`.
- `commands/mb.md` drive row and § drive, and the AGENTS.md drive line in `adapters/_lib_agents_md.sh`: the new flags and actions only; no `$(dirname "$0")`.
- Delete `scripts/mb-drive-preflight.sh` and remove `arm` from `scripts/mb-drive-stop.sh` (no callers left). One CHANGELOG line: drive plans then dispatches through `/mb work`/`/mb team`; several drives per bank with `--goal`; `--route/--phase/--max-cycles` removed; state in `.drive/<run_id>.json`.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_drive_command_contract.bats`, every case named `drive_cmd: …`, through the harness: the planning-phase clauses (tier routing, `--auto` spec, one approval batch, QA target question), the action table equals the actions `mb_drive_decide.py` can print, work under drive uses per-run slots, the plan path claim and never `--takeover`, team under drive uses `--no-goal` and `--source`, `--host-serial` notice, resume with several runs, `--goal`; no fence in drive.md, goal.md or mb.md contains `dirname "$0"` or `BANK=".memory-bank"`; every flag in the drive.md usage line is accepted by `mb-drive.sh start`; the `mb-drive:start` fence passes shellcheck.
- Rework `tests/bats/test_mb_drive_command.bats` (preflight fence → start fence; AGENTS.md line) and `tests/pytest/test_audit_drive.py` (start instead of the preflight).

**DoD:**
- [x] drive.md, mb.md and the AGENTS.md line describe exactly the flags and actions `mb-drive.sh` accepts and prints
- [x] no drive, goal or mb fence resolves the bundle through `dirname "$0"` or fixes the bank
- [x] `scripts/mb-drive-preflight.sh` and `arm` are gone with no remaining caller (`grep` proves it)
- [x] tests pass (were red); shellcheck clean on the start fence and touched scripts
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: Integration tests

**Stage:** 4
**Layer:** integration
**Covers:** REQ-019, REQ-020, REQ-039, REQ-021, REQ-022, REQ-033, REQ-040, REQ-041, REQ-023, REQ-024, REQ-042, REQ-043, REQ-025, REQ-044, REQ-026, REQ-027, REQ-028, REQ-029, REQ-045, REQ-051, REQ-052, REQ-046, REQ-047, REQ-030, REQ-031, REQ-032, REQ-053, REQ-054, REQ-048, REQ-055, REQ-056, REQ-049, REQ-050
**Role:** qa
**Scope:** tests/**
**Budget:** 100000

**What to do:**
- Integration tests over the real wiring; mock only external boundaries.
- Test function names follow the C4 mapping rule: `test_` + the scenario's `test_id` with `-` replaced by `_`.

**Testing (TDD — tests BEFORE implementation):**
- The success scenario plus the spec's main edge scenarios.

**DoD:**
- [x] Covers scenario test ids: `test_REQ_019__planning_gate_refuses_an_unlinked_goal`, `test_REQ_021__independent_items_go_to_team_and_dependent_ones_to_work`, `test_REQ_023__acceptance_counts_evidence_and_reports_unbacked_ticks`, `test_REQ_025__stalled_item_pivots_once_then_stops`, `test_REQ_026__token_usage_is_recorded_and_stops_the_run_early`, `test_REQ_028__resume_and_the_stop_gate_read_the_drive_file`, `test_REQ_030__blocked_qa_is_retried_deferred_and_reported`, `test_REQ_032__final_qa_and_the_firewall_gate_success`, `test_REQ_046__drive_commands_resolve_paths_and_match_the_scripts`, `test_REQ_053__final_qa_bugs_go_through_a_fix_plan`, `test_REQ_051__two_drives_in_one_bank_stay_apart`; green (were red)
- [x] External mocks ≤5 (Testing Trophy)
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: E2E tests

**Stage:** 4
**Layer:** e2e
**Covers:** REQ-019, REQ-020, REQ-039, REQ-021, REQ-022, REQ-033, REQ-040, REQ-041, REQ-023, REQ-024, REQ-042, REQ-043, REQ-025, REQ-044, REQ-026, REQ-027, REQ-028, REQ-029, REQ-045, REQ-051, REQ-052, REQ-046, REQ-047, REQ-030, REQ-031, REQ-032, REQ-053, REQ-054, REQ-048, REQ-055, REQ-056, REQ-049, REQ-050
**Role:** qa
**Scope:** tests/e2e/**
**Budget:** 100000

**What to do:**
- E2E tests over the real wiring; mock only external boundaries.
- Test function names follow the C4 mapping rule: `test_` + the scenario's `test_id` with `-` replaced by `_`.

**Testing (TDD — tests BEFORE implementation):**
- The success scenario plus the spec's main edge scenarios.

**DoD:**
- [x] Covers scenario test ids: `test_REQ_019__planning_gate_refuses_an_unlinked_goal`, `test_REQ_021__independent_items_go_to_team_and_dependent_ones_to_work`, `test_REQ_023__acceptance_counts_evidence_and_reports_unbacked_ticks`, `test_REQ_025__stalled_item_pivots_once_then_stops`, `test_REQ_026__token_usage_is_recorded_and_stops_the_run_early`, `test_REQ_028__resume_and_the_stop_gate_read_the_drive_file`, `test_REQ_030__blocked_qa_is_retried_deferred_and_reported`, `test_REQ_032__final_qa_and_the_firewall_gate_success`, `test_REQ_046__drive_commands_resolve_paths_and_match_the_scripts`, `test_REQ_053__final_qa_bugs_go_through_a_fix_plan`, `test_REQ_051__two_drives_in_one_bank_stay_apart`; green (were red)
- [x] External mocks ≤5 (Testing Trophy)
<!-- /mb-task:7 -->
