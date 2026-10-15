---
type: spec-requirements
topic: drive-autopilot
status: ready
created: 2026-10-15
group: "[SPEC:autopilot]"
parent_context: context/drive-autopilot.md
interview_transcript: context/drive-autopilot-interview.md
linked_design: design.md
depends_on_specs: [planning-qa-sources, team-completion]
backlog: [I-283, I-265, I-266, I-267, I-268, I-269, I-270, I-271, I-272, I-273, I-274]
covers_umbrella: [REQ-019, REQ-020, REQ-021, REQ-022, REQ-023, REQ-024, REQ-025, REQ-026, REQ-027, REQ-028, REQ-029, REQ-030, REQ-031, REQ-032, REQ-033]
layers:
  contract_first: false
  contract_first_reason: orchestration over existing work and team contracts
  integration_tests: true
  e2e_tests: true
---

# Requirements: drive-autopilot

> Spec triple — see also: design.md, tasks.md.
> Slice S3 of group `[SPEC:autopilot]` (backlog I-283). Source: `context/drive-autopilot.md` decisions
> D-01, D-02, D-03 (drive side), D-04, D-07, D-08, D-10, D-13 and NFR-001, NFR-004, i.e. context
> REQ-019..REQ-033, plus the drive review findings I-265..I-274; agreements AGR-099, AGR-101, AGR-103, AGR-104.
> Builds on S1 `planning-qa-sources` (plan `qa:` declaration, test-case authoring, spec wrapper, source
> bundle) and S2 `team-completion` (every track through `/mb work`, team stops, `--no-goal` interplay);
> it does not re-specify them.
> REQ ids follow `mb-req-next-id.sh --spec drive-autopilot`: this spec shares the namespace of
> `context/drive-autopilot.md`, so the fifteen context requirements keep their ids (REQ-019..REQ-033) and
> requirements added here start at REQ-039 (REQ-051..REQ-056 follow the 2026-10-15 user decisions on the final-QA
> fix cycle and several drives per bank). Every requirement names its source.
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

### Requirement 1: Everything is planned with the user before execution starts

**User Story:** As a user handing a goal to drive, I want one planning session in which every acceptance
criterion gets its plans, specs, QA decision or check, so that I can leave and the pipeline never stops
later to ask about something it could have asked up front.

Source: context REQ-019, REQ-020 · D-01, D-02, D-04, D-07, D-12 · AGR-099, AGR-101.

#### Acceptance Criteria

- **REQ-019** (event-driven): WHEN `/mb drive` starts on a goal with no stored drive run, THE SYSTEM SHALL open the planning phase and SHALL refuse to enter the execution phase until every acceptance criterion carries at least one resolvable `plan:` link or `check:` command. Source: context REQ-019 · D-01, D-07.
- **REQ-020** (state-driven): WHILE in the planning phase, THE SYSTEM SHALL plan trivial to standard items itself with `/mb plan --tier <tier>`, write large and extra items as specs with `/mb sdd --auto` and a plan wrapper, and collect the user's approval of all those specs in one batch. Source: context REQ-020 · D-02, D-04.
- **REQ-039** (unwanted): IF a linked plan carries no `qa:` declaration, or a linked wrapper's spec is neither `status: ready` nor approved in the planning batch, THEN THE SYSTEM SHALL refuse the execution phase and name each such plan. Source: D-02, D-04, D-12 · S1 REQ-001..REQ-004.

### Requirement 2: Execution goes through /mb work and /mb team only

**User Story:** As the user who left drive running, I want drive to decide what runs next and leave the running to
`/mb work` and `/mb team`, so that every item passes the same verify, eval, QA and closure gates as a hand-run item
and drive never loops on its own thinner chain.

Source: context REQ-021, REQ-022, REQ-033 · D-03, D-10 · NFR-001 · I-265, I-266 · S2 drive interplay.

#### Acceptance Criteria

