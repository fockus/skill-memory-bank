---
type: spec-tasks
topic: mb-donor-evolution
status: ready
created: 2026-07-15
linked_design: design.md
linked_requirements: requirements.md
source: source-plan.md (§10–§18, §19.2, §29.18, §30.18)
---

# Tasks: mb-donor-evolution

> 132 executable task blocks (mb-task:1–132), normative numbering per source-plan §19.2.
> Release labels use the +1-minor shifted scheme (5.4.0 Baseline … 5.7.0 Plan IR; 6.x unchanged).
> Execute strictly one release slice at a time through a dated plan-as-wrapper
> (`tasks:` range in wrapper frontmatter is the only allowed range for a run).
> Releases 6.5.0 (mb-task:102–116) and 6.6.0 (mb-task:117–132) are ICEBOXED by the
> 2026-07-15 ICE decision — do not activate their wrappers without an explicit thaw.

<!-- mb-task:1 -->
## Task 1: BL-01 — Reconcile status/roadmap/spec metadata

**Release:** 5.4.0
**Priority:** P0
**Covers:** REQ-PGM-003
**Role:** manager
**Depends on:** none
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Reconcile `status.md`, `roadmap.md`, spec frontmatter and task checkboxes against current HEAD (post v5.3.0 release), so reported project state matches reality. Close or explicitly mark superseded any stale active plans, and resolve any drift between claimed and actual test counts / release status without rewriting `progress.md` history.

**Testing (TDD):**
- The deterministic drift suite (`scripts/mb-drift.sh` or equivalent) currently reports N>0 metadata contradictions between status/roadmap/spec-frontmatter/checklist; after the fix the same suite must report 0 contradictions.

**Evidence:**
- `mb-drift.sh` output before/after; diff of `status.md`/`roadmap.md`/`checklist.md`; list of specs whose frontmatter status was corrected.

**DoD:**
- [ ] status.md, roadmap.md and every spec frontmatter/checklist agree on current release (v5.3.0) and project state
- [ ] no active plan/spec references a stale or superseded status without a note
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:1 -->

<!-- mb-task:2 -->
## Task 2: BL-02 — Validate current test/build/package baseline

**Release:** 5.4.0
**Priority:** P0
**Covers:** REQ-PGM-005
**Role:** qa
**Depends on:** none
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Run and record the full pytest/bats/lint/build baseline on current HEAD (relative to the released v5.3.0 tag), producing a baseline evidence report that captures pass/fail counts, timings for quick vs governed `/mb work` flows, worker context size and reviewer/router calibration numbers.

**Testing (TDD):**
- A fresh, timestamped full-suite run (pytest + bats + lint + shellcheck + build) with recorded HEAD SHA is required; no baseline number is accepted without a command transcript backing it.

**Evidence:**
- Full test/lint/build transcripts with timestamps and HEAD SHA; timing table for quick vs governed `/mb work`; measured worker context size vs full-bank size.

**DoD:**
- [ ] baseline evidence report exists with HEAD SHA + timestamp for every recorded metric
- [ ] test/lint/build counts in the report match actual command output
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:2 -->

<!-- mb-task:3 -->
## Task 3: BL-03 — Create umbrella SDD and ADRs

**Release:** 5.4.0
**Priority:** P0
**Covers:** REQ-PGM-001, REQ-PGM-003
**Role:** architect
**Depends on:** BL-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Author the umbrella SDD `mb-donor-evolution` (requirements/design/tasks triple) plus two ADRs: `/mb work` is the sole execution entrypoint/state machine, and core bank files have exactly one orchestrator-writer. Both ADRs and the SDD must be consistent with the metadata reconciled in BL-01.

**Testing (TDD):**
- `scripts/mb-spec-validate.sh mb-donor-evolution --require-scenarios --json` currently fails (spec/tasks incomplete or fail scenario validation); after authoring it must exit 0.

**Evidence:**
- `mb-spec-validate.sh --json` output; ADR files with context/decision/alternatives/consequences sections.

**DoD:**
- [ ] mb-donor-evolution spec triple (requirements/design/tasks) exists and validates
- [ ] both ADRs are committed with context/decision/alternatives/consequences
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:3 -->

<!-- mb-task:4 -->
## Task 4: BL-04 — Supersede obsolete parallel-pipeline design

**Release:** 5.4.0
**Priority:** P0
**Covers:** REQ-PGM-001
**Role:** architect
**Depends on:** BL-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Mark the old `parallel-pipeline` spec as superseded by the mb-donor-evolution architecture, adding an explicit migration note and forward references so nobody plans against the retired design.

**Testing (TDD):**
- A drift/lint check currently allows a spec with terminal-looking content but non-superseded status to remain a default target; after the change, `parallel-pipeline` frontmatter status must resolve to `superseded` and `mb-work-resolve.sh` must no longer offer it as a default target.

**Evidence:**
- parallel-pipeline spec diff (status + migration note); `mb-work-resolve.sh` dry-run output showing it is no longer selected.

**DoD:**
- [ ] parallel-pipeline frontmatter status is `superseded` with a link to mb-donor-evolution
- [ ] mb-work-resolve.sh no longer selects parallel-pipeline as a default target
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:4 -->

<!-- mb-task:5 -->
## Task 5: BL-05 — Close current Unreleased gates

**Release:** 5.4.0
**Priority:** P0
**Covers:** REQ-PGM-005
**Role:** developer
**Depends on:** BL-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Close the Unreleased-gate gaps identified by BL-02's baseline report — scoped to the delta accumulated on `main` after the v5.3.0 release, not a re-litigation of already-shipped work — so the tree reaches release-candidate quality with no hidden red tests described as "pre-existing" without a registered blocker.

**Testing (TDD):**
- BL-02's baseline report currently lists N failing/red or unregistered-red items post-v5.3.0; after this task the same full suite must show 0 unregistered red tests (each remaining red item has a filed blocker + explicit release decision).

**Evidence:**
- Re-run of the full suite compared against BL-02's report; blocker/backlog entries for any deliberately deferred item.

**DoD:**
- [ ] no red test lacks either a fix or a registered blocker + release decision
- [ ] full suite re-run matches or improves on BL-02 baseline counts
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:5 -->

<!-- mb-task:6 -->
## Task 6: BL-06 — Version/changelog/docs/package verification

**Release:** 5.4.0
**Priority:** P0
**Covers:** REQ-PGM-005, REQ-PGM-006
**Role:** qa
**Depends on:** BL-04, BL-05
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Verify VERSION, changelog, package metadata, status and release notes name one consistent version and add a release checklist separating "ready" from "published", producing the v5.3.0 release evidence bundle.

**Testing (TDD):**
- A version-consistency check (VERSION/CHANGELOG/package metadata/status.md) currently may disagree across files; after the task all sources must report the same version string, verified by an automated check.

**Evidence:**
- Version-consistency check output; clean-install/upgrade smoke test transcript; release checklist file.

**DoD:**
- [ ] VERSION, CHANGELOG, package metadata and status.md agree on the same version string
- [ ] release checklist distinguishes readiness from the publish action
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:6 -->

<!-- mb-task:7 -->
## Task 7: CP-01 — Schema and diagnostic envelope

**Release:** 5.5.0
**Priority:** P0
**Covers:** REQ-CP-004, REQ-PGM-004
**Role:** architect
**Depends on:** release gate 5.4.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Design the versioned artifact-state schema (context/requirements/design/tasks/plan) and a diagnostic envelope shared by every control-plane command, so "file exists" is never confused with "valid".

**Testing (TDD):**
- A schema-validation unit test currently has no schema to validate against; after this task, malformed artifact-state fixtures must fail schema validation with a stable diagnostic code, and valid fixtures must pass.

**Evidence:**
- Schema file + JSON-schema validation test transcript; diagnostic-envelope contract test output.

**DoD:**
- [ ] artifact-state schema is versioned and diagnostic envelope has a stable shape (code/message/context)
- [ ] malformed fixtures fail validation; valid fixtures pass
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:7 -->

<!-- mb-task:8 -->
## Task 8: CP-02 — Built-in artifact profiles

**Release:** 5.5.0
**Priority:** P0
**Covers:** REQ-CP-001, REQ-CP-006
**Role:** architect
**Depends on:** release gate 5.4.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the three built-in artifact profiles (`lite`, `standard`, `high-assurance`) with per-profile required/optional artifact lists, so a lite change never demands a design doc unless the profile schema requires it.

**Testing (TDD):**
- No profile fixtures currently exist to assert required-artifact sets; after this task, a profile-resolution test must show `lite` omitting `design` while `high-assurance` requires it, both driven by the same resolver code path.

**Evidence:**
- Profile schema files; profile-resolution test output for all three profiles.

**DoD:**
- [ ] lite/standard/high-assurance profiles are declared with explicit required/optional artifacts
- [ ] profile resolution is data-driven, not hardcoded per-command
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:8 -->

<!-- mb-task:9 -->
## Task 9: CP-03 — DAG/status engine

**Release:** 5.5.0
**Priority:** P0
**Covers:** REQ-CP-001, REQ-CP-002
**Role:** developer
**Depends on:** CP-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the DAG/status engine that detects duplicate artifact IDs, unknown references, cycles and conditional-artifact violations, and reports `mb artifacts status [--json]` deterministically from CP-01's schema.

**Testing (TDD):**
- Cycle/duplicate/unknown-ref fixtures currently have no validator to reject them; after implementation each fixture must produce a non-zero exit and stable diagnostic code, while a valid graph exits 0.

**Evidence:**
- Fixture-driven test suite output (cycle/duplicate/unknown/valid cases); `mb artifacts status --json` sample output.

**DoD:**
- [ ] cycle, duplicate-ID and unknown-reference fixtures are rejected with stable diagnostics
- [ ] `mb artifacts status --json` reflects the schema from CP-01
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:9 -->

<!-- mb-task:10 -->
## Task 10: CP-04 — Exact-context instructions

**Release:** 5.5.0
**Priority:** P0
**Covers:** REQ-CP-003
**Role:** developer
**Depends on:** CP-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement `mb artifacts instructions <artifact-id> [--json]` returning only the exact `context_files` and expected outputs needed for the next artifact, never the full bank.

**Testing (TDD):**
- Currently `instructions` either doesn't exist or returns the whole bank; after implementation, a benchmark fixture must show the returned context pack is a strict subset of full-bank context and covers only files declared relevant to the requested artifact.

**Evidence:**
- Instructions command output for 2+ artifact IDs; context-size comparison (returned pack vs full bank).

**DoD:**
- [ ] `instructions` returns only files relevant to the requested artifact ID
- [ ] output size is measurably smaller than full-bank context on the benchmark fixture
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:10 -->

<!-- mb-task:11 -->
## Task 11: CP-05 — Integrate SDD/plan/work preflight

**Release:** 5.5.0
**Priority:** P0
**Covers:** REQ-CP-005, REQ-PGM-002
**Role:** developer
**Depends on:** CP-03, CP-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Wire the control plane into `/mb sdd`, `/mb plan` and `/mb work` preflight so every existing command consults artifact status/instructions before acting, while remaining backward compatible with sequential `/mb work`.

**Testing (TDD):**
- The existing `/mb sdd`/`/mb plan`/`/mb work` regression suite currently doesn't assert a control-plane preflight call; after wiring, the same commands must still pass their existing tests and additionally invoke/respect CP-03/CP-04 output before dispatch.

**Evidence:**
- Regression-suite transcript for /mb sdd, /mb plan, /mb work showing unchanged external behavior plus preflight invocation.

**DoD:**
- [ ] /mb sdd, /mb plan and sequential /mb work remain fully functional
- [ ] each command consults artifact status/instructions before acting
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:11 -->

<!-- mb-task:12 -->
## Task 12: CP-06 — Legacy import/migration dry-run

**Release:** 5.5.0
**Priority:** P0
**Covers:** REQ-PGM-003, REQ-PGM-004
**Role:** developer
**Depends on:** CP-01, CP-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build a `--dry-run` legacy-import path that derives artifact-profile state from existing SDD triples without mutating them, snapshotting before any real migration and remaining idempotent on repeat runs.

**Testing (TDD):**
- Running the dry-run import twice on the same legacy SDD triple currently has no import path to test; after implementation the second run must produce an identical result to the first (idempotency) and neither run may modify the source files.

**Evidence:**
- Dry-run transcript (two consecutive runs, diffed); snapshot file listing.

**DoD:**
- [ ] legacy SDD triples import into artifact-profile state via --dry-run without mutation
- [ ] repeat dry-run is idempotent (byte-identical import result)
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:12 -->

<!-- mb-task:13 -->
## Task 13: CP-07 — Contract, property and E2E tests

**Release:** 5.5.0
**Priority:** P0
**Covers:** REQ-CP-001, REQ-CP-002, REQ-CP-003, REQ-CP-004, REQ-CP-005, REQ-CP-006
**Role:** qa
**Depends on:** CP-01, CP-02, CP-03, CP-04, CP-05, CP-06
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Deliver the contract/property/E2E test suite for the whole control plane, including a locale-independence property test (same input → semantically identical JSON regardless of locale) and the lite/standard/high-assurance acceptance matrix.

**Testing (TDD):**
- No consolidated CP contract/property/E2E suite currently exists; after this task it must exist and 100% of cycle/unknown/duplicate fixtures must be rejected, and locale variation must not change JSON semantics.

**Evidence:**
- CP contract/property/E2E suite run output; locale-matrix test output (e.g. LC_ALL=C vs LC_ALL=en_US.UTF-8).

**DoD:**
- [ ] contract + property + E2E suite covers REQ-CP-001…REQ-CP-006
- [ ] 100% of cycle/unknown/duplicate fixtures are rejected in the suite
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:13 -->

<!-- mb-task:14 -->
## Task 14: CP-08 — Docs and release evidence

**Release:** 5.5.0
**Priority:** P0
**Covers:** REQ-PGM-005
**Role:** qa
**Depends on:** CP-07
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Write control-plane docs and assemble the v5.5.0 release evidence (acceptance criteria + release metrics from §11.4/11.5), dogfooding the control plane on this very release.

