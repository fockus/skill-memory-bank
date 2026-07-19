---
type: spec-design
topic: mb-donor-evolution — donor-informed evolution of the SDD/execution/authoring stack
status: ready
created: 2026-07-15
source: source-plan.md §§2, 5-7, 22-23, 26, 29-30
authors: [Anton Ivanov]
---

# Design: mb-donor-evolution

Normalized design derived from `source-plan.md` (4245 lines). This document is the
navigable summary; full schemas, YAML/JSON examples and prose stay in the source
plan under the section references cited throughout (`source-plan.md §N`).

## 1. Baseline and superseded architecture

**Verified baseline: `VERSION=5.3.0`**, released 2026-07-13 (repo `VERSION` file,
`main` branch). Source plan §2 was drafted against `5.2.0`; this design corrects
the baseline to the actual released version and renumbers downstream releases
accordingly (§2 below).

Already implemented and **not** to be rebuilt:

- `.memory-bank/` as durable project state, Kiro/EARS SDD triple, executable
  `<!-- mb-task:N -->`;
- composable `/mb work` with workflow presets, durable work-state, budget,
  claims, resume primitives;
- governed verification, review ensemble, judge, bounded fix loop;
- handoff-v2, PreCompact/SessionStart recovery, progress hash chain;
- Dynamic Flow firewall, sprint contracts, trend/pivot, risk-aware gates;
- capability-aware dispatch, host adapters, GraphRAG-lite, session memory,
  traceability, deterministic checks.

This program links these primitives with stricter machine contracts and a
long-session state machine — it does not re-create SDD, review, memory,
handoff or adapter foundations.

**Superseded: `.memory-bank/specs/parallel-pipeline/`.** Kept only as a source
of requirements and test scenarios, not as target architecture (source §2.1):

- introduced a competing `/mb run` instead of extending `/mb work`;
- assumed a shared writable `.memory-bank` across worktrees via symlink;
- its task list never shipped;
- GSD-style execution needs a thin orchestrator, worker-specific handoffs and
  a single canonical-state writer — incompatible with a second state machine;
- host capabilities are uneven, so universal parallel-worktree execution
  cannot be promised.

**Replacement:** extend `/mb work` with a versioned execution engine
(`engine-v2`) inside the existing command surface. A compatible alias
`/mb run → /mb work --parallel` may ship only after `engine-v2` stabilizes —
never as a second state machine.

## 2. Release renumbering

Source-plan version labels were drafted against a stale `5.2.0` baseline while
the actual repo had already shipped `5.3.0`+. Per §23 R-15 (monotonic shift
when a semver is already claimed), all doc-internal release labels below
`6.0.0` shift by one patch step; REQ-IDs and `mb-task:N` numbers are untouched
by this shift (dependency graphs and priorities stay as authored).

| Doc label | Actual release | Codename |
|---|---|---|
| v5.3.0 | **v5.4.0** | Trustworthy Baseline |
| v5.4.0 | **v5.5.0** | Spec Control Plane |
| v5.5.0 | **v5.6.0** | Long-Session Kernel & Event Journal |
| v5.6.0 | **v5.7.0** | Plan IR & Typed Workflow Planner |
| v6.0.0 – v6.6.0 | unchanged | (as authored in source-plan.md) |

Any reference elsewhere in the spec triple (tasks.md, plans) to "v5.5" etc.
must be read against this table until the source plan itself is corrected.

## 3. Invariants

Blocking checks; violation is a defect, not a style note (source §5, §29.15, §30.15).

**Core (INV-01…INV-15, source §5):**

