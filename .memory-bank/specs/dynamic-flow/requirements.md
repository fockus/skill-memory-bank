---
type: spec-requirements
topic: Dynamic Flow — agent-native adaptive orchestration over Memory Bank
status: draft
created: 2026-06-09
linked_design: design.md
linked_tasks: tasks.md
supersedes: [universal-orchestrator, goal-driven-autopilot]
---

# Requirements: dynamic-flow

> EARS patterns: **Ubiquitous** (`The <system> shall <response>`), **Event** (`When <trigger>, the <system> shall <response>`),
> **State** (`While <state>, the <system> shall <response>`), **Optional** (`Where <feature>, the <system> shall <response>`),
> **Unwanted** (`If <condition>, then the <system> shall <response>`). Validate with `mb-ears-validate.sh`.

## Context

Memory Bank today runs a **rigid** pipeline: `/mb plan → /mb work (implement→review→fix→verify) → /mb done`. The order is
hard-coded in `commands/work.md` + `references/pipeline.default.yaml:stage_pipeline` and is identical for every task. If the goal
changes mid-flight, or a task needs research/critique/parallel work, you must manually edit the plan file. The user wants a
**Dynamic Flow** layer on top: describe a GOAL (end-state + acceptance), let the agent pick the right workflow for the task,
adapt mid-flight, and finish ONLY when deterministic checks pass.

**Hard constraint — AGENT-NATIVE, not a standalone library.** Dynamic Flow ships as skills + instructions + workflow-templates +
check-scripts + memory-files that a **code-agent** (Claude Code, Codex, OpenCode, Pi/Mono) reads and executes with its OWN native
subagent/Task/workflow features. "Portable / universal" means **cross-agent**, NOT no-agent. We never own the dispatch loop; the
host agent is the runtime.

**Grounding (verified on disk, 2026-06-09).** Most of the substrate already exists and is **reused**: role-agents, `mb-reviewer`,
`plan-verifier`, the deterministic script fleet (`mb-test-run.sh`, `mb-rules-check.sh`, `mb-drift.sh` [14 checkers],
`mb-work-severity-gate.sh` [exit 0/1/2], `mb-traceability-gen.sh`), the live marker-fence pattern (`<!-- mb-active-plans -->`
etc.), `mb-roadmap-sync.sh`'s `depends_on` topo-sort, and the cross-agent install layer (`install.sh` + `adapters/*` +
`_lib_agents_md.sh` + `git-hooks-fallback.sh`). Net-new is concentrated in: a GOAL primitive, the Router skill + flow-templates,
a verifier fan-out + ~4 thin check scripts, the `mb-flow` fence writer, and 4 thin composable skills.

**Reference reality (sourced).** On Claude Code, dynamic-workflows (v2.1.154) / ultracode (v2.1.160) / `/goal` already exist
NATIVELY — Dynamic Flow does NOT re-implement them. The native `/goal` evaluator is an LLM (Haiku) that **does not call tools**
(it judges what the agent surfaced in conversation). Dynamic Flow's unique value is therefore (A) a **deterministic** completion
firewall the native `/goal` lacks, and (B) porting goal + flow + checks to agents that have no native orchestration (Codex/Pi).

This spec **supersedes** the unimplemented `universal-orchestrator` (its standalone Python runner / `HostAdapter.dispatch` /
durable journal are killed) and `goal-driven-autopilot` (its single `--autopilot` loop is replaced by a route-picking Router);
their pure/CLI primitives survive here.

## Functional Requirements (EARS)

### Goal primitive (L1)

- **REQ-DF-001** (Ubiquitous): The system shall define a `goal.md` artifact carrying an end-state description and a
  `## Acceptance criteria` list of `- [ ]` items that constitute the deterministic termination condition.
- **REQ-DF-002** (Ubiquitous): The system shall define a `project.md` artifact carrying slow-changing non-negotiable constraints
  read at flow start.
- **REQ-DF-003** (Ubiquitous): The system shall compute goal progress from a resolvable `progress_source`
  (checklist | plan-stages | spec-tasks | tests | req-trace | composite) at read-time, never storing a stale percentage.
