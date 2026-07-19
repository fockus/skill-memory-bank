---
type: spec-requirements
topic: mb-donor-evolution
status: ready
created: 2026-07-15
linked_design: design.md
linked_tasks: tasks.md
source: source-plan.md (§8, §29.16, §30.16)
---

# Requirements: mb-donor-evolution

Donor-driven evolution program: Memory Bank becomes a portable long-session
engineering system (donors: GSD, OpenSpec, Archon, Superpowers, CCPM, Ruflo)
while keeping the core contract — agents remember, state belongs to the
project, expensive modes stay opt-in. Release numbering is shifted +1 minor
inside the 5.x series (v5.4.0 Baseline, 5.5.0 Control Plane, 5.6.0 Kernel,
5.7.0 Plan IR; 6.x unchanged) because v5.3.0 was already released 2026-07-13.
REQ-IDs below are stable and match source-plan.md verbatim.

## User stories

- **PGM** — As a maintainer, I want the program governed by validated specs, gates and explicit authorization, so that no release ships on self-reported completion.
- **CP** — As a developer, I want the control plane to tell me which SDD artifacts are valid, blocked or ready and what exact context the next step needs, so that I never implement against an invalid spec.
- **RK** — As a long-session user, I want run state persisted and reconstructable from events, so that I can stop at any moment and resume deterministically without chat history.
- **PI** — As an orchestrator, I want a validated Plan IR with dependencies, scopes, costs and waves, so that ambiguous, oversized or conflicting graphs never reach executors.
- **WF** — As an orchestrator, I want typed execution nodes (agent/check/transform/loop/approval/cancel) with explicit conditions and join policies, so that deterministic work never hides behind AI completion claims.
- **EX** — As a user running parallel work, I want writer tasks isolated per worktree with owned paths and sequential integration, so that concurrent execution can never corrupt my repository or bank.
- **EV** — As a reviewer, I want every completion claim backed by fresh evidence tied to the current HEAD, so that "done" is reproducible rather than asserted.
- **SR** — As a cross-host user, I want a generated capability registry with tiered provider contracts and evals, so that routing and degradation behave identically on every supported host.
- **GH/DS** — As a team member, I want controlled requirement deltas and an optional idempotent GitHub projection of stable local IDs, so that requirements evolve auditable and remote outages never block local work.
- **XE/KB** — As an advanced user, I want external executors and external knowledge behind subordinate adapters with independent verification, so that no external system becomes a second source of truth.
- **RP/OP** — As an operator, I want bounded replanning that touches only the pending graph plus health/forensics diagnostics and privacy-safe telemetry, so that long-running workflows stay diagnosable and auditable.
- **GSD** — As a user preferring GSD execution, I want an approved Memory Bank plan executed by GSD without ceding lifecycle authority, canonical state or final done, so that engine choice never weakens governance. *(release iceboxed 2026-07-15)*
- **OSA** — As a user preferring OpenSpec authoring, I want specs authored externally but normalized, approved and executed through canonical Memory Bank contracts with four-way parity, so that authoring choice never forks the source of truth. *(release iceboxed 2026-07-15)*

## Requirements

### Program and compatibility

- **REQ-PGM-001** (event-driven): WHEN the donor evolution program starts, THE SYSTEM SHALL create and validate an SDD spec triple before dispatching implementation work.
- **REQ-PGM-002** (state-driven): WHILE engine-v2 is not explicitly enabled, THE SYSTEM SHALL preserve current sequential `/mb work` behavior.
- **REQ-PGM-003** (ubiquitous): THE SYSTEM SHALL keep `.memory-bank/` as the only authoritative project-memory store.
- **REQ-PGM-004** (event-driven): WHEN a schema changes, THE SYSTEM SHALL provide a versioned migration, dry-run and rollback path.
- **REQ-PGM-005** (event-driven): WHEN a release gate fails, THE SYSTEM SHALL stop that release without advancing later release tasks.
- **REQ-PGM-006** (ubiquitous): THE SYSTEM SHALL keep external publication and remote mutations behind explicit user authorization.

### Control plane

- **REQ-CP-001** (event-driven): WHEN an artifact profile is loaded, THE SYSTEM SHALL validate duplicate IDs, unknown dependencies and dependency cycles before returning ready artifacts.
- **REQ-CP-002** (event-driven): WHEN artifact status is requested, THE SYSTEM SHALL distinguish missing, draft, valid, ready, claimed, running, blocked, failed, verified and done states.
- **REQ-CP-003** (event-driven): WHEN instructions are requested for an artifact or task, THE SYSTEM SHALL return exact context files, prerequisites, validators and expected outputs.
- **REQ-CP-004** (event-driven): WHEN JSON mode is selected, THE SYSTEM SHALL emit one schema-versioned JSON document and stable diagnostics.
- **REQ-CP-005** (event-driven): WHEN a write/archive operation is planned, THE SYSTEM SHALL prepare and validate all resulting state before committing filesystem changes.
- **REQ-CP-006** (optional): WHERE a project does not configure custom artifact profiles, THE SYSTEM SHALL use a backward-compatible built-in profile.

### Long-session kernel