| ID | Rule |
|---|---|
| INV-01 | Canonical state lives only in `.memory-bank/`; `runs/` is part of the bank, not separate memory. |
| INV-02 | Only the orchestrator writes `STATUS.md/status.md`, `roadmap.md`, `checklist.md`, `progress.md`, `traceability.md`, run index. Workers write only their assigned worktree + unique result dir. |
| INV-03 | Research/plan/plan-check/implement/verify/gap-diagnosis run as fresh scoped agents when the host can spawn; orchestrator never writes production code in engine-v2. |
| INV-04 | State is never inferred from file presence alone; every artifact/task/run has explicit status + validation record. |
| INV-05 | Artifact DAG, Plan IR, host capabilities, file ownership, release gate are validated before dispatch/write. |
| INV-06 | Overlapping scopes / unsafe worktree base / unsupported isolation / failed capability probe → sequential or halt per policy, never simulated parallelism. |
| INV-07 | No `done`/release-readiness/judge-GO without a fresh evidence manifest bound to baseline/head SHA and REQ-ID. |
| INV-08 | Replanning never rewrites completed nodes/evidence; incomplete-graph changes are deltas with a reason. |
| INV-09 | Without explicit opt-in, `/mb work` stays sequential/economic; heavyweight stages are risk/flag/config-gated. |
| INV-10 | Remote trackers (GitHub/Linear/…) get a projection of stable local IDs; losing remote access never blocks local execution. |
| INV-11 | Every execution node has exactly one kind and a valid contract; safety-critical fields for an unsupported node/provider are never silently ignored or downgraded to a warning. |
| INV-12 | AI completion signals (`DONE`, `<promise>COMPLETE</promise>`) are hints only; `verified`/`done` requires a deterministic completion gate + fresh evidence. |
| INV-13 | Run transition, approval, mandatory-artifact and evidence ledgers are atomic and fail-closed; only telemetry/UI events may be best-effort. |
| INV-14 | Provider session resume is a context-cost optimization, not canonical memory; correctness/resume rebuild from `.memory-bank/` artifacts/events even if the provider session is lost. |
| INV-15 | An external executor (GSD, Archon, …) may run a compiled graph but never mutates canonical Memory Bank directly; `external succeeded` ≠ `Memory Bank done` without independent verification. |

**GSD engine (INV-16…INV-20, source §29.15):** bounded engine not lifecycle
authority · engine projection reconstructible from Plan IR/snapshot/adapter
version · one mutation owner per boundary · no silent semantic loss/fallback ·
independent products with versioned compatibility pairing.

**OpenSpec authoring (INV-21…INV-26, source §30.15):** authoring backend is
subordinate (no canonical/approval/execution ownership) · authoring and
execution axes are orthogonal · canonicalization always precedes execution ·
spec synchronization is transactional (digest-bound CAS, no live bidirectional
sync) · profile compatibility (lossless vs stock-import) is explicit, never a
silent semantic loss · authoring provenance (bundle/approval/receipt, plus
mapping/descriptor/snapshot/import-receipt for external) survives workspace
cleanup.

## 4. Target architecture

Authoring and execution are **independent axes** (source §6, §30.1):

```yaml
specification:
  authoring_backend: native          # native | external:openspec
execution:
  backend: native                    # native | external:gsd
```

Memory Bank normalizes any authoring backend's output into its own approved
spec bundle; executors only ever see canonical Plan IR, never raw OpenSpec
artifacts (full flow diagram: source §6, mermaid flowchart).

**Seven layers** (source §6.1):

1. **Memory layer** — existing context, specs, plans, decisions, progress, lessons, code graph.
2. **Control plane** — artifact profiles/DAG/validators, status/instructions API, authoring boundary, canonical promote/import, approval.
3. **Planning plane** — Plan IR, dependencies, scopes, risks, costs, verification, replanning rules.
4. **Workflow compilation plane** — typed execution nodes, conditions, join policies, output schemas, deterministic/AI boundary, backend-neutral graph.
5. **Execution plane** — run state, waves, bounded loops, approvals, worker leases, worktree/capability degradation, file handoff.
6. **Assurance plane** — evidence manifests, UAT, review/judge, gap plans, release gates.
7. **Extension plane** — skill/provider registry, native bundle projector, OpenSpec authoring adapter, native/GSD/Archon executor adapters, evals, external knowledge sources, optional projections.

**File structure** (abbreviated; full tree with all subpaths: source §6.2):

