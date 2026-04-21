# CRITICAL RULES — DO NOT FORGET DURING COMPACTION

> **Contract-First** — Protocol/ABC → contract tests → implementation. Tests must pass for ANY correct implementation.
> **TDD** — tests first, then code. Allowed skips: typos, formatting, exploratory prototypes.
> **Clean Architecture (backend)** — `Infrastructure → Application → Domain` (never the other way around). Domain = 0 external dependencies.
> **FSD (frontend)** — Feature-Sliced Design for React/Vue/Angular. Layers top-down: `app → pages → widgets → features → entities → shared`. Imports only downward; cross-slice communication inside the same layer must go through widget/page; every slice exposes public API through `index.ts`.
> **Mobile (iOS/Android)** — UDF + Clean layers: `View → ViewModel → UseCase → Repository (SSOT) → DataSource`. iOS: SwiftUI + `@Observable`, `async/await`, SwiftData, SPM feature modules. Android: Jetpack Compose + StateFlow + Hilt + Room, Gradle multi-module, Google Recommended Architecture. Immutable UI state, DI through protocols/interfaces.
> **SOLID thresholds** — SRP: >300 lines or >3 public methods of different nature = split candidate. ISP: interface ≤5 methods. DIP: constructor takes abstractions.
> **DRY / KISS / YAGNI** — duplicate >2 times → extract. Three identical lines are better than premature abstraction. Do not write code "for the future."
> **Testing Trophy** — integration > unit > e2e. Mock only external services. >5 mocks = candidate for an integration test.
> **Test quality** — naming: `test_<what>_<condition>_<result>`. Assert business facts. Arrange-Act-Assert. Prefer `@parametrize` over copy-paste.
> **Coverage** — overall 85%+, core/business 95%+, infrastructure 70%+.
> **Fail Fast** — if uncertain, stop and propose a 3-5 line plan.
> **Language** — respond in English; technical terms may remain in English.
> **No placeholders** — no TODO, `...`, or pseudocode. Code must be copy-paste ready. Exception: staged stubs behind a feature flag with a docstring.
> **Plans** — every stage must have detailed DoD (SMART), TDD requirements, verification scenarios, and edge cases.
> **Protected files** — do not touch `.env`, `ci/`**, Docker/K8s/Terraform without explicit request.
> **Detailed rules:** `~/.claude/RULES.md` + project-root `RULES.md`.

---

# Global Rules

## Coding

- No new libraries/frameworks without explicit request
- New business logic → tests FIRST, then implementation
- Full imports, valid syntax, complete functions — copy-paste ready
- Multi-file changes → plan first
- Specification by Example: requirements should be expressed as concrete input/output examples
- Refactor through the Strangler Fig pattern: incremental replacement, tests passing at every step
- Significant decisions → ADR (context → decision → alternatives → consequences)
- Every task you write must include completion criteria (SMART DoD) that you actually verify

## Testing — Testing Trophy

- **Coverage:** 85%+ overall (core 95%+, infrastructure 70%+)
- **Integration tests (primary focus):** real components together, mock only external boundaries
- **Unit tests (secondary):** pure logic and edge cases. 5+ mocks = candidate for integration test
- **E2E (targeted):** only critical user flows
- **Static analysis:** lint, type checking, and stack-specific checks should always run

## Reasoning

- Complex tasks: analysis → plan → implementation → verification
- Before editing: search the project, do not guess
- Response format: Goal → Action → Result
- Destructive actions — only after explicit confirmation
- Do not expand scope without request

## Planning

When creating plans (including built-in plan mode):

- Write plans to `./.memory-bank/plans/` if Memory Bank is active
- Every stage must have SMART DoD criteria
- Every stage must include test requirements BEFORE implementation (TDD)
- Tests: unit + integration + e2e where applicable
- Stages must be atomic and dependency-ordered

## Memory Bank

**If `./.memory-bank/` exists → `[MEMORY BANK: ACTIVE]`.**
If it does not exist, initialize it with the internal structure and print `[MEMORY BANK: INITIALIZED]`.

