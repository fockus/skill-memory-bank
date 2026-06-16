---
type: spec-tasks
topic: Dynamic Flow — agent-native adaptive orchestration over Memory Bank
status: draft
created: 2026-06-09
linked_design: design.md
linked_requirements: requirements.md
supersedes: [universal-orchestrator, goal-driven-autopilot]
---

# Tasks: dynamic-flow

Phased MVP. **Phase 1 is the only committed scope** (independently valuable on Claude Code). Phases 2–3 stay deferred until Phase 1's firewall is proven AND scope is reconfirmed. Determinism in scripts; fail-loud only in the fan-out + gate; reuse existing assets; net-new is thin.

## Phase 0 — supersede the dead specs

<!-- mb-task:1 -->
### Task 1: Supersede prior orchestration specs

**Covers:** REQ-DF-061
**Role:** architect

Testing: manual — confirm both moved dirs carry `SUPERSEDED.md` and no longer appear as active specs.

**DoD:**
- [x] `universal-orchestrator` + `goal-driven-autopilot` moved to `specs/superseded/`.
- [x] Each carries a `SUPERSEDED.md` pointing to `dynamic-flow`.
- [x] `dynamic-flow` is the only active orchestration spec.

## Phase 1 — Goal + Firewall (the common-denominator increment; valuable on Claude Code now)

<!-- mb-task:2 -->
### Task 2: Goal primitive (goal.md / project.md + scaffolder)

**Covers:** REQ-DF-001, REQ-DF-002, REQ-DF-003, REQ-DF-004, REQ-DF-005
**Role:** developer

Testing: bats for the goal validator — valid goal passes; missing acceptance criteria fails; missing/unresolvable `progress_source` fails; adaptive mode without `replan_with` fails.

**DoD:**
- [x] `goal.md` template (end-state + `## Acceptance criteria` `- [ ]`) and `project.md` template exist (shapes lifted from superseded goal-driven-autopilot).
- [x] `commands/goal.md` thin scaffolder creates them.
- [x] A goal with no adaptive fields reproduces today's static behaviour byte-identically.

<!-- mb-task:3 -->
### Task 3: `mb-flow` fence writer (status.md)

**Covers:** REQ-DF-030, REQ-DF-031, REQ-DF-032
**Role:** developer

Testing: bats — first write creates the fence; rewrite is idempotent; content outside the fence is byte-preserved; `goal.md` is never written to.

**DoD:**
- [x] `mb-flow-sync.sh` regenerates the `<!-- mb-flow -->` block in `status.md` idempotently.
- [x] `goal.md` stays durable-only (no live check-results).
- [x] No standalone `flow-state.json` authored as primary state.

<!-- mb-task:4 -->
### Task 4: Thin check runners (lint / no-TODO / diff-scope / acceptance)

**Covers:** REQ-DF-042, REQ-DF-043
**Role:** developer

Testing: pytest/bats per runner — pass case, fail case, and `null`/skip case; all stay exit-0 + JSON like `mb-test-run.sh`.

**DoD:**
- [x] `mb-lint-run.sh`, `no-TODO` scanner, `diff-scope` comparator, `goal-acceptance` aggregator each emit `{name, ok, findings[]}`.
- [x] Each runner exits 0 and reports pass/fail only via JSON (no fail-loud in the runner).
- [x] No build-runner is added (build resolves to `skip`).

<!-- mb-task:5 -->
### Task 5: Verifier fan-out — THE firewall (`mb-flow-verify.sh`)

**Covers:** REQ-DF-040, REQ-DF-041, REQ-DF-044, REQ-DF-060
**Role:** developer

Testing: bats — all-green → exit 0; one blocker → exit 1 naming the breach; a check script that itself errors → exit 2. This is the load-bearing test of the whole spec.

**DoD:**
- [x] `mb-flow-verify.sh` runs route-relevant checks, normalizes to `{blocker,major,minor}`, calls `mb-work-severity-gate.sh`.
- [x] The fan-out is the sole exit-code authority and propagates 0/1/2 as its own exit.
- [x] A red result triggers a repair-loop; the flow is never declared finished on red.

<!-- mb-task:6 -->
### Task 6: Closure wiring (Claude Code Stop-hook + git-hooks fallback)

**Covers:** REQ-DF-045, REQ-DF-062
**Role:** devops

Testing: bats/manual — a deliberately-red flow cannot be declared done on Claude Code; on a hookless agent the git pre-commit fallback catches it at commit-time.