- **REQ-RK-001** (event-driven): WHEN engine-v2 starts a run, THE SYSTEM SHALL persist run ID, plan hash, baseline SHA, release, phase, wave and resume cursor atomically.
- **REQ-RK-002** (event-driven): WHEN a heavy lifecycle step runs, THE SYSTEM SHALL use a fresh scoped agent where the host supports spawning.
- **REQ-RK-003** (event-driven): WHEN execution is interrupted, THE SYSTEM SHALL derive the next safe action from disk state without relying on chat history.
- **REQ-RK-004** (event-driven): WHEN a result exists without a summary or a commit exists without evidence, THE SYSTEM SHALL enter a recovery gate instead of repeating or accepting the task silently.
- **REQ-RK-005** (event-driven): WHEN run state is corrupt, THE SYSTEM SHALL diagnose it and attempt deterministic reconstruction from sequenced events and artifacts without deleting user work.
- **REQ-RK-006** (event-driven): WHEN context headroom crosses configured thresholds, THE SYSTEM SHALL save a bounded handoff and stop dispatching new heavy work.

### Plan IR and waves

- **REQ-PI-001** (event-driven): WHEN a plan is compiled, THE SYSTEM SHALL emit a versioned Plan IR with dependencies, preconditions, effects, scopes, risk, cost and verification.
- **REQ-PI-002** (event-driven): WHEN Plan IR contains cycles, unknown dependencies or unsafe ownership overlap, THE SYSTEM SHALL reject it before dispatch.
- **REQ-PI-003** (event-driven): WHEN nodes are independent and host capabilities permit, THE SYSTEM SHALL group them into deterministic waves.
- **REQ-PI-004** (event-driven): WHEN the host cannot safely execute a wave in parallel, THE SYSTEM SHALL use the configured sequential fallback or halt.
- **REQ-PI-005** (event-driven): WHEN a task exceeds the configured context budget, THE SYSTEM SHALL require decomposition before execution.
- **REQ-PI-006** (event-driven): WHEN a plan passes checking, THE SYSTEM SHALL record its hash so runtime drift can be detected.

### Typed workflow execution

- **REQ-WF-001** (event-driven): WHEN Plan IR is compiled for execution, THE SYSTEM SHALL assign every node exactly one kind from `agent|check|transform|loop|approval|cancel` and validate its kind-specific contract.
- **REQ-WF-002** (event-driven): WHEN a conditional node is evaluated, THE SYSTEM SHALL use a typed source/path/operator/value contract; an invalid condition SHALL fail the node rather than silently skip it.
- **REQ-WF-003** (event-driven): WHEN multiple branches converge, THE SYSTEM SHALL apply an explicit join policy from `all_succeeded|any_succeeded|none_failed_one_succeeded|all_terminal` and persist the reason for ready, blocked or skipped status.
- **REQ-WF-004** (event-driven): WHEN a test, schema check or deterministic transformation can be executed without model judgment, THE SYSTEM SHALL use a `check` or `transform` runner rather than an AI completion claim.
- **REQ-WF-005** (event-driven): WHEN a loop node runs, THE SYSTEM SHALL enforce `max_iterations`, context policy, a deterministic completion gate and an explicit exhausted outcome.
- **REQ-WF-006** (event-driven): WHEN an approval node pauses a run, THE SYSTEM SHALL persist actor, decision, attempt and approved artifact digest; rework SHALL produce a new digest and require a new decision.
- **REQ-WF-007** (event-driven): WHEN a node declares typed output, THE SYSTEM SHALL validate the output schema and persist a per-node artifact manifest before marking a required output successful.
- **REQ-WF-008** (event-driven): WHEN node state changes, THE SYSTEM SHALL append a sequenced idempotent run event and atomically maintain a reconstructable snapshot; correctness-critical events SHALL NOT be best-effort.

### Execution isolation

- **REQ-EX-001** (event-driven): WHEN a writer task is dispatched in parallel, THE SYSTEM SHALL isolate its source tree and git index from other writer tasks.
- **REQ-EX-002** (state-driven): WHILE workers execute, THE SYSTEM SHALL prevent them from changing canonical Memory Bank files and DoD checkboxes.
- **REQ-EX-003** (event-driven): WHEN a worker completes, THE SYSTEM SHALL return a result, summary and evidence through unique file paths.
- **REQ-EX-004** (event-driven): WHEN integrating completed workers, THE SYSTEM SHALL integrate sequentially and stop on conflicts while preserving recoverable worktrees.
- **REQ-EX-005** (event-driven): WHEN worktrees are unavailable or unsafe, THE SYSTEM SHALL not launch concurrent writers.
- **REQ-EX-006** (event-driven): WHEN an orphan worker, lease or worktree is detected, THE SYSTEM SHALL report repair commands without automatic destructive cleanup.

### Verification, UAT and gap closure

- **REQ-EV-001** (event-driven): WHEN a task or release is declared complete, THE SYSTEM SHALL require fresh evidence tied to current source state.
- **REQ-EV-002** (event-driven): WHEN verification runs, THE SYSTEM SHALL map REQ-IDs and acceptance criteria to commands, tests or review evidence.
- **REQ-EV-003** (event-driven): WHEN UAT is required, THE SYSTEM SHALL persist scenarios, results and unresolved observations so UAT can resume.
- **REQ-EV-004** (event-driven): WHEN verification or UAT fails, THE SYSTEM SHALL create bounded gap plans rather than reopening the entire completed graph.
- **REQ-EV-005** (event-driven): WHEN gap plans execute, THE SYSTEM SHALL re-run affected verification and prevent stale evidence reuse.
- **REQ-EV-006** (event-driven): WHEN blocker or major findings remain, THE SYSTEM SHALL prevent release readiness.
- **REQ-EV-007** (event-driven): WHEN a required node artifact or evidence record cannot be persisted or validated, THE SYSTEM SHALL fail closed; advisory output MAY use an explicit best-effort policy.

### Skill registry, provider capabilities and evals