- **REQ-DF-004** (Unwanted): If a goal declares `mode: adaptive` without a resolvable `progress_source` or without acceptance
  criteria, then the system shall refuse the run with exit 1 and a concrete fix-hint.
- **REQ-DF-005** (State): While a goal omits the adaptive fields (`mode`, `replan_with`, `linked_plans`), the system shall behave
  byte-identically to today's static Memory Bank flow.

### Composable skills (L2)

- **REQ-DF-010** (Ubiquitous): The system shall expose each pipeline stage as a small composable skill with a clean file-based
  I/O contract, reusing the existing `write-spec` (discuss+sdd), `review` (mb-reviewer), `verify` (plan-verifier), and
  `update-MB` (done/mb-manager) assets unchanged.
- **REQ-DF-011** (Ubiquitous): The system shall add four thin net-new skills — `analyze-task`, `critique` (wrapping existing
  reflexion/sadd skills), `risk-find`, and `final-report` — without duplicating the role-agents or `mb-reviewer`.
- **REQ-DF-012** (Ubiquitous): The system shall reuse the existing 9 role-agents + `mb-engineering-core.md` prepend for the
  `implement` skill, preserving the `prompt = core + role + body` composition.
- **REQ-DF-013** (State): While the chosen route is `code-change`, the system shall reuse the existing `commands/work.md`
  implement→review→fix→verify loop intact rather than decomposing it into separate skill hops.

### Dynamic Flow Router (L3)

- **REQ-DF-020** (Ubiquitous): The system shall provide an `analyze-task` skill that reads the goal and `git diff --name-only`
  scope and names exactly one route from a catalogue (`bugfix | code-change | arch | migration | research`).
- **REQ-DF-021** (Ubiquitous): The system shall express each route as a declarative `flow-templates/<route>.md` listing its
  phases, the L2 skill per phase, the L5 checks fired at each phase boundary, the retry rule, and a sequential fallback.
- **REQ-DF-022** (Unwanted): If the diff touches `domain/`, an `application/ports` path, a `*Protocol`/`ABC`/interface file, a
  declared `protected_path`, or a plan with `depends_on > 0`, then the `analyze-task` skill shall force the route to be at least
  `arch` (the deterministic route-floor), independent of the LLM's choice.
- **REQ-DF-023** (Event): When the user's goal changes mid-flight, the system shall rewrite the goal artifact and re-run
  `analyze-task` to rebuild the flow, without manual plan-file surgery.
- **REQ-DF-024** (Unwanted): If a phase-boundary check reports a red `diff-scope` breach or unmet acceptance, then the system
  shall halt, surface the breach, and re-run `analyze-task` rather than advancing.

### Flow-state runtime contract (L4)

- **REQ-DF-030** (Ubiquitous): The system shall persist the genuinely-new runtime fields (chosen `route`, `current_phase`, live
  check-results, `gate`, `last_verify_sha`, `stall_count`) in a `<!-- mb-flow -->…<!-- /mb-flow -->` marker-fenced block,
  regenerated idempotently with content outside the fence byte-preserved.
- **REQ-DF-031** (Ubiquitous): The system shall place the ephemeral `mb-flow` fence in `status.md` and keep `goal.md` durable-only
  (end-state + acceptance + constraints), so the acceptance aggregator greps `goal.md` without fence noise.
- **REQ-DF-032** (Unwanted): If a new standalone `flow-state.json` would duplicate an existing SSOT (checklist/roadmap/status/
  plan/goal) or introduce a fourth status vocabulary, then the system shall NOT author it as primary state; any JSON view shall
  be derived read-only from those files.

### Deterministic verifier / firewall (L5)

- **REQ-DF-040** (Ubiquitous): The system shall provide `mb-flow-verify.sh`, a fan-out that runs the route-relevant checks,
  normalizes each into `{blocker, major, minor}` counts, and calls the existing `mb-work-severity-gate.sh` comparator (the SSOT).