**DoD:**
- [x] CC Stop-hook gates "finished" on the `mb-flow-verify.sh` exit code.
- [x] `git-hooks-fallback.sh` enforces closure at commit-time for hookless agents.
- [x] The no-commit false-done limitation on Pi is documented in `AGENTS.md`.

<!-- mb-task:7 -->
### Task 7: AGENTS.md Phase-1 contract

**Covers:** REQ-DF-050, REQ-DF-070
**Role:** developer

Testing: manual — the rendered AGENTS.md block references only scripts that exist after T2–T6; validates on Claude Code.

**DoD:**
- [x] `_lib_agents_md.sh` fenced block carries the goal+firewall loop rule ("do not finish until `mb-flow-verify.sh` exits 0; on red → repair, re-run").
- [x] The block documents only shipped scripts (no vapor).

## Phase 2 — Router + explicit pattern engine + full catalogue (CONFIRMED 2026-06-16; dependency-ordered sub-waves)

> Scope confirmed via discussion (2026-06-16): **Q1** auto-router default + `/mb flow <route>` override · **Q2** DF-owned
> explicit, stateless pattern engine (ADR-1′/ADR-9), NOT native-only delegation · **Q3** full five-route catalogue. Sub-waves run
> in order 2A→2E; each ships behind the proven Phase-1 firewall. Build only after explicit `go` (currently paused at Phase-1 milestone).

### Sub-wave 2A — Router (auto-classify + explicit override)

<!-- mb-task:8 -->
### Task 8: `analyze-task` router + deterministic route-floor + explicit `/mb flow` override

**Covers:** REQ-DF-020, REQ-DF-022, REQ-DF-023, REQ-DF-024, REQ-DF-025, REQ-DF-071
**Role:** developer

Testing: bats — diff under `domain/`/`*Protocol`/`protected_paths` → forced `arch`; `depends_on>0` → forced `arch`; trivial single-file change → `bugfix`/`code-change`; goal-change re-runs analyze-task; `/mb flow arch` override skips classification yet STILL writes `route: arch` + applies floor; an override BELOW the floor is raised to the floor (not honored blindly).

**DoD:**
- [x] `analyze-task` auto-classifies goal + `git diff` scope and writes one `route:` into the `mb-flow` fence (default path).
- [x] The path-glob + `depends_on` route-floor forces route ≥ `arch` independent of the LLM AND of any explicit override.
- [x] `/mb flow <route>` / `--route <route>` selects a route directly, skips classification, still applies floor + firewall.
- [x] A red diff-scope / unmet-acceptance halts and re-runs `analyze-task` rather than advancing.

### Sub-wave 2B — Pattern engine core (`mb-fanout.sh`)

<!-- mb-task:9 -->
### Task 9: `mb-fanout.sh` — stateless, agent-invoked fan-out helper

**Covers:** REQ-DF-081, REQ-DF-084, REQ-DF-085
**Role:** backend

Testing: bats — N branch prompts + a stub sub-invoke command run concurrently and each branch's JSON is collected; a failing/non-JSON branch → exit 2 + per-branch error marker (never silent drop); helper holds no cross-invocation state (no journal survives); bash-3.2 portable; a branch-count cap + `mb-work-budget.sh` pre-check rejects an over-budget fan-out (exit 2) BEFORE spawning.

**DoD:**
- [x] `mb-fanout.sh` takes N branch prompts + a per-agent sub-invoke command, runs them via background jobs + `wait`, collects per-branch JSON.
- [x] A failed/non-JSON branch → exit 2 + per-branch error marker; no branch silently dropped (REQ-DF-084).
- [x] No daemon, no durable journal, no persisted cross-invocation state; agent always initiates (REQ-DF-085); bash-3.2 clean.
- [x] Branch-count cap + budget pre-check (`mb-work-budget.sh`) fail-loud BEFORE spawning when N×cost exceeds budget.

### Sub-wave 2C — Six pattern templates

<!-- mb-task:10 -->
### Task 10: `flow-templates/patterns/*.md` — the six workflow patterns

**Covers:** REQ-DF-080, REQ-DF-083, REQ-DF-086
**Role:** developer

Testing: per-pattern manual + a lint test — each of the six templates declares {fan-out shape, per-branch skill, aggregation/judge step, termination rule} and routes its aggregated result through `mb-flow-verify.sh`; aggregation/judge steps reference only existing assets (`mb-reviewer*`/`judge`/reflexion/sadd), no new rubric dimensions; a CC template may note the native-Task optimization while keeping `mb-fanout` the portable default.