- **REQ-SR-001** (event-driven): WHEN skills, agents, commands or adapters are installed, THE SYSTEM SHALL generate a canonical capability registry.
- **REQ-SR-002** (event-driven): WHEN routing a request, THE SYSTEM SHALL select capabilities from trigger metadata, required inputs, side effects and host support.
- **REQ-SR-003** (event-driven): WHEN a capability is unsupported on the active host, THE SYSTEM SHALL document and apply an explicit degradation path.
- **REQ-SR-004** (event-driven): WHEN a reusable skill changes, THE SYSTEM SHALL run positive, negative-trigger, pressure and portability evals appropriate to its risk.
- **REQ-SR-005** (event-driven): WHEN detailed references are not needed, THE SYSTEM SHALL use progressive disclosure rather than loading the full skill bundle.
- **REQ-SR-006** (event-driven): WHEN registry generation encounters duplicate capability IDs or invalid tool references, THE SYSTEM SHALL fail validation.
- **REQ-SR-007** (event-driven): WHEN an adapter declares structured output, session resume, sandbox, tool policy, subagents or worktree support, THE SYSTEM SHALL use capability levels rather than an ambiguous boolean and validate the required safety level before dispatch.
- **REQ-SR-008** (event-driven): WHEN project/global/built-in workflows or skills share an identity, THE SYSTEM SHALL apply deterministic precedence, preserve an immutable safety floor and ask on unsafe routing ambiguity.

### External projection and delta specs

- **REQ-GH-001** (optional): WHERE GitHub projection is enabled, THE SYSTEM SHALL preserve stable local task IDs and store remote IDs only in a mapping file.
- **REQ-GH-002** (event-driven): WHEN a projection write is requested, THE SYSTEM SHALL produce a dry-run and require explicit authorization before remote mutation.
- **REQ-GH-003** (event-driven): WHEN projection is retried, THE SYSTEM SHALL be idempotent and shall detect partial remote state.
- **REQ-GH-004** (event-driven): WHEN GitHub is unavailable, THE SYSTEM SHALL keep local planning and execution functional.
- **REQ-DS-001** (optional): WHERE delta specs are enabled, THE SYSTEM SHALL support ADDED, MODIFIED, REMOVED and RENAMED requirement changes.
- **REQ-DS-002** (event-driven): WHEN a delta is applied, THE SYSTEM SHALL validate the rebuilt target specification before writing it.

### External executors and context sources

- **REQ-XE-001** (optional): WHERE an external executor is enabled, THE SYSTEM SHALL use a backend-neutral adapter supporting capability validation, start, status, events, decisions, cancellation and artifact discovery.
- **REQ-XE-002** (event-driven): WHEN an external backend reports success, THE SYSTEM SHALL keep the Memory Bank run non-terminal until imported artifacts and evidence pass independent local verification.
- **REQ-XE-003** (event-driven): WHEN external events or artifacts are imported repeatedly, THE SYSTEM SHALL deduplicate them by stable idempotency keys and SHALL NOT allow the backend to write canonical Memory Bank state directly.
- **REQ-XE-004** (event-driven): WHEN an external session, service or provider context is lost, THE SYSTEM SHALL remain recoverable from local Plan IR, events, decisions and artifact manifests.
- **REQ-XE-005** (optional): WHERE an external backend may mutate a checkout, THE SYSTEM SHALL enforce the same immutable safety floor as native execution: isolated checkout per concurrent writer, `owned_paths`, tool/sandbox policy and no project extension capable of weakening those controls; otherwise execution SHALL serialize or halt.
- **REQ-KB-001** (optional): WHERE external documentation retrieval is enabled, THE SYSTEM SHALL record source provenance, project scope, retrieval timestamp and citations in an immutable context bundle; the external index SHALL NOT become canonical project memory.

### Replanning and operations

- **REQ-RP-001** (event-driven): WHEN a precondition fails, verification fails, scope conflicts or material new facts appear, THE SYSTEM SHALL evaluate a replan trigger.
- **REQ-RP-002** (event-driven): WHEN replanning occurs, THE SYSTEM SHALL modify only pending nodes and preserve completed node history.
- **REQ-RP-003** (event-driven): WHEN a replan is accepted, THE SYSTEM SHALL record reason, graph delta, author/agent, timestamp and new plan hash.
- **REQ-RP-004** (event-driven): WHEN automatic replanning exceeds its configured limit, THE SYSTEM SHALL stop for human direction.
- **REQ-OP-001** (event-driven): WHEN workflow health is requested, THE SYSTEM SHALL diagnose state drift, orphan worktrees, stale leases, incomplete summaries and evidence freshness.
- **REQ-OP-002** (event-driven): WHEN repair is requested, THE SYSTEM SHALL default to dry-run and require explicit apply for mutations.
- **REQ-OP-003** (event-driven): WHEN telemetry is enabled, THE SYSTEM SHALL record local, privacy-safe timing, dispatch, token and failure metrics without prompt/source content.

### Optional specification authoring


### Optional GSD execution engine (v6.5.0 — iceboxed)

