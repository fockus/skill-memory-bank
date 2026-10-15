---
topic: drive-autopilot
created: 2026-10-15
status: ready
group: "[SPEC:autopilot]"
child_specs: [planning-qa-sources, team-completion, drive-autopilot]
agreements: [AGR-097, AGR-099, AGR-101, AGR-102]
estimated_tokens:
  total: 386000
  breakdown:
    shell_scripts: {count: 3, unit_tokens: 15000, subtotal: 45000}
    prompt_changes: {count: 12, unit_tokens: 8000, subtotal: 96000}
    python_modules: {count: 3, unit_tokens: 25000, subtotal: 75000}
    test_files: {count: 15, unit_tokens: 10000, subtotal: 150000}
    docs_pages: {count: 4, unit_tokens: 5000, subtotal: 20000}
    external_integrations: {count: 0, unit_tokens: 30000, subtotal: 0}
interview_transcript: context/drive-autopilot-interview.md
---

# Context: drive-autopilot

`/mb drive` becomes the full-automation mode of Memory Bank (AGR-099): the user plans everything up front together
with drive, then the pipeline moves on its own. Drive decides what to do, `/mb work` executes items, `/mb team`
runs independent items in parallel. Along the way plans and specs get a QA stage by default (AGR-101), verifier,
reviewer and judge see both plan and spec, and `/mb team` is finished (I-275..I-280).

## Purpose & Users

Users: the owner and anyone driving a multi-plan goal with this skill on Claude Code, Codex, OpenCode or Pi.
Problem: drive runs its own simplified implement→review→judge chain that bypasses `/mb work` (verify, eval gate,
QA, closure), loops `implement` without bound, accepts the goal on checkboxes ticked by the same model, never
counts budget, and loses its run id between shell calls; team deadlocks on a cancelled dependency and waits
silently on a red goal. Success: after one planning session the user leaves, and drive brings the goal to
`stop_success` through work/team with verified, QA-checked results — or stops with a short report and one
concrete question.

## Research Digest

- drive is a stateless decision function: `mb-drive.sh next` prints one action per call (`commands/drive.md:90-127`).
- drive dispatches implement itself, then review→judge; `/mb work` is not used (`commands/drive.md:118-119`, I-265).
- rule 7 re-emits `implement` while acceptance <100% and the firewall is green (`scripts/mb-drive.sh:189-197`, I-266).
- acceptance counts `[x]` in goal.md ticked by the working model (`commands/drive.md:153-160`, I-267).
- drive never calls `mb-work-budget.sh add`, `stop_budget` is unreachable (I-268); stall/pivot inputs hard-coded (`mb-drive.sh:338-340,375`, I-269).
- run id lives in env `MB_WORK_RUN_ID`, not persisted across Bash calls (`commands/drive.md:162-172`, I-272).
- goal.md already has `linked_plans` and `progress_source` (`.memory-bank/goal.md:1-9`).
- team `next` loop: dispatch → verify → review → collect → team review → stop_success (`scripts/mb_team_status.py:140-176`).
- team: cancelled dep never counts as finished (`mb_team_status.py:153`, I-275); all done + red goal/flow → `wait` (`:171-173`, I-276); STATUS read from the first report line only (`:180-185`, I-278).
- standard team track = implementer with TDD + plan-verifier (AGR-097).
- `/mb work` QA loop inside verify, cadence stage|plan|run, position before/after review (AGR-098, `commands/work.md` §5c2).
- plan-verifier receives one source, plan or spec (`agents/plan-verifier.md:42-46`); reviewer gets "plan/spec path" (`agents/mb-reviewer.md:58`).
- plan-as-wrapper with `linked_spec:` already exists (`commands/plan.md` § Plan as execution wrapper).
- `mb-flow-verify.sh` is the stop_success firewall of drive and team and already gates open critical/major QA bugs.
- lightweight mode: one verifier per plan (AGR-075), stages only at real boundaries (AGR-078).
- `specs/quality-track` (0/62 tasks done) designed a different QA contract at `specs/<topic>/qa.md` — see Open Questions.

## Decision Log

