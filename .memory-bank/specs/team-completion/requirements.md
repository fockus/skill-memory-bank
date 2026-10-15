---
type: spec-requirements
topic: team-completion
status: ready
created: 2026-10-15
group: "[SPEC:autopilot]"
parent_context: context/drive-autopilot.md
interview_transcript: context/drive-autopilot-interview.md
linked_design: design.md
depends_on_specs: [mb-team]
backlog: [I-282, I-275, I-276, I-277, I-278, I-279, I-280]
layers:
  contract_first: false
  contract_first_reason: fixes over the existing team contract
  integration_tests: true
  e2e_tests: true
---

# Requirements: team-completion

> Spec triple — see also: design.md, tasks.md.
> Slice S2 of group `[SPEC:autopilot]` (backlog I-282). Source: `context/drive-autopilot.md` decisions
> D-03 (every team track executes through `/mb work`) and D-09 (team stops, I-275..I-280), context
> REQ-012..REQ-018 and NFR-001. REQ ids here are spec-local; every requirement names its source.
> Runs in parallel with S1 `planning-qa-sources`; S3 `drive-autopilot` depends on both.
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

### Requirement 1: Every track runs through /mb work

**User Story:** As the team orchestrator, I want every track to run through the `/mb work` per-item loop, so that
verify, the eval gate, QA and closure come from one engine instead of a second, thinner team pipeline.

Source: context REQ-012 · D-03 · NFR-001 · AGR-099.

#### Acceptance Criteria

- **REQ-001** (ubiquitous): THE SYSTEM SHALL execute every team track through the `/mb work` per-item loop, with the track prompt as the default work source.
- **REQ-002** (ubiquitous): THE SYSTEM SHALL emit no verifier, review or acceptance action of its own for a returned track beyond the gates of that track's `/mb work` loop.

### Requirement 2: The team stops instead of hanging

**User Story:** As the user who left a team running, I want a dead end to stop the team with one clear reason,
so that a cancelled dependency or a red flow never turns into an endless `wait`.

Source: context REQ-013 (I-275), REQ-014 (I-276), REQ-015 (I-277) · D-09.

#### Acceptance Criteria

- **REQ-003** (unwanted): IF a dependency of a planned track is cancelled, THEN THE SYSTEM SHALL emit `stop_human blocked:dep-cancelled:<dependency id>` and show each such dependent track as `blocked:dep-cancelled:<dependency id>` in `team status`.
- **REQ-004** (unwanted): IF every track is finished and collected and the team review is clean or off while the goal acceptance or the flow check is red, THEN THE SYSTEM SHALL emit `stop_human goal-red` or `stop_human flow-red:<check>` instead of `wait`.
- **REQ-005** (event-driven): WHEN `team next` produces a `stop_human` action, THE SYSTEM SHALL print only the `stop_human` actions.

### Requirement 3: Track STATUS from the last STATUS line

**User Story:** As the orchestrator, I want a report's STATUS read from its last STATUS line, so that a role agent
that ends its report with STATUS is not misread as `no-report`.

Source: context REQ-016 (I-278) · D-09.

#### Acceptance Criteria

- **REQ-006** (ubiquitous): THE SYSTEM SHALL read a track report's STATUS from the last line of the report that carries a STATUS value.

### Requirement 4: Commit, review and lock hardening

**User Story:** As a user sharing one working tree with the team, I want the team's side-effect commands to fail
cleanly and to agree with each other, so that a failed step never leaves my index, the review state or a lock in an
unexpected state.

Source: context REQ-017 (I-280) · D-09 open follow-ups m1, m2, m3, m6 (I-279, `reports/mb-team/review.md`).

#### Acceptance Criteria

- **REQ-007** (unwanted): IF `git commit` fails after `team commit` staged files, THEN THE SYSTEM SHALL restore the index entries of the staged paths to their state before `team commit`.
- **REQ-008** (ubiquitous): THE SYSTEM SHALL route a team-review finding to a track with the same glob rule that `team commit` uses for ownership, after stripping the tree or mirror prefix from the finding path.
- **REQ-009** (unwanted): IF `team review gate` receives output that is not a JSON verdict, THEN THE SYSTEM SHALL exit 2 without a traceback and leave the recorded reviews unchanged.
- **REQ-010** (unwanted): IF a checkpoint id already exists in the checkpoint directory, THEN THE SYSTEM SHALL refuse the checkpoint without overwriting any file.
- **REQ-011** (unwanted): IF a checkpoint label is not a plain name of letters, digits, dot, dash or underscore, THEN THE SYSTEM SHALL refuse the checkpoint with exit 2.
- **REQ-012** (ubiquitous): THE SYSTEM SHALL compute the host-scope lock root in one place as `MB_LOCK_DIR` or a fixed per-user directory that does not depend on `TMPDIR`.

