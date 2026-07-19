---
topic: quality-track
created: 2026-07-15
status: ready
---

# Context: quality-track

MB Quality Track — spec-driven QA component turning requirements, tests and execution
results into a single provable evidence chain: Requirement → Scenario → QA Case →
Verification Implementation → Execution Evidence → Quality Gate. Vision source:
`mb-quality-track-final-solution.md` (snapshot of the user's concept document, 2026-07-15).

## Purpose & Users

Users: skill users running `/mb work` on spec/plan-driven projects, plus CI pipelines
that must gate releases without an LLM. Problem: "124 tests passed" does not prove
"all mandatory requirements are implemented and verified" — there is no persisted link
between requirements, tests, runs and freshness. Success (qualitative): for any topic
the system can provably answer which requirements are covered, by which tests, when they
ran, whether the results are still fresh, and whether the change may proceed —
deterministically, with `NOT_RUN ≠ PASS`.

## Research Digest

Facts gathered in Phase 0 — each line one fact + citation.

- Donor umbrella spec already contains the evidence layer: REQ-EV-001…007 (fresh evidence bound to SHA, REQ→test mapping, UAT persistence, gap plans, fail-closed evidence) — `.memory-bank/specs/mb-donor-evolution/requirements.md:95-103`
- Release v6.1.0 "Evidence, UAT & Gap Closure" has authored tasks EV-01…EV-05: Evidence Manifest §7.5 + freshness by SHA/diff/spec/plan hashes, risk-based evidence policy, collectors ("failed can never become passed"), verification report `passed|failed|unverified|waived`, release aggregator — `.memory-bank/specs/mb-donor-evolution/tasks.md:1373-1483`
- Donor invariants already encode the vision's principles: INV-07 "no done without fresh evidence manifest", INV-12 "AI completion signals are hints only" — `.memory-bank/specs/mb-donor-evolution/design.md:88,93`
- AGR-003: on overlap donor wins — quality-track could not ship as an independent legacy feature without positioning against v6.1.0
- Existing structured runner: `scripts/mb-test-run.sh` (bats/pytest/go, JSON `tests_pass`, exit always 0) — becomes the compatibility facade per vision §13
- Traceability exists: `scripts/mb-traceability-gen.sh` builds REQ → Plan → Test matrix; Quality Track extends it to an Evidence Graph with statuses
- Workflow engine ready for embedding: canonical stages `discuss→sdd→plan→implement→verify→review→judge→fix→done` — `scripts/mb-workflow.sh:90`; verify step configurable per workflow in `pipeline.yaml`
- `agents/mb-qa.md` exists (test design / coverage / edge cases) — reused for generation; vision adds qa-planner and qa-auditor
- Python core is repo-conventional: `memory_bank_skill/` already hosts cli.py + codegraph modules — `quality/` package fits
- Deterministic gate is an established pattern: `scripts/mb-work-severity-gate.sh`, `scripts/mb-work-review-parse.sh`
- AGR-006: update-notify must finish before donor v5.4.0 — quality-track queues after the donor chain
- AGR-007 sdd-openspec-parity is complementary, not conflicting: it hardens spec *authoring* (lint, scenarios, provenance), Quality Track proves *implementation* against those specs; its GWT scenario layer feeds QA cases
- No prior decisions on "/mb qa", "quality track", "evidence graph" in notes/backlog — topic is new

## Decision Log

- **D-01**: quality-track = a new release of the donor program layered on v6.1.0; the evidence core (§7.5 manifest, freshness, collectors EV-01…05) is NOT duplicated — vision Stage 1 merges with the EV tasks. — Rationale: AGR-003 (donor wins), zero duplicate evidence systems. Rejected: extend v6.1.0 scope (mega-release, contra AGR-001); independent legacy feature before donor (builds the evidence layer twice, freeze+migration at 6.1.0 start).
- **D-02**: Queue position: immediately after 6.1.0 (rough ICE ≈ 9×7×4 = 252 — above 6.2/6.3/6.4). — Rationale: clean dependency on the finished evidence core, zero reordering risk. Rejected: decouple EV tasks from gate 6.0.0 and pull QA forward (needs ADR + re-ICE + umbrella dependency edits); pair with 6.1.0 (mega-release).
- **D-03**: Release number **v6.2.0**; the 6.x tail shifts +1 (Portable Skills→6.3.0, Delta Specs→6.4.0, Adaptive Ops→6.5.0, icebox GSD/OpenSpec→6.6.0/6.7.0). AGR-002 amended; REQ-IDs and mb-task numbers unchanged. — Rationale: releases must stay monotonic; precedent = the 5.x shift in AGR-002. Caveat: if Portable Skills actually ships earlier on the parallel lane, numbers are revisited at slice time. Rejected: assign at slice time (defers a cheap decision); v7.0.0 (QA is opt-in, no breaking change — major not justified).
- **D-04**: v6.2.0 scope = vision Stages 1–3 in full: evidence-QA foundation + QA planning + **test generation** + full `/mb work --qa`. Stages 4–5 (Playwright/browser E2E, safe healer, extended adapters) → later JIT slices. — Rationale: user explicitly wants QA usable inside `/mb work` including generation, not foundation-only (user overrode the recommended Stages 1–2 cut). Rejected: Stages 1–2 only (recommended, declined); all 5 stages (mega-release, contra AGR-001).
- **D-05**: Requirement sources in v6.2.0 = native SDD (`specs/<topic>/requirements.md`, primary) + plan-based (active plan DoD, scope labelled) + diff-based regression (completeness: UNKNOWN), behind a `source.kind` adapter interface. OpenSpec source adapter deferred. — Rationale: aligned with iceboxed OpenSpec runtime (AGR-004 → now v6.7.0) and native-only AGR-007; adapter interface keeps the door open without breakage. Rejected: all 4 sources now (drags OpenSpec parsing in before the runtime is unfrozen); native SDD only (loses brownfield diff mode the vision treats as core).
- **D-06**: Semantic audit ships in v6.2.0: agent mb-qa-auditor, input = one case + oracle + mapped test only (never the repo), result cached by (case digest, test digest), rules weak→WARN / mismatch→FAIL in change profile (release profile for critical: weak→FAIL). — Rationale: generation is in scope (D-04); without semantic audit a generated green-but-empty test passes the gate. The vision's stage list omits it while its gate/profiles reference it — contradiction resolved in favour of inclusion. Rejected: defer to next slice (unsafe with generation on).
- **D-07**: Core in Python (`memory_bank_skill/quality/`: models, source_resolver, manifest, freshness, runner, gate, report, adapters/) + thin shell dispatchers; `scripts/mb-test-run.sh` stays as compatibility facade. — Rationale: existing repo pattern (cli.py, codegraph modules); resolved from code, not asked. Rejected: pure-shell core (JUnit/TAP parsing + digest graph too heavy for bash 3.2).
- **D-08**: Quality profiles `fast` / `change` / `release` ship in v6.2.0 as a `pipeline.yaml quality:` config layer; `change` is the default for `--qa`. — Rationale: cheap config layer, vision §12 semantics preserved (fast = changed/impacted only, release = no stale evidence, no cache).
- **D-09**: First-wave runner adapters = pytest JUnit XML + Bats TAP (dogfooding on this repo) + generic JUnit XML (covers Jest/Vitest/Go/Cypress via their junit reporters) + generic exit-code (suite-only, no per-case mapping). Native JSON adapters (Jest/Vitest/Go/Playwright) → later slices on demand. — Rejected: full vision §13.2 list now (each native parser is code+tests while junit reporters already exist).
- **D-10**: These REQs live here with topic-local numbering (REQ-001…029); at JIT slice time they migrate into the donor umbrella spec as `REQ-QT-*` alongside REQ-EV, and tasks are authored as mb-task blocks per AGR-001. — Rationale: `/mb discuss` output stays canonical, umbrella stays the single donor catalog.

## Functional Requirements (EARS)

QA contract & planning:

- **REQ-001** (event-driven): When `/mb qa plan <target>` runs, the system shall create or update a single QA contract at `specs/<topic>/qa.md` whose cases carry `<!-- mb-case:ID -->` markers.
- **REQ-002** (ubiquitous): The system shall classify every QA case origin as exactly one of specified, derived, or regression.
- **REQ-003** (event-driven): When a derived case's expected behavior cannot be inferred from the requirements source, the system shall mark the case NEEDS_SPEC instead of inventing assertions.
- **REQ-004** (ubiquitous): The system shall require every QA case to declare an oracle listing observable facts that prove the requirement.

Requirement sources:

- **REQ-005** (ubiquitous): The system shall resolve requirements through a source adapter interface supporting kinds memory-bank, plan, and diff.
- **REQ-006** (state-driven): While the source kind is diff, the system shall report requirements completeness as UNKNOWN in every produced report.
- **REQ-007** (state-driven): While the source kind is plan, the system shall label report scope as implementation-plan verification.
- **REQ-008** (event-driven): When a QA contract is built or updated, the system shall record the source document digest without copying the source into a second requirements catalog.

Test-to-case linkage:

- **REQ-009** (ubiquitous): The system shall map tests to QA cases via language-agnostic `mb:case` and `mb:covers` comment markers.
- **REQ-010** (state-driven): While a test-to-case mapping is inferred rather than marker-based, the system shall exclude that mapping from strict PASS and flag it in the report.

Runner & evidence:

- **REQ-011** (event-driven): When `/mb qa run` executes, the system shall run configured suites as argv arrays without shell string evaluation.
- **REQ-012** (ubiquitous): The system shall parse suite results through adapters for pytest JUnit XML, Bats TAP, generic JUnit XML, and generic exit-code.
- **REQ-013** (ubiquitous): The system shall compute case statuses PASS, FAIL, MISSING, NOT_RUN, STALE, FLAKY, WAIVED, and NEEDS_SPEC in the deterministic core from parsed runner output only.
- **REQ-014** (event-driven): When a suite run completes, the system shall persist an evidence manifest with run id, git commit, source digest, contract digest, test digest, suite config digest, profile, and timestamp under `.memory-bank/.qa/`.
- **REQ-015** (event-driven): When any digest recorded in an evidence manifest no longer matches the current inputs, the system shall mark that evidence STALE.
- **REQ-016** (unwanted): If a required suite was not executed, then the system shall report its cases as NOT_RUN and never as PASS.

Quality gate & waivers:

- **REQ-017** (ubiquitous): The system shall apply a deterministic, configuration-driven quality gate that produces a machine-readable verdict and process exit code.
- **REQ-018** (unwanted): If a specified case has no verification implementation or its mapped test fails, then the quality gate shall block.
- **REQ-019** (unwanted): If a critical case receives semantic status mismatch, then the quality gate shall block.
- **REQ-020** (event-driven): When a waiver passes its expiry date, the system shall convert it into a blocking gate finding.

Semantic audit:

- **REQ-021** (event-driven): When semantic audit runs, the system shall evaluate each mapped test against its case oracle producing exactly one of strong, weak, mismatch, or uncertain.

Test generation:

- **REQ-022** (optional): Where write mode is enabled, the system shall generate missing tests carrying `mb:case` markers and following existing project test conventions.
- **REQ-023** (event-driven): When a test is generated for not-yet-implemented behavior in TDD mode, the system shall confirm the expected RED result before the product fix proceeds.
- **REQ-024** (event-driven): When the generator selects a verification level for a case, the system shall choose the lowest suitable level instead of defaulting to end-to-end.

`/mb work` integration:

- **REQ-025** (event-driven): When `/mb work <target> --qa` runs, the system shall execute quality actions inside the existing canonical stages without introducing new mandatory stages.
- **REQ-026** (state-driven): While quality is not enabled by config or flag, the system shall keep `/mb work` behavior byte-identical to the current engine.

Reporting & memory:

- **REQ-027** (event-driven): When a QA run completes, the system shall write a report to `.memory-bank/reports/qa-<topic>-latest.md` linking raw artifacts instead of inlining them.
- **REQ-028** (event-driven): When a gate verdict is produced, the system shall update status.md, checklist.md, progress.md, and traceability.md, adding only unresolved actions to the checklist.

CI:

- **REQ-029** (ubiquitous): The system shall execute the pipeline parse, run, collect evidence, gate, report, and exit code without requiring an LLM.

## Non-Functional Requirements

- **NFR-001**: Compatibility — QA is off by default; without `--qa`/`quality.enabled` all existing behavior is byte-identical (project design contract; guarded by regression tests).
- **NFR-002**: CI autonomy — the deterministic pipeline runs with no LLM and no API key; LLM audit results are pre-computed and cached, or run as an optional separate job.
- **NFR-003**: Token economy — semantic audit input is one case + oracle + mapped test + minimal fixtures; results cached by (case digest, test digest) pair, never re-audited on unchanged inputs.
- **NFR-004**: Portability — shell dispatchers run on bash 3.2 and 5.x; Python core targets 3.11+ (CI matrix).
- **NFR-005**: Artifact hygiene — `.memory-bank/.qa/` is gitignore-able runtime data; Markdown reports link artifacts (junit/traces/logs), never inline raw dumps.

## Constraints

- Depends on the donor v6.1.0 evidence core (§7.5 Evidence Manifest, collectors, freshness); Quality Track reuses that contract and must not fork it.
- AGR-002 numbering (as amended by D-03): QA = v6.2.0, 6.x tail shifted +1; REQ-IDs and mb-task numbers never renumbered.
- `scripts/mb-test-run.sh` remains a working compatibility facade for existing callers.
- Suite commands are stored as argv arrays in `pipeline.yaml` — no `eval`, exact command preserved in evidence.
- No new mandatory lifecycle stages: quality actions attach to plan / implement / verify / done (vision §3.2).
- Update-notify (AGR-006) and the donor chain 5.4→6.1 precede any implementation work on this topic.

## Edge Cases & Failure Modes

- Runner binary absent from PATH (e.g. pytest not installed): the required suite is NOT_RUN → gate FAIL (never silently PASS, REQ-016).
- Test file deleted while `qa.md` still lists it as implementation: case → MISSING, gate blocks if the case is specified.
- Orphan `mb:case TC-X` marker in a test with no matching case in `qa.md`: WARNING in report (inverse of MISSING; not a gate blocker).
- Generated test expected RED but passes immediately: forced semantic audit — strong ⇒ behavior already implemented (record as PASS with note), weak/uncertain ⇒ WARNING, mismatch ⇒ FAIL.
- Run interrupted mid-suite (partial JUnit XML): parsed cases keep their results, unparsed cases → NOT_RUN; gate treats required-suite interruption as failure.
- Waiver without expiry or approver: invalid_waiver → gate blocks (fail-closed, mirrors REQ-EV-007).
- Source spec edited between run and gate evaluation: digest mismatch → evidence STALE → gate blocks (REQ-015).
- Two tests mapped to one case: allowed (vision §7.3 lists multiple implementations); case status = worst of the mapped results.
- Empty requirements source (no REQs / no DoD): plan step emits NEEDS_SPEC report; gate result is FAIL with "nothing to verify" diagnostic rather than vacuous PASS.

## Out of Scope (v6.2.0)

- Playwright / browser E2E integration, traces, screenshots (vision Stage 4 → later slice).
- Safe healer and failure classification for auto-repair (vision Stage 4 → later slice; until then PRODUCT_DEFECT vs TEST_DEFECT classification is manual/report-only).
- OpenSpec requirement source adapter (deferred; interface reserved via `source.kind`, aligned with iceboxed v6.7.0).
- Extended adapters: contract/property/mutation testing, accessibility, security, performance, visual regression, chaos (vision Stage 5).
- Native JSON runner adapters (Jest/Vitest/Go/Cypress/Playwright) — covered via generic JUnit until demanded.
- Line coverage as a primary gate metric; enabling QA by default; a second catalog of product requirements; multiple always-read QA documents (single `qa.md` only).

## Open Questions

- O-01: Integration with the sdd-openspec-parity scenario layer — GWT scenarios as direct input to QA cases (mapping `#### Scenario:` → `SCN-*` → `TC-*`). (blocked on: AGR-007 Phase 1 landing; resolve at `/mb sdd quality-track` time)
- O-02: FLAKY detection policy — v6.2.0 has no auto-retry; FLAKY = differing results across manifests with identical digests. Decide retry budget and new-flake gate wiring at design time. (blocked on: design.md)
- O-03: Exact mechanics of migrating REQ-001…029 → umbrella `REQ-QT-*` at slice time (renumber map, traceability continuity). (blocked on: JIT slice creation, AGR-001 procedure)
- O-04: Whether v6.2.0's `quality.generate-red` step reuses `mb-qa` agent as-is or needs a dedicated generator agent prompt. (blocked on: design.md)