```text
.memory-bank/
  specs/<topic>/{requirements,design,tasks}.md, artifact-state.json, deltas/
  authoring/<change-id>/attempts/<n>/  # canonical-bundle, semantic-diff, diagnostics,
                                       # approvals/, promotion-receipt (native) or
                                       # external-openspec/ (descriptor, snapshot, import-*)
  plans/
  runs/index.json, <run-id>/{state.json, plan.ir.json, events.jsonl,
      context-manifest.json, nodes/, dispatch/, results/, summaries/,
      artifacts/<semantic-type>/, approvals/, evidence/, verification.md,
      uat.md, replans/, external/<backend>.json}
  integrations/{github-map, engines.lock, authoring.lock}.json  # optional
  tmp/runs/<run-id>/raw/                # ephemeral, never source of truth
.mb-workspaces/openspec/<change-id>-<attempt>/openspec/  # reconstructible, isolated
```

Completed-run compaction may drop raw logs but must retain `state.json`,
`plan.ir.json`, `events.jsonl`, node/artifact manifests, approvals, summary,
evidence index and verification result.

## 5. Machine contracts

All schemas carry `schema_version`, deterministic validation and migration
tests. JSON mode prints exactly one JSON document to stdout; human explanation
goes to stderr (source §7 preamble). Full schema per contract: `source-plan.md
§7.N` as noted.

**§7.1 Artifact DAG profile.** Declares artifact `id`/`path`/`requires`/`validators`
per spec stage (requirements → design → tasks → release_plan → apply).
States: `missing → draft → valid → ready → claimed → running → verified →
done`, with `blocked`/`failed` branches. Only validator/orchestrator drive
transitions; file presence (`present`) is never `valid`.

**§7.2 Plan IR.** One node per unit of work: `id`, `kind`, `goal`, `phase`,
`depends_on`, `condition`, `join_policy`, `conflicts_with`, `preconditions`,
`expected_effects`, typed `inputs`/`output`, `context` (fresh/bootstrap),
`policy` (`owned_paths`, `read_only_paths`, `tools`, `risk`), `retry`,
`timeout_ms`, `cost`, `completion_gate`, `verify`, `replan_on`. Validator
rejects unknown deps, cycles, duplicate IDs, non-single node kind, invalid
condition/join policy, missing ownership, unsafe path overlap, bad output
schema refs, impossible host capability, blown context budget.

Compiler emits a **Plan Digest Manifest V1** with two digests:
`plan_artifact_digest` (SHA-256 of exact canonical `plan.ir.json` bytes) and
`plan_semantic_digest` (`sha256("mb-plan-semantic/v1\n" || JCS)` over a
projection excluding `plan_id`, timestamps, provider/session refs, backend
selection, and other provenance-only fields). Four-way authoring/execution
parity (§6 below) compares `plan_semantic_digest`, not byte equality of
provenance-bearing manifests.

Node kinds (exactly one per node): `agent | check | transform | loop |
approval | cancel`. Join policies: `all_succeeded | any_succeeded |
none_failed_one_succeeded | all_terminal`. Conditions are a typed
`source + JSON path + operator + value` tuple — no arbitrary expression eval;
an invalid condition is `failed`, never a silent `skip`.

**§7.3 Run state.** Atomic `state.json` snapshot: `run_id`, `program`,
`release`, `status`, `phase`, `current_wave`, node buckets (`active`,
`completed`, `blocked`, `paused`, `skipped`, `cancelled`), `baseline_sha`,
`head_sha`, both plan digests, `resume_cursor`, `decision_refs`,
`external_refs`, `blockers`. Every state change appends a sequenced event to
`events.jsonl`; `state.json` must be reconstructible from events + filesystem
evidence. Run transitions/approvals/mandatory-artifact/evidence events are
never best-effort.

**§7.4 Dispatch manifest.** Scoped work order to a worker: `task_id`,
`node_id`, `kind`, `role`, `goal`, `context_files`, `owned_paths`,
`read_only_paths`, `worktree` (mode/path/baseline_sha), typed `output`
(result/summary/evidence paths, semantic type, schema ref, `required`),
`verification` commands, `commit_policy`. Workers never get rights to core
bank files or DoD checkboxes.

