## Mandatory first response guard

This is an output-format invariant, not optional workflow advice.

Before any substantive response in a project directory:
1. Resolve the active Memory Bank through `scripts/_lib.sh::mb_resolve_path`. The bank may be **local** (`<project>/.memory-bank/`), **global** (registered under `<agent_config>/memory-bank/registry.json` via `/mb init --storage=global`), or **legacy** (`.claude-workspace`).
2. If the resolver returns an existing bank, the first line of the response MUST be `[MEMORY BANK: ACTIVE]`.
3. If no bank is resolved, the first line MUST be `[MEMORY BANK: ABSENT]`. Do not silently initialize Memory Bank for meta/install/debug questions.
4. If the user explicitly asks to initialize Memory Bank, create it and print `[MEMORY BANK: INITIALIZED]`.
5. Never confuse global skill installation with project Memory Bank activation. A global skill install never implies an active bank — only an explicit `/mb init` does. Never omit this status line when Memory Bank skill/rules are discussed or project work starts.

### Rules-only mode

`[MEMORY BANK: ABSENT]` is a valid steady state. When the user chooses not to initialize a Memory Bank, **all engineering rules below still apply** — TDD, SOLID, Clean Architecture / FSD, DRY/KISS/YAGNI, Testing Trophy, protected files, no placeholders, verification before completion. Only the `/mb` lifecycle commands stay inactive.

Before final answer, verify:
- Did I mention Memory Bank status when applicable?
- Did I distinguish global skill installation from project Memory Bank activation?
- Did I apply the coding rules (TDD, Clean Architecture/FSD, SOLID, Testing Trophy) before claiming completion — including in rules-only mode?

# CRITICAL RULES — DO NOT FORGET DURING COMPACTION

> **Contract-First** — Protocol/ABC → contract tests → implementation. Tests must pass for ANY correct implementation.
> **TDD** — tests first, then code. Allowed skips: typos, formatting, exploratory prototypes.
> **Clean Architecture (backend)** — `Infrastructure → Application → Domain` (never the other way around). Domain = 0 external dependencies.
> **FSD (frontend)** — Feature-Sliced Design for React/Vue/Angular. Layers top-down: `app → pages → widgets → features → entities → shared`. Imports only downward; cross-slice communication inside a layer goes through widget/page; every slice exposes its public API through `index.ts`.
> **Mobile (iOS/Android)** — UDF + Clean layers: `View → ViewModel → UseCase → Repository (SSOT) → DataSource`. iOS: SwiftUI + `@Observable`, `async/await`, SwiftData, SPM feature modules. Android: Jetpack Compose + StateFlow + Hilt + Room, Gradle multi-module. Immutable UI state, DI through protocols/interfaces.
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

The CRITICAL block above is the always-on core. Edge cases, examples, the jq query library and the full `/mb` reference live in `~/.claude/RULES.md` (read on demand). The essentials:

## Coding & Reasoning
- No new libraries/frameworks without explicit request; multi-file change → plan first; before editing → search the project, don't guess.
- New business logic → tests FIRST. Full imports, complete functions — copy-paste ready, no placeholders.
- Specification by Example (concrete input/output); refactor via Strangler Fig (tests green at every step); significant decision → ADR (context → decision → alternatives → consequences).
- Response format: **Goal → Action → Result**. Destructive actions → confirm first. Do not expand scope without request.
- Every task carries SMART DoD criteria you actually verify.

## Testing — Testing Trophy
Integration > unit > e2e; mock only external boundaries; 5+ mocks = integration candidate. Coverage 85%+ (core 95%+, infra 70%+). Static analysis (lint, type-checking, stack-specific checks) — always.

## Planning
Plans → `./.memory-bank/plans/` when Memory Bank is active. Every stage: SMART DoD + test requirements BEFORE implementation (TDD), atomic, dependency-ordered.

## Memory Bank
**If `./.memory-bank/` exists → `[MEMORY BANK: ACTIVE]`.** Else `[MEMORY BANK: ABSENT]`; initialize only after an explicit `/mb init` or user request → `[MEMORY BANK: INITIALIZED]`.
**Skill:** `memory-bank`. **Command:** `/mb`. **Subagent:** MB Manager (sonnet). **Path:** `./.memory-bank/`.

### Session Pipeline
```
/mb start  →  /mb plan <type> <topic>  →  [work]  →  /mb verify  →  /mb done
```
**`/mb verify` is MANDATORY before `/mb done` when work followed a plan.** Full `/mb` command reference → `~/.claude/RULES.md` or `/mb help`.

### Key invariants
- `progress.md` = **append-only** (never rewrite old entries); IDs monotonic (I-/EXP-/ADR-NNN, never reused); `checklist.md` ✅/⬜ updated **immediately**; `notes/` = patterns (5–15 lines), not chronology.

### Codebase Map & Code Graph
`.memory-bank/codebase/`: 4 MD docs (`STACK`/`ARCHITECTURE`/`CONVENTIONS`/`CONCERNS`, via `/mb map`, auto-loaded by `/mb context`) + `graph.json` + `god-nodes.md` (`/mb graph --apply`). Prefer the graph over `grep -rn` for structural questions. Example: `jq -c 'select(.type=="edge" and .dst=="WriteFile")' .memory-bank/codebase/graph.json`.
- **Opt-in layers** (off by default, base output byte-identical): `/mb graph --questions` (suggested questions in `god-nodes.md`) · `/mb graph --cochange` (`co_change` edges from git history) · `mb-semantic-search.py "<query>"` (semantic search — BM25 $0 default, optional embeddings) · `/mb wiki` (LLM per-community wiki + "surprising connections" = `semantic` edges, Haiku/Sonnet subagents, no API key).
- **Session memory (cross-chat):** lifecycle hooks log each session to `.memory-bank/session/*.md`; **`/mb recall <query>`** does lexical recall over `session/` + `notes/`. Off: `MB_SESSION_CAPTURE=off`. Distinct from `/mb search` (core files) and `mb-semantic-search.py` (code graph).
- Routing + jq library + schema → `~/.claude/RULES.md § Code Graph — usage`.

### When to read the detailed rules
Before these, read the matching `~/.claude/RULES.md` section: `/mb plan` → `§ Session Pipeline` + `§ Planning chain`; `/mb verify` / `/mb done` → `§ Session Pipeline`; `/mb graph` / `/mb map` / jq → `§ Code Graph — usage`; tests → `§ Tests — Testing Trophy`; ADR → `§ Architecture`.

Project-specific overrides live in `<project-root>/RULES.md` (or `.memory-bank/RULES.md`). Read them **in addition to** the global ones, not instead.