- **REQ-021** (state-driven): WHILE in the execution phase, THE SYSTEM SHALL print `team <item> <item>…` when two or more ready items have no dependency between them and disjoint declared files, and `work <item>` when only one is ready. Source: context REQ-021 · D-03.
- **REQ-022** (optional feature): WHERE `--serial` or `drive.parallel: false` is set, THE SYSTEM SHALL print only `work <item>` dispatch actions. Source: context REQ-022 · D-03.
- **REQ-033** (optional feature): WHERE the host cannot run parallel subagents, THE SYSTEM SHALL record the run as serial with reason `host` and print one notice line saying so. Source: context REQ-033 · D-10.
- **REQ-040** (ubiquitous): THE SYSTEM SHALL emit no `implement`, `repair`, review or judge action of its own and SHALL keep no item cycle counter, leaving item cycles to `/mb work`. Source: I-265, I-266, I-270 · D-08 · NFR-001.
- **REQ-041** (event-driven): WHEN drive dispatches a `team` action, THE SYSTEM SHALL start the team with `--no-goal` and one track per item whose source is the item's plan path and whose files are the item's declared files. Source: D-03 · S2 design "Drive interplay".

### Requirement 3: Acceptance comes from evidence only

**User Story:** As the owner of the goal, I want a criterion to count as met only when its linked work is closed or
its check passes, so that a checkbox ticked by the working model can never end the run.

Source: context REQ-023, REQ-024 · D-07 · I-267.

#### Acceptance Criteria

- **REQ-023** (ubiquitous): THE SYSTEM SHALL count a linked criterion as met only when every linked plan has all of its work items done and every linked `check:` command exits 0. Source: context REQ-023 · D-07.
- **REQ-024** (unwanted): IF a linked criterion is ticked `[x]` without that evidence, THEN THE SYSTEM SHALL not count it and SHALL list it as unbacked in the acceptance output and in the drive report. Source: context REQ-024 · I-267.
- **REQ-042** (event-driven): WHEN drive records a returned run, THE SYSTEM SHALL set every linked criterion's checkbox in `goal.md` to its evidence result. Source: D-07.
- **REQ-043** (ubiquitous): THE SYSTEM SHALL keep the acceptance output of a goal without any links byte-identical to checkbox counting, and SHALL let the drive resume gate read checkboxes only, without running any `check:` command. Source: NFR-003 discipline · resume-gate cost contract (I-131).

### Requirement 4: Stalls, pivots and budget are real

**User Story:** As the user paying for the run, I want drive to notice an item that does not move, try one change of
approach and then stop, and to stop before the budget runs out, so that an autonomous run cannot burn tokens in a
loop.

Source: context REQ-025, REQ-026, REQ-027 · D-08, D-09 · I-268, I-269.

#### Acceptance Criteria

- **REQ-025** (unwanted): IF a work or team run of an item returns without that item closing, THEN THE SYSTEM SHALL print `pivot <item>` after the first such stall and `stop_human stall` after the second stall of the same item. Source: context REQ-025 · D-08.
- **REQ-044** (unwanted): IF a work or team run ends with a `stop_human`, THEN THE SYSTEM SHALL count it as a stall of every item of that run that did not close. Source: D-08, D-09.
- **REQ-026** (event-driven): WHEN a work, team or QA run returns, THE SYSTEM SHALL add its reported token usage with `mb-work-budget.sh add` under the drive run id. Source: context REQ-026 · I-268.
- **REQ-027** (unwanted): IF the drive budget is exceeded, or the average token cost of a returned run exceeds the remaining budget, THEN THE SYSTEM SHALL print `stop_budget`. Source: context REQ-027 · I-268.

### Requirement 5: Drive state survives the session

**User Story:** As a user whose session was compacted or killed, or who runs several drives in one bank, I want each
drive to keep its run, goal, bank, phase and mode in its own file, so that `/mb drive --resume` and the Stop hook find
the right run without any environment variable.

Source: context REQ-028, REQ-029 · D-10 · I-271, I-272, I-273 · REQ-DR-034 · user decision 2026-10-15 (several drives per bank).

#### Acceptance Criteria