**§7.5 Evidence manifest.** `baseline_sha`/`head_sha`, `changed_files`,
`requirements` → test mapping, executed `commands` with exit codes,
`tests`/`findings` counters, `scope_check`, `fresh` flag. Freshness = tested
HEAD/diff hash matches the currently integrated state.

**§7.6 Diagnostic envelope.** `{command, ok, result, diagnostics:[{severity,
code, message, target, fix}]}`. Stable exit codes: `0` success, `1`
validation/user-input, `2` blocking gate, `3` environment/capability, `4`
conflict/claim, `5` corrupt state.

**§7.7 Host capability contract.** Declares, per host, tiered support for
`structured_output`, `session_resume`, `tool_policy`, `sandbox`, `subagents`,
`worktrees`, `hooks`, `skills`, plus `degradation` rules
(`unsafe_parallelism`, `missing_spawn`, `missing_precompact`). Probe must
reflect the actual environment, not a static table; an unsupported *safety*
capability is a validation error, a warning is allowed only for optional
UX/optimization; `best_effort` structured output requires bounded
repair-then-schema-validate.

**§7.8 Commit policy.** `none | checkpoint | per-task`. Default preserves
current project policy; `per-task` is never enabled implicitly; push always
stays outside the execution engine.

**§7.9 Run Event V1.** Append-only, strictly sequenced: `schema_version`,
`run_id`, `sequence`, `event_id`, `type`, `node_id`, `attempt`, `timestamp`,
`payload_ref`, `idempotency_key`. Vocabulary: `node_ready | node_started |
node_paused | node_succeeded | node_failed | node_skipped | node_cancelled |
retry_scheduled | artifact_produced | approval_recorded |
external_event_imported`. Telemetry may be a separate best-effort stream but
never participates in correctness/resume.

**§7.10 Approval Decision V1.** `decision: approved|rejected` bound to
`artifact_digest`; a rejection triggers bounded `rework → new digest →
re-present` — an approval never carries over to a changed artifact.

**§7.11 Typed Node Artifact V1.** Per-node manifest (`semantic_type`, `path`,
`checksum`, `size_bytes`, `producer`, `schema_ref`, `evidence_refs`,
`required`, `produced_at`); no shared mutable artifact index — it's computed
by reading metadata. A failed `required: true` artifact write fails the node;
advisory artifacts may be best-effort.

**§7.12 External Executor Adapter V1.** `validate | start | status | events |
decision | cancel | artifacts` over `(plan_ir, capabilities)` /
`dispatch_manifest` / `external_run_ref`. Backend selector: `native` or
`external:<adapter-id>`; `gsd`/`archon` are IDs of a separately installed,
conformance-tested adapter — core ships no such runtime. External events
import idempotently; the external backend never writes `.memory-bank/` core
state; Memory Bank independently verifies imported artifacts/evidence.

**§7.13 Context Source Contract.** Typed `context_sources` list (`memory-bank`,
`code-graph` query, `prior-artifact`, `git-diff`, optional P3
`external-docs` adapter requiring citations). Context bundle is immutable
with exact source refs + checksum; external knowledge never becomes Memory
Bank's source of truth.

**§7.14 Specification Authoring Contracts.** External authoring backends
implement a separate **Specification Authoring Adapter V1** (not the
Executor Adapter). Normative schemas `Canonical Spec Bundle V1`, `OpenSpec
Authoring Descriptor V1`, `Spec Import Transaction V1`, `Spec Reconciliation
V1` are defined in source §30.6–§30.11. Every execution binding references a
committed canonical spec digest, approval digest, `plan_artifact_digest` and
`plan_semantic_digest`; external authoring additionally retains source
snapshot and import receipt digests.

## 6. Capability and degradation matrix

Per-host capability tiers (source §7.7) drive required behavior; per-host
class scenarios must hold regardless of speed (source §20.3):