- **REQ-GSD-001** (optional): WHERE backend `external:gsd` selected, THE SYSTEM SHALL keep `/mb work` and the compiled Memory Bank pipeline as the sole lifecycle authority.
- **REQ-GSD-002** (event-driven): WHEN source mutation is imminent, THE SYSTEM SHALL first validate installed GSD version, adapter, bridge, runtime, Node/npm, Plan IR projection, commit policy and isolation policy.
- **REQ-GSD-003** (event-driven): WHEN install, enable or update changes executable surfaces, THE SYSTEM SHALL disclose exact provenance and surfaces and SHALL require explicit consent.
- **REQ-GSD-004** (ubiquitous): THE SYSTEM SHALL deterministically project approved Plan IR while preserving stable IDs, REQ-IDs, dependencies, owned scopes, acceptance and verification semantics, and SHALL block required semantic loss.
- **REQ-GSD-005** (ubiquitous): THE SYSTEM SHALL invoke GSD through `engine.execute_verified` with autonomous transition, ship, push and release disabled.
- **REQ-GSD-006** (ubiquitous): THE SYSTEM SHALL treat `.planning` as reconstructible engine projection, SHALL store validated imported artifacts under the Memory Bank run namespace and SHALL NOT use a writable symlink as canonical integration.
- **REQ-GSD-007** (ubiquitous): THE SYSTEM SHALL record GSD, adapter, bridge and runtime versions plus source, spec, plan, pipeline, projection and baseline hashes before dispatch.
- **REQ-GSD-008** (event-driven): WHEN GSD returns has completed, THE SYSTEM SHALL import native artifacts idempotently and SHALL independently verify the current HEAD before terminal Memory Bank transition.
- **REQ-GSD-009** (ubiquitous): THE SYSTEM SHALL select exactly one isolation owner and SHALL serialize or halt when runtime concurrency safety is not proven.
- **REQ-GSD-010** (unwanted): IF selected commit policy is incompatible with GSD, THE SYSTEM SHALL fail before mutation and SHALL NOT silently enable commits.
- **REQ-GSD-011** (event-driven): WHEN resume is imminent, THE SYSTEM SHALL first classify state as `exact`, `gsd_ahead`, `mb_ahead`, `divergent` or `corrupt`, and SHALL NOT blindly redispatch a task with commit but missing SUMMARY.
- **REQ-GSD-012** (event-driven): WHEN first source mutation has completed, THE SYSTEM SHALL NOT switch execution backend without explicit reconciliation, approval and a new attempt.
- **REQ-GSD-013** (ubiquitous): THE SYSTEM SHALL update Memory Bank and GSD independently and SHALL fail closed for `external:gsd` after compatibility drift.
- **REQ-GSD-014** (ubiquitous): THE SYSTEM SHALL prevent bridge capability and direct GSD workflows from recursively invoking Memory Bank orchestration or writing canonical Memory Bank state.
- **REQ-GSD-015** (ubiquitous): THE SYSTEM SHALL keep GSD planning and replanning non-canonical until a separate validated semantic-delta contract is released.
- **REQ-GSD-016** (ubiquitous): THE SYSTEM SHALL migrate legacy Build configuration through dry-run, semantic diff and idempotent conversion without deleting user installations, configuration or work artifacts.

### Optional OpenSpec authoring engine (v6.6.0 — iceboxed)

- **REQ-OSA-001** (event-driven): WHEN OpenSpec authoring is selected, THE SYSTEM SHALL keep Memory Bank as the sole owner of canonical specification revisions, approvals and lifecycle state.
- **REQ-OSA-002** (ubiquitous): THE SYSTEM SHALL select specification authoring and execution backends independently and SHALL support all four native/OpenSpec × native/GSD combinations.
- **REQ-OSA-003** (ubiquitous): THE SYSTEM SHALL keep native authoring as default with `authoring_profile=null` and SHALL bind an explicit OpenSpec profile, version, source snapshot and adapter per external change before staged mutation.
- **REQ-OSA-004** (event-driven): WHEN OpenSpec authoring is imminent, THE SYSTEM SHALL first validate exact version, runtime, public surfaces, schema profile, adapter, normalizer and host compatibility.
- **REQ-OSA-005** (ubiquitous): THE SYSTEM SHALL run OpenSpec in an isolated reconstructible workspace and SHALL prevent it from writing canonical Memory Bank state.
- **REQ-OSA-006** (ubiquitous): THE SYSTEM SHALL allow only declared authoring surfaces and SHALL prevent apply, sync, archive, bulk-archive, implementation verification and autonomous execution transitions.
- **REQ-OSA-007** (event-driven): WHEN memory-bank-spec-v1 is selected, THE SYSTEM SHALL preserve all required requirement, dependency, scope, risk, permission, acceptance, verification and evidence semantics.
- **REQ-OSA-008** (event-driven): WHEN stock spec-driven is selected, THE SYSTEM SHALL identify missing semantics, require enrichment and block canonical import while blocking diagnostics remain.
- **REQ-OSA-009** (ubiquitous): THE SYSTEM SHALL project a native SDD draft and normalize either OpenSpec profile into a deterministic Canonical Spec Bundle V1 with stable IDs, source mapping, exact provenance and content digests.
- **REQ-OSA-010** (ubiquitous): THE SYSTEM SHALL bind deltas to an exact base spec digest and SHALL reject stale, ambiguous or conflicting delta operations.
- **REQ-OSA-011** (ubiquitous): THE SYSTEM SHALL require approval bound to draft/bundle, semantic diff and base digests and SHALL atomically commit at most one canonical revision through native promotion or external CAS import.
- **REQ-OSA-012** (ubiquitous): THE SYSTEM SHALL NOT perform watcher-based, background or implicit bidirectional synchronization between OpenSpec and Memory Bank.
- **REQ-OSA-013** (event-driven): WHEN external OpenSpec resume or import is imminent, THE SYSTEM SHALL first classify state as exact, openspec_ahead, mb_ahead, divergent or corrupt and SHALL fail closed for unresolved divergence.
- **REQ-OSA-014** (ubiquitous): THE SYSTEM SHALL NOT compile executable Plan IR until the promoted or imported canonical revision is approved, complete and free of blocking diagnostics.
- **REQ-OSA-015** (ubiquitous): THE SYSTEM SHALL hand both native and GSD execution only the canonical Plan IR and SHALL NOT expose raw OpenSpec lifecycle state as execution authority.
- **REQ-OSA-016** (ubiquitous): THE SYSTEM SHALL preserve bundle, semantic diff and approval for both paths; native authoring SHALL preserve its promotion receipt, while external OpenSpec SHALL additionally preserve upstream artifacts, mappings, version bindings, source snapshot and import receipt as auditable evidence.
- **REQ-OSA-017** (ubiquitous): THE SYSTEM SHALL update Memory Bank and OpenSpec independently and SHALL disable only the OpenSpec backend when compatibility cannot be proven.
- **REQ-OSA-018** (ubiquitous): THE SYSTEM SHALL prevent direct OpenSpec workflows from invoking Memory Bank execution, GSD execution, canonical approval, archive or terminal lifecycle transitions.
- **REQ-OSA-019** (event-driven): WHEN a canonical specification revision is committed has completed, THE SYSTEM SHALL execute and resume native or GSD work without requiring the OpenSpec runtime or staging workspace.
- **REQ-OSA-020** (state-driven): WHILE processing semantically equivalent approved input, THE SYSTEM SHALL preserve requirement, `plan_semantic_digest`, verification and lifecycle semantics across all four authoring/execution combinations.

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Program start requires a valid spec triple
**Covers:** REQ-PGM-001, REQ-PGM-002