- **REQ-028** (ubiquitous): THE SYSTEM SHALL persist each drive run's id, goal path, bank, phase, parallel mode, owner session id when the host gives one, and per-item stall and QA records in `<bank>/.drive/<run_id>.json`, and read them on every `mb-drive.sh` call. Source: context REQ-028 · REQ-DR-034 · user decision 2026-10-15.
- **REQ-029** (event-driven): WHEN `/mb drive --resume [<run_id>]` runs, THE SYSTEM SHALL continue the named run, or the only live run when no id is given, at its stored phase, and SHALL list the live runs and exit 2 when several are live and no id is given (run selection, design C2). Source: context REQ-029 · user decision 2026-10-15.
- **REQ-045** (event-driven): WHEN the drive resume gate runs, THE SYSTEM SHALL check the execution-phase runs owned by the hook's session, or the single execution-phase run when the host gives no session or no run is owned, block a stop while that run's goal is not met, and allow the stop with a warning when several runs qualify. Source: I-272 · user decision 2026-10-15.
- **REQ-051** (unwanted): IF `/mb drive` starts on a goal file that a live drive run already drives, THEN THE SYSTEM SHALL refuse with a message naming that run and the `--resume <run_id>` and `--goal <path>` ways out. Source: user decision 2026-10-15.
- **REQ-052** (optional feature): WHERE `--goal <path>` is given, THE SYSTEM SHALL drive that goal file instead of `<bank>/goal.md`, validate and measure acceptance on it, and run the firewall without its bank-goal acceptance check. Source: user decision 2026-10-15.
- **REQ-046** (ubiquitous): THE SYSTEM SHALL resolve the skill bundle in the drive and goal commands through `MB_SKILLS_ROOT`, then `SKILL_DIR`, then the default install path, and the bank through `mb_resolve_path`, never through `$(dirname "$0")/..` or a fixed `.memory-bank`. Source: I-273.
- **REQ-047** (ubiquitous): THE SYSTEM SHALL name every item in drive actions and status by its plan path, and in status also by the heading of its first pending work item. Source: I-271.

### Requirement 6: QA under drive

**User Story:** As the user who left drive running, I want QA that is blocked by the environment to be retried and
postponed instead of stopping everything, and one final QA before success, so that the run finishes all the work it
can and tells me exactly what was not verified.

Source: context REQ-030, REQ-031, REQ-032 · D-05, D-13.

#### Acceptance Criteria

- **REQ-030** (unwanted): IF a run reports QA blocked by the environment, THEN THE SYSTEM SHALL dispatch the item once more, then defer that item's QA, continue the remaining items, and print `qa <item>` once for each deferred item after all other items are closed. Source: context REQ-030 · D-13.
- **REQ-031** (unwanted): IF a deferred QA is still blocked after its final retry, THEN THE SYSTEM SHALL print `stop_human qa-blocked:<reason>`, keep the other closed items counted, and mark the criteria that link the deferred item as waiting for QA in the status. Source: context REQ-031 · D-13.
- **REQ-032** (event-driven): WHEN every criterion is met and a linked plan declares `qa: on`, THE SYSTEM SHALL print `final_qa` before any `stop_success`, selecting the QA cases tagged with the topics of the run's own plans. Source: context REQ-032 · D-05.
- **REQ-053** (unwanted): IF the final QA leaves bugs that fail `qa.gate`, THEN THE SYSTEM SHALL write one fix plan with `qa: on` per owning case topic, dispatch it through `/mb work` like any other item, and run the final QA again, at most `qa.max_cycles` times. Source: user decision 2026-10-15 · `/mb work` §5c2.
- **REQ-054** (unwanted): IF the final QA still fails `qa.gate` after `qa.max_cycles` fix cycles, THEN THE SYSTEM SHALL write the final report and print `stop_human qa-red`. Source: user decision 2026-10-15.
- **REQ-048** (event-driven): WHEN every criterion is met and the final QA has passed or does not apply, THE SYSTEM SHALL run `mb-flow-verify.sh --skip acceptance` once and print `stop_success` on exit 0, `stop_human flow-red:<checks>` on exit 1 and `stop_human check-broke:<check>` on exit 2. Source: REQ-DR-014 (drive-loop) · D-09 symmetry · NFR-001.

### Requirement 7: Several drives share one bank without fighting

**User Story:** As a user running two drives in one bank, I want an item that another live run is working on to be
left alone and retried later, so that two drives never steal each other's claims and neither counts the other's
work as its own stall.

Source: user decision 2026-10-15 · `commands/work.md` step 4 claim rule (exit 4, no `--takeover` of a live worker) · S2 C2.