| Capability | Tiers | Required behavior when degraded |
|---|---|---|
| `structured_output` | enforced / best_effort / unsupported | best-effort → bounded repair + post-parse schema validation; unsupported → validated file fallback or fail-closed |
| `session_resume` | reliable / opaque / unsupported | correctness never depends on it (INV-14) |
| `sandbox` / `subagents` | native / partial-emulated / unsupported | unsafe tier → sequential or halt, never simulated isolation |
| `worktrees` | host / adapter / unsupported | unsafe base → sequential per INV-06 |
| `hooks` (PreCompact etc.) | native / adapter / unsupported | missing → explicit handoff before the context boundary |
| `skills` | native / adapter / flat / unsupported | flat/unsupported → CLI/skill entrypoint parity, not a feature cut |

| Host class (§20.3) | Required scenario |
|---|---|
| Native spawn + safe worktree | full parallel wave, fresh agents, resume |
| Spawn without worktree | fresh sequential, no concurrent writers |
| No spawn | classic checkpoint/resume or explicit halt |
| No PreCompact hook | explicit handoff before the boundary |
| No native slash commands | skill/CLI entrypoint parity |
| Structured output best-effort | bounded repair + schema validation, no unvalidated success |
| Structured output unsupported | validated file result fallback or fail-closed per policy |

## 7. Security boundaries

- **Single-writer core files (INV-02).** Only the orchestrator mutates
  `STATUS.md/status.md`, `roadmap.md`, `checklist.md`, `progress.md`,
  `traceability.md`, run index. Workers are scoped to `owned_paths` in their
  dispatch manifest (§7.4) plus a unique result directory; `read_only_paths`
  are enforced, not advisory.
