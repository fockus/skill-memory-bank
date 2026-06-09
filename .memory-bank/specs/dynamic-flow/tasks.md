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
- [ ] `goal.md` template (end-state + `## Acceptance criteria` `- [ ]`) and `project.md` template exist (shapes lifted from superseded goal-driven-autopilot).
- [ ] `commands/goal.md` thin scaffolder creates them.
- [ ] A goal with no adaptive fields reproduces today's static behaviour byte-identically.

<!-- mb-task:3 -->
### Task 3: `mb-flow` fence writer (status.md)

**Covers:** REQ-DF-030, REQ-DF-031, REQ-DF-032
**Role:** developer

Testing: bats — first write creates the fence; rewrite is idempotent; content outside the fence is byte-preserved; `goal.md` is never written to.

**DoD:**
- [ ] `mb-flow-sync.sh` regenerates the `<!-- mb-flow -->` block in `status.md` idempotently.
- [ ] `goal.md` stays durable-only (no live check-results).
- [ ] No standalone `flow-state.json` authored as primary state.

<!-- mb-task:4 -->
### Task 4: Thin check runners (lint / no-TODO / diff-scope / acceptance)

**Covers:** REQ-DF-042, REQ-DF-043
**Role:** developer

Testing: pytest/bats per runner — pass case, fail case, and `null`/skip case; all stay exit-0 + JSON like `mb-test-run.sh`.

**DoD:**
- [ ] `mb-lint-run.sh`, `no-TODO` scanner, `diff-scope` comparator, `goal-acceptance` aggregator each emit `{name, ok, findings[]}`.
- [ ] Each runner exits 0 and reports pass/fail only via JSON (no fail-loud in the runner).
- [ ] No build-runner is added (build resolves to `skip`).

<!-- mb-task:5 -->
### Task 5: Verifier fan-out — THE firewall (`mb-flow-verify.sh`)

**Covers:** REQ-DF-040, REQ-DF-041, REQ-DF-044, REQ-DF-060
**Role:** developer

Testing: bats — all-green → exit 0; one blocker → exit 1 naming the breach; a check script that itself errors → exit 2. This is the load-bearing test of the whole spec.

**DoD:**
- [ ] `mb-flow-verify.sh` runs route-relevant checks, normalizes to `{blocker,major,minor}`, calls `mb-work-severity-gate.sh`.
- [ ] The fan-out is the sole exit-code authority and propagates 0/1/2 as its own exit.
- [ ] A red result triggers a repair-loop; the flow is never declared finished on red.

<!-- mb-task:6 -->
### Task 6: Closure wiring (Claude Code Stop-hook + git-hooks fallback)

**Covers:** REQ-DF-045, REQ-DF-062
**Role:** devops

Testing: bats/manual — a deliberately-red flow cannot be declared done on Claude Code; on a hookless agent the git pre-commit fallback catches it at commit-time.

**DoD:**
- [ ] CC Stop-hook gates "finished" on the `mb-flow-verify.sh` exit code.
- [ ] `git-hooks-fallback.sh` enforces closure at commit-time for hookless agents.
- [ ] The no-commit false-done limitation on Pi is documented in `AGENTS.md`.

<!-- mb-task:7 -->
### Task 7: AGENTS.md Phase-1 contract

**Covers:** REQ-DF-050, REQ-DF-070
**Role:** developer

Testing: manual — the rendered AGENTS.md block references only scripts that exist after T2–T6; validates on Claude Code.

**DoD:**
- [ ] `_lib_agents_md.sh` fenced block carries the goal+firewall loop rule ("do not finish until `mb-flow-verify.sh` exits 0; on red → repair, re-run").
- [ ] The block documents only shipped scripts (no vapor).

## Phase 2 — Mini-router (deferred; after Phase 1 firewall is proven)

<!-- mb-task:8 -->
### Task 8: `analyze-task` skill + deterministic route-floor

**Covers:** REQ-DF-020, REQ-DF-022, REQ-DF-023, REQ-DF-024, REQ-DF-071
**Role:** developer

Testing: bats — diff under `domain/`/`*Protocol`/`protected_paths` → forced `arch`; `depends_on>0` → forced `arch`; trivial single-file change → `bugfix`/`code-change`; goal-change re-runs analyze-task.

**DoD:**
- [ ] `analyze-task` classifies the goal and names one route, writing `route:` into the fence.
- [ ] The path-glob + `depends_on` route-floor forces route ≥ arch independent of the LLM.
- [ ] A red diff-scope / unmet-acceptance halts and re-runs analyze-task.

<!-- mb-task:9 -->
### Task 9: Two flow-templates (code-change, bugfix)

**Covers:** REQ-DF-012, REQ-DF-013, REQ-DF-021
**Role:** developer

Testing: manual — `code-change` reproduces the current `work.md` loop; `bugfix` runs reproduce→debug→patch→verify; each declares its boundary-checks and sequential fallback.

**DoD:**
- [ ] `flow-templates/code-change.md` reuses the `work.md` loop verbatim (one skill, no over-split).
- [ ] `flow-templates/bugfix.md` lists phases → skill → boundary-checks → retry → sequential-fallback.

## Phase 3 — Cross-agent + full catalogue (deferred; on confirmed multi-agent use)

<!-- mb-task:10 -->
### Task 10: Cross-agent adapters

**Covers:** REQ-DF-051, REQ-DF-052, REQ-DF-053, REQ-DF-072
**Role:** devops

Testing: per-agent smoke — flow-templates + fence rules install on Codex/OpenCode/Pi; no-parallel hosts run sequentially and emit a stderr WARN.

**DoD:**
- [ ] `adapters/{codex,opencode,pi}.sh` ship `flow-templates/` + the fence rules.
- [ ] Hosts without parallel dispatch degrade to sequential + WARN (no standalone dispatcher rebuilt).

<!-- mb-task:11 -->
### Task 11: Remaining templates + composable skills

**Covers:** REQ-DF-010, REQ-DF-011
**Role:** developer

Testing: per-skill — `critique`/`risk-find`/`final-report` produce their artifacts; arch/migration/research templates expand; parallel dispatch uses host-native subagents.

**DoD:**
- [ ] `arch.md` / `migration.md` / `research.md` templates exist.
- [ ] `critique` (wraps reflexion/sadd), `risk-find`, `final-report` skills exist without duplicating role-agents.
- [ ] Parallel dispatch uses host-native subagents; collision-DAG ships only as an optional CLI.

## Gate (whole spec)

Phase 1 ships when: `mb-flow-verify.sh` propagates 0/1/2 (tested), a red flow is blockable on Claude Code, `goal.md`/`project.md` exist with deterministic acceptance, and behaviour with no `goal.md` is byte-identical to today. Phases 2–3 are not started without explicit scope reconfirmation.
