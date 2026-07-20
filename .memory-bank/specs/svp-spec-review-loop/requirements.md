---
topic: svp-spec-review-loop
group: sdd-vision-pipeline
ice: {impact: 8, confidence: 7, ease: 6}
ice_confirmed: false
blocked_by: [svp-sdd-core]
covers_umbrella: [REQ-035]
review: waived
status: ready
---

# Requirements: svp-spec-review-loop

> Spec triple — see also: design.md, tasks.md.
> Слайс S9 группы `sdd-vision-pipeline` (ICE 336, не подтверждён — AGR-021). Контекст: `context/svp-spec-review-loop.md`.
> Создан 2026-07-18 по решению пользователя AGR-022; **codex-ревью спеки не проводилось** (`review: waived`) —
> ревью-долг гасится первым боевым прогоном самого механизма S9 по этой же спеке (dogfooding).
> Расширяет S2-C5 (`sdd.spec_review`, судья-человек D-30) автоматическим судьёй, fix-петлёй,
> реестром отклонений и preflight-гейтом `/mb work`. Umbrella-интеграция отложена до конца
> ремедиации круга 3 (D-08).
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous: `THE SYSTEM SHALL` · Event: `WHEN … THE SYSTEM SHALL` · State: `WHILE … THE SYSTEM SHALL` · Optional: `WHERE … THE SYSTEM SHALL` · Unwanted: `IF … THEN THE SYSTEM SHALL`

## Requirements (EARS)

### Requirement 1: Автоматический судья вердикта spec-ревью

**User Story:** As a spec author, I want an independent judge to decide GO / GO_WITH_BACKLOG / NO_GO over the reviewer's verdict, so that the review loop terminates on a decision instead of the reviewer improving the spec forever.

#### Acceptance Criteria

- **REQ-001** (optional): Where pipeline.yaml enables `sdd.spec_judge`, the system shall dispatch the configured judge with the recorded review verdict, the spec triple, the deviations registry and the rubric after each spec_review verdict is recorded. <!-- D-02 -->
- **REQ-002** (ubiquitous): The system shall record every judge decision as an append-only JSONL line of kind `judge` with decision `GO`, `GO_WITH_BACKLOG` or `NO_GO` in the same verdict journal as spec_review verdicts. <!-- D-02 -->
- **REQ-015** (ubiquitous): The system shall record, in the judge journal line, for every finding of the verdict under judgement, whether the judge confirmed that finding against the spec text, using the field `confirmed` with one entry per finding id. <!-- AMEND-S9-2, ADR-S9-6 -->
- **REQ-003** (unwanted): If the resolved judge model equals the resolved spec_review model or the model that generated the spec, then the system shall refuse dispatch with the observable `same_model` signature and a non-zero exit before any judge call. <!-- D-02, S2-C5 -->

- **REQ-016** (unwanted): If the spec frontmatter carries no `generated_by` key, then the system shall proceed with the remaining same-model checks and record the skipped leg in the judge journal line as `generator_check=skipped`, so a GO issued without the full independence check is auditable. <!-- AMEND-S9-4, D-02 -->

### Requirement 2: Fix-петля с независимым re-review

**User Story:** As an orchestrator, I want NO_GO to trigger a fix pass followed by a fresh independent review, bounded by max_cycles, so that findings actually get fixed and the loop cannot spin silently.

#### Acceptance Criteria

- **REQ-004** (event-driven): When the judge decides NO_GO, the system shall route the verdict findings to a fix pass and then re-run spec_review as a fresh independent review of the fixed spec. <!-- D-03 -->
- **REQ-005** (unwanted): If `max_cycles` review-judge cycles complete without GO or GO_WITH_BACKLOG, then the system shall stop, leave the spec not accepted, print the observable line `spec=not_accepted reason=review_cycles_exhausted topic=<topic>` and defer the decision to the user. <!-- D-03 -->
- **REQ-006** (event-driven): When the judge decides GO_WITH_BACKLOG, the system shall record every surviving finding as a backlog item before the spec is accepted. <!-- D-02 -->

### Requirement 3: Durable реестр принятых отклонений

**User Story:** As a spec owner, I want rejected-with-evidence findings recorded durably and injected into future review prompts, so that consciously rejected findings are not re-raised round after round.

#### Acceptance Criteria