#### Acceptance Criteria

- **REQ-055** (unwanted): IF an item's plan is claimed by a live `/mb work` run that this drive run did not record, THEN THE SYSTEM SHALL treat the item as owned elsewhere, skip it without counting a stall, never pass `--takeover`, and print `wait <item>…` when no other item is ready. Source: user decision 2026-10-15.
- **REQ-056** (unwanted): IF three waits in a row pass with only owned-elsewhere items left, THEN THE SYSTEM SHALL print `stop_human owned-elsewhere:<work run id>`. Source: user decision 2026-10-15 (bounded retry).

### Requirement 8: The drive surface is small and documented as it runs

**User Story:** As a maintainer, I want the drive scripts to stay within the size contract and the drive, goal and
mb command docs and the AGENTS.md block to describe exactly the flags and actions the scripts accept, so that a
host agent follows the real loop and not a stale one.

Source: NFR-004 · I-274.

#### Acceptance Criteria

- **REQ-049** (ubiquitous): THE SYSTEM SHALL keep `scripts/mb-drive.sh` and every drive script and module under 400 lines and list them in the zone size contract. Source: NFR-004 · I-274.
- **REQ-050** (ubiquitous): THE SYSTEM SHALL document in `commands/drive.md`, `commands/mb.md` and the AGENTS.md drive line only the flags and actions that `mb-drive.sh` accepts and prints, and in the resume gate the hosts that actually call it. Source: I-274.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Planning gate refuses an unlinked goal
**Covers:** REQ-019, REQ-020, REQ-039

- GIVEN a started drive in the planning phase on a goal with three criteria, one without any link
- WHEN `mb-drive.sh phase execution` runs
- THEN it exits 1, names the unlinked criterion, and the stored phase stays planning
- AND after the criterion links a plan with `qa: on` and a wrapper whose spec is approved with `--approve`, the same call exits 0 and the stored phase is execution
- AND a linked plan without a `qa:` line is refused by name
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Independent items go to team and dependent ones to work
**Covers:** REQ-021, REQ-022, REQ-033, REQ-040, REQ-041

- GIVEN an execution-phase drive whose goal links plans A and B with disjoint files and plan C that depends on A
- WHEN `mb-drive.sh next` runs
- THEN it prints `team <A path> <B path>` and never `implement`, `repair` or a review action
- AND after A and B close it prints `work <C path>`
- AND a drive started with `--serial`, with `drive.parallel: false`, or with `--host-serial` prints `work <A path>` first, and the host case printed one notice line at start
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Acceptance counts evidence and reports unbacked ticks
**Covers:** REQ-023, REQ-024, REQ-042, REQ-043

- GIVEN a goal whose first criterion is ticked by hand and links a plan with a pending item, and whose second criterion links `check: true`
- WHEN `mb-goal-acceptance.sh` runs
- THEN `ok` is false, the first criterion is listed under `unbacked`, and the second counts as met
- AND `--tick` unticks the first and ticks the second in `goal.md`
- AND `--ticks-only` runs no check command, and a goal without links gives the same bytes as before this change
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Stalled item pivots once then stops
**Covers:** REQ-025, REQ-044, REQ-040

- GIVEN an execution-phase drive with one linked plan that has a pending item
- WHEN `mb-drive.sh returned` records a work run of that plan that ended with `stop_human claim:1` and the plan is still open
- THEN `next` prints `pivot <plan path>`
- AND after the pivot is recorded and a second run returns with the plan still open, `next` prints `stop_human stall`
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Token usage is recorded and stops the run early
**Covers:** REQ-026, REQ-027

- GIVEN a drive started with `--budget 100000`
- WHEN two runs return with 40000 tokens each
- THEN `mb-work-budget.sh status` under the drive run id shows 80000 spent
- AND `next` prints `stop_budget`, because the average run cost of 40000 exceeds the remaining 20000
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Resume and the stop gate read the drive file
**Covers:** REQ-028, REQ-029, REQ-045, REQ-047