- **No writable symlink as canonical integration.** `.planning`/OpenSpec
  staging workspaces are reconstructible projections, never a shared writable
  path back into `.memory-bank/` (REQ-GSD-006, source §29.16; superseded
  parallel-pipeline's symlink model is the counter-example, source §2.1).
- **External backends are subordinate (INV-15/16/21).** GSD/Archon/OpenSpec
  execute or author within their adapter boundary; canonical mutation always
  routes back through Memory Bank's own promote/import + independent
  verification. No adapter writes `.memory-bank/` core state directly.
- **Parallel-write isolation (R-02/R-03/R-17).** Overlapping `owned_paths`,
  a shared Git index across writers, or a failed capability probe fall back
  to sequential execution or halt — never simulated concurrency.
- **Privacy/telemetry boundary.** Telemetry defaults to off; when enabled it
  is local, privacy-safe, allowlisted metrics only, and is a best-effort
  stream that never affects resume/completion (INV-13, R-12). Correctness
  journals (run transitions, approvals, evidence) are always separate from
  telemetry and fail-closed.
- **Consent for executable surfaces.** Installing/enabling/updating an
  external adapter (GSD bridge, OpenSpec adapter) requires disclosed exact
  provenance and explicit consent (REQ-GSD-003); no autonomous ship/push/
  release from within an execution engine (REQ-GSD-005).

## 8. Migration, compatibility and defaults

**General rules (source §22.1):** Markdown stays the human authoring
interface; machine artifacts are versioned; minor schema changes are
additive (readers ignore unknown optional fields); major changes need a
migrator that is dry-run-first, snapshot-first, deterministic, idempotent,
validates before commit, and emits a migration manifest (old/new version +
hashes); legacy completed work never gets fabricated evidence/history; user
`pipeline.yaml`/adapters/rules/profiles are never overwritten by an upgrade;
no rollback deletes remote entities or user work automatically.

**Compatibility window (source §22.2; version labels per §2 renumbering):**

| Period | Read | Write |
|---|---|---|
| v5.4 | legacy Markdown/state + control-plane contracts | classic only |
| v5.5–v5.6 | legacy + run/Plan IR contracts | classic or opt-in engine-v2 |
| v6.0–v6.2 | legacy import/read + canonical run contracts | canonical v1 for engine-v2 |
| v6.3–v6.4 | canonical v1 + optional delta/projection | canonical v1 |
| v6.5 | canonical v1 + optional GSD projection/import | canonical v1; GSD state non-canonical |
| v6.6 | canonical v1 + native/OpenSpec authoring import | canonical v1; authoring workspace non-canonical |
| After v6.6 | dropping legacy read / authoring compat needs its own ADR/release | current canonical |

**Feature defaults (source §22.3):**

| Capability | Initial default |
|---|---|
| Artifact control plane | advisory low-risk, blocking medium/high risk |
| Engine-v2 | opt-in in v5.x; stable in v6.0 |
| Execution backend | `native`; external only by explicit selection |
| Parallel waves | explicit `--parallel`; never guessed on an unsafe host |
| Commit policy | existing project default / `none` if unset |
| Strict evidence | risk-aware |
| Dynamic skill routing | opt-in until precision gate |
| Delta specs | opt-in |
| GSD execution backend | explicit opt-in; exact compatible pairing required |
| OpenSpec authoring backend | native default; explicit per-spec opt-in |
| OpenSpec synchronization | explicit transaction only; no background two-way sync |
| GitHub writes | dry-run/read-only first + explicit approval |
| Automatic replanning | off until v6.4 dogfood; bounded when enabled |
| Telemetry | off; local and privacy-safe when enabled |

**Decisions to confirm before code (source §26)** — defaults below are the
recommendation; ask the user only if repo context makes a different choice
materially better:

1. CLI naming: minimal new surface (`mb artifacts ...` or fold into existing
   `mb flow/spec`), thin aliases only if needed.
2. Engine-v2 activation at v6.0: sequential stays default; engine-v2 for all
   governed runs; parallel stays explicit/risk-selected.
3. Run retention: compact manifests/events in git, raw output in ignored `tmp/`.
4. GitHub adapter: optional plugin; core ships only interface/schema.
5. Commit policy: `none` default, `checkpoint` opt-in for long sessions,
   `per-task` only via project config.
6. Auto replan: advisory by default; low-risk auto-apply only after v6.4 metrics.
7. Execution backend: `native` default; `external:<adapter-id>` only after
   optional adapter install + v6.3 conformance; GSD/Archon runtime never in core.
8. Event durability: correctness journal vs telemetry are separate; journal
   blocks transition on write failure, telemetry never affects resume/completion.
9. Provider capability truth: conformance-test-verified tiers; project config
   cannot inflate the actual capability level.
10. External knowledge: optional context-source adapter with citations/
    freshness; existing GraphRAG stays the canonical retrieval layer.
11. Specification authoring backend: `native` default; `external:openspec`
    explicit and pinned to a spec revision.
12. OpenSpec profiles: `memory-bank-spec-v1` lossless production default;
    stock `spec-driven` is a compatibility import requiring enrichment before approval.
13. OpenSpec sync model: explicit snapshot/import transaction with base
    digest + CAS only; background bidirectional sync is forbidden.

Any change to these 13 decisions needs its own ADR and a release-specific SDD delta.

## 9. Risks

Top risks from source §23 (all 20, condensed):

| ID | Risk | Mitigation | Kill trigger |
|---|---|---|---|
| R-01 | Second state store diverges from Memory Bank | INV-01, ADR, migration tests | any canonical divergence |
| R-02 | Workers race on core bank files | single writer, unique result dirs | any state loss/overwrite |
| R-03 | Parallel writers share the Git index | worktree-per-writer, capability probe | any same-index race |
| R-04 | Context overhead hurts small tasks | lite/quick path, progressive disclosure | p95 overhead > 25% |
| R-05 | Host docs promise nonexistent parity | runtime probes, conformance matrix | silent degradation |
| R-06 | Evidence goes stale after integration | SHA/diff/spec hashes, invalidation | stale evidence accepted |
| R-07 | Auto replan rewrites completed work | immutable completed graph | any confirmed case |
| R-08 | Remote sync creates/overwrites entities | dry-run, idempotency, read-before-write | silent overwrite/destructive retry |
| R-09 | Registry/router picks the wrong skill | negative/pressure evals, explicit wins | precision < 90% for default-on |
| R-10 | Mega-spec becomes unexecutable | release slices, context-fit checker | cross-release task/run |
| R-11 | Status/changelog drift returns | artifact receipts, release reconciliation | contradictions before release |
| R-12 | Telemetry leaks private/source content | allowlist metrics, privacy tests | any content leakage |
| R-13 | Worktree cleanup destroys uncommitted work | report-only default, explicit apply | auto destructive cleanup |
| R-14 | Donor feature creep turns skill into a runtime | non-goals, dependency budget | daemon/DB/swarm introduced |
| R-15 | SemVer numbers conflict with parallel roadmap | v5.3 baseline reconciliation (§2 renumbering) | existing claimed version found |
| R-16 | Best-effort event loss re-runs a side effect on resume | critical event journal, sequence/gap checks, idempotency keys | duplicate external/source mutation |
| R-17 | DAG layer runs parallel writers in a shared checkout | worktree per writer, owned-path enforcement, read-only shared context | any same-checkout writer race |
| R-18 | External executor state diverges from canonical run | subordinate adapter, independent verifier, local recovery | backend success accepted without local evidence |
| R-19 | Provider overstates its capability level | conformance fixtures, tiered degradation, fail-closed safety | unsupported safety semantics silently accepted |
| R-20 | External knowledge goes stale or loses provenance | project scope, timestamps/digests, citations, TTL | uncited/stale source accepted as trusted context |

If a specific semver is already taken at execution time, numbers may shift
strictly monotonically (per §2); release boundaries, dependencies, priority
and value are never merged in the process.

## 10. ADR links

**GSD execution engine (source §29.17):**

| ADR | Decision |
|---|---|
| ADR-GSD-001 | GSD is a subordinate optional engine; Memory Bank is the sole control plane |
| ADR-GSD-002 | `.planning` is a reconstructible projection/cache — no writable symlink |
| ADR-GSD-003 | bundled MB adapter + official GSD capability overlay; no patch, fork or third product |
| ADR-GSD-004 | composite `execute_verified` with explicit gate ownership |
| ADR-GSD-005 | one worktree owner + explicit commit-policy compatibility |
| ADR-GSD-006 | independent version, update, consent and conformance lifecycle |
| ADR-GSD-007 | legacy Build is a migration layer only |

**OpenSpec authoring (source §30.17):**

| ADR | Decision |
|---|---|
| ADR-OSA-001 | OpenSpec is an optional subordinate authoring backend; Memory Bank is the sole specification authority |
| ADR-OSA-002 | authoring backend and execution backend are independent axes |
| ADR-OSA-003 | Canonical Spec Bundle V1 is the portable authoring handoff/audit envelope — native derives it in-place, external imports it |
| ADR-OSA-004 | `memory-bank-spec-v1` lossless default; stock `spec-driven` is compatibility import with mandatory enrichment |
| ADR-OSA-005 | synchronization is an explicit digest-bound CAS transaction — no live bidirectional sync |
| ADR-OSA-006 | Memory Bank owns delta apply, approval and archive |
| ADR-OSA-007 | raw OpenSpec artifacts are never passed to an executor |
| ADR-OSA-008 | upstream OpenSpec is used without fork, vendoring or internal API coupling |

**Program-level ADRs (to be authored under task BL-03, not yet in
`backlog.md`):**

- **"`/mb work` is the single execution entrypoint"** — codifies §2.1's
  replacement decision (engine-v2 inside `/mb work`, no parallel `/mb run`
  state machine) as a standalone, citable ADR.
- **"Single orchestrator-writer for core bank files"** — codifies INV-02 +
  R-02/R-17 as a standalone ADR so downstream specs can cite one ADR ID
  instead of re-deriving the rule from the invariant list.

## Open questions

- None blocking: source §26's 13 decisions carry explicit recommended
  defaults and are treated as accepted unless repo context overrides them.
  Confirm during BL-03 ADR authoring rather than re-litigating here.
