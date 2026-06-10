# Agents reference

The skill ships **29 agent definitions** in `agents/`: 27 dispatchable subagents plus 2 shared
"core" preambles that are prepended to other agents and never dispatched directly. Your host
agent (Claude Code, OpenCode, …) picks them up automatically after `memory-bank install`.

All agents follow an evidence-before-claims discipline: no "tests pass" without the actual test
output, no "done" without verification.

## Dev-role agents (used by `/mb work`)

`/mb work` matches the stage description against a role and dispatches the matching specialist.
Every dev-role agent receives the `mb-engineering-core` discipline preamble (TDD, Clean
Architecture/FSD, SOLID, no placeholders) and the `mb-tooling-core` routing preamble
(graph-first code navigation).

| Agent | Specialty | When it's picked |
|-------|-----------|------------------|
| `mb-developer` | Generic implementer | Default when no specialist matches |
| `mb-backend` | APIs, services, DB, async/concurrency | Backend-shaped stages |
| `mb-frontend` | React/Vue/Svelte/Solid, a11y, responsive UI | Frontend-shaped stages |
| `mb-ios` | SwiftUI/UIKit, Combine, async/await | iOS stages |
| `mb-android` | Jetpack Compose, coroutines, Hilt, Room | Android stages |
| `mb-devops` | CI/CD, Docker, K8s, Terraform, observability | Infra stages |
| `mb-qa` | Test design, coverage strategy, edge cases | Test-focused stages |
| `mb-analyst` | SQL, dashboards, ETL, A/B analysis | Data/metrics stages (no production code) |
| `mb-architect` | Domain modelling, ADRs, refactoring strategy | Design stages (doesn't ship features alone) |

## Verification & quality gates

| Agent | Role | Invoked by |
|-------|------|------------|
| `plan-verifier` | Audits the diff against the plan's DoD, item by item | `/mb verify` (required before `/mb done` for plan work) |
| `mb-test-runner` | Runs tests, parses output into strict JSON; never reports "not-run" as pass | `/test`, plan-verifier |
| `mb-rules-enforcer` | Deterministic SRP / Clean Architecture / TDD-delta checks on changed files | `/review`, `/commit`, `/pr`, plan-verifier |
| `mb-judge` | Independent final gate: GO / GO_WITH_BACKLOG / NO_GO | `/mb work --judge` and governed workflows |

## Review ensemble (opt-in via `--review` or governed workflows)

| Agent | Focus |
|-------|-------|
| `mb-reviewer` | Single-reviewer mode: structured verdict (APPROVED / CHANGES_REQUESTED) with severity-classified issues |
| `mb-reviewer-logic` | Requirement coverage, behavior, edge cases, regressions |
| `mb-reviewer-quality` | Maintainability, SOLID/DRY/KISS/YAGNI, architecture boundaries |
| `mb-reviewer-security` | Secrets, injection, authz/authn, filesystem/network risks |
| `mb-reviewer-tests` | TDD evidence, regression coverage, test determinism |
| `mb-reviewer-scalability` | Complexity, hot paths, memory, concurrency, IO |
| `mb-reviewer-lead` | Synthesizes the aspect reports into one canonical review |

## Memory & knowledge agents

| Agent | Role | Invoked by |
|-------|------|------------|
| `mb-manager` | Maintains `.memory-bank/` core files (actualize, search, notes, tasks) | `/mb context\|search\|note\|tasks\|update\|done`, PreCompact hook |
| `mb-doctor` | Finds & fixes inconsistencies across core files | `/mb doctor` |
| `mb-codebase-mapper` | Writes `codebase/*.md` docs (stack/arch/quality/concerns) | `/mb map` |
| `mb-wiki-author` | Writes one wiki article per code community (Haiku-tier) | `/mb wiki` |
| `mb-wiki-synthesizer` | Finds surprising cross-community connections (Sonnet-tier) | `/mb wiki` |

## Research agents (never author plans or code)

| Agent | Role |
|-------|------|
| `mb-research` | Codebase + web research router: graph for structure, semantic search for concepts, `/mb recall` for decisions, web for the rest |
| `mb-researcher` | Ecosystem research, option matrices, technical due diligence before planning |

## Shared cores (not dispatchable)

| File | Purpose |
|------|---------|
| `mb-engineering-core` | Engineering-discipline preamble prepended to every dev-role agent |
| `mb-tooling-core` | Graph-first code-navigation routing prepended to every dev-role agent |

## See also

- [Composable `/mb work` pipeline](../commands/work.md) — how stages map to agents
- [SKILL.md § Agents](../SKILL.md) — the agent-facing roster table