- **REQ-007** (event-driven): When a finding is rejected with anchored evidence by the user or the judge, the system shall append it to `specs/<topic>/review-deviations.md` with its id, source, decision, evidence, date and a `status` of `active`. <!-- D-04, AMEND-S9-3 -->
- **REQ-008** (state-driven): While `specs/<topic>/review-deviations.md` contains at least one row whose `status` is `active`, the system shall include ONLY the active rows in every subsequent spec_review prompt, with the instruction not to re-raise them. <!-- D-04, D-06, AMEND-S9-3 -->
- **REQ-017** (event-driven): When a previously accepted deviation is reopened, the system shall append a new row for the same id with `status: active` and rewrite only the prior row's `status` field to `superseded`, so the reopened finding is raised again and the audit trail is preserved. <!-- AMEND-S9-3 -->

### Requirement 4: Preflight-гейт /mb work по действующему вердикту

**User Story:** As a user, I want `/mb work` to refuse executing a spec whose current review verdict is unresolved CHANGES_REQUESTED, so that known-defective specs do not burn governed implementation cycles.

#### Acceptance Criteria

- **REQ-009** (unwanted): If `/mb work` targets a spec whose effective spec_review verdict is CHANGES_REQUESTED without a judge GO or GO_WITH_BACKLOG while `sdd.spec_review` is enabled, then the system shall refuse execution before any dispatch, print `work=blocked reason=spec_review_pending topic=<topic>` on stdout and exit non-zero. <!-- D-05 -->
- **REQ-010** (optional): Where the user passes the explicit `--skip-spec-gate` flag, the system shall proceed and record the override as an append-only JSONL line of kind `override` in the verdict journal. <!-- D-05 -->
- **REQ-011** (state-driven): While `sdd.spec_review` is disabled or the spec has no verdict journal, the system shall run `/mb work` without the spec gate and without new warnings. <!-- D-05, обратная совместимость -->
- **REQ-014** (unwanted): If the effective verdict cannot be resolved while `sdd.spec_review` is enabled — the status query fails, exits non-zero, or returns an unparsable line — then the system shall refuse execution before any dispatch, print `work=blocked reason=spec_status_unavailable topic=<topic>` on stdout and exit 4. <!-- AMEND-S9-1, D-05 -->

### Requirement 5: Детерминированная сборка review-промпта и рубрика

**User Story:** As a maintainer, I want the review prompt assembled by a deterministic script from the bundled rubric, the deviations registry and the spec files, so that prompt composition is testable instead of being an unverifiable instruction.

#### Acceptance Criteria

- **REQ-012** (ubiquitous): The system shall assemble the spec_review prompt by script from the rubric, the spec triple file list, the verdict schema and, when present, the deviations registry, writing the result to stdout. <!-- D-06 -->
- **REQ-013** (optional): Where pipeline.yaml sets `sdd.spec_review.rubric` to a path, the system shall use that rubric file instead of the bundled default `references/spec-review-rubric.md`. <!-- D-07 -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Judge GO accepts the spec
**Covers:** REQ-001, REQ-002

- GIVEN `sdd.spec_judge.enabled=true` and a recorded spec_review verdict APPROVED for topic `demo`
- WHEN the judge dispatch completes with decision GO
- THEN the verdict journal gains an append-only line with kind `judge` and decision `GO`
- AND the previously recorded review lines remain unchanged

**test_id:** judge_go_appends_decision
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Same model triple check refuses dispatch
**Covers:** REQ-003

- GIVEN `sdd.spec_judge.model` resolves to the same exact model as `sdd.spec_review.model`
- WHEN the judge step starts for topic `demo`
- THEN stderr carries the `same_model` signature and the exit code is 2
- AND no judge call is made and the verdict journal gains no `judge` line

**test_id:** judge_same_model_refused
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: NO_GO routes to fix and independent re-review
**Covers:** REQ-004

- GIVEN a judge decision NO_GO over a CHANGES_REQUESTED verdict with three findings
- WHEN the fix pass completes
- THEN spec_review runs again as a fresh review attempt with a new `attempt` value
- AND the new verdict line is appended after the fix, not edited in place

**test_id:** no_go_triggers_refix_and_rereview
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Cycles exhausted stops honestly
**Covers:** REQ-005

- GIVEN `max_cycles: 2` and two completed review-judge cycles both ending in NO_GO
- WHEN the loop would start a third cycle
- THEN the system stops and prints `spec=not_accepted reason=review_cycles_exhausted topic=demo`
- AND the spec stays not accepted and the decision is deferred to the user

**test_id:** cycles_exhausted_honest_stop
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: GO_WITH_BACKLOG writes surviving findings to backlog
**Covers:** REQ-006

- GIVEN a judge decision GO_WITH_BACKLOG with two surviving minor findings
- WHEN the acceptance step runs
- THEN each surviving finding becomes a backlog item before the spec is marked accepted
- AND the journal line for the decision references the created item ids