- GIVEN an active Memory Bank without a validated spec triple for the program and engine-v2 not enabled
- WHEN the user requests implementation work for mb-donor-evolution
- THEN the system refuses to dispatch implementation until requirements/design/tasks validate
- AND `/mb work` keeps its current sequential behavior unchanged
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Single source of truth and versioned migration
**Covers:** REQ-PGM-003, REQ-PGM-004

- GIVEN run artifacts under `.memory-bank/runs/` and a schema bump from v1 to v2
- WHEN the migration runs
- THEN it offers dry-run and rollback, and no state store outside `.memory-bank/` is created
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Failed release gate stops the train
**Covers:** REQ-PGM-005, REQ-PGM-006

- GIVEN release 5.5.0 with a failing implementation gate
- WHEN the gate is evaluated
- THEN tasks of 5.6.0+ stay blocked and no tag/publish/push happens without explicit user authorization
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Artifact profile rejects a cyclic DAG
**Covers:** REQ-CP-001, REQ-CP-006

- GIVEN a project with no custom profile and a fixture profile containing a dependency cycle
- WHEN the profile loads
- THEN the cycle yields a stable diagnostic code and non-zero exit, while the built-in profile keeps legacy specs working
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Artifact status distinguishes draft from ready
**Covers:** REQ-CP-002, REQ-CP-003

- GIVEN a partially filled design.md
- WHEN artifact status and instructions are requested
- THEN the artifact reports draft (not ready) and instructions return the exact context files and expected outputs for the next step
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: JSON mode and prepare-before-write
**Covers:** REQ-CP-004, REQ-CP-005

- GIVEN a pending artifact state update
- WHEN JSON mode validation runs
- THEN exactly one schema-versioned JSON document is emitted and filesystem changes commit only after the full resulting state validates
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Run state survives a process kill
**Covers:** REQ-RK-001, REQ-RK-003

- GIVEN an engine-v2 run persisted atomically with plan hash, baseline SHA and resume cursor
- WHEN the process is killed and a new session starts
- THEN the next safe action derives from disk state alone, without chat history
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Fresh agents and context headroom
**Covers:** REQ-RK-002, REQ-RK-006

- GIVEN a host with spawn capability and context usage crossing the configured threshold
- WHEN the next heavy lifecycle step is due
- THEN it runs in a fresh scoped agent, and past the threshold a bounded handoff is saved instead of dispatching new heavy work
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Inconsistent run state enters recovery
**Covers:** REQ-RK-004, REQ-RK-005

- GIVEN a result file without a summary and a corrupt state.json
- WHEN resume is attempted
- THEN the system enters a recovery gate, reconstructs state deterministically from sequenced events and deletes no user work
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Plan IR compile rejects invalid graphs
**Covers:** REQ-PI-001, REQ-PI-002

- GIVEN mb-task blocks compiled to a versioned Plan IR
- WHEN the graph contains a cycle or overlapping owned paths
- THEN compilation fails before dispatch with the offending nodes named
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Deterministic waves with sequential fallback
**Covers:** REQ-PI-003, REQ-PI-004

- GIVEN independent nodes on a host without safe worktree isolation
- WHEN waves are planned
- THEN grouping is deterministic and execution falls back to the configured sequential mode or halts — never simulated parallelism
<!-- /mb-scenario:11 -->

<!-- mb-scenario:12 -->
### Scenario: Context budget and plan drift
**Covers:** REQ-PI-005, REQ-PI-006

- GIVEN a task exceeding its context budget and an approved plan whose hash was recorded
- WHEN execution is requested after the plan file changed
- THEN the oversized task requires decomposition and the hash mismatch forces revalidation
<!-- /mb-scenario:12 -->

<!-- mb-scenario:13 -->
### Scenario: Every node has exactly one validated kind
**Covers:** REQ-WF-001, REQ-WF-004

- GIVEN a plan containing a schema check expressible without model judgment
- WHEN the plan compiles
- THEN the node gets kind `check` (not `agent`), and a node with an unknown kind or foreign kind-specific fields is rejected
<!-- /mb-scenario:13 -->

<!-- mb-scenario:14 -->
### Scenario: Typed conditions and explicit joins
**Covers:** REQ-WF-002, REQ-WF-003