- **D-01** Drive starts from `goal.md`. An item with a plan/spec goes to `/mb work`; an item without one is planned by drive itself (`/mb plan`, or `/mb sdd --self` for large), assumptions recorded. Rejected: execute-only (planning stays manual); fully autonomous discuss→sdd→plan with review at the end.
- **D-02** "Large" is the effort tier scale (`references/effort-tiers.md`): trivial..standard planned and run without a stop; large/extra get a self-interviewed spec that the user approves. Rejected: stop on every new plan; never stop.
- **D-03** Parallelism is mechanical: ≥2 ready independent items (no deps, disjoint `Files:`) → `/mb team`; one → `/mb work`. Every team track executes through `/mb work`. Off via `--serial` or `drive.parallel: false`. Rejected: model decides; team only with `--team`.
- **D-04** Drive has two phases: planning (with the user: all plans/specs, large-spec approval in one batch, QA cases, QA target) and execution (no human; stops only on hard failures). After a spec drive writes a plan-as-wrapper telling the model how to execute it.
- **D-05** QA cases are written by `mb-qa` right after plan/sdd, from requirements and DoD (not code), into `qa/test_cases/<topic>/` tagged `@<topic>`, each with `covers: REQ-…`. The implementer never edits them. Plan cadence runs `@<topic>`; run cadence runs all. `qa.cadence: run` defers all QA to the end; drive runs a final QA before `stop_success`. Rejected: planner writes cases itself; cases written after execution.
- **D-06** Verifier, reviewer and judge get one source bundle: spec (requirements/design/tasks), plan wrapper, last QA report; `mb-work-plan.sh` emits `spec_path` and `plan_path` per item. Verifier reports per plan (DoD) and per spec (REQ coverage via tasks and `covers:`, Eval); plan↔spec divergence is critical. Rejected: paths only, agent chooses what to read.
- **D-07** Goal acceptance comes from evidence: each criterion links its plans/specs in the planning phase; it is met when they are closed (in `done/`, verifier PASS, `@<topic>` QA gate green) or its `check: <cmd>` exits 0. `mb-goal-acceptance.sh` ticks `[x]`; an unbacked manual tick does not count and is reported. Rejected: manual ticks verified by plan-verifier before stop.
- **D-08** Item cycles belong to `/mb work` (`max_cycles`, `on_max_cycles`); drive's goal-wide counter goes. Drive watches stall (a work/team run ended and acceptance did not grow): first stall or work `stop_for_human` → one automatic pivot via `mb-architect` (re-plan/ADaPT split); second stall on the same item → `stop_human stall`. Work and team record real tokens with `mb-work-budget.sh add` under drive's run id; `stop_budget` fires when the average step cost exceeds the remainder. Rejected: stop on first stall.
- **D-09** Team: a cancelled dependency → dependents `blocked:dep-cancelled:<id>` → `stop_human`; all done with red goal/flow → `stop_human goal-red|flow-red:<check>` (under drive, team just ends and drive checks the goal); `stop_human` is the only action when present; plus fixes I-278 (STATUS from the last line), I-279 (m1, m2, m3, m6), I-280 (Codex/OpenCode/Pi dispatch, index rollback after a failed commit). Under drive any team `stop_human` is a stall. Rejected: auto-cancel dependents and continue.
- **D-10** Drive state lives in `<bank>/.drive/current.json` (run id, bank, phase, parallel mode), read by every `mb-drive.sh` call and the resume gate; `/mb drive --resume` continues at the stored phase. Skill/bank paths resolve like the other commands (`MB_SKILLS_ROOT` → `SKILL_DIR` → `mb_resolve_path`). Hosts: Claude Code, Codex, OpenCode, Pi through the `/mb work` dispatch adapter table; a host without parallel subagents falls back to serial work with a one-line notice. Rejected: Claude Code and Codex first.
- **D-11** Three specs in group `[SPEC:autopilot]`: S1 `planning-qa-sources` (D-04 wrapper, D-05, D-06, D-12) and S2 `team-completion` (D-03 track via work, D-09) in parallel, then S3 `drive-autopilot` (D-01..D-04, D-07, D-08, D-10, D-13; I-265..I-274). The split follows dependency and parallel boundaries, not size: the rubric estimate is ~386k tokens. Rejected: one spec.
- **D-12** QA default by tier (AGR-101): small off (`--qa` turns it on); standard on with one case per key user path, one test-case dispatch and one QA run per plan; large/extra one case per testable REQ. Disable: `--no-qa`, a prompt phrase, `qa.enabled: false`; without `qa/README.md` the plan marks QA `off — no QA target` (in drive this is asked in the planning phase). Rejected: on for every tier.
- **D-13** QA blocked by the environment under drive: retry once → defer that plan's QA (`deferred`) and continue → retry deferred QA at the end → still blocked → final report (done / not verified) + `stop_human qa-blocked:<reason>` with a question; the rest of the work counts as done and dependent criteria are marked "waiting for QA". No pivot. Standalone `/mb work` keeps halting on BLOCKED. Rejected: stop at the first failure.

