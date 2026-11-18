---
topic: svp-adapt-escalation
group: sdd-vision-pipeline
ice: {impact: 7, confidence: 7, ease: 6}
ice_confirmed: false
blocked_by: [svp-sdd-core, svp-roadmap-backlog-db]
covers_umbrella: [REQ-030, REQ-031, REQ-032]
status: ready
---

# Requirements: svp-adapt-escalation

> Spec triple — see also: design.md, tasks.md.
> Slice S5 of the `sdd-vision-pipeline` group (ICE 294).
> **Revision 4 (2026-11-19, master-completion Stage 18a): rebased on ADaPT-lite.** Commit `190251c`
> (AGR-080, AGR-082) already ships the signal, the verify and token guards, the four HITL choices and
> in-run sub-items in `scripts/mb_work_adapt.py`, the `adapt:` block of `references/pipeline.default.yaml`
> and `references/adapt.md`. This revision maps REQ-001..010 onto that code: delivered parts are waived
> with the commit link (Task 1), the rest is owned by Tasks 2-5 on the existing files. The former hard
> dependency on `svp-parallel-engine` (S3) is dropped: the scope guard is a minimal check inside
> `mb_work_adapt.py` against the item's `Files:`, S3's `mb-work-scope-check.sh` stays out of scope.
> Reading context: `context/svp-adapt-escalation.md`; transcripts: the slice and the parent ones.
>
> EARS: Ubiquitous `THE SYSTEM SHALL` · Event `WHEN …` · State `WHILE …` · Optional `WHERE …` · Unwanted `IF … THEN …`

## Rebase map (Stage 18a)

| REQ | Status after rebase | Evidence or owner |
|---|---|---|
| 001 | covered, waiver | `scripts/mb_work_adapt.py:155` `parse_escalation`, `commands/work.md` step 5c1, test `test_escalation_block_parses_with_and_without_pyyaml`; commit 190251c; Task 1 |
| 002 | partial: verify and token guards covered; open | Delivered: `mb_work_adapt.py:247` `check`. Open: scope, review, judge, eval-not-green guards, Task 2 |
| 003 | partial: verify threshold covered; open | Delivered: `adapt.verify_fail_cycles: 3` (`pipeline.default.yaml:286`, `mb_work_adapt.py:37`). Open: review 3, judge 2 keys, Task 2 |
| 004 | open | Task 5 (stub behind a flag plus backlog item), after Task 4 |
| 005 | covered, waiver (amended wording) | `references/adapt.md` § Fork, `commands/work.md` step 5c1; commit 190251c; Task 1 |
| 006 | covered, waiver (amended wording) | `mb_work_adapt.py:195` `split`, `:227` `sub_done`, `:239` `gate`; commit 190251c; Task 1 |
| 007 | open | Task 3 (journal under `mb_lock_acquire`) |
| 008 | open | Task 3 (`esc-summary`), stub lines fed by Tasks 4-5; the one-line-per-escalation prose in `adapt.md` § Summary stays as the HITL baseline |
| 009 | open | Task 4 (`verify-stub`) |
| 010 | open | Task 3 (consecutive counter in `esc-open`, `decision=stop_run`) |

Amended wording (assumption of this rebase, flagged to the owner): lite offers four HITL choices
continue / simplify / **decompose** / skip, not "replan via decomposition or requirement change", and it
splits the stuck item inside the run instead of registering a child spec (AGR-080, AGR-082). A
requirement change is the `simplify` path: the run stops until the user cuts scope, DoD or requirements.
The decomposed-spec registry route and the `replan-gate` of revision 3 are dropped as YAGNI.

## Requirements (EARS)

### Requirement 1: ADaPT triggers

**User Story:** As an operator, I want both a conscious agent signal and deterministic guards to detect oversized tasks, so that escalation fires early (signal) and reliably (guards).

#### Acceptance Criteria