**Testing (TDD):**
- The release-evidence assembler currently has nothing to aggregate for CP; after this task it must produce one report referencing CP-07's suite output and this release's own artifacts validated through the new control plane.

**Evidence:**
- v5.5.0 release evidence report; docs diff; dogfood transcript (this release validated via `mb artifacts validate`).

**DoD:**
- [ ] v5.5.0 release notes/docs describe the control plane commands and profiles
- [ ] this release's own SDD artifacts pass `mb artifacts validate`
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:14 -->

<!-- mb-task:15 -->
## Task 15: RK-01 — Run/state/event-journal schemas

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-001
**Role:** architect
**Depends on:** release gate 5.5.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Design the run/state/event-journal schemas — the program/release→phase→plan→task hierarchy, run store fields (§6.2) and node states (`pending|ready|running|paused|succeeded|failed|skipped|cancelled`) — as the canonical data model for the long-session kernel.

**Testing (TDD):**
- A schema-validation test currently has no run-store schema to check; after this task, fixtures for each declared node state must validate, and an undeclared/typo'd state must fail schema validation.

**Evidence:**
- Run-store schema file; node-state fixture validation output.

**DoD:**
- [ ] run/state/event schemas are versioned and documented
- [ ] all 8 node states are declared and mutually exclusive in the schema
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:15 -->

<!-- mb-task:16 -->
## Task 16: RK-02 — Dispatch/result contract and ownership rules

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-002, REQ-PGM-003
**Role:** architect
**Depends on:** release gate 5.5.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the dispatch/result contract and ownership rules — the thin orchestrator selects next action, builds the dispatch manifest, never edits production source, and is the sole writer of canonical bank state.

**Testing (TDD):**
- A contract test currently has no dispatch/result schema to validate against; after this task, a manifest missing a required ownership field must fail contract validation, and a compliant manifest must pass.