**test_id:** go_with_backlog_records_items
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Rejected finding lands in the deviations registry
**Covers:** REQ-007

- GIVEN the user rejects finding `R4-002` with an anchored quote from design.md
- WHEN the rejection is recorded
- THEN `specs/demo/review-deviations.md` gains a row with id `R4-002`, the decision, the evidence and the date
- AND existing registry rows are preserved unchanged

**test_id:** rejection_appends_deviation_row
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Deviations registry is injected into the next review prompt
**Covers:** REQ-008, REQ-012

- GIVEN a non-empty `specs/demo/review-deviations.md`
- WHEN the review prompt is assembled by the prompt script
- THEN stdout contains the deviations block with the do-not-re-raise instruction
- AND the rubric and the spec triple file list are present in the same output

**test_id:** prompt_injects_deviations
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Work is blocked on an unresolved CHANGES_REQUESTED verdict
**Covers:** REQ-009

- GIVEN `sdd.spec_review.enabled=true` and an effective verdict CHANGES_REQUESTED for topic `demo` with no judge GO line
- WHEN `/mb work demo` starts
- THEN stdout prints `work=blocked reason=spec_review_pending topic=demo` and the exit code is non-zero
- AND no work item is dispatched

**test_id:** work_blocked_on_pending_review
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Explicit override runs work and is journaled
**Covers:** REQ-010

- GIVEN the blocked state of the previous scenario
- WHEN the user runs `/mb work demo --skip-spec-gate`
- THEN execution proceeds and the verdict journal gains an append-only line of kind `override`
- AND the override line carries the timestamp of the run

**test_id:** work_override_journaled
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Gate is silent when the feature is off or the journal is absent
**Covers:** REQ-011

- GIVEN `sdd.spec_review.enabled=false` for one bank and a second bank whose spec has no verdict journal
- WHEN `/mb work` runs against each
- THEN both runs proceed without the spec gate and without any new warning lines
- AND exit codes match the pre-S9 behavior

**test_id:** gate_silent_when_disabled_or_absent
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Custom rubric path overrides the bundled default
**Covers:** REQ-013

- GIVEN `sdd.spec_review.rubric: custom/rubric.md` present in pipeline.yaml and the file exists
- WHEN the review prompt is assembled
- THEN the prompt contains the custom rubric content and not the bundled default
- AND with the key absent the bundled `references/spec-review-rubric.md` is used

**test_id:** custom_rubric_overrides_default
<!-- /mb-scenario:11 -->

<!-- mb-scenario:12 -->
### Scenario: Gate fails closed when the verdict cannot be resolved
**Covers:** REQ-014

- GIVEN `sdd.spec_review.enabled=true` and a status query that fails (helper missing, non-zero exit, or an unparsable line)
- WHEN `/mb work demo` starts
- THEN stdout prints `work=blocked reason=spec_status_unavailable topic=demo` and the exit code is 4
- AND no work item is dispatched
- AND an ABSENT journal still takes the silent REQ-011 path, because "no review yet" is a known state and "cannot tell" is not

**test_id:** gate_fails_closed_on_unresolvable_status
<!-- /mb-scenario:12 -->

<!-- mb-scenario:13 -->
### Scenario: Judge records per-finding confirmation
**Covers:** REQ-015

- GIVEN a CHANGES_REQUESTED verdict carrying findings `R1-001` and `R1-002`
- WHEN the judge records its decision
- THEN the judge journal line carries a `confirmed` entry for each of `R1-001` and `R1-002`
- AND a decision recorded without a `confirmed` entry per finding is refused as malformed

**test_id:** judge_records_per_finding_confirmation
<!-- /mb-scenario:13 -->

<!-- mb-scenario:14 -->
### Scenario: Only active deviations are injected, superseded ones are raised again
**Covers:** REQ-008, REQ-017

- GIVEN `review-deviations.md` holds `R4-002` with `status: superseded` and `R4-009` with `status: active`
- WHEN the review prompt is assembled
- THEN the deviations block contains `R4-009` and does NOT contain `R4-002`
- AND the reopened `R4-002` is therefore free to be raised again by the reviewer

**test_id:** prompt_injects_only_active_deviations
<!-- /mb-scenario:14 -->

<!-- mb-scenario:15 -->
### Scenario: Missing generator model is journaled, not silently skipped
**Covers:** REQ-016

- GIVEN spec frontmatter with no `generated_by` key and a judge model differing from the reviewer model
- WHEN the judge step records its decision
- THEN the run proceeds and the judge journal line carries `generator_check=skipped`
- AND stderr carries the `generator_model_unknown` warning

**test_id:** judge_journals_skipped_generator_check
<!-- /mb-scenario:15 -->
