# Agents reference

Full roster of the bundled subagents. Dispatch rules (by name, per host) stay in `SKILL.md` § Invocation.

## Agents — subagents

| Agent | When to invoke | Prompt |
|-------|----------------|--------|
| `mb-manager` | `/mb context`, `search`, `note`, `tasks`, `done`, `update`, PreCompact hook | `agents/mb-manager.md` |
| `mb-doctor` | `/mb doctor` — memory-bank inconsistencies (use `mb-plan-sync.sh` first, only edit for semantic drift) | `agents/mb-doctor.md` |
| `mb-codebase-mapper` | `/mb map [focus]` — scan the codebase → `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md` | `agents/mb-codebase-mapper.md` |
| `plan-verifier` | `/mb verify` — required before `/mb done` when work followed a plan. Uses `**Baseline commit:**` from plan header for `git diff`, runs `mb-test-run.sh` and `mb-rules-check.sh` directly | `agents/plan-verifier.md` |
| `mb-rules-enforcer` | `/review`, `/commit`, `/pr`, `plan-verifier` step 3.6 — runs `mb-rules-check.sh` (solid/srp, clean_arch/direction, tdd/delta) + LLM ISP/DRY judgment. Returns strict JSON + summary | `agents/mb-rules-enforcer.md` |
| `mb-test-runner` | `/test`, `plan-verifier` step 3.5 — runs `mb-test-run.sh`, correlates failures with session diff. Returns JSON `{stack, tests_pass, tests_total, failures[], coverage, duration_ms}` | `agents/mb-test-runner.md` |
| `mb-reviewer` | `/mb work` legacy single-reviewer fallback — reads stage diff + `pipeline.yaml:review_rubric`, emits structured JSON verdict | `agents/mb-reviewer.md` |
| `mb-reviewer-logic` | `/mb work` governed review ensemble — correctness / logic aspect reviewer with scoped context | `agents/mb-reviewer-logic.md` |
| `mb-reviewer-tests` | `/mb work` governed review ensemble — test-coverage / quality-of-tests aspect reviewer | `agents/mb-reviewer-tests.md` |
| `mb-reviewer-quality` | `/mb work` governed review ensemble — code-quality / maintainability aspect reviewer | `agents/mb-reviewer-quality.md` |
| `mb-reviewer-security` | `/mb work` governed review ensemble — security aspect reviewer | `agents/mb-reviewer-security.md` |
| `mb-reviewer-scalability` | `/mb work` governed review ensemble — performance / scalability aspect reviewer | `agents/mb-reviewer-scalability.md` |
| `mb-reviewer-lead` | `/mb work` governed review — synthesizes aspect reports, verifies previous master report closure, separates blockers from backlog | `agents/mb-reviewer-lead.md` |
| `mb-judge` | `/mb work` governed final gate — decides GO / GO_WITH_BACKLOG / NO_GO from plan, verifier, lead-review, and evidence | `agents/mb-judge.md` |
| `mb-engineering-core` | **[partial — not dispatched directly]** Composed into every dev-role agent below at install time (`compose:` frontmatter). Carries the shared discipline: TDD, Contract-First, Clean Architecture, production-wiring, evidence-before-claims with proportional verification, escalation, STATUS contract — in a calm tone with reasons. Excluded from the `~/.claude/agents/` registry via `partial: true` frontmatter. | `agents/mb-engineering-core.md` |
| `mb-tooling-core` | **[partial — not dispatched directly]** Composed at install time into the dev-role agents, `mb-reviewer`, and `plan-verifier`. Carries the graph-first, fail-open code-understanding routing (`code_context` / `graph_neighbors` / `graph_impact` / `graph_tests` / `search_code` / `recall`). Optional indexes degrade to `Grep`/`Read`. Excluded from the registry via `partial: true`. | `agents/mb-tooling-core.md` |
| `mb-discipline-strict` | **[partial — not dispatched directly]** Strict addendum to `mb-engineering-core` (Iron Law, NEVER rules, rationalization table). `/mb work` appends it to the dispatch prompt when the item's `discipline` is `strict` (model in `pipeline.yaml` `discipline.strict_models`). Excluded from the registry via `partial: true`. | `agents/mb-discipline-strict.md` |
| `mb-developer` | `/mb work` — generic implementer when no specialist role matches. Discipline from `mb-engineering-core` + DoD-driven implementation | `agents/mb-developer.md` |
| `mb-architect` | `/mb work` — architecture / ADR / system-design specialist. Domain modelling, interface definition, refactoring strategy | `agents/mb-architect.md` |
| `mb-backend` | `/mb work` — APIs, services, database, async/concurrency, server-side business logic | `agents/mb-backend.md` |
| `mb-frontend` | `/mb work` — React/Vue/Svelte/Solid components, browser UI, accessibility, responsive layouts | `agents/mb-frontend.md` |
| `mb-ios` | `/mb work` — SwiftUI/UIKit, Combine, async/await, Apple platform conventions | `agents/mb-ios.md` |
| `mb-android` | `/mb work` — Jetpack Compose, Kotlin coroutines, Hilt/DI, Room, Material3 | `agents/mb-android.md` |
| `mb-devops` | `/mb work` — CI/CD, Docker, Kubernetes, Terraform, observability, release engineering | `agents/mb-devops.md` |
| `mb-qa` | `/mb work` — test design, coverage strategy, edge-case enumeration, flake elimination, contract tests | `agents/mb-qa.md` |
| `mb-debugger` | `/mb work` / bugfix — systematic debugging (adapted from superpowers, MIT): root cause before fix, four phases, failing test → single fix → verification; tools in `references/debugging/` + `scripts/mb-find-polluter.sh` | `agents/mb-debugger.md` |
| `mb-analyst` | `/mb work` — data / analytics / metrics: SQL, dashboards, cohorts, ETL pipelines, instrumentation | `agents/mb-analyst.md` |
| `mb-research` | `/mb research` (and broad `/mb work` research steps) — graph-first, multi-source research over codebase + project memory + library docs + GitHub prior-art + open web; read-only (no Write/Edit), returns `file:line` / source-grounded conclusions, degrades to `Grep` when indexes are absent | `agents/mb-research.md` |
| `mb-researcher` | `/mb work` governed research role (wired in `pipeline.default.yaml`) — ecosystem research, implementation reconnaissance, source comparisons, technical due diligence, and evidence-backed option matrices before planning or implementation | `agents/mb-researcher.md` |
| `mb-wiki-author` | `/mb wiki` — bulk worker pinned to a small model (`model: haiku`). Writes one codebase-wiki article per community from a deterministic evidence pack | `agents/mb-wiki-author.md` |
| `mb-wiki-synthesizer` | `/mb wiki` — finds surprising cross-community connections, emits strict-JSON `semantic` edges | `agents/mb-wiki-synthesizer.md` |

> **Composition.** An agent lists the partials it needs under `compose:` in its frontmatter; the
> installer (`scripts/mb-agent-render.py`) places those partials above the agent's own text, so the
> installed agent carries the shared discipline and a dispatch by name needs only the task data.
> Reading a role file from the skill directory directly (clients without named dispatch) means reading
> its `compose:` partials first.