**Evidence:**
- Dispatch/result contract schema + contract-test output; ownership-rule documentation (reference to BL-03's orchestrator-writer ADR).

**DoD:**
- [ ] dispatch manifest and result contract schemas are defined and validated
- [ ] ownership rule (single canonical-state writer) is encoded, not just documented
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:16 -->

<!-- mb-task:17 -->
## Task 17: RK-03 — Atomic run store and event reducer

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-001
**Role:** developer
**Depends on:** RK-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the atomic run store and event reducer — append-only `events.jsonl` with sequence, attempt and idempotency key, and atomic state transitions with optimistic revision.

**Testing (TDD):**
- A concurrent-write test currently has no run store to race against; after implementation, two competing writers attempting the same transition must produce exactly one accepted transition and one rejected-with-conflict, never a corrupted state file.

**Evidence:**
- Concurrency test output; event reducer replay test reconstructing state.json from events.jsonl.

**DoD:**
- [ ] events.jsonl is append-only with sequence/attempt/idempotency key
- [ ] optimistic-revision conflicts are detected, never silently overwritten
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:17 -->

<!-- mb-task:18 -->
## Task 18: RK-04 — Context manifest builder

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-002
**Role:** developer
**Depends on:** RK-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the context manifest builder that assembles the exact-context dispatch package per RK-02's contract, integrating with the existing budget/statusline primitives.

**Testing (TDD):**
- A manifest-shape test currently has nothing to build against; after implementation, a manifest built for a given task must include only its declared owned/read-only paths and satisfy RK-02's schema.

**Evidence:**
- Manifest builder test output; sample manifest for a fixture task.

**DoD:**
- [ ] context manifest builder produces RK-02-schema-valid manifests
- [ ] manifest excludes files not declared relevant to the task
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:18 -->

<!-- mb-task:19 -->
## Task 19: RK-05 — /mb work orchestrator integration

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-002
**Role:** developer
**Depends on:** RK-03, RK-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Integrate the run store, event reducer and manifest builder into `/mb work` as the orchestrator, replacing/augmenting current dispatch logic to run in thin-orchestrator mode.

**Testing (TDD):**
- `/mb work`'s current dispatch-selection tests don't reference a run store; after integration, running `/mb work` on a fixture plan must produce corresponding events.jsonl entries for each dispatched action and a deterministic next_action from the same state.

**Evidence:**
- /mb work fixture-run transcript with matching events.jsonl; regression suite for existing /mb work behavior.

**DoD:**
- [ ] /mb work drives dispatch through the run store/event reducer
- [ ] existing /mb work regression tests still pass
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:19 -->

<!-- mb-task:20 -->
## Task 20: RK-06 — Resume cursor and interrupted-state recovery

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-003, REQ-RK-004
**Role:** developer
**Depends on:** RK-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the resume cursor and interrupted-state recovery per the PLAN↔SUMMARY ledger rules (plan without result = pending/interrupted; result without summary = recovery gate; commit/diff without evidence = verification gate; completed summary/evidence = safe skip).

**Testing (TDD):**
- A kill-mid-task fixture currently has no resume path; after implementation, `/mb work --resume` on each ledger state (pending/result-only/commit-only/completed) must return the documented deterministic next_action for that state.

**Evidence:**
- Four resume fixtures (one per ledger state) with recorded next_action; `/mb work --resume` transcript.

**DoD:**
- [ ] all four PLAN↔SUMMARY ledger states resolve to their documented next_action
- [ ] completed summary/evidence is safely skipped on re-run
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:20 -->

<!-- mb-task:21 -->
## Task 21: RK-07 — Headroom/handoff boundary behavior

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-006
**Role:** developer
**Depends on:** RK-05, RK-06
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Wire context-headroom detection into the orchestrator so that hitting the threshold blocks new heavy-task dispatch and produces a handoff containing the exact resume cursor, reusing existing budget/statusline/handoff primitives.

**Testing (TDD):**
- A headroom-threshold fixture currently has no gate; after implementation, simulating threshold breach must prevent a new heavy task from dispatching and must emit a handoff document with a valid resume cursor.

**Evidence:**
- Headroom-threshold test transcript; sample handoff document with cursor validated against RK-06's resume path.

**DoD:**
- [ ] heavy task dispatch is blocked once headroom threshold is reached
- [ ] handoff document contains a cursor RK-06's resume path can consume
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:21 -->

<!-- mb-task:22 -->
## Task 22: RK-08 — Doctor/rebuild/forensics lite

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-005
**Role:** developer
**Depends on:** RK-03, RK-06
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement `doctor --runs` and dry-run state reconstruction that detects a corrupt `state.json` and rebuilds it from correctness-critical events without deleting anything automatically.

**Testing (TDD):**
- A deliberately corrupted state.json fixture currently has no detector; after implementation `doctor --runs` must flag the corruption and a `--dry-run` reconstruction must propose a rebuilt state without touching the original file.

**Evidence:**
- doctor --runs output on a corrupted fixture; dry-run reconstruction diff (proposed vs original, original untouched).

**DoD:**
- [ ] corrupt state.json is detected by doctor --runs
- [ ] dry-run reconstruction never deletes/mutates files automatically
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:22 -->

<!-- mb-task:23 -->
## Task 23: RK-09 — Crash matrix and dogfood

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-004
**Role:** qa
**Depends on:** RK-05, RK-06, RK-07, RK-08
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build and run the crash-matrix suite (kill/restart at every state transition) plus a dogfood pass of the kernel on a real multi-stage plan, verifying identical safe next_action after each induced crash.

**Testing (TDD):**
- No crash-matrix harness currently exists; after this task, kill/restart injected at each declared node-state transition must reproduce the same safe next_action as an uninterrupted run, for every transition in the matrix.

**Evidence:**
- Crash-matrix suite output (pass/fail per transition); dogfood resume-success log.

**DoD:**
- [ ] crash matrix covers every declared state transition with 0 lost/duplicated completed work
- [ ] dogfood resume-success rate is recorded and meets the ≥95% target
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:23 -->

<!-- mb-task:24 -->
## Task 24: RK-10 — Migration, docs, release

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-PGM-005
**Role:** qa
**Depends on:** RK-09, RK-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Migrate existing `.work-state*` into the new run store (one-time, old files retained until verify succeeds), finalize `execution_engine: classic|v2` defaulting to classic, write docs, and assemble the v5.6.0 release evidence.

**Testing (TDD):**
- A migration-dry-run fixture on a real `.work-state.json` currently has no importer; after this task the importer must produce a valid run-store entry while leaving the original `.work-state.json` untouched until verification succeeds.

**Evidence:**
- Migration dry-run transcript; release evidence report referencing RK-09/RK-11 suite output; docs diff.

**DoD:**
- [ ] .work-state* migrates to the run store without deleting originals pre-verify
- [ ] execution_engine defaults to classic; v2 is opt-in
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:24 -->

<!-- mb-task:25 -->
## Task 25: RK-11 — Run Event V1, replay/idempotency and snapshot reconstruction

**Release:** 5.6.0
**Priority:** P0
**Covers:** REQ-RK-005, REQ-WF-008
**Role:** developer
**Depends on:** RK-03, RK-06, RK-08
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement Run Event V1 with replay/idempotency guarantees and snapshot reconstruction — losing or duplicating a correctness-critical event must be detectable, and replay must never repeat an already-confirmed side effect.

**Testing (TDD):**
- An event-loss and an event-duplication fixture currently have no detector; after implementation both must be flagged, and replaying a confirmed event twice must not create a duplicate checklist/progress mutation.

**Evidence:**
- Event-loss/duplication detection test output; replay-idempotency test output (0 duplicate mutations).

**DoD:**
- [ ] lost or duplicated correctness-critical events are detected
- [ ] replay of a confirmed event produces zero duplicate side effects
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:25 -->

<!-- mb-task:26 -->
## Task 26: PI-01 — Plan IR schema/compiler

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-PI-001
**Role:** architect
**Depends on:** release gate 5.6.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Design the Plan IR schema and compiler that turns existing `mb-task`/`mb-stage` blocks into a typed graph (depends_on, conflicts_with, preconditions/effects, consumes/produces, owned/read-only paths, risk, context cost, verify commands) without inventing a new human authoring format.

**Testing (TDD):**
- A compiler unit test currently has nothing to compile against; after this task, compiling a fixture tasks.md must produce a Plan IR document that validates against the new schema, and a malformed mb-task block must fail compilation with a stable diagnostic.

**Evidence:**
- Plan IR schema file; compiler test output (valid + malformed fixtures).

**DoD:**
- [ ] Plan IR schema captures depends_on/conflicts_with/preconditions/effects/owned-paths/risk/context-cost/verify
- [ ] compiler derives Plan IR from existing mb-task/mb-stage markdown without a new authoring format
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:26 -->

<!-- mb-task:27 -->
## Task 27: PI-02 — Path ownership vocabulary/migration

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-PI-002
**Role:** architect
**Depends on:** release gate 5.6.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the path-ownership vocabulary (owned/read-only paths, unknown-ownership fallback) and a migration path for existing plans/specs that don't declare ownership yet.

**Testing (TDD):**
- An ownership-inference test currently has no vocabulary to validate; after this task, a task with unknown ownership must resolve to serial-only scheduling, and a task with declared overlapping owned_paths against another task must be flagged.

**Evidence:**
- Ownership vocabulary schema; migration script dry-run output on an existing spec.

**DoD:**
- [ ] owned/read-only path vocabulary is defined with an explicit unknown-ownership fallback (serial-only)
- [ ] existing specs migrate to the vocabulary without manual rewrite
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:27 -->

<!-- mb-task:28 -->
## Task 28: PI-03 — Graph validator/toposort

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-PI-002
**Role:** developer
**Depends on:** PI-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the graph validator and deterministic topological sort — unknown dependencies, cycles and duplicate IDs are always rejected, and ownership overlaps are computed from PI-02's vocabulary.

**Testing (TDD):**
- Cycle/unknown-dep/duplicate-ID fixtures currently have no validator; after implementation each must be rejected with a stable diagnostic, and a valid graph must produce the same topological order on repeated runs.

**Evidence:**
- Validator/toposort fixture-suite output; determinism check (same input → same order across N runs).

**DoD:**
- [ ] unknown deps, cycles and duplicate IDs are always rejected
- [ ] topological order is deterministic for identical input
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:28 -->

<!-- mb-task:29 -->
## Task 29: PI-04 — Context-fit checker

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-PI-005
**Role:** developer
**Depends on:** PI-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the context-fit checker enforcing the default 1–3 bounded tasks per worker (configurable `context_pct_max`), returning an actionable decomposition diagnostic for oversized nodes instead of silently dispatching them.

**Testing (TDD):**
- An oversized-node fixture currently has no checker to reject it; after implementation the oversized node must fail the context-fit check with a decomposition diagnostic, while a bounded node passes.

**Evidence:**
- Context-fit checker test output (oversized rejected, bounded accepted); sample decomposition diagnostic.

**DoD:**
- [ ] oversized nodes never dispatch and receive an actionable decomposition diagnostic
- [ ] context_pct_max is configurable and enforced
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:29 -->

<!-- mb-task:30 -->
## Task 30: WF-01 — Typed node union and kind-specific schema

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-WF-001
**Role:** architect
**Depends on:** PI-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the typed node union (`agent|check|transform|loop|approval|cancel`) with kind-specific validation, so a node with an unknown kind or a broken kind-specific schema is rejected before dispatch.

**Testing (TDD):**
- A node with an unrecognized kind currently passes through unchecked; after this task it must be rejected with a stable diagnostic, and one valid fixture per kind must pass its kind-specific schema.

**Evidence:**
- Typed-node-union schema; kind-specific validation test output (6 kinds × valid/invalid fixture).

**DoD:**
- [ ] all 6 node kinds have kind-specific schema validation
- [ ] unknown kind or missing completion gate is rejected before dispatch
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:30 -->

<!-- mb-task:31 -->
## Task 31: WF-02 — Typed condition evaluator and diagnostics

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-WF-002
**Role:** developer
**Depends on:** WF-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the typed condition evaluator with diagnostics — only typed conditions are allowed, arbitrary expression evaluation is forbidden, and an invalid condition fails loudly rather than silently skipping.

**Testing (TDD):**
- An invalid/malformed condition fixture currently has no evaluator to reject it; after implementation it must fail with a stable diagnostic (never a silent skip), while valid typed conditions evaluate correctly.

**Evidence:**
- Condition-evaluator fixture-suite output including the invalid-condition-never-silent-skip case.

**DoD:**
- [ ] invalid conditions always fail loudly, never silently skip
- [ ] arbitrary expression evaluation is structurally impossible (typed-only)
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:31 -->

<!-- mb-task:32 -->
## Task 32: PI-05 — Wave planner and critical path

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-PI-003, REQ-PI-004
**Role:** developer
**Depends on:** PI-02, PI-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the wave planner with `--dry-run`, critical-path computation and an explicit reason string whenever two nodes are forced into serial execution (overlap, unknown ownership or declared conflict).

**Testing (TDD):**
- An overlapping-owned-paths fixture currently has no wave planner to split it; after implementation the two nodes must never land in the same wave, and the planner must emit a human-readable serialization reason.

**Evidence:**
- Wave planner --dry-run output (fixture graph, critical path highlighted); serialization-reason log for the overlap case.

**DoD:**
- [ ] overlapping owned_paths never co-schedule in the same wave
- [ ] every forced serialization has an explicit reason
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:32 -->

<!-- mb-task:33 -->
## Task 33: PI-06 — Pre-spawn analysis renderer

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-PI-004
**Role:** developer
**Depends on:** PI-02, PI-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the CCPM-style pre-spawn stream-analysis renderer that shows, before dispatch, which nodes are eligible to run concurrently given the current ownership/context-fit results from PI-02/PI-04.

**Testing (TDD):**
- A pre-spawn render currently doesn't exist; after implementation, running it against a fixture graph with known conflicts must list exactly the conflict-free concurrent stream and exclude conflicting/oversized nodes.

**Evidence:**
- Pre-spawn renderer output on a fixture graph (concurrent streams list) cross-checked against PI-04/PI-05 results.

**DoD:**
- [ ] renderer output matches PI-04/PI-05's ownership and context-fit results (no unauthorized concurrency suggested)
- [ ] oversized/conflicting nodes are excluded from suggested streams
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:33 -->

<!-- mb-task:34 -->
## Task 34: WF-03 — Join-policy readiness/skipping model

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-WF-003
**Role:** developer
**Depends on:** PI-03, WF-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the join-policy readiness/skipping model with truth-table fixtures for all four join policies across success/failure/skip/cancel combinations of upstream branches.

**Testing (TDD):**
- No join-policy engine currently exists; after implementation, each of the 4 policies × 4 outcome combinations (16 truth-table cases) must resolve to its documented ready/skipped/blocked state.

**Evidence:**
- Join-policy truth-table test output (16/16 cases passing).

**DoD:**
- [ ] all four join policies have truth-table fixtures for success/failure/skip/cancel
- [ ] every combination resolves deterministically to ready/skipped/blocked
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:34 -->

<!-- mb-task:35 -->
## Task 35: WF-04 — Typed input/output references and schema checks

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-WF-007
**Role:** developer
**Depends on:** WF-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement typed input/output references with schema validation, ensuring large outputs pass by artifact reference rather than prompt substitution, laying the groundwork for the artifact-evidence linkage used later by EV-11.

**Testing (TDD):**
- A fixture with an oversized output currently gets inlined into the next prompt; after implementation it must be passed as an artifact reference, and a schema-mismatched I/O reference must fail validation before dispatch.

**Evidence:**
- Typed I/O reference schema; test output showing large-output-as-artifact-ref and schema-mismatch rejection.

**DoD:**
- [ ] large outputs are passed as artifact refs, never inlined into prompts
- [ ] schema-mismatched input/output references are rejected before dispatch
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:35 -->

<!-- mb-task:36 -->
## Task 36: WF-05 — Bounded loop and completion-gate contract

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-WF-005
**Role:** architect
**Depends on:** WF-01, WF-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Design and specify the bounded-loop and completion-gate contract that compiles into the graph in this release, with production loop runners deferred to v6.0 (XN-03).

**Testing (TDD):**
- A loop-node fixture without a deterministic completion gate currently has no rejection path; after this task it must fail graph validation, and a fixture with a valid bounded completion gate must compile successfully.

**Evidence:**
- Bounded-loop contract schema; validation test output (missing-gate rejected, valid-gate compiles).

**DoD:**
- [ ] loop nodes without a deterministic completion gate are rejected at compile time
- [ ] bounded-loop contract compiles into the graph without requiring a production runner yet
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:36 -->

<!-- mb-task:37 -->
## Task 37: WF-06 — Approval/cancel contracts and decision digest

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-WF-006
**Role:** architect
**Depends on:** WF-01, WF-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Design and specify the approval/cancel contract and decision digest — approval after rework must bind only to the new artifact digest, with production runners deferred to v6.0 (XN-04).

**Testing (TDD):**
- An approval-node fixture with a stale digest (pre-rework) currently has no binding check; after this task, an approval bound to a stale digest must fail validation, and one bound to the current digest must pass.

**Evidence:**
- Approval/cancel contract schema; decision-digest binding test output.

**DoD:**
- [ ] approval decisions bind to the current artifact digest, never a stale one
- [ ] approval/cancel contract compiles into the graph without requiring a production runner yet
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:37 -->

<!-- mb-task:38 -->
## Task 38: PI-07 — Work preflight and typed-graph dry-run integration

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-PI-006
**Role:** developer
**Depends on:** PI-05, PI-06, WF-02, WF-03, WF-04, WF-05, WF-06
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Integrate the Plan IR/typed-graph dry-run into `/mb work` preflight, so every dispatch is preceded by validation, wave planning and pre-spawn analysis using the components built in this release, while the executor itself stays sequential.

**Testing (TDD):**
- `/mb work`'s existing preflight regression suite currently doesn't invoke Plan IR validation; after integration, dispatching against an invalid graph (cycle/conflict/oversized) must be blocked at preflight, while a valid graph proceeds sequentially as before.

**Evidence:**
- /mb work preflight regression transcript (valid + invalid graph cases); confirmation the executor remains sequential this release.

**DoD:**
- [ ] /mb work preflight runs Plan IR validation, context-fit and pre-spawn analysis before dispatch
- [ ] invalid graphs are blocked at preflight; valid graphs execute sequentially unchanged
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:38 -->

<!-- mb-task:39 -->
## Task 39: PI-08 — Property/fuzz/fixture tests and release

**Release:** 5.7.0
**Priority:** P0
**Covers:** REQ-PI-001, REQ-PI-002, REQ-PI-003, REQ-PI-004, REQ-PI-005, REQ-PI-006, REQ-WF-001, REQ-WF-002, REQ-WF-003, REQ-WF-004, REQ-WF-005, REQ-WF-006, REQ-WF-007, REQ-PGM-005
**Role:** qa
**Depends on:** PI-07
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Deliver the property/fuzz/fixture test suite for Plan IR and typed workflow nodes (scheduler determinism, 0 declared-conflict co-scheduling, 0 false-ready nodes, ≥90% dogfood tasks within declared context budget) and assemble the v5.7.0 release evidence.

**Testing (TDD):**
- No consolidated property/fuzz suite currently exists for Plan IR/WF; after this task, 100% of scheduler-determinism fixtures must pass and 0 false-ready nodes must appear across the property-test corpus.

**Evidence:**
- Property/fuzz/fixture suite output; v5.7.0 release evidence report (determinism %, conflict co-scheduling count, context-budget compliance %).

**DoD:**
- [ ] scheduler determinism is 100% across fixtures; 0 false-ready nodes in property tests
- [ ] release evidence records context-budget compliance ≥90% on dogfood tasks
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:39 -->

<!-- mb-task:40 -->
## Task 40: EX-01 — Capability probe and degradation policy

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-005, REQ-PI-004
**Role:** architect
**Depends on:** release gate 5.7.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the host capability probe and degradation policy (full waves / fresh sequential / classic / halt) that decides, before planning concurrency, which execution mode the current host supports.

**Testing (TDD):**
- A host-without-spawn fixture currently has no probe to detect it; after implementation the probe must select `classic` degradation for that host and `full waves` for a capability-complete host, verified by a documented decision matrix.

**Evidence:**
- Capability probe test output across the 4 degradation modes; decision-matrix documentation.

**DoD:**
- [ ] capability probe selects the correct one of full-waves/fresh-sequential/classic/halt per host profile
- [ ] policy decision is documented and testable, not implicit
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:40 -->

<!-- mb-task:41 -->
## Task 41: EX-02 — Worktree ownership/lifecycle design

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-001
**Role:** devops
**Depends on:** release gate 5.7.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Design the worktree ownership/lifecycle model — one source tree and Git index per writer, baseline SHA and dirty-state preflight, reuse only on matching run/task ownership, and non-destructive orphan discovery/repair hints.

**Testing (TDD):**
- An orphaned-worktree fixture currently has no discovery mechanism; after this task, orphan discovery must list it with a non-destructive repair hint, never auto-deleting it.

**Evidence:**
- Worktree lifecycle design doc; orphan-discovery test output (fixture worktree flagged, not deleted).

**DoD:**
- [ ] worktree lifecycle model enforces one Git index per writer with baseline SHA/dirty-state preflight
- [ ] orphan discovery never auto-deletes; only proposes non-destructive repair
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:41 -->

<!-- mb-task:42 -->
## Task 42: EX-03 — Worktree manager

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-001, REQ-EX-006
**Role:** devops
**Depends on:** EX-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the worktree manager per EX-02's design, including reuse-on-ownership-match and portability across supported hosts (documented degradation where worktree capability is unsupported).

**Testing (TDD):**
- A same-run/same-task reuse fixture currently has no manager to test; after implementation the manager must reuse the existing worktree for a matching run/task and create a fresh one otherwise, verified on at least two host configurations.

**Evidence:**
- Worktree manager test output (reuse + fresh-create cases); portability matrix across tested hosts.

**DoD:**
- [ ] worktree manager reuses only on exact run/task ownership match
- [ ] unsupported-worktree-capability hosts get documented degradation, not a crash
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:42 -->

<!-- mb-task:43 -->
## Task 43: EX-04 — Lease/claim manager

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-002
**Role:** developer
**Depends on:** EX-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the worker lease/claim manager with expiry and an explicit takeover policy, so a stalled worker's lease can be safely reclaimed without a second writer racing the first.

**Testing (TDD):**
- An expired-lease fixture currently has no takeover mechanism; after implementation, a second worker attempting to claim a non-expired lease must be rejected, while an expired lease must be safely reclaimed by exactly one taker.

**Evidence:**
- Lease/claim test output (rejection on live lease, single-winner reclaim on expired lease).

**DoD:**
- [ ] a live lease cannot be claimed by a second worker
- [ ] expired-lease takeover is safe and produces exactly one winner
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:43 -->

<!-- mb-task:44 -->
## Task 44: EX-05 — Worker result directories and guards

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-002, REQ-EX-003
**Role:** developer
**Depends on:** EX-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement worker-specific output directories and write guards ensuring a worker can only write inside its own result path and never touches another worker's directory or the shared `.memory-bank/` core state.

**Testing (TDD):**
- A worker attempting to write outside its declared output directory currently isn't blocked; after implementation such a write must be rejected/guarded, while writes inside its own directory succeed.

**Evidence:**
- Write-guard test output (in-bounds write succeeds, out-of-bounds write blocked with diagnostic).

**DoD:**
- [ ] worker writes are confined to its own result directory
- [ ] no shared writable symlink onto .memory-bank/ exists
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:44 -->

<!-- mb-task:45 -->
## Task 45: EX-06 — Wave dispatcher/collector

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-004
**Role:** developer
**Depends on:** EX-03, EX-04, EX-05
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the wave dispatcher/collector that spawns ready-wave workers into their worktrees/leases/output directories and collects their results, honoring barrier semantics between waves.

**Testing (TDD):**
- A two-wave fixture currently has no dispatcher; after implementation, wave 2 nodes must not start before all wave 1 nodes reach a terminal state (barrier), and the collector must gather every wave-1 result before advancing.

**Evidence:**
- Dispatcher/collector test output showing barrier enforcement across 2 waves.

**DoD:**
- [ ] no wave-2 node starts before the wave-1 barrier is satisfied
- [ ] collector gathers all dispatched results before signaling wave completion
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:45 -->

<!-- mb-task:46 -->
## Task 46: EX-07 — Sequential integrator/conflict preservation

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-004
**Role:** developer
**Depends on:** EX-03, EX-05
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the sequential integrator that validates each worker's result/evidence, checks owned paths, integrates commit/diff per commit policy, updates bank state through the single writer, and halts on conflict while preserving the worktree.

**Testing (TDD):**
- A worker result that writes outside its owned paths currently isn't blocked at integration; after implementation such a result must be rejected with the worktree preserved (not deleted), while a compliant result integrates cleanly.

**Evidence:**
- Integrator test output (conflict case preserves worktree + diagnostic; clean case integrates and updates bank state via single writer).

**DoD:**
- [ ] out-of-owned-path writes are blocked at integration, never silently merged
- [ ] conflicting integration preserves source/result/evidence for recovery
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:46 -->

<!-- mb-task:47 -->
## Task 47: EX-08 — /mb work --parallel orchestration

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-005
**Role:** developer
**Depends on:** EX-06, EX-07, XN-02, XN-03, XN-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement `/mb work --parallel` orchestration tying together the wave dispatcher/collector, sequential integrator and the typed-node runtimes (condition/join, loop, approval) so a mixed-node graph executes end-to-end under the chosen degradation mode.

**Testing (TDD):**
- An end-to-end fixture graph mixing agent/check/transform/loop/approval nodes currently has no `--parallel` entrypoint; after implementation running `/mb work --parallel` on it must complete with the correct terminal states for every node kind and update bank state through the single writer only.

**Evidence:**
- End-to-end `/mb work --parallel` transcript on the mixed-node fixture; bank-state diff showing single-writer updates only.

**DoD:**
- [ ] /mb work --parallel executes a mixed-node fixture graph to correct terminal states
- [ ] canonical bank state is updated only by the orchestrator, never by workers
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:47 -->

<!-- mb-task:48 -->
## Task 48: EX-09 — Sequential/classic fallbacks

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-005, REQ-PI-004
**Role:** developer
**Depends on:** EX-01, EX-08
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the fresh-sequential and classic fallback modes so a host without full parallel-worktree capability (or without spawn capability at all) still executes the same plan correctly, just without concurrency speedup.

**Testing (TDD):**
- Forcing EX-01's probe to report "no worktree capability" currently has no fallback path wired end-to-end; after implementation the same fixture graph must complete correctly in fresh-sequential mode, and forcing "no spawn" must complete correctly in classic mode.

**Evidence:**
- Fallback-mode test transcripts (fresh-sequential + classic) on the same fixture graph used for EX-08, showing equivalent terminal states.

**DoD:**
- [ ] fresh-sequential and classic modes both reach the same correct terminal states as full-waves on the fixture graph
- [ ] mode selection follows EX-01's capability probe without manual override needed
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:48 -->

<!-- mb-task:49 -->
## Task 49: EX-10 — Fault injection, race and portability tests

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-EX-006
**Role:** qa
**Depends on:** EX-08, EX-09
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Run fault-injection, race and portability tests against the parallel execution engine — same-index race attempts, owned-path conflict injection, worker crash mid-wave — across the supported host matrix.

**Testing (TDD):**
- No fault-injection harness currently exists for the parallel engine; after this task, injected same-index races and owned-path conflicts must be caught with 0 undetected occurrences across the fault suite, and the suite must run on every supported host in the portability matrix.

**Evidence:**
- Fault-injection suite output (races/conflicts: 0 undetected); portability matrix run log (per-host pass/fail).

**DoD:**
- [ ] fault suite shows 0 same-index races and 0 undetected owned-path conflicts
- [ ] portability matrix covers every supported host with recorded pass/fail
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:49 -->

<!-- mb-task:50 -->
## Task 50: EX-11 — Migration/docs/dogfood/release

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-PGM-005
**Role:** qa
**Depends on:** EX-10
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Migrate legacy manual `MB_WORK_PARALLEL` state (import or terminate into classic mode), inventory pre-migration worktrees without deleting unknowns, dogfood the parallel engine on a real multi-task release slice, write docs, and assemble the v6.0.0 release evidence.

**Testing (TDD):**
- A fixture repo with legacy `MB_WORK_PARALLEL` state and an orphan worktree currently has no migration path; after this task the legacy state must resolve to classic mode or be cleanly imported, and the orphan worktree must appear in the inventory, untouched.

**Evidence:**
- Migration/inventory transcript; dogfood run log on a real multi-task slice; v6.0.0 release evidence report referencing EX-10's fault-suite results and the ≥1.3x speedup benchmark on ≥4 independent nodes.

**DoD:**
- [ ] legacy MB_WORK_PARALLEL state is migrated or safely defaulted to classic
- [ ] pre-migration worktree inventory never deletes unknown worktrees
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:50 -->

<!-- mb-task:51 -->
## Task 51: XN-01 — Native agent/check/transform runners

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-WF-001, REQ-WF-004
**Role:** developer
**Depends on:** WF-01, WF-04, EX-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the native `agent`/`check`/`transform` runner boundary — scoped provider dispatch for `agent`, argv-based test/lint/schema commands for `check`, and deterministic typed conversion without model judgment for `transform`.

**Testing (TDD):**
- A `check` node fixture running a real lint command currently has no native runner; after implementation it must execute the exact argv, capture pass/fail deterministically, and a `transform` node must produce identical typed output on repeated runs without invoking a model.

**Evidence:**
- Native runner test output for agent/check/transform kinds; determinism check for transform (same input → same output, N runs).

**DoD:**
- [ ] check/transform nodes execute deterministically without AI judgment
- [ ] agent nodes dispatch through the scoped provider boundary only
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:51 -->

<!-- mb-task:52 -->
## Task 52: XN-02 — Condition/join runtime and terminal-state reducer

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-WF-002, REQ-WF-003, REQ-WF-008
**Role:** developer
**Depends on:** WF-02, WF-03, RK-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the condition/join runtime and terminal-state reducer that computes ready/skipped/blocked purely from typed outputs and terminal dependency states, wired to RK-11's Run Event V1.

**Testing (TDD):**
- The WF-03 truth-table fixtures currently run against a design-only model; after implementation, the same 16 truth-table cases must execute against the real runtime and match documented outcomes exactly, backed by Run Event V1 records.

**Evidence:**
- XN-02 runtime truth-table execution output (16/16 matching WF-03 design); Run Event V1 trace for a fixture run.

**DoD:**
- [ ] condition/join runtime reproduces all WF-02/WF-03 truth-table outcomes at execution time
- [ ] ready/skipped/blocked decisions are derived only from typed outputs and terminal states
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:52 -->

<!-- mb-task:53 -->
## Task 53: XN-03 — Bounded loop runner with deterministic completion

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-WF-005
**Role:** developer
**Depends on:** WF-05, XN-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the bounded loop runner with deterministic completion, executing WF-05's contract at runtime and terminating on either the completion gate or the declared bound, whichever comes first — loop exhaustion is a distinct, audit-visible outcome, never masked as a generic failure.

**Testing (TDD):**
- A loop fixture designed to exceed its bound currently has no runner to enforce termination; after implementation it must terminate at the declared bound with an explicit `loop_exhausted` outcome, distinct from `failed`.

**Evidence:**
- Bounded-loop runner test output (completion-gate success case + bound-exhaustion case with distinct outcome code).

**DoD:**
- [ ] loop terminates at completion gate or declared bound, never runs unbounded
- [ ] loop exhaustion is a distinct audit-visible outcome, not a generic failure
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:53 -->

<!-- mb-task:54 -->
## Task 54: XN-04 — Approval/rework/cancel runtime

**Release:** 6.0.0
**Priority:** P1
**Covers:** REQ-WF-006
**Role:** developer
**Depends on:** WF-06, RK-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the approval/rework/cancel runtime executing WF-06's contract — a durable pause on approval nodes, rework re-binding to the new artifact digest, and cancellation as a controlled terminal transition, all recorded as distinct audit-visible outcomes via RK-11's event journal.

**Testing (TDD):**
- An approval-then-rework fixture currently has no runtime; after implementation, approving after rework must only accept the new digest (a stale-digest approval attempt must be rejected), and cancellation must reach a terminal state without being confused with `failed`.

**Evidence:**
- Approval/rework/cancel runtime test output (stale-digest rejection, rework re-approval success, distinct cancel outcome); RK-11 event trace for the fixture.

**DoD:**
- [ ] approval after rework binds only to the new artifact digest
- [ ] rejection and cancellation are distinct, audit-visible, non-generic outcomes
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:54 -->

<!-- mb-task:55 -->
## Task 55: EV-01 — Evidence schema/freshness/diagnostics

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-001
**Role:** architect
**Depends on:** release gate 6.0.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Design the Evidence Manifest contract (§7.5) and a deterministic freshness check tying evidence to current SHA/diff/spec/plan hashes, invalidated after integration or replan.

**Testing (TDD):**
- An evidence-manifest fixture tied to a stale SHA currently isn't flagged; after this task the freshness check must mark it stale, while a manifest matching current SHA/diff/spec/plan hashes must pass as fresh.

**Evidence:**
- Evidence Manifest schema; freshness-check test output (stale + fresh cases).

**DoD:**
- [ ] Evidence Manifest schema is versioned and includes SHA/diff/spec/plan hash fields
- [ ] freshness check correctly flags stale evidence after integration/replan
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:55 -->

<!-- mb-task:56 -->
## Task 56: EV-02 — Risk-based evidence policy

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-002
**Role:** architect
**Depends on:** release gate 6.0.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the risk-based evidence policy — low-risk docs/config get evidence-lite, behavior changes require tests + scope/diff, and security/data-migration/public-API changes require an independent verifier plus UAT/human gate.

**Testing (TDD):**
- A fixture task tagged security/data-migration currently isn't forced through an independent-verifier gate; after this task it must be, while a docs-only fixture is correctly routed to evidence-lite.

**Evidence:**
- Risk-policy schema/decision table; policy-routing test output for all three risk tiers.

**DoD:**
- [ ] all three risk tiers route to their documented evidence requirement
- [ ] security/data-migration/public-API tier always requires independent verifier + UAT gate
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:56 -->

<!-- mb-task:57 -->
## Task 57: EV-03 — Evidence collectors for tests/lint/diff/review

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-001
**Role:** developer
**Depends on:** EV-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement evidence collectors for tests/lint/diff/review that populate EV-01's Evidence Manifest from real command output, so a failed command can never become passing evidence.

**Testing (TDD):**
- A collector fed a failing test-command output currently has nothing to prevent misclassification; after implementation feeding it a failing run must record `failed` in the manifest, never `passed`.

**Evidence:**
- Collector test output for tests/lint/diff/review sources, including the failing-command-never-becomes-passing case.

**DoD:**
- [ ] a failed command's evidence entry is always recorded as failed, never passed
- [ ] collectors cover tests, lint, diff and review sources
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:57 -->

<!-- mb-task:58 -->
## Task 58: EV-04 — Plan checker and evidence plan

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-002
**Role:** developer
**Depends on:** EV-01, EV-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the pre-dispatch plan checker validating bounded goal, acceptance testability, context fit, ownership/dependencies and the presence of a required evidence plan, using EV-02's risk policy to decide strictness.

**Testing (TDD):**
- A plan fixture missing a required evidence plan for its risk tier currently passes preflight; after implementation it must be blocked with an actionable diagnostic, while a compliant plan passes.

**Evidence:**
- Plan-checker test output (missing-evidence-plan blocked, compliant plan passes) across all three risk tiers.

**DoD:**
- [ ] plan checker blocks dispatch when a required evidence plan is missing for the task's risk tier
- [ ] bounded-goal, testability, context-fit and ownership checks are enforced together
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:58 -->

<!-- mb-task:59 -->
## Task 59: EV-05 — Verification report and release aggregator

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-002, REQ-EV-006
**Role:** developer
**Depends on:** EV-03, EV-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the verification report (statuses `passed|failed|unverified|waived`) and the release evidence aggregator that composes task-level evidence into release-level evidence without re-authoring it.

**Testing (TDD):**
- Aggregating two fixture tasks with known statuses currently has no aggregator; after implementation the release report must reflect exactly the union of task statuses (no status invented or dropped), and a critical `waived` entry must require a recorded human approval + rationale.

**Evidence:**
- Verification report + aggregator test output; waiver-without-approval rejection case.

**DoD:**
- [ ] release evidence is aggregated from task evidence only, never fabricated
- [ ] critical waivers require explicit human approval + rationale
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:59 -->

<!-- mb-task:60 -->
## Task 60: EV-06 — Resumable UAT

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-003
**Role:** qa
**Depends on:** EV-01, EV-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the resumable `uat.md` format with scenario IDs, observed result, evidence ref and disposition, so a UAT pass can be interrupted and resumed without losing prior scenario results.

**Testing (TDD):**
- An interrupted UAT run currently has no resume path; after implementation resuming `uat.md` must preserve already-recorded scenario dispositions and continue only with remaining scenarios.

**Evidence:**
- uat.md fixture with interrupted + resumed run, diffed to show prior dispositions preserved.

**DoD:**
- [ ] uat.md scenarios each carry ID, observed result, evidence ref and disposition
- [ ] resuming a UAT pass never loses already-recorded scenario dispositions
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:60 -->

<!-- mb-task:61 -->
## Task 61: EV-07 — Gap diagnosis and gap Plan IR

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-004
**Role:** developer
**Depends on:** EV-05, EV-06
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement gap diagnosis and bounded gap Plan IR generation — dispatching a fresh diagnosis agent against failed/unverified verification-report or UAT entries and compiling a gap-only Plan IR scoped strictly to those failures and their dependencies.

**Testing (TDD):**
- A verification report with 2 failed criteria among 10 currently has no gap-plan generator; after implementation the generated gap Plan IR must contain exactly the 2 failed criteria (plus true dependencies), never the other 8 passing ones.

**Evidence:**
- Gap Plan IR output for a fixture verification report; scope-check confirming no unrelated criteria are included.

**DoD:**
- [ ] gap Plan IR is scoped only to failed/unverified criteria and their real dependencies
- [ ] diagnosis runs in a fresh agent context, not the polluted original context
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:61 -->

<!-- mb-task:62 -->
## Task 62: EV-08 — gaps-only execute/reverify

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-005
**Role:** developer
**Depends on:** EV-07
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement `gaps-only` execution and reverification that runs only the gap Plan IR from EV-07, then reverifies exactly the affected scope, refusing to reuse evidence invalidated by newer changes since the gap was diagnosed.

**Testing (TDD):**
- A reverify fixture where source files changed after the gap plan was generated currently would reuse stale evidence; after implementation reverification must detect the staleness (via EV-01 freshness) and re-collect evidence rather than reuse it.

**Evidence:**
- gaps-only execution transcript; reverification output showing stale-evidence rejection and fresh re-collection.

**DoD:**
- [ ] gaps-only execution touches only the affected scope from the gap plan
- [ ] reverification never reuses evidence invalidated by newer changes
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:62 -->

<!-- mb-task:63 -->
## Task 63: EV-09 — Adversarial false-done/freshness evals

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-006
**Role:** qa
**Depends on:** EV-03, EV-04, EV-05, EV-06, EV-07, EV-08
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Run adversarial false-done and freshness-evasion evaluations against the whole evidence/gap-closure chain, measuring the reduction in false-done rate versus the v5.3.0 baseline recorded in BL-02.

**Testing (TDD):**
- An adversarial fixture attempting to mark a failing task as done (stale evidence, forged pass, fabricated aggregation) currently may succeed on the pre-evidence-layer system; after this task every such adversarial fixture must be caught.

**Evidence:**
- Adversarial eval suite output (100% of attempted false-done fixtures caught); false-done-rate comparison against BL-02 baseline (≥50% reduction target).

**DoD:**
- [ ] adversarial false-done/freshness-evasion fixtures are all caught
- [ ] measured false-done rate reduction vs BL-02 baseline is recorded (target ≥50%)
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:63 -->

<!-- mb-task:64 -->
## Task 64: EV-10 — Dogfood, docs and release

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-PGM-005
**Role:** qa
**Depends on:** EV-09, EV-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Dogfood the full evidence/UAT/gap-closure chain on a real release slice, write docs, and assemble the v6.1.0 release evidence bundle aggregating EV-09's adversarial results and EV-11's artifact-manifest evidence.

**Testing (TDD):**
- Assembling v6.1.0 release evidence currently has nothing to aggregate; after this task the aggregator must produce one report referencing EV-09 and EV-11 output plus a real dogfood run transcript.

**Evidence:**
- v6.1.0 release evidence report; dogfood transcript; docs diff.

**DoD:**
- [ ] v6.1.0 release evidence aggregates EV-09 and EV-11 results plus a real dogfood run
- [ ] docs describe the evidence/UAT/gap-closure workflow end-to-end
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:64 -->

<!-- mb-task:65 -->
## Task 65: EV-11 — Typed node artifacts, required/advisory policy and manifest index

**Release:** 6.1.0
**Priority:** P1
**Covers:** REQ-EV-007, REQ-WF-007
**Role:** developer
**Depends on:** EV-01, WF-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement Typed Node Artifact V1 (per-node metadata, semantic type, checksum, schema ref, producer, evidence refs) built from immutable per-node manifests rather than one shared mutable index file, enforcing that a `required` artifact write failure blocks producer-node success while `advisory` output never participates in the completion gate.

**Testing (TDD):**
- A producer node with a checksum-mismatched required artifact currently could still report success; after implementation that node must fail, and two nodes producing colliding sanitized artifact IDs must be detected before either writes manifest metadata.

**Evidence:**
- Typed-artifact test output (required-artifact checksum-mismatch blocks producer; advisory-output-never-blocks case; sanitized-ID-collision detection case).

**DoD:**
- [ ] required artifact with missing bytes/checksum mismatch/schema failure blocks the producer node
- [ ] advisory output is clearly separated and never blocks completion
- [ ] sanitized node-ID collisions are detected before manifest metadata is written
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:65 -->

<!-- mb-task:66 -->
## Task 66: SR-01 — Registry schema and stable ID policy

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-001
**Role:** architect
**Depends on:** release gate 5.5.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the canonical capability registry schema (stable capability ID/version, trigger/negative trigger, inputs/outputs, side effects/risk, required/optional host capabilities, context cost, eval references) and the stable-ID allocation policy that all later registry generation and validation rely on.

**Testing (TDD):**
- Schema/contract tests reject fixtures with duplicate capability IDs and with broken tool/agent references before any generator exists.

**Evidence:**
- Schema definition + fixture validation run showing pass/fail on valid vs. invalid sample entries.

**DoD:**
- [ ] Registry schema and stable-ID policy documented and machine-validatable
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:66 -->

<!-- mb-task:67 -->
## Task 67: SR-02 — Eval case schema/runner contract

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-004
**Role:** qa
**Depends on:** release gate 5.5.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the eval case schema and runner contract covering positive triggers, negative/ambiguous triggers, pressure/rationalization cases, required side-effect boundaries, cross-host semantic parity and long-session resume/scheduler scenarios, so later corpora (SR-06) and conformance suites (SR-07) share one contract.

**Testing (TDD):**
- Runner contract tests validate that a sample case of each required eval category conforms to the schema and that a malformed case is rejected.

**Evidence:**
- Eval schema definition + runner contract fixture run output.

**DoD:**
- [ ] Eval case schema and runner contract cover all six required case categories
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:67 -->

<!-- mb-task:68 -->
## Task 68: SR-03 — Registry generator/validator

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-001, REQ-SR-006
**Role:** developer
**Depends on:** SR-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the generator that produces the capability registry from canonical sources (existing skills, agents, commands, workflows, adapters) without becoming a second place to edit workflow definitions, plus the validator enforcing the SR-01 schema and duplicate-ID/broken-reference rules.

**Testing (TDD):**
- Regenerating the registry twice from unchanged canonical sources is byte-identical (determinism); validator fails closed on injected duplicate-ID and broken-reference fixtures.

**Evidence:**
- Registry generation command output + diff between two consecutive runs.

**DoD:**
- [ ] Registry generation is deterministic and validator rejects duplicate IDs/broken references
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:68 -->

<!-- mb-task:69 -->
## Task 69: SR-04 — Adapter capability manifests

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-003, REQ-SR-007
**Role:** developer
**Depends on:** SR-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Author adapter capability manifests declaring tiered levels (`structured_output`, `session_resume`, `sandbox`, `tool_policy`/`subagents`/`worktrees`/`hooks` where applicable: `native|adapter|emulated|unsupported` or the matching tier) instead of ambiguous booleans, and the documented degradation path per unsupported capability.

**Testing (TDD):**
- Manifest schema tests reject boolean-only capability declarations; a manifest claiming `enforced` without a matching conformance proof fails validation.

**Evidence:**
- Manifest schema validation run against sample adapter manifests.

**DoD:**
- [ ] Every adapter manifest declares tiered capability levels with an explicit degradation path
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:69 -->

<!-- mb-task:70 -->
## Task 70: SR-05 — Two-stage router + explanations

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-002, REQ-SR-008
**Role:** developer
**Depends on:** SR-03, SR-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the two-stage router: stage 1 does cheap candidate selection from registry metadata, stage 2 loads the full skill/workflow only for selected candidates; explicit command/skill invocation always wins, and the router emits a human-readable explanation for the chosen route.

**Testing (TDD):**
- Router tests assert explicit invocation always overrides auto-routed candidates, and an ambiguous write-capable route either asks for a choice or fails closed (never silent substring selection).

**Evidence:**
- Router integration test run output including the emitted route explanation.

**DoD:**
- [ ] Explicit invocation and ambiguity fail-closed behavior are both enforced
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:70 -->

<!-- mb-task:71 -->
## Task 71: SR-06 — Positive/negative/pressure corpus

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-004
**Role:** qa
**Depends on:** SR-02, SR-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the eval corpus (positive triggers, negative/ambiguous triggers, pressure/rationalization cases, required side-effect boundaries) conforming to the SR-02 schema and run it against the SR-03 registry/router.

**Testing (TDD):**
- Corpus runner reports routing precision ≥92% and recall ≥90% on the assembled corpus before it is accepted as the release baseline.

**Evidence:**
- Corpus run report with per-category pass/fail counts.

**DoD:**
- [ ] Corpus covers all required case categories and meets the precision/recall baseline
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:71 -->

<!-- mb-task:72 -->
## Task 72: SR-07 — Cross-host conformance suites

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-004
**Role:** qa
**Depends on:** SR-04, SR-05, SR-06
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build adapter conformance suites that verify declared capability tiers against real/simulated host behavior across every supported host, and enforce cross-host semantic parity for core routing.

**Testing (TDD):**
- Conformance suite fails when an adapter declares `enforced` but its fixture only proves best-effort/post-validation behavior; parity check reports ≥95% core cross-host semantic parity.

**Evidence:**
- Conformance suite run log per supported host.

**DoD:**
- [ ] Conformance suite catches over-claimed capability tiers and meets the parity target
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:72 -->

<!-- mb-task:73 -->
## Task 73: SR-08 — Progressive-disclosure refactor

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-005
**Role:** developer
**Depends on:** SR-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Refactor skill bodies so detailed schemas/examples move into references while the core skill body stays compact, without duplicating the existing Superpowers reviewer override.

**Testing (TDD):**
- Eager-loaded skill context is measured before/after and shows a ≥40% reduction; a regression test confirms no duplicated reviewer-override logic was introduced.

**Evidence:**
- Before/after context-size report.

**DoD:**
- [ ] Eager-loaded skill context reduced by at least 40% with no duplicated reviewer override
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:73 -->

<!-- mb-task:74 -->
## Task 74: SR-09 — CI, dogfood and release

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-PGM-005
**Role:** qa
**Depends on:** SR-07, SR-08, SR-10
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Wire the registry/eval/conformance/precedence suites into CI without a network dependency, run cross-host dogfood, and ship v6.2.0 once all release metrics (routing precision ≥92%, recall ≥90%, forbidden selection ≤2%, core cross-host parity ≥95%, required adapter contract pass rate 100%, eager-loaded context reduced ≥40%) are met.

**Testing (TDD):**
- CI job executes the full SR suite with zero network calls; dogfood report captures live metrics against every release target.

**Evidence:**
- CI run log, dogfood report, release metrics summary.

**DoD:**
- [ ] All v6.2.0 release metrics meet or exceed target before tagging the release
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:74 -->

<!-- mb-task:75 -->
## Task 75: SR-10 — Tiered provider capabilities, precedence and ambiguity policy

**Release:** 6.2.0
**Priority:** P1
**Covers:** REQ-SR-003, REQ-SR-007, REQ-SR-008
**Role:** architect
**Depends on:** SR-04, SR-05
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the precedence chain `built-in < user/global < project < explicit invocation` with an immutable safety floor that project overrides cannot weaken; add bounded repair plus post-parse schema validation for `best_effort` structured output, and hard-block dispatch when a required safety capability is `unsupported`.

**Testing (TDD):**
- Precedence resolver test asserts a project override cannot weaken the safety baseline; `best_effort` repair path is exercised end-to-end and validated post-parse; an `unsupported` safety-capability fixture blocks dispatch in an integration test.

**Evidence:**
- Precedence/ambiguity policy test run output.

**DoD:**
- [ ] Precedence, best-effort repair and unsupported-capability blocking are all enforced
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:75 -->

<!-- mb-task:76 -->
## Task 76: DS-01 — Delta schema/parser/validator

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-DS-001
**Role:** architect
**Depends on:** release gate 5.5.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the change-package schema carrying a `base_spec_digest`, the `ADDED|MODIFIED|REMOVED|RENAMED` operation set (MODIFIED carries the full new target requirement), and the parser/validator that enforces it. Delta mode stays opt-in; current-state SDD remains available unchanged.

**Testing (TDD):**
- Parser/validator tests reject malformed operations and any operation kind outside the four supported ones.

**Evidence:**
- Schema/validator test run against valid and malformed delta fixtures.

**DoD:**
- [ ] Delta schema/parser/validator enforce all four operation kinds and reject malformed input
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:76 -->

<!-- mb-task:77 -->
## Task 77: DS-02 — Impact analysis

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-DS-002
**Role:** developer
**Depends on:** DS-01, release gate 5.7.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement impact analysis that maps an applied delta to the affected tasks, tests, Plan IR nodes, evidence records and release slices, feeding the DS-03 prepare/apply/archive pipeline.

**Testing (TDD):**
- Impact analyzer tests assert the full recompute set for representative ADDED/MODIFIED/REMOVED/RENAMED fixtures matches the expected affected-node list.

**Evidence:**
- Impact analysis run report per fixture delta.

**DoD:**
- [ ] Impact analysis produces a complete, correct affected-node set for every operation kind
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:77 -->

<!-- mb-task:78 -->
## Task 78: DS-03 — Prepare/apply/archive

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-DS-002
**Role:** developer
**Depends on:** DS-01, DS-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the prepare-rebuilt-spec-in-memory → validate → atomic-apply → archive-with-hashes-and-traceability pipeline; an invalid rebuilt spec must never replace the current spec.

**Testing (TDD):**
- Apply-pipeline integration test asserts an invalid rebuild leaves the current spec byte-for-byte unchanged, and a successful apply produces an archived delta with a reversible audit record and new digest.

**Evidence:**
- Apply/archive run transcript for a valid and an invalid delta fixture.

**DoD:**
- [ ] Invalid rebuilds never replace the current spec; applied deltas are archived with hashes and traceability
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:78 -->

<!-- mb-task:79 -->
## Task 79: DS-04 — Migration/failure tests

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-DS-002
**Role:** qa
**Depends on:** DS-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Exercise migration/failure-injection scenarios (partial apply, invalid rebuild, concurrent delta) against DS-03 to prove the atomic-apply/archive invariants hold under failure, including existing-spec migration to base revision without synthetic history.

**Testing (TDD):**
- Failure-injection suite proves zero silent spec corruption and zero orphan archive entries across every seeded fault fixture.

**Evidence:**
- Failure-injection suite run log.

**DoD:**
- [ ] Seeded partial-apply/invalid-rebuild/concurrent-delta fixtures never corrupt the current spec
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:79 -->

<!-- mb-task:80 -->
## Task 80: GH-01 — Projection adapter/mapping schema

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-GH-001
**Role:** architect
**Depends on:** release gate 6.2.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the GitHub projection adapter interface (not hard-coded shell parsing) and the mapping schema for program/release/task/run/evidence → milestone/issue/PR/comment/check reference, with remote IDs stored only in `.memory-bank/integrations/github-map.json`.

**Testing (TDD):**
- Schema/contract tests assert a local stable task ID is never replaced by a remote issue number in the mapping structure.

**Evidence:**
- Adapter interface + mapping schema validation run.

**DoD:**
- [ ] Adapter interface and mapping schema keep local stable IDs authoritative
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:80 -->

<!-- mb-task:81 -->
## Task 81: GH-02 — Read/diff/dry-run

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-GH-002, REQ-GH-004, REQ-PGM-006
**Role:** developer
**Depends on:** GH-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement read-before-write, a dry-run projection preview and diff against remote state, defaulting to read-only until explicit configuration; loss of GitHub access must never block local planning/execution.

**Testing (TDD):**
- Dry-run integration test asserts zero remote mutations from a read/diff pass; a simulated GitHub-outage fixture proves local planning and execution stay fully functional.

**Evidence:**
- Dry-run/diff run transcript plus GitHub-outage fixture result.

**DoD:**
- [ ] Dry-run/diff produces zero remote mutations and outage never blocks local work
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:81 -->

<!-- mb-task:82 -->
## Task 82: GH-03 — Idempotent write/recovery journal

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-GH-003, REQ-PGM-006
**Role:** developer
**Depends on:** GH-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement idempotency keys, a partial-failure journal and reconciliation so repeated writes/retries never duplicate remote mutations and remote drift is never silently overwritten; any destructive remote action requires explicit approval.

**Testing (TDD):**
- Repeated-sync integration test asserts zero remote mutations when no local changes exist; injected partial failure produces a reconciliation record instead of an orphan mapping.

**Evidence:**
- Repeated-sync run log and partial-failure recovery transcript.

**DoD:**
- [ ] Repeated sync is idempotent and partial failures always leave a reconciliation record
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:82 -->

<!-- mb-task:83 -->
## Task 83: GH-04 — PR/CI/review evidence links

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-GH-002, REQ-EV-002
**Role:** developer
**Depends on:** GH-03, release gate 6.1.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Link PR/CI/review evidence, built on the v6.1 verification/evidence system, into the GH-03 mapping so review/check state surfaces alongside projected tasks and runs; any remote mutation for these links still requires explicit authorization.

**Testing (TDD):**
- Integration test asserts PR/CI/check references resolve to the same evidence records the v6.1 verifier produced, and no destructive remote action is taken without prior approval.

**Evidence:**
- PR/CI/review evidence-link resolution test run.

**DoD:**
- [ ] PR/CI/review evidence links resolve to verifier-produced evidence with no unapproved remote action
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:83 -->

<!-- mb-task:84 -->
## Task 84: XE-01 — External Executor Adapter V1 schema and state mapping

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-XE-001, REQ-XE-005
**Role:** architect
**Depends on:** release gate 6.0.0, SR-10
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the backend-neutral `validate/start/status/events/decision/cancel/artifacts` interface and the `execution.backend: native|external:<adapter-id>` config, keeping `native` the default; `gsd`/`archon` IDs only become selectable after the optional adapter is installed and passes conformance.

**Testing (TDD):**
- Contract tests assert core does not import an Archon/GSD runtime dependency, and an unconfigured or unconformant adapter ID is rejected at config time.

**Evidence:**
- Adapter interface contract test run + dependency-manifest check showing zero Archon/GSD runtime deps in core.

**DoD:**
- [ ] External executor interface and backend config exclude unconformant/unconfigured adapters
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:84 -->

<!-- mb-task:85 -->
## Task 85: XE-02 — Event/artifact import, idempotency and independent verification

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-XE-002, REQ-XE-003, REQ-XE-004
**Role:** developer
**Depends on:** XE-01, EV-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Normalize imported events into Run Event V1, deduplicate by idempotency key with sequence/gap checks, and import artifacts through Typed Node Artifact V1, always independently verifying against the Memory Bank verifier before any terminal transition.

**Testing (TDD):**
- Import pipeline test asserts an external backend success alone never marks a run/task `done`, and a repeated event/artifact import produces zero duplicate transitions or side effects.

**Evidence:**
- Import pipeline run log with duplicate-import fixture result.

**DoD:**
- [ ] External success never terminates a run without independent local verification; duplicate imports are no-ops
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:85 -->

<!-- mb-task:86 -->
## Task 86: XE-03 — Backend conformance kit + GSD/Archon external-adapter fixtures

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-XE-004, REQ-XE-005
**Role:** qa
**Depends on:** XE-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the conformance kit (with GSD/Archon external-adapter fixtures) proving a backend cannot write canonical bank files, local resume works after simulated backend/session loss, and concurrent external writers are isolated per `owned_paths` or serialized.

**Testing (TDD):**
- Conformance suite asserts zero canonical writes by the backend and successful local resume after simulated provider/session loss, run against both GSD and Archon fixtures.

**Evidence:**
- Conformance kit run log per adapter fixture.

**DoD:**
- [ ] Conformance kit proves zero canonical writes and successful resume after simulated backend loss
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:86 -->

<!-- mb-task:87 -->
## Task 87: DG-01 — Cross-lane traceability/reconciliation

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-DS-002, REQ-GH-003, REQ-XE-004
**Role:** developer
**Depends on:** DS-04, GH-04, XE-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the cross-lane reconciliation gate tying delta (Lane A), GitHub projection (Lane B) and external executor (Lane C) traceability together, so `v6.3.0` ships only after this joint reconciliation gate passes.

**Testing (TDD):**
- Reconciliation gate integration test asserts every applied delta, GitHub mapping and imported external event is traceable end-to-end with zero orphan mapping records.

**Evidence:**
- Cross-lane reconciliation report covering all three lanes.

**DoD:**
- [ ] Reconciliation gate produces zero orphan mappings across all three lanes
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:87 -->

<!-- mb-task:88 -->
## Task 88: DG-02 — Security/failure injection/dogfood

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-GH-004, REQ-XE-005, REQ-PGM-006
**Role:** qa
**Depends on:** DG-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Run security and failure-injection scenarios across all three lanes plus dogfood: attempted destructive remote actions without approval, silent drift-overwrite attempts and attempted external writes to canonical bank files, confirming every one is blocked.

**Testing (TDD):**
- Injected-fault suite asserts zero silent remote drift overwrite and zero destructive remote action without approval across every seeded fixture.

**Evidence:**
- Security/failure-injection suite run log and dogfood report.

**DoD:**
- [ ] Zero silent drift overwrite and zero unapproved destructive remote action across seeded fixtures
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:88 -->

<!-- mb-task:89 -->
## Task 89: DG-03 — Docs and release

**Release:** 6.3.0
**Priority:** P2
**Covers:** REQ-PGM-005
**Role:** qa
**Depends on:** DG-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Finalize v6.3.0 docs and migration guidance, and ship the release once every metric (delta impact trace completeness 100%, idempotent sync rate 100%, mapping round-trip integrity 100%, silent remote drift overwrite 0, local execution success during GitHub outage 100% of fixtures, external adapter conformance required checks 100%, zero Archon/GSD runtime deps in core) is met.

**Testing (TDD):**
- Release-metrics report is validated against every target before tagging v6.3.0.

**Evidence:**
- Release metrics report, migration doc diff, release checklist.

**DoD:**
- [ ] All v6.3.0 release metrics meet or exceed target before tagging the release
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:89 -->

<!-- mb-task:90 -->
## Task 90: RP-01 — Replan patch schema/invariants

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-RP-002, REQ-RP-003
**Role:** architect
**Depends on:** release gate 6.3.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the replan patch schema and invariants: patch operations apply only to the pending graph, completed nodes stay immutable, and every patch must carry an impact report and a new plan hash before it can be applied.

**Testing (TDD):**
- Schema/invariant tests reject any patch that touches a completed node or omits the impact report/new plan hash.

**Evidence:**
- Schema/invariant test run against valid and invalid patch fixtures.

**DoD:**
- [ ] Replan patch schema rejects completed-node mutation and missing impact/hash fields
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:90 -->

<!-- mb-task:91 -->
## Task 91: RP-02 — Trigger/impact evaluator

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-RP-001
**Role:** developer
**Depends on:** RP-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the typed replan trigger evaluator covering failed precondition, unexpected effect, failed verification, scope/file conflict, material requirement delta, capability/environment loss and budget/risk threshold breach, producing an impact report before any patch is applied.

**Testing (TDD):**
- Trigger evaluator unit tests assert each of the seven typed triggers fires on its dedicated fixture and none fire on an unrelated fixture.

**Evidence:**
- Trigger evaluator test run output per trigger type.

**DoD:**
- [ ] All seven typed triggers are detected correctly with no cross-firing
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:91 -->

<!-- mb-task:92 -->
## Task 92: RP-03 — Pending-graph patch/apply/history

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-RP-002, REQ-RP-003
**Role:** developer
**Depends on:** RP-02
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement patch application restricted to pending nodes with a full audit history entry (reason, author/agent, timestamp, old/new hash, impact), validating the new graph before commit.

**Testing (TDD):**
- Apply/history integration test asserts new-graph validation runs before commit and the resulting record contains every required audit field.

**Evidence:**
- Apply/history run transcript with audit-record dump.

**DoD:**
- [ ] Patch apply validates the new graph before commit and records a complete audit entry
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:92 -->

<!-- mb-task:93 -->
## Task 93: RP-04 — Approval/oscillation/bounds

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-RP-004
**Role:** developer
**Depends on:** RP-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the approval policy (auto for bounded low-risk pending-node adjustment; human for scope expansion, public API, security, destructive migration, completed-work invalidation), the two-automatic-replan cap, and an oscillation/stagnation detector that stops for human direction.

**Testing (TDD):**
- Bounds integration test asserts a third automatic replan attempt is blocked pending human direction; an oscillation fixture is detected and halted.

**Evidence:**
- Approval/bounds test run output including the oscillation-detection fixture result.

**DoD:**
- [ ] Two-automatic-replan cap and oscillation detector both stop for human direction as designed
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:93 -->

<!-- mb-task:94 -->
## Task 94: OP-01 — Health/forensics diagnostic model

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-OP-001
**Role:** architect
**Depends on:** release gate 6.3.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define the workflow health/forensics diagnostic model covering state drift, orphan worktree/lease, result-without-summary/evidence, stale evidence and plan-hash/remote-mapping drift.

**Testing (TDD):**
- Diagnostic-model contract tests assert every listed fault class has a dedicated, distinguishable detector signature.

**Evidence:**
- Diagnostic model contract test run against one fixture per fault class.

**DoD:**
- [ ] Every documented fault class has a distinguishable detector signature
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:94 -->

<!-- mb-task:95 -->
## Task 95: OP-02 — Doctor/repair dry-run

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-OP-002
**Role:** developer
**Depends on:** OP-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the doctor/repair command defaulting to dry-run; destructive cleanup is never automatic and requires explicit `--apply` for any mutation.

**Testing (TDD):**
- Repair-without-`--apply` integration test asserts zero bytes changed; forensics run against seeded corrupt/orphan/stale fixtures detects all of them.

**Evidence:**
- Dry-run repair transcript and forensics detection report.

**DoD:**
- [ ] Repair without `--apply` never mutates state; forensics detects all seeded fault fixtures
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:95 -->

<!-- mb-task:96 -->
## Task 96: OP-03 — Privacy-safe telemetry/events

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-OP-003
**Role:** developer
**Depends on:** OP-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement local, privacy-safe telemetry recording durations, queue/wave utilization, retries/replans/resumes, conflict/failure codes, token/context estimates and evidence completeness, with no prompt/source/private content ever recorded.

**Testing (TDD):**
- Telemetry-content test asserts recorded events never contain paths/content marked private, prompts or source snippets, across every telemetry event type.

**Evidence:**
- Telemetry event dump audited against the private-content exclusion list.

**DoD:**
- [ ] Telemetry never records prompt/source/private content across all event types
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:96 -->

<!-- mb-task:97 -->
## Task 97: OP-04 — Reconstruction/undo runbooks

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-OP-002
**Role:** devops
**Depends on:** OP-02, OP-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Write and validate reconstruction/undo runbooks for repair/replan operations, keeping the repair feature dry-run-by-default and off the automatic destructive path until dogfood gate.

**Testing (TDD):**
- Runbook dry-run walkthrough test asserts each documented undo step is executable and reversible against a seeded incident fixture.

**Evidence:**
- Runbook walkthrough transcript.

**DoD:**
- [ ] Every documented undo step is executable and reversible against a seeded fixture
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:97 -->

<!-- mb-task:98 -->
## Task 98: OP-05 — Event query/projection and typed workflow timeline

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-OP-003
**Role:** developer
**Depends on:** RK-11, OP-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build a UI-neutral local event query/projection over canonical `events.jsonl` — filters by run/node/type/attempt, critical-path timing, and pause/retry/replan timeline — without introducing a new database/server.

**Testing (TDD):**
- Projection integration test asserts the timeline is fully rebuilt from `events.jsonl` alone and that projection output never participates in correctness decisions.

**Evidence:**
- Event projection run output rebuilt from a sample `events.jsonl`.

**DoD:**
- [ ] Timeline projection is fully derivable from the local journal with no new server/database
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:98 -->

<!-- mb-task:99 -->
## Task 99: KB-01 — Optional cited external-docs context-source adapter

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-KB-001
**Role:** developer
**Depends on:** SR-10, release gate 6.3.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the optional external-docs context-source adapter with project-scoped sources, provenance/retrieved-at/content-digest tracking, separate prose/code result types, required citations in the context bundle and TTL/freshness diagnostics; it never replaces GraphRAG/Memory Bank as source of truth.

**Testing (TDD):**
- Context-bundle test asserts an answer without provenance/citations, or with a stale source, never enters the trusted context bundle.

**Evidence:**
- Context bundle fixture run showing accepted vs. rejected answers.

**DoD:**
- [ ] Trusted context bundle only ever contains cited, fresh, provenance-tracked answers
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:99 -->

<!-- mb-task:100 -->
## Task 100: AO-01 — Replan/forensics/freshness fault corpus

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-RP-004, REQ-OP-002, REQ-KB-001
**Role:** qa
**Depends on:** RP-04, OP-04, OP-05, KB-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the combined fault corpus exercising replan bounds (RP-04), doctor/repair and telemetry/timeline (OP-04, OP-05) and external-docs freshness (KB-01) together as one regression suite.

**Testing (TDD):**
- Corpus run asserts oscillation/replan escapes automatic bound = 0 and seeded recovery diagnosis accuracy ≥95%.

**Evidence:**
- Combined fault-corpus run report with per-fixture pass/fail.

**DoD:**
- [ ] Combined corpus meets zero-oscillation-escape and ≥95% recovery-diagnosis-accuracy targets
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:100 -->

<!-- mb-task:101 -->
## Task 101: AO-02 — Performance, dogfood, docs, release

**Release:** 6.4.0
**Priority:** P3
**Covers:** REQ-PGM-005
**Role:** qa
**Depends on:** AO-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Run performance/benchmark trend reports, dogfood the full v6.4.0 stack, finalize docs, and ship the release once every metric (invalid post-replan graphs accepted 0, unaffected completed tasks restarted 0, replan impact trace completeness 100%, oscillation escapes 0, seeded recovery diagnosis accuracy ≥95%, small-task p95 overhead ≤15% via quick path) is met.

**Testing (TDD):**
- Release-metrics report is validated against every target before tagging v6.4.0.

**Evidence:**
- Benchmark trend report, dogfood report, release checklist.

**DoD:**
- [ ] All v6.4.0 release metrics meet or exceed target before tagging the release
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:101 -->

<!-- mb-task:102 -->
## Task 102: GSD-01 — ADR set, ownership and gate matrix

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-001, REQ-GSD-005
**Role:** architect
**Depends on:** XE-03, SR-10, OP-05, release gate 6.3.0, release gate 6.4.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Author the ADR set defining the GSD-as-optional-executor architecture, the ownership model, and the gate matrix for `/mb work` when `execution.backend=external:gsd`, establishing `/mb work`/the compiled Memory Bank pipeline as the sole lifecycle authority.

**Testing (TDD):**
- ADR/gate-matrix review checklist confirms every documented duplicate-gate risk (review/security/TDD) resolves to exactly one owner or a declared defense-in-depth duplicate before implementation starts.

**Evidence:**
- ADR documents and gate matrix table.

**DoD:**
- [ ] Gate matrix assigns exactly one owner (or declared duplicate) to every pipeline gate under `external:gsd`
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:102 -->

<!-- mb-task:103 -->
## Task 103: GSD-02 — descriptor, detect/doctor, lock and compatibility schema

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-002, REQ-GSD-003, REQ-GSD-007, REQ-GSD-013, REQ-SR-003, REQ-SR-007, REQ-XE-001
**Role:** developer
**Depends on:** GSD-01, SR-09
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the GSD descriptor, detect/doctor diagnostics, exact-version lock and pre-mutation compatibility schema validating GSD version, adapter, bridge, runtime, Node/npm, Plan IR projection, commit policy and isolation policy before any source mutation.

**Testing (TDD):**
- Doctor fixture test asserts exact version/runtime/bridge mismatch is reported accurately and blocks dispatch before mutation.

**Evidence:**
- Doctor diagnostic run against matched and mismatched version fixtures.

**DoD:**
- [ ] Doctor blocks dispatch on any pre-mutation compatibility mismatch
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:103 -->

<!-- mb-task:104 -->
## Task 104: GSD-03 — deterministic Plan IR renderer and semantic-loss validator

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-004, REQ-GSD-015, REQ-PI-001, REQ-PI-002
**Role:** developer
**Depends on:** PI-08, GSD-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the deterministic Plan IR renderer that projects an approved plan while preserving stable IDs, REQ-IDs, dependencies, owned scopes, acceptance and verification semantics, blocking any required semantic loss; GSD planning/replanning stays non-canonical.

**Testing (TDD):**
- Renderer golden tests assert byte-stable output on unchanged input; blocking semantic-loss fixtures (dependency, scope, acceptance, permission) are all rejected.

**Evidence:**
- Golden test run diff and semantic-loss fixture rejection log.

**DoD:**
- [ ] Renderer is deterministic and rejects every blocking semantic-loss fixture
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:104 -->

<!-- mb-task:105 -->
## Task 105: GSD-04 — workstream, projection, mapping and native mirror manager

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-004, REQ-GSD-006, REQ-GSD-007, REQ-PI-001, REQ-PI-002
**Role:** developer
**Depends on:** GSD-02, GSD-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the workstream/projection mapping and native mirror manager keeping GSD's `.planning` workspace and the Memory Bank Plan IR in a deterministic, stable mapping; `.planning` is treated as fully reconstructible, never a writable symlink into canonical storage.

**Testing (TDD):**
- Mapping round-trip test asserts Plan/REQ/dependency/owned-path mapping stays deterministic across repeated renders.

**Evidence:**
- Round-trip mapping test run comparing two consecutive renders.

**DoD:**
- [ ] Plan/REQ/dependency/owned-path mapping is deterministic and `.planning` stays reconstructible
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:105 -->

<!-- mb-task:106 -->
## Task 106: GSD-05 — prompt-native invocation binding with `--no-transition`

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-005, REQ-XE-001
**Role:** developer
**Depends on:** GSD-02, GSD-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the bounded `engine.execute_verified` invocation binding with autonomous transition, ship, push and release disabled, so GSD only executes verified work under `/mb work` control.

**Testing (TDD):**
- Invocation integration test asserts GSD invocation never triggers transition/ship/push/release outside the compiled pipeline.

**Evidence:**
- Invocation binding test run with attempted autonomous-transition fixture rejected.

**DoD:**
- [ ] GSD invocation never performs autonomous transition/ship/push/release
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:106 -->

<!-- mb-task:107 -->
## Task 107: GSD-06 — pipeline composite lowering and gate-owner reconciliation

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-001, REQ-GSD-005, REQ-GSD-015, REQ-XE-001
**Role:** developer
**Depends on:** GSD-03, GSD-05, WF-06
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement pipeline composite lowering that maps the governed Memory Bank pipeline stages onto GSD execution while reconciling gate ownership so review/security/TDD gates are never silently duplicated or dropped.

**Testing (TDD):**
- Lowering test asserts each lowered pipeline gate resolves to exactly one declared owner or an explicitly declared defense-in-depth duplicate.

**Evidence:**
- Pipeline lowering test run with gate-ownership report.

**DoD:**
- [ ] Every lowered pipeline gate has exactly one owner or a declared defense-in-depth duplicate
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:107 -->

<!-- mb-task:108 -->
## Task 108: GSD-07 — official `memory-bank-bridge` capability and outbox receipts

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-003, REQ-GSD-014, REQ-XE-003
**Role:** developer
**Depends on:** GSD-02, GSD-05
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the official `memory-bank-bridge` capability with outbox-only receipts, so GSD/bridge can report status without ever writing canonical Memory Bank state directly, and cannot recursively invoke Memory Bank orchestration.

**Testing (TDD):**
- Canonical write sentinel test asserts every bridge/GSD write attempt against canonical bank files is rejected.

**Evidence:**
- Write-sentinel test run log.

**DoD:**
- [ ] Zero canonical writes by GSD/bridge across the sentinel fixture set
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:108 -->

<!-- mb-task:109 -->
## Task 109: GSD-08 — normalized status/events and transactional artifact importer

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-007, REQ-GSD-008, REQ-EV-001, REQ-EV-002, REQ-EV-004, REQ-XE-002, REQ-XE-003
**Role:** developer
**Depends on:** GSD-04, GSD-07, EV-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the normalized status/event importer (dedup, sequence/gap checks) and transactional artifact import performing independent current-HEAD verification before any terminal Memory Bank transition.

**Testing (TDD):**
- Forged-success and wrong-SHA evidence fixtures are rejected; duplicate/out-of-order/sequence-gap event fixtures are detected and handled without corrupting run state.

**Evidence:**
- Import pipeline run log covering forged-evidence and sequence-gap fixtures.

**DoD:**
- [ ] Forged/wrong-SHA evidence and duplicate/out-of-order events never advance a run to done
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:109 -->

<!-- mb-task:110 -->
## Task 110: GSD-09 — resume reconciliation and commit-without-summary recovery

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-011, REQ-GSD-012, REQ-RK-003, REQ-RK-004, REQ-XE-004, REQ-OP-001
**Role:** developer
**Depends on:** GSD-08, RK-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement pre-resume reconciliation classifying state as `exact`, `gsd_ahead`, `mb_ahead`, `divergent` or `corrupt`, ensuring a commit-but-missing-SUMMARY state is never blindly redispatched, and that no backend switch happens post-mutation without explicit reconciliation and approval.

**Testing (TDD):**
- All five reconciliation classes are exercised as fixtures and the commit-without-summary recovery path is validated end-to-end.

**Evidence:**
- Reconciliation classifier run log per state class.

**DoD:**
- [ ] All five reconciliation classes are correctly classified and commit-without-summary never blindly redispatches
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:110 -->

<!-- mb-task:111 -->
## Task 111: GSD-10 — commit/worktree ownership arbitration

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-009, REQ-GSD-010, REQ-EX-001, REQ-EX-005, REQ-XE-005
**Role:** developer
**Depends on:** GSD-02, GSD-05, EX-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement single-isolation-owner arbitration for commit/worktree so unproven runtime concurrency serializes or halts, and an incompatible commit policy fails before mutation rather than silently enabling commits.

**Testing (TDD):**
- Claude worktree-owner and Codex sequential-profile fixtures both pass; a `commit_policy:none` fixture is refused before any mutation.

**Evidence:**
- Worktree-ownership arbitration test run per host profile.

**DoD:**
- [ ] Single isolation owner is enforced per run and incompatible commit policy fails before mutation
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:111 -->

<!-- mb-task:112 -->
## Task 112: GSD-11 — consent-aware install/update/disable/remove lifecycle

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-003, REQ-GSD-013, REQ-PGM-006
**Role:** devops
**Depends on:** GSD-02, GSD-07
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the install/enable/update/disable/remove lifecycle that discloses exact provenance and executable surfaces and requires explicit consent before any executable-surface change; updates to Memory Bank and GSD stay independent.

**Testing (TDD):**
- Consent-flow integration test asserts install/update without explicit consent is blocked, and disable/remove leaves no residual executable surface.

**Evidence:**
- Install/update/disable/remove lifecycle transcript with consent-prompt evidence.

**DoD:**
- [ ] No executable-surface change happens without explicit consent; disable/remove leaves zero residual surface
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:112 -->

<!-- mb-task:113 -->
## Task 113: GSD-12 — security, cross-host and version conformance matrix

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-002, REQ-GSD-006, REQ-GSD-009, REQ-GSD-013, REQ-GSD-014, REQ-SR-003, REQ-SR-007, REQ-EX-001, REQ-EX-005
**Role:** security
**Depends on:** GSD-03, GSD-04, GSD-05, GSD-06, GSD-07, GSD-08, GSD-09, GSD-10, GSD-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the security/cross-host/version conformance matrix proving 100% adapter conformance for the pinned GSD version and rejecting exact-version drift or an unsupported newest version.

**Testing (TDD):**
- Exact GSD version-drift and unsupported-newest-version fixtures are both rejected; adapter conformance for the pinned version reaches 100% across all supported hosts.

**Evidence:**
- Conformance matrix run report per host/version combination.

**DoD:**
- [ ] Adapter conformance for the pinned version reaches 100% and version drift is rejected
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:113 -->

<!-- mb-task:114 -->
## Task 114: GSD-13 — native-vs-GSD E2E dogfood and crash/failure injection

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-008, REQ-GSD-009, REQ-GSD-011, REQ-GSD-012, REQ-GSD-014, REQ-PGM-005, REQ-RK-003, REQ-RK-004, REQ-EX-001, REQ-EX-005, REQ-EV-001, REQ-EV-002, REQ-EV-004, REQ-XE-002, REQ-XE-004, REQ-XE-005, REQ-OP-001
**Role:** qa
**Depends on:** GSD-08, GSD-09, GSD-10, GSD-11, GSD-12
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Run native-vs-GSD end-to-end dogfood plus crash/failure injection at prepare/start/wave/verify/import points, confirm backend loss after mutation never falls back silently, and validate the direct-GSD-recursion guard.

**Testing (TDD):**
- Crash-in-prepare/start/wave/verify/import fixtures all recover without duplicate mutation; backend loss after mutation never silently falls back; the direct-GSD-recursion guard fixture is blocked; GSD dogfood governed completion reaches ≥95%.

**Evidence:**
- Crash-injection run log per injection point and dogfood completion report.

**DoD:**
- [ ] All crash-injection points recover without duplicate mutation and dogfood completion is ≥95%
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:114 -->

<!-- mb-task:115 -->
## Task 115: GSD-14 — legacy Build dry-run migrator, aliases and transition docs

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-016
**Role:** developer
**Depends on:** GSD-06, GSD-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the legacy Build migrator (dry-run, semantic diff, idempotent conversion) plus transition docs and command aliases, never deleting user installations, configuration or work artifacts.

**Testing (TDD):**
- Migration dry-run/apply integration test asserts user config and work artifacts are preserved across repeated idempotent conversions.

**Evidence:**
- Migration dry-run/apply transcript with before/after config diff.

**DoD:**
- [ ] Repeated idempotent migration never overwrites or deletes user config/work artifacts
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:115 -->

<!-- mb-task:116 -->
## Task 116: GSD-15 — clean install, upgrade, rollback, docs and release evidence

**Release:** 6.5.0
**Priority:** P2
**Covers:** REQ-GSD-003, REQ-GSD-013, REQ-GSD-016, REQ-PGM-005, REQ-PGM-006
**Role:** devops
**Depends on:** GSD-12, GSD-13, GSD-14
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Execute clean install, upgrade and rollback conformance, finalize v6.5.0 docs and assemble release evidence against every release metric (adapter conformance 100%, stable mapping 100%, accepted blocking semantic loss 0, canonical writes by GSD/bridge 0, duplicate mutations after resume 0, forged/wrong-SHA evidence accepted 0, silent fallback after mutation 0, nested/unsafe worktree races 0, user config overwritten by update 0, update-direction compatibility 100%, native regression parity 100%, GSD dogfood governed completion ≥95%).

**Testing (TDD):**
- Release-metrics report is validated against every target before tagging v6.5.0; update-direction compatibility fixtures pass in both directions.

**Evidence:**
- Install/upgrade/rollback transcripts, release metrics report, release checklist.

**DoD:**
- [ ] All v6.5.0 release metrics meet or exceed target before tagging the release
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:116 -->

<!-- mb-task:117 -->
## Task 117: OSA-01 — ADR set, two-axis model, ownership, UX and gate matrix

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-001, REQ-OSA-002, REQ-OSA-003, INV-01, INV-02, INV-13, INV-15
**Role:** architect
**Depends on:** GSD-15, release gate 6.5.0
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Author the ADR set defining the two-axis authoring×execution model (native/OpenSpec × native/GSD), ownership boundaries, backend-selection UX and gate matrix, keeping Memory Bank the sole owner of canonical specification revisions, approvals and lifecycle state.

**Testing (TDD):**
- ADR/gate-matrix review checklist confirms all four authoring/execution combinations have a documented ownership and gate path before implementation starts.

**Evidence:**
- ADR documents and two-axis gate matrix table.

**DoD:**
- [ ] All four authoring/execution combinations have a documented ownership and gate path
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:117 -->

<!-- mb-task:118 -->
## Task 118: OSA-02 — Canonical Spec Bundle V1, native projector/promotion receipt, Authoring Adapter, Import Transaction and JSON schemas

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-009, REQ-OSA-011, REQ-OSA-016
**Role:** developer
**Depends on:** OSA-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Define Canonical Spec Bundle V1, the native SDD-draft projector with its promotion receipt, the Specification Authoring Adapter interface and the Spec Import Transaction schema as backend-neutral JSON-schema contracts.

**Testing (TDD):**
- JSON schema contract tests validate bundle/adapter/import-transaction fixtures for both the native path and the external OpenSpec path.

**Evidence:**
- JSON schema contract test run per contract.

**DoD:**
- [ ] Bundle/adapter/import-transaction contracts validate both native and external fixtures
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:118 -->

<!-- mb-task:119 -->
## Task 119: OSA-03 — OpenSpec doctor, exact-version lock, descriptor and compatibility/consent policy

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-003, REQ-OSA-004, REQ-OSA-017, REQ-SR-003, REQ-SR-007
**Role:** developer
**Depends on:** OSA-01
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement OpenSpec doctor diagnostics, exact-version lock, the OpenSpec Authoring Descriptor V1, and pre-authoring compatibility/consent policy validation (version, runtime, public surfaces, schema profile, adapter, normalizer, host).

**Testing (TDD):**
- Compatibility-validation fixture asserts version/runtime/public-surface/schema/adapter/normalizer/host mismatch blocks authoring before any mutation.

**Evidence:**
- Doctor/compatibility validation run against matched and mismatched fixtures.

**DoD:**
- [ ] Every compatibility mismatch class blocks authoring before mutation
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:119 -->

<!-- mb-task:120 -->
## Task 120: OSA-04 — production memory-bank-spec-v1 schema, templates and golden fixtures

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-007, REQ-OSA-009
**Role:** developer
**Depends on:** OSA-02, OSA-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the production memory-bank-spec-v1 schema, authoring templates and golden fixtures preserving every required requirement/dependency/scope/risk/permission/acceptance/verification/evidence semantic.

**Testing (TDD):**
- Golden tests for memory-bank-spec-v1 assert a lossless round trip on every required semantic field.

**Evidence:**
- Golden fixture round-trip test run.

**DoD:**
- [ ] memory-bank-spec-v1 round-trips losslessly on every required semantic field
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:120 -->

<!-- mb-task:121 -->
## Task 121: OSA-05 — isolated workspace, immutable source snapshot and storage boundary

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-005, REQ-OSA-012, INV-07, INV-12
**Role:** developer
**Depends on:** OSA-02, OSA-03
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the isolated, reconstructible OpenSpec workspace with an immutable source snapshot and a storage boundary that prevents OpenSpec from writing canonical Memory Bank state, with no background/watcher-based synchronization.

**Testing (TDD):**
- Canonical write sentinel test asserts OpenSpec workspace writes never reach canonical bank files, and no background/watcher synchronization process exists.

**Evidence:**
- Write-sentinel test run + background-process audit.

**DoD:**
- [ ] Zero canonical writes from the OpenSpec workspace and zero background synchronization
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:121 -->

<!-- mb-task:122 -->
## Task 122: OSA-06 — prompt-native invocation binding, allowed-surface guard and recursion sentinel

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-005, REQ-OSA-006, REQ-OSA-018, INV-13, INV-15
**Role:** developer
**Depends on:** OSA-03, OSA-05
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement prompt-native OpenSpec invocation binding, an allowed-surface guard blocking apply/sync/archive/bulk-archive/implementation-verification/autonomous-execution transitions, and a recursion sentinel preventing direct OpenSpec workflows from invoking Memory Bank/GSD execution or lifecycle transitions.

**Testing (TDD):**
- Surface-guard fixture asserts apply/sync/archive/bulk-archive/autonomous-implementation calls are all rejected; recursion-sentinel fixture blocks a direct OpenSpec-to-MB-execution call.

**Evidence:**
- Surface-guard and recursion-sentinel test run log.

**DoD:**
- [ ] All disallowed surfaces are blocked and the recursion sentinel prevents direct execution invocation
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:122 -->

<!-- mb-task:123 -->
## Task 123: OSA-07 — stock spec-driven importer and mandatory enrichment workflow

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-008, REQ-OSA-009
**Role:** developer
**Depends on:** OSA-02, OSA-05
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the stock spec-driven importer that identifies missing Memory Bank semantics, requires enrichment, and blocks canonical import while blocking diagnostics remain.

**Testing (TDD):**
- Stock-profile import fixtures with complete and incomplete enrichment assert incomplete enrichment is blocked with actionable diagnostics.

**Evidence:**
- Stock-profile import run log for complete vs. incomplete enrichment fixtures.

**DoD:**
- [ ] Incomplete stock-profile enrichment is always blocked with actionable diagnostics
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:123 -->

<!-- mb-task:124 -->
## Task 124: OSA-08 — profile-neutral normalizer, stable-ID mapper, delta compiler and semantic-loss validator

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-007, REQ-OSA-008, REQ-OSA-009, REQ-OSA-010, REQ-PI-001, REQ-PI-002
**Role:** developer
**Depends on:** OSA-04, OSA-07
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Build the profile-neutral normalizer, stable-ID mapper, delta compiler binding operations to an exact base spec digest, and the semantic-loss validator rejecting stale, ambiguous or conflicting delta operations.

**Testing (TDD):**
- ADDED/MODIFIED/REMOVED/RENAMED delta fixtures pass, and stale-base/target-collision/ambiguous-rename fixtures are all rejected.

**Evidence:**
- Delta compiler test run per operation kind and rejection case.

**DoD:**
- [ ] All four delta operation kinds pass and every stale/collision/ambiguous fixture is rejected
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:124 -->

<!-- mb-task:125 -->
## Task 125: OSA-09 — deterministic status/instructions/validate collector and spec-readiness diagnostics

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-004, REQ-OSA-009, REQ-OSA-014, REQ-OSA-016
**Role:** developer
**Depends on:** OSA-06, OSA-08
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the deterministic status/instructions/validate collector and spec-readiness diagnostics gating Plan IR compilation until the canonical revision is approved, complete and free of blocking diagnostics.

**Testing (TDD):**
- Readiness-diagnostics fixture asserts Plan IR compilation is refused while any blocking diagnostic remains open, and proceeds once resolved.

**Evidence:**
- Readiness-gate test run for blocked and cleared diagnostics.

**DoD:**
- [ ] Plan IR compilation is gated strictly on approval + completeness + zero blocking diagnostics
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:125 -->

<!-- mb-task:126 -->
## Task 126: OSA-10 — native atomic promotion + external CAS import, digest-bound approval and idempotent receipts

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-001, REQ-OSA-010, REQ-OSA-011, REQ-OSA-012, REQ-OSA-016, INV-01, INV-02, INV-07, INV-12, REQ-EV-001, REQ-EV-002
**Role:** developer
**Depends on:** OSA-02, OSA-08, OSA-09
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement native atomic promotion and external CAS import, both requiring approval bound to draft/bundle/semantic-diff/base digests, committing at most one canonical revision with idempotent receipts.

**Testing (TDD):**
- Crash-before-temp-write, before-atomic-commit, after-commit and before-receipt fixtures all recover atomically; duplicate-transaction fixtures produce idempotent recovery with zero duplicate canonical revisions.

**Evidence:**
- Crash-point recovery transcript and duplicate-transaction idempotency test run.

**DoD:**
- [ ] Every crash point recovers atomically and duplicate transactions never create a second canonical revision
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:126 -->

<!-- mb-task:127 -->
## Task 127: OSA-11 — five-state reconciliation, rebase/resume and crash recovery

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-010, REQ-OSA-012, REQ-OSA-013, INV-07, INV-12
**Role:** developer
**Depends on:** OSA-05, OSA-10
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement reconciliation classifying state as `exact`/`openspec_ahead`/`mb_ahead`/`divergent`/`corrupt` before any external resume or import, failing closed on unresolved divergence, plus rebase/resume and crash recovery.

**Testing (TDD):**
- All five reconciliation states are exercised as fixtures, and unresolved divergence fails closed rather than resuming.

**Evidence:**
- Reconciliation classifier run log per state.

**DoD:**
- [ ] All five reconciliation states are correctly classified and unresolved divergence always fails closed
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:127 -->

<!-- mb-task:128 -->
## Task 128: OSA-12 — /mb sdd lifecycle integration, audit, cancel/discard and safe cleanup

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-003, REQ-OSA-005, REQ-OSA-018
**Role:** developer
**Depends on:** OSA-06, OSA-10, OSA-11
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Wire OpenSpec authoring into the `/mb sdd` lifecycle with an audit trail, cancel/discard handling and safe, report-only staging cleanup that never destroys provenance.

**Testing (TDD):**
- Staging-cleanup integration test asserts audit/provenance records survive cleanup and can be reconstructed correctly afterward.

**Evidence:**
- Cleanup-then-reconstruct transcript with audit trail diff.

**DoD:**
- [ ] Staging cleanup never destroys audit/provenance records
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:128 -->

<!-- mb-task:129 -->
## Task 129: OSA-13 — approved native/external spec to Plan IR gate and conditional GSD provenance binding

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-002, REQ-OSA-014, REQ-OSA-015, REQ-OSA-016, REQ-OSA-019, INV-01, INV-02, INV-13, INV-15, REQ-PI-001, REQ-PI-002, REQ-GSD-004, REQ-GSD-007, REQ-GSD-008
**Role:** developer
**Depends on:** OSA-10, OSA-12, GSD-03, GSD-04
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Implement the gate compiling only approved native/external canonical revisions into executable Plan IR, with conditional GSD provenance binding and a single `plan_semantic_digest` shared across the native and GSD paths.

**Testing (TDD):**
- Raw OpenSpec-to-GSD handoff-rejection fixture blocks any unapproved artifact; `plan_semantic_digest` parity fixture matches across native and both OpenSpec profiles.

**Evidence:**
- Handoff-rejection test run and digest-parity comparison report.

**DoD:**
- [ ] Only approved canonical revisions compile to Plan IR and `plan_semantic_digest` matches across all paths
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:129 -->

<!-- mb-task:130 -->
## Task 130: OSA-14 — four-way E2E matrix, semantic parity evals and dogfood

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-002, REQ-OSA-007, REQ-OSA-008, REQ-OSA-014, REQ-OSA-015, REQ-OSA-019, REQ-OSA-020, REQ-PI-001, REQ-PI-002, REQ-EV-001, REQ-EV-002, REQ-GSD-004, REQ-GSD-007, REQ-GSD-008
**Role:** qa
**Depends on:** OSA-12, OSA-13
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Run the four-way native/OpenSpec × native/GSD end-to-end matrix, semantic-parity evals and dogfood proving that semantically equivalent approved input preserves requirement, `plan_semantic_digest`, verification and lifecycle semantics across all four combinations.

**Testing (TDD):**
- All four authoring/execution combination fixtures pass with matching `plan_semantic_digest`; governed OpenSpec dogfood completion reaches ≥95%.

**Evidence:**
- Four-way E2E matrix run report and dogfood completion report.

**DoD:**
- [ ] All four authoring/execution combinations pass with matching digest and dogfood completion is ≥95%
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:130 -->

<!-- mb-task:131 -->
## Task 131: OSA-15 — security, failure injection, version/schema drift, update and rollback conformance

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-004, REQ-OSA-005, REQ-OSA-006, REQ-OSA-011, REQ-OSA-013, REQ-OSA-017, REQ-OSA-018, REQ-OSA-019, REQ-SR-003, REQ-SR-007
**Role:** security
**Depends on:** OSA-03, OSA-06, OSA-10, OSA-11, OSA-12, OSA-13, OSA-14
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Run security/failure-injection scenarios (forged approval/bundle/mapping/receipt, exact version/schema/executable-surface drift, OpenSpec absent/disabled at native authoring) plus update/rollback conformance preserving user config/schema.

**Testing (TDD):**
- Forged-approval/bundle/mapping/receipt fixtures are all rejected; an OpenSpec-absent-or-disabled fixture leaves native authoring fully functional; update/rollback fixtures preserve user config and schema.

**Evidence:**
- Security/failure-injection suite run log and update/rollback conformance report.

**DoD:**
- [ ] All forged-evidence and drift fixtures are rejected; native authoring works with OpenSpec absent/disabled
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:131 -->

<!-- mb-task:132 -->
## Task 132: OSA-16 — clean install, upgrade, operator docs, migration guidance and release evidence

**Release:** 6.6.0
**Priority:** P2
**Covers:** REQ-OSA-003, REQ-OSA-016, REQ-OSA-017, REQ-OSA-020, REQ-EV-001, REQ-EV-002
**Role:** devops
**Depends on:** OSA-14, OSA-15
**Owned paths:** to-be-confirmed-before-dispatch
**What:** Execute clean install/upgrade, finalize operator docs and migration guidance, and assemble v6.6.0 release evidence against every release metric (canonical writes by OpenSpec 0, accepted blocking semantic loss 0, import without exact approval 0, native promotion without exact approval 0, stale-base imports 0, duplicate canonical revisions after retry 0, stable-ID/digest determinism 100%, lossless strict-profile fixtures 100%, stock-profile blocking-diagnostics recall 100%, four-way semantic parity 100%, raw OpenSpec execution handoffs 0, native authoring regression parity 100%, execution runs requiring OpenSpec after import 0, version/update conformance 100%, governed OpenSpec dogfood completion ≥95%).

**Testing (TDD):**
- Release-metrics report is validated against every target before tagging v6.6.0; an OpenSpec-removal-after-approved-import-before-`/mb work` fixture keeps execution runnable.

**Evidence:**
- Install/upgrade transcripts, migration guidance doc, release metrics report, release checklist.

**DoD:**
- [ ] All v6.6.0 release metrics meet or exceed target before tagging the release
- [ ] required tests pass on current HEAD
- [ ] requirement/evidence trace updated
- [ ] release-specific docs/migration updated when applicable
<!-- /mb-task:132 -->