- GIVEN a conditional branch whose condition references a missing source and a fan-in of three branches
- WHEN the graph executes
- THEN the invalid condition fails the node (never silent skip) and the join applies its declared policy, persisting the reason for ready/blocked/skipped
<!-- /mb-scenario:14 -->

<!-- mb-scenario:15 -->
### Scenario: Bounded loops and digest-bound approvals
**Covers:** REQ-WF-005, REQ-WF-006

- GIVEN a loop node at max_iterations without passing its deterministic gate and an approval rework producing a new artifact digest
- WHEN both nodes resolve
- THEN the loop ends as explicit `exhausted` and the old approval does not transfer to the new digest
<!-- /mb-scenario:15 -->

<!-- mb-scenario:16 -->
### Scenario: Typed outputs and fail-closed events
**Covers:** REQ-WF-007, REQ-WF-008

- GIVEN a node declaring a required typed output
- WHEN its artifact write fails the schema check or the event journal write fails
- THEN the node fails closed, and every state change appends a sequenced idempotent event with a reconstructable snapshot
<!-- /mb-scenario:16 -->

<!-- mb-scenario:17 -->
### Scenario: Concurrent writers never share a Git index
**Covers:** REQ-EX-001, REQ-EX-005

- GIVEN two parallel writer tasks on a host with worktree support disabled
- WHEN dispatch is planned
- THEN no concurrent writers launch; with worktrees available each writer gets an isolated tree and index
<!-- /mb-scenario:17 -->

<!-- mb-scenario:18 -->
### Scenario: Workers return results through unique paths only
**Covers:** REQ-EX-002, REQ-EX-003

- GIVEN a running worker
- WHEN it attempts to edit checklist.md or a DoD checkbox
- THEN the write is prevented, and its result/summary/evidence arrive only through its unique result directory
<!-- /mb-scenario:18 -->

<!-- mb-scenario:19 -->
### Scenario: Sequential integration and orphan repair
**Covers:** REQ-EX-004, REQ-EX-006

- GIVEN two completed workers with a merge conflict and one orphan worktree from a crashed run
- WHEN integration runs
- THEN it integrates sequentially, stops on the conflict preserving the worktree, and reports repair commands without destructive cleanup
<!-- /mb-scenario:19 -->

<!-- mb-scenario:20 -->
### Scenario: Done requires fresh mapped evidence
**Covers:** REQ-EV-001, REQ-EV-002

- GIVEN a task claiming completion after new commits landed
- WHEN verification runs
- THEN stale evidence is rejected and REQ-IDs/acceptance criteria map to concrete commands, tests or review records
<!-- /mb-scenario:20 -->

<!-- mb-scenario:21 -->
### Scenario: Resumable UAT and release readiness
**Covers:** REQ-EV-003, REQ-EV-006

- GIVEN a UAT session interrupted mid-scenario and one unresolved major finding
- WHEN the session resumes
- THEN persisted scenarios/results/observations restore, and release readiness stays blocked until the major finding resolves
<!-- /mb-scenario:21 -->

<!-- mb-scenario:22 -->
### Scenario: Bounded gap closure
**Covers:** REQ-EV-004, REQ-EV-005

- GIVEN a verification failure on two of ten criteria
- WHEN gap plans are created and executed
- THEN only the failed criteria and their dependencies reopen, affected verification re-runs and stale evidence is not reused
<!-- /mb-scenario:22 -->

<!-- mb-scenario:23 -->
### Scenario: Required evidence fails closed
**Covers:** REQ-EV-007

- GIVEN a node whose required evidence record cannot be persisted
- WHEN completion is evaluated
- THEN the node fails; only explicitly marked advisory output may be best-effort
<!-- /mb-scenario:23 -->

<!-- mb-scenario:24 -->
### Scenario: Registry generation is validated
**Covers:** REQ-SR-001, REQ-SR-006

- GIVEN installed skills and agents including two entries sharing a capability ID
- WHEN the canonical registry generates
- THEN generation fails validation naming the duplicate; with unique IDs a deterministic registry is produced
<!-- /mb-scenario:24 -->

<!-- mb-scenario:25 -->
### Scenario: Two-stage routing with progressive disclosure
**Covers:** REQ-SR-002, REQ-SR-005

- GIVEN a request matching several capabilities
- WHEN routing runs
- THEN candidates select on trigger metadata/inputs/side effects/host support, and only selected candidates load their full bundles
<!-- /mb-scenario:25 -->

<!-- mb-scenario:26 -->
### Scenario: Tiered capabilities gate dispatch
**Covers:** REQ-SR-003, REQ-SR-007

- GIVEN an adapter declaring `structured_output: best_effort` and a host lacking a required safety capability
- WHEN dispatch is prepared
- THEN best-effort output goes through bounded repair plus post-parse validation, and the unsupported safety capability applies its documented degradation path instead of proceeding silently
<!-- /mb-scenario:26 -->

<!-- mb-scenario:27 -->
### Scenario: Skill evals and precedence
**Covers:** REQ-SR-004, REQ-SR-008

- GIVEN a changed reusable skill and a project workflow shadowing a built-in identity
- WHEN evals and routing run
- THEN positive/negative/pressure/portability evals execute per risk, deterministic precedence applies, the safety floor stays immutable and unsafe ambiguity asks the user
<!-- /mb-scenario:27 -->

<!-- mb-scenario:28 -->
### Scenario: Projection preserves local IDs and dry-runs writes
**Covers:** REQ-GH-001, REQ-GH-002