**DoD:**
- [ ] Six templates exist: `classify-and-act`, `fanout-synthesize`, `adversarial-verify`, `generate-filter`, `tournament`, `loop-until-done`.
- [ ] Each declares fan-out shape + per-branch skill + aggregation/judge + termination rule; composition documented (Tournament = fanout + pairwise-judge aggregation; Loop-Until-Done wraps a body until a stop predicate).
- [ ] Each pattern's aggregated result passes `mb-flow-verify.sh` before "done" (REQ-DF-086); no new LLM-judge rubric dimensions.

### Sub-wave 2D — Five route templates

<!-- mb-task:11 -->
### Task 11: `flow-templates/<route>.md` — full five-route catalogue

**Covers:** REQ-DF-012, REQ-DF-013, REQ-DF-021
**Role:** developer

Testing: per-route manual — `code-change` reproduces the current `work.md` loop verbatim; `bugfix` = reproduce→debug→patch→verify; `arch`/`migration`/`research` expand their phases; each route declares phases→skill→boundary-checks→retry→sequential-fallback AND names which pattern(s) it invokes; `arch` exists so the route-floor's forced target is real.

**DoD:**
- [ ] `code-change.md` reuses the `work.md` loop verbatim (one skill, no over-split, ADR-7).
- [ ] `bugfix.md`, `arch.md`, `migration.md`, `research.md` each list phases → skill → boundary-checks → retry → sequential-fallback and name the pattern(s) they use.
- [ ] `arch.md` is present (mandatory: route-floor can force `arch` — REQ-DF-022).

### Sub-wave 2E — Per-agent sub-invoke (Claude Code + Codex) + fence concurrency

<!-- mb-task:12 -->
### Task 12: Per-agent sub-invoke contract (CC + Codex) + parallel fence discipline

**Covers:** REQ-DF-082, REQ-DF-030, REQ-DF-051
**Role:** devops

Testing: bats — the adapter bakes a per-agent sub-invoke command (CC Task/background + `codex exec`); `mb-fanout.sh` discovers it; parallel branches each write `.mb-flow/branch-<i>.json` and the fence is written once, serially, by the initiating agent (never by a branch) — no race, content outside the fence byte-preserved.

**DoD:**
- [ ] The adapter declares a per-agent shell sub-invoke command for Claude Code + Codex (REQ-DF-082).
- [ ] `mb-fanout.sh` resolves the sub-invoke command for the active agent (baked env / resolver).
- [ ] Parallel branches write per-branch JSON sinks; the `mb-flow` fence is written once serially by the initiator; no concurrent-fence race (open-Q2).

## Phase 3 — Broaden sub-invoke + composable skills (deferred)

<!-- mb-task:13 -->
### Task 13: Broaden per-agent sub-invoke (Pi/OpenCode) + native-feature preference + sequential fallback

**Covers:** REQ-DF-052, REQ-DF-053, REQ-DF-083, REQ-DF-072
**Role:** devops

Testing: per-agent smoke — Pi/OpenCode sub-invoke commands fan out via `mb-fanout`; where a native parallel feature exists it MAY be preferred; where no sub-invoke is resolvable → sequential + stderr WARN (last resort, not the default).

**DoD:**
- [ ] `adapters/{pi,opencode}.sh` declare their sub-invoke command; `flow-templates/` + fence rules ship in the install payload.
- [ ] A host with a native feature MAY prefer it (REQ-DF-083); the explicit helper stays the portable default.
- [ ] No sub-invoke resolvable → sequential + WARN; no standalone dispatcher rebuilt (ADR-1′).

<!-- mb-task:14 -->
### Task 14: Composable skills — `critique` / `risk-find` / `final-report`

**Covers:** REQ-DF-010, REQ-DF-011
**Role:** developer

Testing: per-skill — `critique` (wraps reflexion/sadd), `risk-find`, `final-report` each produce their artifact without duplicating the role-agents or `mb-reviewer`.

**DoD:**
- [ ] `critique`/`risk-find`/`final-report` skills exist with a file-based I/O contract.
- [ ] None duplicates an existing role-agent or `mb-reviewer`; `critique` wraps the existing reflexion/sadd skills.

## Gate (whole spec)

Phase 1 ships when: `mb-flow-verify.sh` propagates 0/1/2 (tested), a red flow is blockable on Claude Code, `goal.md`/`project.md` exist with deterministic acceptance, and behaviour with no `goal.md` is byte-identical to today. **Phase 1 = DONE (2026-06-16).** Phase 2 (CONFIRMED scope above) ships sub-wave by sub-wave behind the firewall; each sub-wave: TDD → `mb-flow-verify.sh` green → governed review → judge. Phase 2/3 build starts only on explicit `go` (paused at the Phase-1 milestone).
