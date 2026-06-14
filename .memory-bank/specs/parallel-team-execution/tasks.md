---
type: spec-tasks
topic: parallel-team-execution
status: draft
created: 2026-06-14
linked_requirements: requirements.md
linked_design: design.md
---

# Tasks: parallel-team-execution

> Numbered, checkbox-tracked work items. Each task references the REQ-IDs it satisfies via Covers.
> SKELETON — titles + REQ coverage + TDD anchors in place; flesh out steps from design.md decisions.
> Ordered by phase: Phase 1 (REQ-PTE-070) → Phase 2 (REQ-PTE-071) → Phase 3 (REQ-PTE-072).

## Phase 1 — Parallel implement via subagents + schema (REQ-PTE-070)

<!-- mb-task:1 -->
## Task 1: pipeline.yaml parallel/team schema + validator

**Covers:** REQ-PTE-060, REQ-PTE-061, REQ-PTE-062, REQ-PTE-053
**Role:** developer

**What to do:**
- Add a first-class `execution`/`implement.parallelism`/`patterns` block to the bundled `pipeline.default.yaml`.
- Teach `mb-pipeline-validate.sh` to recognize + validate it (known keys, types, bounds; reject `max_parallel<=0`, unknown pattern, team-mode w/o fallback). <!-- TODO: exact keys -->

**Testing (TDD — tests BEFORE implementation):**
- Validator unit tests: valid block → exit 0; each invalid case → exit≠0 naming the key.

**DoD:**
- [ ] schema documented in `pipeline.default.yaml`; absence still validates (additive)
- [ ] validator covers all REQ-PTE-062 invalid cases
- [ ] tests pass; lint clean

<!-- mb-task:2 -->
## Task 2: work-unit decomposition (dependency-disjoint DAG)

**Covers:** REQ-PTE-001, REQ-PTE-005
**Role:** architect

**What to do:**
- Build a decomposer: plan/spec + `git diff --name-only` scope → unit DAG (id, files, deps, role); reuse roadmap `depends_on` topo-sort. <!-- TODO: format -->
- Reject dependency cycles (reuse parallel-pipeline DAG validation, REQ-141).

**Testing (TDD):**
- Cases: all-disjoint, mixed dependent+disjoint, single-unit, cycle (→reject).

**DoD:**
- [ ] disjoint vs dependent units correctly separated
- [ ] cycle → non-zero with named edge
- [ ] tests pass; lint clean

<!-- mb-task:3 -->
## Task 3: parallel-implement subagent dispatch + worktree-per-unit + merge

**Covers:** REQ-PTE-002, REQ-PTE-003, REQ-PTE-004, REQ-PTE-006, REQ-PTE-007
**Role:** developer

**What to do:**
- Dispatch one implementer subagent per disjoint unit via host-native subagents; dynamic degree bounded by `max_parallel`; worktree-per-unit (reuse parallel-pipeline worktree layer).
- Sequential-after-unit-green integration; sequential+WARN fallback when no native subagents.