- **REQ-001** (event-driven): When an implementer report contains a `complexity_escalation` block, the system shall trigger the ADaPT fork. <!-- S5-A-02 -->
- **REQ-002** (event-driven): When a deterministic guard fires — item token budget exceeded, declared-scope violation (a changed path outside the item's `Files:`), eval not green after `max_cycles` attempts, or a verify/review/judge loop threshold reached — the system shall trigger the ADaPT fork. <!-- D-16 -->
- **REQ-003** (ubiquitous): The loop thresholds shall default to verify 3, review 3 and judge 2 and shall be configurable in the `adapt:` block of pipeline.yaml; the verify default stays 3 (AGR-082). <!-- S5-A-01 -->

### Requirement 2: Fork by mode

**User Story:** As a user (including a vibecoder), I want auto mode to split or stub-and-continue and interactive mode to give me four clear choices, so that work never stalls and never hides problems.

#### Acceptance Criteria

- **REQ-004** (state-driven): While in autonomous mode, on an ADaPT trigger that splitting cannot resolve (the split is refused at `adapt.max_depth`), the system shall implement a stub behind a feature flag with a docstring, register a backlog item for the deferred work and continue execution. <!-- S5-A-03 -->
- **REQ-005** (state-driven): While in HITL mode, on an ADaPT trigger the system shall offer the choices: continue anyway, simplify, decompose, or skip the step. <!-- D-16 -->
- **REQ-006** (event-driven): When the item is decomposed (auto mode, or the decompose choice in HITL mode), the system shall split only that item into 2-5 sub-items inside the run, each with its own `Files:`, and the parent shall close only after the last sub-item. <!-- D-10 -->

### Requirement 3: Honesty and telemetry

**User Story:** As a project owner, I want every escalation logged and reported, so that nothing is silently swallowed and thresholds can be calibrated from data.

#### Acceptance Criteria

- **REQ-007** (ubiquitous): The system shall log every escalation as an `opened` JSONL record at trigger time and its resolution as a matching `resolved` JSONL record, correlated by `escalation_id`, writing under the shared lock `mb_lock_acquire`. <!-- S5-A-04, umbrella §Interfaces 3 -->
- **REQ-008** (ubiquitous): The system shall report every escalation and stub to the user in the run summary — an escalation shall never be silently swallowed. <!-- D-33 -->
- **REQ-009** (unwanted): If a stub is created without a feature flag or without a backlog item, then verification shall fail for that task. <!-- no-placeholders, rules/RULES.md § Staged stubs -->

### Requirement 4: Cascade stop

**User Story:** As a project owner, I want a run to stop after repeated escalations, so that a mis-sized spec is revised instead of being ground through task by task.

#### Acceptance Criteria

- **REQ-010** (unwanted): If `cascade_stop` consecutive ADaPT escalations occur within one run, then the system shall stop before dispatching the next item and report a recommendation to revise the whole spec. <!-- D-35 -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Agent escalation signal
**Covers:** REQ-001

- GIVEN an implementer decides the item needs a new subsystem
- WHEN its report carries a complexity_escalation block with proposed sub-items
- THEN the orchestrator opens the fork before the next cycle
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Cycle guard fires
**Covers:** REQ-002, REQ-003

- GIVEN review ran a third cycle on one item (`review_cycle` count 3 in the run state) and `adapt.review_cycles` is 3
- WHEN adapt-check runs after the cycle is recorded
- THEN the check reports a trigger and `reasons` contains `review_cycles`; with the count at 2 it does not
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Autonomous mode stubs and continues
**Covers:** REQ-004, REQ-009

- GIVEN autonomous mode and a trigger on an item whose split is refused at max depth
- WHEN the fork resolves
- THEN the backlog item reaches READY through the existing S4 writers before any code is edited, the stub carries the marker `MB-ADAPT-STUB backlog=I-NNN flag=<NAME> eval=<path>` behind a default-off flag, and execution continues; verify fails when the flag, the driver or the backlog reference is missing
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: HITL four options
**Covers:** REQ-005

- GIVEN HITL mode and a trigger
- WHEN the fork is shown to the user
- THEN the choices are continue / simplify / decompose / skip, and the choice is written as a resolved event
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Decomposition splits only the stuck item
**Covers:** REQ-006

- GIVEN a split of item 3 into two sub-items with disjoint Files
- WHEN the first sub-item is done and the second is still open
- THEN the parent `done` is refused (exit 6), the plan file is untouched, and after the last sub-item is done the parent closes
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Escalation telemetry is two phase
**Covers:** REQ-007

- GIVEN a fork is opened and then resolved, with two sessions appending concurrently
- WHEN the resolution is recorded
- THEN `tmp/escalations.jsonl` holds exactly one valid `opened` and one valid `resolved` line with the same `escalation_id` and `ts`/`seq`, folding by id yields the last event, an unknown key makes the journal invalid (exit 1, nothing appended), and no line is lost under the lock
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Nothing is silenced
**Covers:** REQ-008

- GIVEN an autonomous run that ended with two stubs
- WHEN the final report is printed
- THEN both stubs and their backlog items are listed explicitly, together with every escalation and any correction of a resolution
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Escalation cascade stops the run
**Covers:** REQ-010

- GIVEN a third consecutive escalation in one run (`adapt.cascade_stop` is 3) with no item closed clean in between
- WHEN the third fork is opened
- THEN the decision is `stop_run`, the run stops before dispatching the next item and prints the recommendation to revise the whole spec
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Simplify stops the run until scope is cut
**Covers:** REQ-005

- GIVEN HITL mode and the user picks simplify
- WHEN the choice is resolved
- THEN the item stays pending, the checkbox is not flipped, the run stops, and the resolved event records `simplify`
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Stub gate rejects a default-on flag
**Covers:** REQ-009

- GIVEN a stub with a correct marker, an existing `I-NNN` and a driver `eval=<path>`, but the flag is on by default
- WHEN the verify gate runs the driver without the flag variable
- THEN the driver prints `MB-ADAPT-STUB-PATH: staged` instead of `baseline`, the gate reports `flag_default_on` and exits 1, and the task fails
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Scope guard fires on a stray file
**Covers:** REQ-002

- GIVEN an item whose declared Files are `src/a.py` and `tests/test_a.py`
- WHEN adapt-check receives a changed-file list that includes `src/b.py`
- THEN the check reports a trigger with `reasons` containing `scope_violation`; with only declared paths it does not, and without a declared list the guard is reported as degraded instead of passing silently
<!-- /mb-scenario:11 -->