- **REQ-DF-041** (Ubiquitous): The `mb-flow-verify.sh` fan-out shall be the sole exit-code authority, propagating
  `0` (pass) / `1` (fail, naming the breach) / `2` (a check script itself broke); individual check runners remain exit-0 + JSON.
- **REQ-DF-042** (Ubiquitous): The system shall reuse existing checks (`git diff --name-only`, `mb-test-run.sh`,
  `mb-rules-check.sh`, `mb-drift.sh`, `mb-traceability-gen.sh`, `mb-work-protected-check.sh`, `mb-work-budget.sh`) and add only
  thin runners — `lint-run`, `no-TODO`, `diff-scope`, and a `goal-acceptance` aggregator (`[x]/N` in `goal.md`).
- **REQ-DF-043** (Ubiquitous): The system shall NOT ship a build-runner in v1 (no local build for this project's EAS/Kamal
  toolchain); `build` resolves to `skip` until a route demonstrably needs a runnable local build.
- **REQ-DF-044** (Unwanted): If `mb-flow-verify.sh` returns non-zero, then the system shall enter a repair-loop and shall NOT
  declare the flow finished.
- **REQ-DF-045** (Event): When the host provides a Stop-hook (Claude Code / Cursor / Cline / Windsurf / OpenCode), the system
  shall gate "finished" on the `mb-flow-verify.sh` exit code so a red verify physically blocks completion.

### Cross-agent adapters (L6)

- **REQ-DF-050** (Ubiquitous): The system shall ship a lowest-common-denominator contract of `AGENTS.md` (refcount-fenced via the
  existing `_lib_agents_md.sh`) + a `skills/` dir of `SKILL.md` + `scripts/` + `flow-templates/`, executable by every target agent.
- **REQ-DF-051** (Optional): Where the host has a native parallel-subagent feature (Claude Code Task / OpenCode subagents), the
  system shall fan out tracks through that feature; the system shall never rebuild a standalone dispatcher.
- **REQ-DF-052** (Unwanted): If the host has no parallel dispatch (Codex / Pi), then the system shall execute the same template
  phases sequentially and emit a stderr WARN, preserving correctness.
- **REQ-DF-053** (Ubiquitous): The system shall extend the existing `adapters/*` install layer only by adding `flow-templates/`
  to the copied payload and the `mb-flow` fence rules to the `AGENTS.md` block.

### Fail-loud & reuse constraints

- **REQ-DF-060** (Ubiquitous): The system shall never let the LLM self-certify completion; the deterministic firewall exit code,
  not the model's assessment, gates "done".
- **REQ-DF-061** (Ubiquitous): The system shall be implemented as agent-consumable skills/scripts/templates only, with no
  standalone runtime process and no JavaScript/TypeScript runtime dependency on the critical path.
- **REQ-DF-062** (State): While a hookless agent (Pi) runs a flow, the system shall enforce closure at commit-time via
  `git-hooks-fallback.sh` and shall document that a no-commit false-done is detectable only after the fact.

### Phasing

- **REQ-DF-070** (Ubiquitous): The system shall ship Phase 1 (goal primitive + `mb-flow-verify.sh` firewall + Stop-hook wiring)
  as an independently valuable increment that strengthens the existing `work.md` loop on Claude Code.
- **REQ-DF-071** (Ubiquitous): The system shall ship Phase 2 (`analyze-task` + route-floor + `code-change`/`bugfix` templates)
  only after Phase 1's firewall is real, so route choice is self-correcting by red exits.
- **REQ-DF-072** (Ubiquitous): The system shall ship Phase 3 (Codex/OpenCode/Pi adapters + remaining templates + parallel
  dispatch + critique/risk-find/final-report skills) last, building on the existing adapter layer.

## Constraints

- No new third-party runtime dependency on the critical path; determinism lives in POSIX shell / Python check scripts.
- The base behaviour with no `goal.md` and no `mode: adaptive` must remain byte-identical (additive migration).
- All net-new check runners stay exit-0 + JSON; fail-loud exit codes exist only in the fan-out and the severity-gate comparator.
- Scope excludes a durable-execution journal, a standalone dispatcher, and new LLM-judge rubric dimensions.
