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

**Command:** `/mb`. **Workflow:** start → work → verify → done.


| Command                | Description                                   |
| ---------------------- | --------------------------------------------- |
| `/mb` or `/mb context` | Collect project context                       |
| `/mb start`            | Extended session start                        |
| `/mb update`           | Actualize core files                          |
| `/mb done`             | Finish the session                            |
| `/mb verify`           | Verify plan vs code                           |
| `/mb init --full`      | Rebuild `CLAUDE.md` with stack auto-detection |


### `.memory-bank/` structure


| File           | Purpose                         | When to update            |
| -------------- | ------------------------------- | ------------------------- |
| `STATUS.md`    | Current state, roadmap, metrics | Stage completed           |
| `checklist.md` | Tasks ✅/⬜                       | Every session             |
| `plan.md`      | Priorities, direction           | Focus change              |
| `RULES.md`     | Project rules                   | When updated              |
| `RESEARCH.md`  | Hypotheses + findings           | New finding               |
| `progress.md`  | Completed work (append-only)    | End of session            |
| `lessons.md`   | Anti-patterns                   | When a pattern is noticed |
| `codebase/`    | Codebase map: stack, architecture, conventions, concerns | After `/mb init` or `/mb map` |