- GIVEN GitHub projection enabled for a release
- WHEN a projection write is requested
- THEN local task IDs stay canonical (remote IDs only in the mapping file) and a dry-run plus explicit authorization precede any remote mutation
<!-- /mb-scenario:28 -->

<!-- mb-scenario:29 -->
### Scenario: Idempotent sync and GitHub outage
**Covers:** REQ-GH-003, REQ-GH-004

- GIVEN a projection retry after a partial failure and later a GitHub outage
- WHEN sync re-runs and local work continues
- THEN the retry detects partial remote state without duplicating entities, and planning/execution stay fully functional offline
<!-- /mb-scenario:29 -->

<!-- mb-scenario:30 -->
### Scenario: Delta specs rebuild-validate-apply
**Covers:** REQ-DS-001, REQ-DS-002

- GIVEN an enabled delta package with ADDED/MODIFIED/REMOVED/RENAMED operations
- WHEN the delta applies
- THEN the rebuilt target spec validates before any write; an invalid rebuild never replaces the current spec
<!-- /mb-scenario:30 -->

<!-- mb-scenario:31 -->
### Scenario: External executor is subordinate
**Covers:** REQ-XE-001, REQ-XE-002

- GIVEN an enabled external executor reporting success
- WHEN the Memory Bank run is evaluated
- THEN the backend-neutral adapter (validate/start/status/events/decision/cancel/artifacts) is the only boundary and the run stays non-terminal until imported artifacts pass independent local verification
<!-- /mb-scenario:31 -->

<!-- mb-scenario:32 -->
### Scenario: Idempotent import and local recovery
**Covers:** REQ-XE-003, REQ-XE-004

- GIVEN duplicated external events and a lost provider session
- WHEN import and resume run
- THEN events deduplicate by idempotency key, the backend never writes canonical state, and recovery proceeds from local Plan IR/events/manifests
<!-- /mb-scenario:32 -->

<!-- mb-scenario:33 -->
### Scenario: Safety floor for external checkouts and cited knowledge
**Covers:** REQ-XE-005, REQ-KB-001

- GIVEN an external backend mutating a checkout and an external-docs retrieval
- WHEN execution and retrieval run
- THEN the same isolation/owned-paths/tool-policy floor applies (or execution serializes/halts), and retrieved knowledge carries provenance, scope, timestamp and citations without becoming canonical memory
<!-- /mb-scenario:33 -->

<!-- mb-scenario:34 -->
### Scenario: Replanning touches only the pending graph
**Covers:** REQ-RP-001, REQ-RP-002

- GIVEN a failed precondition on a mid-graph node with five completed ancestors
- WHEN a replan is evaluated and accepted
- THEN only pending nodes change; completed node history and evidence stay immutable
<!-- /mb-scenario:34 -->

<!-- mb-scenario:35 -->
### Scenario: Replan audit and automatic bounds
**Covers:** REQ-RP-003, REQ-RP-004

- GIVEN two consecutive automatic replans on one run
- WHEN a third trigger fires
- THEN the system stops for human direction, and each accepted replan recorded reason, graph delta, author, timestamp and new plan hash
<!-- /mb-scenario:35 -->

<!-- mb-scenario:36 -->
### Scenario: Health diagnostics, dry-run repair, private telemetry
**Covers:** REQ-OP-001, REQ-OP-002, REQ-OP-003

- GIVEN seeded orphan worktrees, a stale lease and telemetry enabled
- WHEN health and repair are requested
- THEN diagnostics find the seeded faults, repair defaults to dry-run requiring explicit apply, and telemetry contains timing/dispatch/failure metrics but no prompt or source content
<!-- /mb-scenario:36 -->

<!-- mb-scenario:37 -->
### Scenario: GSD never gains lifecycle authority
**Covers:** REQ-GSD-001, REQ-GSD-002, REQ-GSD-003

- GIVEN backend `external:gsd` selected with a version drift and a pending install changing executable surfaces
- WHEN dispatch is prepared
- THEN compatibility validation fails before any source mutation, explicit consent with exact provenance is required, and `/mb work` remains the sole lifecycle authority
<!-- /mb-scenario:37 -->

<!-- mb-scenario:38 -->
### Scenario: Deterministic projection with bounded execution
**Covers:** REQ-GSD-004, REQ-GSD-005, REQ-GSD-015

- GIVEN an approved Plan IR projected for GSD
- WHEN projection and execution run
- THEN stable IDs/REQ-IDs/scopes/verification semantics survive (semantic loss blocks), execution goes through `engine.execute_verified` with autonomous ship/push/release disabled, and GSD planning stays non-canonical
<!-- /mb-scenario:38 -->

<!-- mb-scenario:39 -->
### Scenario: Reconstructible workspace and immutable binding
**Covers:** REQ-GSD-006, REQ-GSD-007

- GIVEN a GSD run with `.planning` workspace
- WHEN artifacts are integrated
- THEN `.planning` is treated as reconstructible projection (no writable symlink), imports land under the run namespace, and engine/adapter/runtime versions plus all hashes were recorded before dispatch
<!-- /mb-scenario:39 -->

<!-- mb-scenario:40 -->
### Scenario: Independent verification and update safety
**Covers:** REQ-GSD-008, REQ-GSD-013

- GIVEN GSD returning success and a later Memory Bank upgrade breaking compatibility
- WHEN import and the next `external:gsd` run happen
- THEN artifacts import idempotently with independent verification of current HEAD before terminal transition, and the incompatible pairing fails closed
<!-- /mb-scenario:40 -->

<!-- mb-scenario:41 -->
### Scenario: One isolation owner and commit compatibility
**Covers:** REQ-GSD-009, REQ-GSD-010