**Skill:** `memory-bank`. **Command:** `/mb`. **Subagent:** MB Manager (sonnet).
**Global rules:** `~/.claude/RULES.md` (TDD, SOLID, DRY, KISS, YAGNI, Clean Architecture, Testing Trophy, Memory Bank workflow — for ALL projects)
**Project-specific rules:** project-root `RULES.md`
**Templates:** `~/.claude/skills/memory-bank/references/templates.md`
**Workflow:** `~/.claude/skills/memory-bank/references/workflow.md`

### `/mb` commands


| Command                   | Description                                                                  |
| ------------------------- | ---------------------------------------------------------------------------- |
| `/mb` or `/mb context`    | Collect project context (status, checklist, plan)                            |
| `/mb start`               | Extended session start (context + full active plan)                          |
| `/mb search <query>`      | Search the memory bank by keywords                                           |
| `/mb note <topic>`        | Create a note for a topic                                                    |
| `/mb update`              | Actualize core files (`checklist`, `plan`, `status`)                         |
| `/mb tasks`               | Show unfinished tasks                                                        |
| `/mb index`               | Registry of all entries (core files + notes/plans/experiments/reports)       |
| `/mb done`                | Finish the session (actualize + note + progress)                             |
| `/mb plan <type> <topic>` | Create a plan (`feature`, `fix`, `refactor`, `experiment`)                   |
| `/mb verify`              | Verify plan vs code. **REQUIRED** before `/mb done` when working from a plan |
| `/mb init`                | Initialize Memory Bank in a new project                                      |


### Key rules

- `progress.md` = **append-only** (never delete or rewrite old entries)
- Numbering is monotonic: H-NNN, EXP-NNN, ADR-NNN (never reuse IDs)
- `notes/` = knowledge and patterns (5-15 lines), **not chronology**. Do not create notes for trivial changes
- `reports/` = detailed reports useful to future sessions (analysis, post-mortems, comparisons)
- `checklist`: ✅ = done, ⬜ = todo. Update **immediately** when a task finishes

**Path:** `./.memory-bank/`

### Structure

**Core files (read every session):**


| File           | Purpose                                    | When to update                                    |
| -------------- | ------------------------------------------ | ------------------------------------------------- |
| `STATUS.md`    | Current state, roadmap, key metrics, gates | Stage complete, roadmap moved, metrics changed    |
| `checklist.md` | Current tasks ✅/⬜                          | Every session, immediately when a task completes  |
| `plan.md`      | Priorities and direction                   | When focus/priorities change                      |
| `RESEARCH.md`  | Hypotheses + findings + current experiment | Hypothesis status changed or new finding appeared |


**Detailed records (read on demand):**


| File / Folder  | Purpose                                     | When to update                                 |
| -------------- | ------------------------------------------- | ---------------------------------------------- |
| `BACKLOG.md`   | Ideas, ADRs, rejected items                 | New idea or architectural decision appears     |
| `progress.md`  | Completed work by date                      | End of session (append-only)                   |
| `lessons.md`   | Repeated mistakes and anti-patterns         | When a pattern is noticed                      |
| `experiments/` | `EXP-NNN_<n>.md` — ML experiments           | When an experiment finishes                    |
| `plans/`       | `YYYY-MM-DD_<type>_<n>.md` — detailed plans | Before complex work                            |
| `reports/`     | `YYYY-MM-DD_<type>_<n>.md` — reports        | When useful to future sessions                 |
| `notes/`       | `YYYY-MM-DD_HH-MM_<topic>.md` — notes       | On task completion (knowledge, not chronology) |


### Workflow (short)

**Start:** `/mb start` → read the 4 core files (`STATUS`, `checklist`, `plan`, `RESEARCH`) → summarize focus.
**During work:** update `checklist.md` immediately (⬜→✅). Update `STATUS.md` for milestones/metrics. Update `RESEARCH.md` when hypotheses change.
**Finish:** `/mb verify` (if working from a plan) → `/mb done` (`checklist` + `progress` + note + `STATUS`/`RESEARCH` if needed).
**Before compaction:** run `/mb update` so progress is not lost.