- **D-14** One proof chain for both QA systems (AGR-102): REQ/DoD → case in `qa/test_cases/<topic>/<id>.md` (one catalog: `id`, `covers`, `origin: specified|derived|regression`, `proof: live|test|both`, `status: needs_spec` when the expected result cannot be derived) → proof by the live runner or by an automated test carrying an `mb:case <id>` comment → findings through the one severity gate → verifier coverage table. Live QA finds, white-box locks: a fixed critical/major bug gets a `regression` case and its regression test carries `mb:case <id>`. S1 ships the schema, `needs_spec`, regression cases, the marker convention and the coverage table; parsers, manifests, freshness, waivers, semantic audit and generation stay in parked `quality-track`. Rejected: supersede quality-track (B); full rewrite now (A).

## Functional Requirements (EARS)

Planning and QA cases (S1):

- **REQ-001** (event-driven): When `/mb plan` or `/mb sdd` creates a plan or spec of tier standard or higher and QA is not disabled, the system shall add a QA item to the DoD and a test-case authoring stage.
- **REQ-002** (event-driven): When a plan or spec of tier small is created without `--qa`, the system shall leave QA off.
- **REQ-003** (event-driven): When `--no-qa`, a prompt request to skip QA, or `qa.enabled: false` is present, the system shall create the plan or spec without the QA item and stage.
- **REQ-004** (event-driven): When the test-case authoring stage runs, the system shall dispatch `mb-qa` to write cases from the requirements and DoD into `qa/test_cases/<topic>/`, each tagged `@<topic>` and carrying `covers: <REQ ids>`.
- **REQ-005** (state-driven): While the tier is standard, the system shall require one case per key user path; while the tier is large or extra, the system shall require one case per externally testable REQ.
- **REQ-006** (unwanted): If `<bank>/qa/README.md` is absent when QA would be enabled, then the system shall mark the plan's QA as `off — no QA target` instead of failing.
- **REQ-007** (event-driven): When `/mb sdd` finishes a spec that will be executed, the system shall offer or create a plan-as-wrapper with `linked_spec` that states how to execute the spec.

Source bundle (S1):

- **REQ-008** (ubiquitous): The system shall emit `spec_path` and `plan_path` for every work item in `mb-work-plan.sh` output when those artifacts exist.
- **REQ-009** (event-driven): When the verifier, reviewer or judge is dispatched, the system shall pass the spec, the plan wrapper and the last QA report of the item.
- **REQ-010** (event-driven): When the verifier checks an item that has both a plan and a spec, the system shall report plan DoD coverage and spec REQ coverage separately.
- **REQ-011** (unwanted): If the plan and the spec diverge (a REQ not covered by the plan, or plan work outside the spec), then the system shall report a critical finding.

- **REQ-034** (ubiquitous): The system shall give every QA case frontmatter fields `id`, `covers`, `origin` (specified, derived or regression) and `proof` (live, test or both).
- **REQ-035** (unwanted): If the expected result of a case cannot be derived from the requirements or DoD, then the system shall mark the case `needs_spec` instead of inventing assertions.
- **REQ-036** (event-driven): When a critical or major QA bug is fixed, the system shall add a case with `origin: regression` and require the regression test to carry an `mb:case <id>` comment.
- **REQ-037** (event-driven): When the verifier checks an item with QA cases, the system shall report, per REQ, its cases and their proof: live PASS, a test carrying `mb:case`, or none.
- **REQ-038** (unwanted): If an item has no requirement, DoD item or case to verify, then the system shall report "nothing to verify" instead of PASS.

Team completion (S2):

- **REQ-012** (ubiquitous): The system shall execute every team track through the `/mb work` per-item loop.
- **REQ-013** (unwanted): If a track dependency is cancelled, then the system shall mark the dependent tracks `blocked:dep-cancelled:<id>` and emit `stop_human`.
- **REQ-014** (unwanted): If every track is finished and collected while the goal or flow check is red, then the system shall emit `stop_human goal-red` or `stop_human flow-red:<check>` instead of `wait`.
- **REQ-015** (event-driven): When `team next` produces a `stop_human` action, the system shall print it as the only action.
- **REQ-016** (ubiquitous): The system shall read a track report's STATUS from its last STATUS line.
- **REQ-017** (unwanted): If `git commit` fails after `team commit` staged files, then the system shall restore the index to its previous state.
- **REQ-018** (ubiquitous): The system shall dispatch team tracks on Claude Code, Codex, OpenCode and Pi through the shared dispatch adapter table.