- GIVEN unproven runtime concurrency safety and a commit policy incompatible with GSD
- WHEN execution is planned
- THEN exactly one isolation owner is selected with serialize-or-halt, and the incompatible commit policy fails before mutation instead of silently enabling commits
<!-- /mb-scenario:41 -->

<!-- mb-scenario:42 -->
### Scenario: Reconciliation before resume, no silent fallback
**Covers:** REQ-GSD-011, REQ-GSD-012

- GIVEN a crashed GSD run with a commit but no SUMMARY
- WHEN resume is attempted
- THEN state classifies as exact/gsd_ahead/mb_ahead/divergent/corrupt, the task is not blindly redispatched, and no backend switch happens without explicit reconciliation and approval
<!-- /mb-scenario:42 -->

<!-- mb-scenario:43 -->
### Scenario: Bridge boundary and legacy Build migration
**Covers:** REQ-GSD-014, REQ-GSD-016

- GIVEN a GSD workflow invoking the memory-bank bridge and a legacy Build configuration
- WHEN the bridge is used and migration runs
- THEN recursion into Memory Bank orchestration and writes to canonical state are blocked, and migration is dry-run-first, semantically diffed, idempotent and non-destructive
<!-- /mb-scenario:43 -->

<!-- mb-scenario:44 -->
### Scenario: Specification authority and independent axes
**Covers:** REQ-OSA-001, REQ-OSA-002, REQ-OSA-003

- GIVEN OpenSpec authoring selected for one change
- WHEN authoring starts
- THEN Memory Bank stays sole owner of canonical revisions/approvals, all four authoring×execution combinations remain selectable, native stays default and the OpenSpec binding fixes profile/version/snapshot/adapter before staged mutation
<!-- /mb-scenario:44 -->

<!-- mb-scenario:45 -->
### Scenario: Isolated staging with bounded surfaces
**Covers:** REQ-OSA-004, REQ-OSA-005, REQ-OSA-006

- GIVEN an OpenSpec workspace and an attempted `apply` command
- WHEN authoring proceeds
- THEN compatibility validated exactly (version/runtime/schema/adapter/host) beforehand, the workspace is isolated and reconstructible with no canonical writes, and apply/sync/archive/execution transitions are blocked
<!-- /mb-scenario:45 -->

<!-- mb-scenario:46 -->
### Scenario: Lossless strict profile, guarded stock profile
**Covers:** REQ-OSA-007, REQ-OSA-008

- GIVEN one change authored with memory-bank-spec-v1 and another with stock spec-driven missing task semantics
- WHEN both normalize
- THEN the strict profile round-trips losslessly, and the stock import blocks canonical promotion until mandatory enrichment resolves its diagnostics
<!-- /mb-scenario:46 -->

<!-- mb-scenario:47 -->
### Scenario: Deterministic bundle and base-bound deltas
**Covers:** REQ-OSA-009, REQ-OSA-010

- GIVEN an authored draft normalized to Canonical Spec Bundle V1 and a delta bound to a stale base digest
- WHEN normalization and delta application run
- THEN the bundle is deterministic with stable IDs/provenance/digests, and the stale/ambiguous delta is rejected
<!-- /mb-scenario:47 -->

<!-- mb-scenario:48 -->
### Scenario: Atomic canonicalization without background sync
**Covers:** REQ-OSA-011, REQ-OSA-012

- GIVEN an approved bundle and a watcher-style sync proposal
- WHEN canonicalization runs
- THEN approval binds to draft/bundle/semantic-diff/base digests with at most one atomic canonical revision, and no background bidirectional synchronization ever runs
<!-- /mb-scenario:48 -->

<!-- mb-scenario:49 -->
### Scenario: Reconciliation and execution readiness
**Covers:** REQ-OSA-013, REQ-OSA-014

- GIVEN a divergent OpenSpec workspace and an unapproved imported revision
- WHEN resume/import and Plan IR compilation are requested
- THEN state classifies into exact/openspec_ahead/mb_ahead/divergent/corrupt failing closed on unresolved divergence, and no executable Plan IR compiles until the revision is approved and diagnostics-free
<!-- /mb-scenario:49 -->

<!-- mb-scenario:50 -->
### Scenario: Executor-neutral handoff with full provenance
**Covers:** REQ-OSA-015, REQ-OSA-016

- GIVEN a canonical revision executed by native and GSD backends
- WHEN handoff occurs
- THEN both receive only canonical Plan IR (raw OpenSpec lifecycle state carries no authority) and bundle/diff/approval plus receipts/snapshots persist as auditable evidence
<!-- /mb-scenario:50 -->

<!-- mb-scenario:51 -->
### Scenario: Independent updates and non-recursion
**Covers:** REQ-OSA-017, REQ-OSA-018

- GIVEN an OpenSpec upgrade with unproven compatibility and a direct OpenSpec workflow attempting execution
- WHEN both occur
- THEN only the OpenSpec backend disables (native SDD unaffected), and direct workflows cannot invoke Memory Bank execution, GSD, approval or terminal transitions
<!-- /mb-scenario:51 -->

<!-- mb-scenario:52 -->
### Scenario: Runtime independence and four-way parity
**Covers:** REQ-OSA-019, REQ-OSA-020

- GIVEN a committed canonical revision and the OpenSpec runtime uninstalled
- WHEN native or GSD execution resumes and parity fixtures run
- THEN execution needs no OpenSpec runtime or staging workspace, and semantically equivalent input preserves requirement/plan_semantic_digest/verification semantics across all four combinations
<!-- /mb-scenario:52 -->