- GIVEN a drive run R1 in the execution phase recorded in `<bank>/.drive/R1.json` with session S1, and no `MB_WORK_RUN_ID` in the environment
- WHEN `mb-drive.sh resume` runs and then the resume gate receives a Stop event with session S1 while R1's goal is unmet
- THEN resume prints run id R1 and phase execution, and the gate blocks the stop
- AND with a second live run R2 started on another goal, `resume` without an id lists R1 and R2 and exits 2, and a Stop event with no session id is allowed with a warning
- AND after `mb-drive-stop.sh record --run-id R1 --action stop_human\ stall` a Stop event with session S1 is allowed
- AND `mb-drive.sh status --run-id R1` lists every linked item by plan path with the heading of its first pending item
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Blocked QA is retried deferred and reported
**Covers:** REQ-030, REQ-031

- GIVEN an execution-phase drive with plans A and B where A's runs report QA blocked by the environment
- WHEN A returns `qa-blocked:no-browser` twice while B is open
- THEN `next` prints `work <A path>` after the first return and `work <B path>` after the second
- AND once B is closed `next` prints `qa <A path>`, and after one more blocked return `stop_human qa-blocked:no-browser`
- AND `mb-drive.sh status` marks the criterion that links A as waiting for QA
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Final QA and the firewall gate success
**Covers:** REQ-032, REQ-048, REQ-052

- GIVEN an execution-phase drive whose linked plans are all closed and one of them declares `qa: on`
- WHEN `next` runs
- THEN it prints `final_qa`, and after a passed final QA is recorded it runs the firewall once with `--skip acceptance`
- AND the firewall exit 0 gives `stop_success`, exit 1 with a red `tests` check gives `stop_human flow-red:tests`, exit 2 gives `stop_human check-broke:<check>`
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Drive commands resolve paths and match the scripts
**Covers:** REQ-046, REQ-049, REQ-050

- GIVEN the installed `/mb drive` and `/mb goal` commands and the drive scripts
- WHEN their bash fences and the AGENTS.md drive line are checked
- THEN no fence resolves the skill through `$(dirname "$0")` or sets `BANK=.memory-bank`, and every documented flag and action is accepted or printed by `mb-drive.sh`
- AND every drive script and module is under 400 lines and listed in the zone size contract
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Final QA bugs go through a fix plan
**Covers:** REQ-053, REQ-054

- GIVEN an execution-phase drive with `qa.max_cycles: 2` whose final QA run leaves an open major bug on a case under `qa/test_cases/checkout/`
- WHEN `returned` records the final QA
- THEN a fix plan with `topic: checkout` and `qa: on` naming the bug exists, and `next` prints `work <fix plan path>`
- AND after the fix plan closes `next` prints `final_qa` again
- AND when the final QA after the second fix cycle still leaves a blocking bug, `next` prints `stop_human qa-red`
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Two drives in one bank stay apart
**Covers:** REQ-051, REQ-052, REQ-055, REQ-056

- GIVEN a live drive run R1 on `<bank>/goal.md` that links plan P
- WHEN a second `mb-drive.sh start` runs on the same goal, and then with `--goal <bank>/goals/second.md` that also links P while a live work run not recorded by R2 claims P
- THEN the first start exits 1 naming R1, and the second start succeeds as R2
- AND R2's `next` prints `wait <P path>` and counts no stall, and after three recorded waits prints `stop_human owned-elsewhere:<work run id>`
<!-- /mb-scenario:11 -->

## Non-Functional Requirements

- **NFR-001** (context NFR-001): lightweight mode stays — drive adds no verification of its own on top of `/mb work`
  and `/mb team`; the only check drive runs itself is the existing firewall, once, before `stop_success`.
- **NFR-002** (context NFR-004): every touched drive script stays under 400 lines; `scripts/mb-drive.sh` (463) is split.
- **NFR-003**: no new dependency — bash and the Python standard library, as today.

## Out of Scope

- QA defaults, test-case authoring, the plan wrapper and the source bundle (S1 `planning-qa-sources`).
- Team stops, track execution through `/mb work`, team hardening and host dispatch inside team (S2 `team-completion`).
- Closing plans into `plans/done/`, committing or pushing: `/mb done` and the user keep them.
- Goal lifecycle commands beyond `--goal <path>` (`/goal set|list`) and changes to `mb-goal-state.sh` or the done gates, which keep reading `<bank>/goal.md`.
