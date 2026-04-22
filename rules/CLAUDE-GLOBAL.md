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
If it does not exist, initialize it and print `[MEMORY BANK: INITIALIZED]`.

**Skill:** `memory-bank`. **Command:** `/mb`. **Path:** `./.memory-bank/`.

### Session Pipeline (one-liner)

```
/mb start  →  /mb plan <type> <topic>  →  [work]  →  /mb verify  →  /mb done
```

**`/mb verify` is MANDATORY before `/mb done` when work followed a plan.**

### `/mb` commands (quick reference)


| Command                                     | Purpose                                                            |
| ------------------------------------------- | ------------------------------------------------------------------ |
| `/mb start` / `/mb context [--deep]`        | Restore context (core files + codebase summary)                    |
| `/mb plan <feature\|fix\|refactor\|experiment> <topic>` | Create plan with SMART DoD per stage + TDD                         |
| `/mb verify`                                | Verify code vs plan (plan-verifier subagent). **Required** before `/mb done` |
| `/mb done`                                  | End session — actualize + note + progress                          |
| `/mb update`                                | Intermediate actualize (no note) — before compaction               |
| `/mb map [stack\|arch\|quality\|concerns\|all]` | Generate/refresh `.memory-bank/codebase/*.md`                      |
| `/mb graph [--apply]`                       | Build code graph (JSON Lines, grep/jq-friendly)                    |
| `/mb idea "<title>" [HIGH\|MED\|LOW]` / `/mb adr "<title>"` | Capture idea (I-NNN) / ADR (ADR-NNN) into `backlog.md`             |
| `/mb search <query>` / `/mb tasks` / `/mb index` / `/mb doctor` | Search / unfinished tasks / entries registry / consistency check   |
| `/mb init`                                  | Initialize Memory Bank in a new project                            |


### Key invariants

- `progress.md` = **append-only** (never delete or rewrite old entries)
- Numbering is monotonic: I-NNN, EXP-NNN, ADR-NNN (never reuse IDs)
- `checklist.md`: ✅ = done, ⬜ = todo. Update **immediately** when a task finishes
- `notes/` = knowledge and patterns (5-15 lines), **not chronology**

### Codebase Map & Code Graph (one-liner)

`.memory-bank/codebase/` contains living project map:
- **4 MD docs** (`STACK.md` / `ARCHITECTURE.md` / `CONVENTIONS.md` / `CONCERNS.md`) — generated by `mb-codebase-mapper` subagent (`/mb map`), auto-loaded by `/mb context`
- **`graph.json`** (JSON Lines) + **`god-nodes.md`** (top-20 by degree) — generated by `/mb graph --apply`
- Prefer the graph over `grep -rn` for structural questions ("who calls X?", "what imports Y?"). Example: `jq -c 'select(.type=="edge" and .dst=="WriteFile")' .memory-bank/codebase/graph.json`

### When to read the detailed rules

**Before** invoking these commands/workflows, **read the matching section of `~/.claude/RULES.md`**:

- `/mb plan` → `§ Session Pipeline` + `§ Planning chain (Source of Truth)`
- `/mb verify` → `§ Session Pipeline § Verification`
- `/mb done` → `§ Session Pipeline § Session end`
- `/mb graph` / `/mb map` / jq queries → `§ Code Graph — usage`
- Test writing → `§ Tests — Testing Trophy`
- Architecture decisions (ADR) → `§ Architecture` + `§ Coding Standards`

Project-specific overrides live in `<project-root>/RULES.md` (or `.memory-bank/RULES.md`). Read it **in addition to** the global one, not instead of.