**Testing (TDD):**
- Degree = min(#units, max_parallel); no two units touch same file; fallback path WARNs + stays correct.

**DoD:**
- [ ] N disjoint units run concurrently in isolated worktrees
- [ ] unit integrated only after its tests green
- [ ] fallback verified; tests pass; lint clean

<!-- mb-task:4 -->
## Task 4: code-as-verification gate + repair loop for parallel units

**Covers:** REQ-PTE-040, REQ-PTE-041, REQ-PTE-042
**Role:** qa / backend
**Depends on:** Task 3

**What to do:**
- Gate each unit's integration on `mb-flow-verify.sh` + `mb-work-severity-gate.sh` (sole authority); non-zero → per-unit repair loop, never "finished".

**Testing (TDD):**
- Red verify on one unit blocks completion + enters repair; green-but-verifier-disagrees → verifier wins.

**DoD:**
- [ ] completion gated by exit code, not self-assessment
- [ ] repair loop bounded; tests pass; lint clean

## Phase 2 — Native Team mode + mode selection (REQ-PTE-071)

<!-- mb-task:5 -->
## Task 5: orchestrator scope→mode decision matrix + deterministic floor

**Covers:** REQ-PTE-012, REQ-PTE-022
**Role:** architect

**What to do:**
- Implement mode selector (sequential|subagent|team) from scope, mirroring GSD matrix; deterministic floor forces ≥ wave/team on `domain/`/ports/interface/`protected_path`/multi-plan scope. <!-- TODO: thresholds -->

**Testing (TDD):**
- Scope fixtures map to expected mode; floor overrides heuristic on protected/interface scope.

**DoD:**
- [ ] matrix documented; floor non-overridable by heuristic
- [ ] tests pass; lint clean

<!-- mb-task:6 -->
## Task 6: native Team mode (TeamCreate + SendMessage) + assignment + degrade

**Covers:** REQ-PTE-010, REQ-PTE-011, REQ-PTE-013, REQ-PTE-014
**Role:** developer
**Depends on:** Task 5

**What to do:**
- Team-mode path: spawn persistent teammates, assign role+work-slice, coordinate via host messaging under a lead; persist membership/slice in the runtime fence; degrade team→subagent→sequential + WARN on Team-less hosts.

**Testing (TDD):**
- Assignment covers all slices; degrade ladder verified; fence membership idempotent.

**DoD:**
- [ ] teammates persistent + addressable on Team-capable host
- [ ] degrade path correct; tests pass; lint clean

<!-- mb-task:7 -->
## Task 7: progress monitoring + runtime fence

**Covers:** REQ-PTE-030, REQ-PTE-031, REQ-PTE-032
**Role:** developer

**What to do:**
- Monitor per-unit/teammate status (pending/running/green/failed); halt+surface+retry/fallback on fail/timeout/stall; persist status in `<!-- mb-flow -->` fence (idempotent, outside-fence byte-preserved).

**Testing (TDD):**
- Stall → halt+retry, no silent drop; fence regen preserves surrounding content.

**DoD:**
- [ ] live status surfaceable mid-run
- [ ] no unit silently dropped; tests pass; lint clean

## Phase 3 — Pattern library + adapters + validation (REQ-PTE-072)

<!-- mb-task:8 -->
## Task 8: execution-pattern library + workflow-as-code

**Covers:** REQ-PTE-020, REQ-PTE-021, REQ-PTE-023, REQ-PTE-024
**Role:** architect

**What to do:**
- Author `patterns/<name>.md` templates (sequential, parallel-fanout, pipeline, wave-DAG, loop-until-dry, adversarial-verify, judge-panel); orchestrator selects one + records justification; allow reproducible patterns as workflow-as-code whose structured output is consumed; reuse review-ensemble + parallel-pipeline waves.

**Testing (TDD):**
- Selection records pattern+justification; coded pattern's structured output parsed for verification.

**DoD:**
- [ ] ≥7 patterns catalogued; no parallel primitive reimplemented
- [ ] tests pass; lint clean

<!-- mb-task:9 -->
## Task 9: cross-agent adapters + budget + backward-compat

**Covers:** REQ-PTE-050, REQ-PTE-051, REQ-PTE-052, NFR-PTE-003
**Role:** devops

**What to do:**
- Extend existing `adapters/*` for parallel/team dispatch (Claude Code native; Pi/Codex/OpenCode degrade); wire per-wave budget reserve; assert default `/mb work` stays byte-identical when no parallel/team requested.

**Testing (TDD):**
- Golden test: no-parallel run byte-identical to current; budget hard-stop fires; degrade per host.

**DoD:**
- [ ] default behavior unchanged (regression golden)
- [ ] budget enforced; tests pass; lint clean

<!-- mb-task:10 -->
## Task 10: performance + observability validation

**Covers:** NFR-PTE-001, NFR-PTE-002, NFR-PTE-004, NFR-PTE-005, NFR-PTE-006
**Role:** qa

**What to do:**
- Measure wall-clock speedup vs sequential for N disjoint units; assert no two agents mutate same file; verify live progress surfaceable; confirm deterministic completion + Opus-tier default per pipeline.yaml.

**Testing (TDD):**
- Bench: speedup approaches linear up to max_parallel minus overhead; safety + determinism asserted.

**DoD:**
- [ ] measured speedup documented; safety/determinism proven
- [ ] tests pass; lint clean