### Requirement 5: Track dispatch on four hosts

**User Story:** As a user on Claude Code, Codex, OpenCode or Pi, I want `/mb team` to tell me how tracks are
dispatched and relayed on my host, so that the same team runs everywhere the skill installs.

Source: context REQ-018 (I-280) · D-10 constraint "dispatch adapters shared".

#### Acceptance Criteria

- **REQ-013** (ubiquitous): THE SYSTEM SHALL describe track dispatch for Claude Code, Codex, OpenCode and Pi through the shared host dispatch table in `SKILL.md` § Invocation, plus each host's relay rule.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Track runs through the work loop
**Covers:** REQ-001, REQ-002

- GIVEN a team with one small and one standard track added without `--source`
- WHEN the tracks are resolved and the standard track returns with `STATUS: DONE`
- THEN both tracks resolve to `mode: work` with their own track prompt as the work source
- AND `team next` prints `collect` with no `verify` or `review` action for the returned track
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Cancelled dependency stops the team
**Covers:** REQ-003, REQ-005

- GIVEN track B depends on track A and track C is ready to dispatch
- WHEN track A is cancelled while B is still planned
- THEN `team next` prints exactly `stop_human blocked:dep-cancelled:A` and no `dispatch C`
- AND `team status` shows B as `blocked:dep-cancelled:A`
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Red flow after the last collect stops the team
**Covers:** REQ-004, REQ-005, REQ-006

- GIVEN a team without a goal whose only track report ends with the line `STATUS: DONE` after other text
- WHEN the track is collected and the flow check reports the `tests` check red
- THEN `team next` prints exactly `stop_human flow-red:tests` instead of `wait`
- AND the flow check that `team next` runs leaves out goal acceptance
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Failed commit leaves the index as it was
**Covers:** REQ-007, REQ-008

- GIVEN a finished track that owns a new file and a modified file, and a pre-commit hook that fails
- WHEN `team commit --yes` runs for that track
- THEN the command exits 1 and `git diff --cached --name-only` is the same as before the command
- AND a review finding on a path under `src/**/*.py` is routed to the track that commit treats as the owner
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Broken inputs are refused cleanly
**Covers:** REQ-009, REQ-010, REQ-011, REQ-012

- GIVEN a team with team review on and a lock resource with host scope
- WHEN the review gate prints no JSON, a checkpoint repeats an existing id, and a checkpoint label is `../x`
- THEN the gate exits 2 without a traceback, the repeated checkpoint is refused and the label is refused with exit 2
- AND the host lock root stays the same when only `TMPDIR` changes
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Track dispatch is described for four hosts
**Covers:** REQ-013

- GIVEN the installed `/mb team` command
- WHEN a user on Codex, OpenCode or Pi reads its Hosts section
- THEN the section names Claude Code, Codex, OpenCode and Pi and links the dispatch table in `SKILL.md` § Invocation
- AND it states the relay rule for hosts without mid-flight messaging
<!-- /mb-scenario:6 -->

## Non-Functional Requirements

- **NFR-001** (context NFR-001): lightweight mode stays — a track costs what its `/mb work` workflow costs (standard:
  one implementer + one plan verifier, AGR-097/AGR-075); team adds no checks of its own on top.
- **NFR-002** (context NFR-004): every touched script stays under 400 lines; `commands/work.md` (399 lines, zone file)
  is not touched by this spec.

## Out of Scope

- `/mb drive` itself (S3 `drive-autopilot`): stall handling of team `stop_human`, budget, resume.
- QA defaults, plan/spec source bundle, plan-as-wrapper (S1 `planning-qa-sources`).
- review findings m4, m5, m7, m8, m9 and the nits of `reports/mb-team/review.md` (m5, m8, m9 are already fixed).