Drive (S3):

- **REQ-019** (event-driven): When `/mb drive` starts on a goal, the system shall run a planning phase that gives every acceptance criterion linked plans or specs or a `check:` command before any execution starts.
- **REQ-020** (state-driven): While in the planning phase, the system shall plan trivial to standard items itself and collect the approval of every large or extra spec in one batch.
- **REQ-021** (state-driven): While in the execution phase, the system shall dispatch ready items through `/mb team` when two or more are independent and through `/mb work` otherwise.
- **REQ-022** (where): Where `--serial` or `drive.parallel: false` is set, the system shall execute items through `/mb work` only.
- **REQ-023** (ubiquitous): The system shall compute goal acceptance only from evidence: closed linked plans or specs with a verifier PASS and a green QA gate, or a `check:` command exiting 0.
- **REQ-024** (unwanted): If an acceptance checkbox is ticked without evidence, then the system shall not count it and shall list it in the report.
- **REQ-025** (unwanted): If a work or team run ends without an acceptance increase, then the system shall pivot that item once via `mb-architect` and stop with `stop_human stall` on the second stall.
- **REQ-026** (event-driven): When a work or team dispatch returns, the system shall add its token usage to the drive run budget.
- **REQ-027** (unwanted): If the average step cost exceeds the remaining budget, then the system shall stop with `stop_budget`.
- **REQ-028** (ubiquitous): The system shall persist the drive run id, bank, phase and parallel mode in `<bank>/.drive/current.json`.
- **REQ-029** (event-driven): When `/mb drive --resume` runs, the system shall continue from the phase stored in `<bank>/.drive/current.json`.
- **REQ-030** (unwanted): If QA is blocked by the environment during drive, then the system shall retry once, defer that plan's QA, continue the remaining items, and retry the deferred QA after all other work.
- **REQ-031** (unwanted): If deferred QA is still blocked at the end, then the system shall write the final report and stop with `stop_human qa-blocked:<reason>`, keeping the other work counted as done.
- **REQ-032** (event-driven): When all acceptance criteria are met, the system shall run the final QA before `stop_success`.
- **REQ-033** (where): Where the host cannot run parallel subagents, the system shall execute serially through `/mb work` and report the fallback in one line.

## Non-Functional Requirements

- **NFR-001**: Lightweight mode stays: one verifier per plan by default (AGR-075), stages only at real boundaries (AGR-078); drive and team add no verification of their own on top of `/mb work`. The S1–S3 specs are cut into coarse tasks.
- **NFR-002**: Default QA cost for a standard plan is at most two extra dispatches (test-case authoring + one QA run).
- **NFR-003**: Resolver output stays byte-identical when the new options are off (same discipline as AGR-098).
- **NFR-004**: Touched scripts and commands keep the 400-line zone contract; `mb-drive.sh` (463) is split.

## Constraints

- Hosts: Claude Code, Codex, OpenCode, Pi; dispatch adapters shared with `commands/work.md`.
- No new dependencies; bash + python stdlib as today.
- Everything written to the repo is in English (AGR-085).
- No auto-commit or push without the user's explicit permission.

## Edge Cases & Failure Modes

- Team tracks overlap despite `Files:` and a commit fails → `stop_human claim:<id>`; under drive a stall and pivot.
- The user edits code while drive runs → `COORDINATION.md` and scoped commits; drive touches only its items' `Files:`.
- A large spec is not yet approved while other items are ready → impossible in execution: approvals are collected in the planning phase.
- A QA case contradicts the spec → only the test-case stage edits cases; execution stops with `stop_human qa-case-invalid`.
- Environment down for QA → D-13 (retry, defer, retry at the end, report + `stop_human qa-blocked`).
- Session killed or compacted mid-run → `/mb drive --resume` from `.drive/current.json`.

## Out of Scope

- UI or dashboard for drive.
- Hosts beyond Claude Code, Codex, OpenCode, Pi.
- Changes to `/mb work` presets other than the QA default.
- Auto-commit or push without permission.

## Open Questions

- none — the quality-track question is resolved by D-14 / AGR-102.
