# CLAUDE.md Template

Template used by `/mb init --full` to generate `CLAUDE.md`.
Variables in `{VARIABLE}` are filled through auto-detection.

---

## Project

**{PROJECT_NAME}**

{PROJECT_DESCRIPTION}

### Constraints

- **Tech stack**: {LANGUAGE} {LANGUAGE_VERSION}+, {KEY_DEPS}
- **Testing**: 85%+ overall, 95%+ core/business coverage. TDD mandatory.
- **Architecture**: SOLID, KISS, DRY, YAGNI, Clean Architecture

## Technology Stack

## Languages

- {LANGUAGE} {LANGUAGE_VERSION}+ — all application source code in `{SRC_DIR}/`

## Runtime

- {RUNTIME_INFO}
- {PACKAGE_MANAGER} — primary manager

## Frameworks

- {FRAMEWORKS}

## Key Dependencies

{KEY_DEPENDENCIES}

## Configuration

{CONFIG_FILES}

## Conventions

## Naming Patterns

{NAMING_CONVENTIONS}

## Code Style

- Tool: `{LINTER}` (`{LINTER}>={LINTER_VERSION}`)
- Line length: {LINE_LENGTH} characters
- Target: {LANGUAGE} {LANGUAGE_VERSION} syntax

## Architecture

## Pattern Overview

- All cross-layer dependencies point inward: Infrastructure → Application → Domain
- Domain layer contains zero external dependencies
- All components receive dependencies via constructor injection

{ARCHITECTURE_DETAILS}

## Rules

Detailed rules: `~/.claude/RULES.md` + `.memory-bank/RULES.md`

### Critical rules (always follow)

> **Contract-First** — Protocol/ABC → contract tests → implementation. Tests must pass for ANY correct implementation.
> **TDD** — tests first, then code. Allowed skip: typos, formatting, exploratory prototypes.
> **Clean Architecture** — `Infrastructure → Application → Domain` (never the other way around). Domain = 0 external dependencies.
> **SOLID thresholds** — SRP: >300 lines or >3 public methods of different nature = split candidate. ISP: Interface ≤5 methods. DIP: constructor takes abstractions.
> **DRY / KISS / YAGNI** — duplicate >2 times → extract. Three identical lines are better than premature abstraction. Do not write code "for the future."
> **Testing Trophy** — integration > unit > e2e. Mock only external services. >5 mocks → candidate for an integration test.
> **Test quality** — naming: `test_<what>_<condition>_<result>`. Assert business facts. Arrange-Act-Assert. `@parametrize` over copy-paste.
> **Coverage** — overall 85%+, core/business 95%+, infrastructure 70%+.
> **No placeholders** — no TODO, `...`, or pseudocode. Code must be copy-paste ready.
> **Language** — respond in English; technical terms may remain in English.

## Memory Bank

**If `./.memory-bank/` exists → `[MEMORY BANK: ACTIVE]`.**

**Session pipeline (one-liner):**

```
/mb start  →  /mb plan <type> <topic>  →  [work]  →  /mb verify  →  /mb done
```

**`/mb verify` is MANDATORY before `/mb done` when work followed a plan.**


| Command                                     | Description                                                   |
| ------------------------------------------- | ------------------------------------------------------------- |
| `/mb start` / `/mb context [--deep]`        | Restore context (core files + codebase summary)               |
| `/mb plan <type> <topic>`                   | Create plan with SMART DoD + TDD (types: feature/fix/refactor/experiment) |
| `/mb verify`                                | Verify code vs plan (plan-verifier subagent)                  |
| `/mb done`                                  | End session — actualize + note + progress                     |
| `/mb update`                                | Intermediate actualize (no note) — before compaction          |
| `/mb map [focus]` / `/mb graph [--apply]`   | Refresh codebase map (MD docs) / code graph (JSON Lines)      |
| `/mb idea "<t>" [HIGH\|MED\|LOW]` / `/mb adr "<t>"` | Capture idea (I-NNN) / ADR (ADR-NNN)                          |
| `/mb init --full`                           | Rebuild `CLAUDE.md` with stack auto-detection                 |


### `.memory-bank/` structure


| File           | Purpose                         | When to update            |
| -------------- | ------------------------------- | ------------------------- |
| `status.md`    | Current state, roadmap, metrics | Stage completed           |
| `checklist.md` | Tasks ✅/⬜                       | Every session             |
| `roadmap.md`      | Priorities, direction           | Focus change              |
| `RULES.md`     | Project rules                   | When updated              |
| `research.md`  | Hypotheses + findings           | New finding               |
| `progress.md`  | Completed work (append-only)    | End of session            |
| `lessons.md`   | Anti-patterns                   | When a pattern is noticed |
| `plans/`       | Detailed plans (`YYYY-MM-DD_<type>_<name>.md`) | Before complex work |
| `codebase/`    | Codebase map + code graph (`STACK.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `CONCERNS.md`, `graph.json`, `god-nodes.md`) | After `/mb init`, stack change, or major refactor |


### Code Graph (structural queries)

`.memory-bank/codebase/graph.json` — JSON Lines graph (module/function/class nodes + import/call edges). Prefer it over `grep -rn` for structural questions:

```bash
# Who calls function X?
jq -r 'select(.type=="edge" and .kind=="call" and .dst=="X") | .src' \
  .memory-bank/codebase/graph.json | sort -u
```

Full jq query library + schema + decision table → `~/.claude/RULES.md § Code Graph — usage`.

### Read detailed rules on demand

Before specific commands/workflows, **read the matching section of `~/.claude/RULES.md`** (and this project's `.memory-bank/RULES.md` for overrides):

- `/mb plan` → `§ Session Pipeline` + `§ Source of Truth`
- `/mb verify` / `/mb done` → `§ Session Pipeline § Phase 4/5`
- `/mb graph` / jq queries → `§ Code Graph — usage`
- Writing tests → `§ Tests — Testing Trophy`
- ADR, architecture change → `§ Architecture` + `§ Coding Standards`

