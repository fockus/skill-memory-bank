## Memory Bank status line

Open your first reply to the user in a project session with one line that says whether project memory is in play: `[MEMORY BANK: ACTIVE]` when a bank resolves for this project, `[MEMORY BANK: ABSENT]` when none does, and `[MEMORY BANK: INITIALIZED]` right after the user asked you to create one. A bank may be **local** (`<project>/.memory-bank/`), **global** (registered under `<agent_config>/memory-bank/registry.json` via `/mb init --storage=global`), or **legacy** (`.claude-workspace`); `scripts/_lib.sh::mb_resolve_path` resolves all three. The line is for the human: leave it out of later replies, subagent reports, and output that a script parses.

A globally installed skill never means this project has a bank; only an explicit `/mb init` creates one. Do not silently initialize Memory Bank for meta/install/debug questions.

### Rules-only mode

`[MEMORY BANK: ABSENT]` is a valid steady state. When the user chooses not to initialize a Memory Bank, **all engineering rules below still apply** — TDD, SOLID, Clean Architecture / FSD, DRY/KISS/YAGNI, Testing Trophy, protected files, no placeholders, verification before completion. Only the `/mb` lifecycle commands stay inactive.

# Engineering rules

> **Contract-First** — Protocol/ABC → contract tests → implementation. Tests must pass for ANY correct implementation.
> **TDD** — tests first, then code. Allowed skips: typos, formatting, exploratory prototypes.
> **Clean Architecture (backend)** — `Infrastructure → Application → Domain` (never the other way around). Domain = 0 external dependencies.
> **FSD (frontend)** — Feature-Sliced Design for React/Vue/Angular. Layers top-down: `app → pages → widgets → features → entities → shared`. Imports only downward; cross-slice communication inside a layer goes through widget/page; every slice exposes its public API through `index.ts`.
> **DDD folder structure (backend + frontend)** — group modules into coherent sub-packages by responsibility / bounded context across ALL layers, never a flat dump. No single-file folders (KISS). Backend layers: `domain/ application/ infrastructure/ interfaces/ di/`. Frontend: FSD slices ARE the DDD grouping (`entities/<context>`, `features/<action>`).
> **Backend macro-architecture (pick one)** — serverless (FaaS) · microservices · modular monolith. In a modular monolith, modules do not depend on each other directly; cross-module communication goes through a shared layer or explicit contracts. Clean Architecture direction still holds inside each function/service/module.
> **Mobile (iOS/Android)** — UDF + Clean layers: `View → ViewModel → UseCase → Repository (SSOT) → DataSource`. iOS: SwiftUI + `@Observable`, `async/await`, SwiftData, SPM feature modules. Android: Jetpack Compose + StateFlow + Hilt + Room, Gradle multi-module. Immutable UI state, DI through protocols/interfaces.
> **SOLID thresholds** — SRP: >300 lines or >3 public methods of different nature = split candidate (warns); it blocks when a change pushes a file over the threshold or adds a responsibility to one already over it. ISP: interface ≤5 methods. DIP: constructor takes abstractions.
> **DRY / KISS / YAGNI** — the same logic in 3+ places → extract; three identical lines are better than a premature abstraction. Do not write code "for the future."
> **Testing Trophy** — integration > unit > e2e. Mock only external services. >5 mocks = candidate for an integration test.
> **Test quality** — naming: `test_<what>_<condition>_<result>`. Assert business facts. Arrange-Act-Assert. Prefer `@parametrize` over copy-paste.
> **Coverage** — overall 85%+, core/business 95%+, infrastructure 70%+.
> **Fail Fast** — when different readings of the task would lead to materially different work, say so briefly with your proposed approach and ask; make routine judgment calls yourself and state the assumption.
> **Language** — respond in English; technical terms may remain in English.
> **No placeholders** — no TODO, `...`, or pseudocode. Code must be copy-paste ready. Exception: staged stubs behind a feature flag with a docstring.
> **Plans** — every stage must have detailed DoD (SMART), TDD requirements, verification scenarios, and edge cases.
> **Protected files** — do not touch `.env`, `ci/`**, Docker/K8s/Terraform without explicit request.
> **Detailed rules:** `~/.claude/RULES.md` + project-root `RULES.md`.

---

# Global Rules

The engineering rules above are the always-on core. Edge cases, examples, the jq query library and the full `/mb` reference live in `~/.claude/RULES.md` (read on demand). The essentials:

## Coding & Reasoning
- No new libraries/frameworks without explicit request; multi-stage work → a `/mb plan` plan first; before editing → search the project, don't guess.
- New business logic → tests FIRST. Full imports, complete functions — copy-paste ready, no placeholders.
- Specification by Example (concrete input/output); refactor via Strangler Fig (tests green at every step); significant decision → ADR (context → decision → alternatives → consequences).
- Destructive actions → confirm first. Do not expand scope without request.
- Every task carries SMART DoD criteria you actually verify.

## Testing — Testing Trophy
Integration > unit > e2e; mock only external boundaries; 5+ mocks = integration candidate. Coverage 85%+ (core 95%+, infra 70%+). Static analysis (lint, type-checking, stack-specific checks) — always.

## Planning
Plans → `./.memory-bank/plans/` when Memory Bank is active. Every stage: SMART DoD + test requirements BEFORE implementation (TDD), atomic, dependency-ordered.
**Agent routing (unless the user says otherwise):** author plans with `/mb plan`; its template carries these rules (TDD-first, SOLID, Clean Architecture/FSD, SMART DoD). Size numbers are guidelines: the only mechanical size check is SRP at 300 lines and it warns, so don't reshape a module just to meet a number. Execute plans/specs with `/mb work`, which dispatches the `mb-*` role agents with the engineering core built in (review is opt-in). Use the host's general research agent and `mb-research` for research, not for plans or code: they don't carry that core.

## Memory Bank
**Skill:** `memory-bank`. **Command:** `/mb`. **Path:** `./.memory-bank/`.
**Three-in-one:** (1) long-term project memory (`.memory-bank/`), (2) the engineering RULES above, (3) a dev toolkit of slash commands. **Design contract:** agents remember by default; everything above that is a configurable, token-economical layer — defaults never change without explicit opt-in, expensive paths are off by default.
**`/mb context`** (alias `/mb`) — gather the current project context (status + checklist + active plan + codebase summary). Run it at the START of any project work; `/mb context --deep` expands the full `codebase/*.md`. `/mb start` = extended start (context + the full active plan read in).
**Subagents** (model and effort come from each agent's definition or `pipeline.yaml`): MB Manager (mechanical actualize) · plan-verifier (`/mb verify`) · mb-doctor · mb-codebase-mapper · mb-rules-enforcer · mb-test-runner · mb-reviewer + dev-role agents for `/mb work` (the engineering core is built into them). Full roster + when-to-invoke → `SKILL.md` § Agents.

### Session Pipeline
```
plan-based:  /mb start → /mb plan <type> <topic> → [work] → /mb verify → /mb done
spec-driven: /mb start → /mb discuss <topic> → /mb sdd <topic> → /mb work <topic> → /mb verify → /mb done
```
**Run `/mb verify` before `/mb done` when work followed a plan** — it checks every DoD item against the code. SDD adds EARS-validated requirements + optional GIVEN/WHEN/THEN scenarios → executable `tasks.md` (`<!-- mb-task:N -->`). `/mb work` is the executor: drives plan stages or spec tasks through a per-item **implement→verify→done** loop (composable — **review off by default**, opt in with `--review`/`--judge` or `pipeline.yaml`) with severity-gates + `pipeline.yaml` protected-paths/budget. Full `/mb` reference + SDD + work engine → `~/.claude/RULES.md` or `/mb help`.

### Key invariants
- `progress.md` = **append-only** (never rewrite old entries); IDs monotonic (I-/EXP-/ADR-NNN, never reused); `checklist.md` ✅/⬜ updated **immediately**; `notes/` = patterns (5–15 lines), not chronology.
- **Parallel sessions in one working tree** → coordinate via the append-only board `.memory-bank/COORDINATION.md`: read it with `scripts/mb-coord.sh active` (freezes + unACKed handovers + last 3 entries; the full file only when investigating) at session start, before each stage/commit, and before editing shared files; scoped `git add` only (never `-A`); freezes/handovers/commit-order agreements require an ACK entry. Protocol → skill `references/coordination.md`.
- **Running list of agreements** — explicit user decision → `mb-agree.sh add "<statement>"` then announce `→ AGR-NNN записано: <statement>`; unconfirmed idea/hypothesis → `mb-agree.sh question "<text>"`; a changed decision → `add "<new>" --supersedes N` (never leave two active). Kill-switch `MB_AGREEMENTS=off`. Protocol → skill `references/agreements.md`.

### Codebase Map & Code Graph
`.memory-bank/codebase/`: 4 MD docs (`STACK`/`ARCHITECTURE`/`CONVENTIONS`/`CONCERNS`, via `/mb map`, auto-loaded by `/mb context`) + `graph.json` + `god-nodes.md` (`/mb graph --apply`). Prefer the graph over `grep -rn` for structural questions. Example: `jq -c 'select(.type=="edge" and .dst=="WriteFile")' .memory-bank/codebase/graph.json`.
- **Opt-in layers** (off by default, base output byte-identical): `/mb graph --questions` (suggested questions in `god-nodes.md`) · `/mb graph --cochange` (`co_change` edges from git history) · `/mb graph --docs` (enrich nodes with `signature`+`doc` for richer semantic search) · `mb-semantic-search.py "<query>" [--backend embeddings] [--source-only]` (semantic search — embeddings for concepts, BM25 for exact names; cached under `.index/codesearch/`) · `/mb wiki` (LLM per-community wiki + "surprising connections" = `semantic` edges, runs as subagents, no API key). **Routing:** concept→embeddings · exact name→bm25 · impact/god-node→`mb-graph-query` · why→wiki/`recall`. Table → `references/code-graph.md` (`/mb help`).
- **Session memory (cross-chat):** lifecycle hooks log each session to `.memory-bank/session/*.md`; **`/mb recall <query>`** does lexical recall over `session/` + `notes/`. Off: `MB_SESSION_CAPTURE=off`. Distinct from `/mb search` (core files) and `mb-semantic-search.py` (code graph).
- Routing + jq library + schema → `references/code-graph.md` (`/mb help`).

### Personalization, privacy, native memory
- **Rule profiles:** `/mb profile init --scope=user|project --role --stack --architecture --delivery` tunes the configurable rules layer (the immutable safety baseline always stays). Works even without a bank (user scope).
- **Private content:** wrap secrets/PII in `<private>…</private>` — excluded from `index.json` + redacted in `/mb search` output (does NOT filter `git diff`; use `.gitattributes` for that).
- **`.memory-bank/` vs native auto-memory:** project/team/git-tracked facts (status, plans, ADRs, lessons) → `.memory-bank/`; personal cross-project facts (preferences, role, feedback) → the agent's native memory (Claude Code: `~/.claude/projects/.../memory/`). They coexist — don't duplicate one into the other.

### When to read the detailed rules
Before these, read the matching `~/.claude/RULES.md` section: `/mb plan` → `§ Session Pipeline` + `§ Planning chain`; `/mb discuss` / `/mb sdd` → `§ SDD — spec-driven flow`; `/mb work` → `§ /mb work — execution engine`; `/mb verify` / `/mb done` → `§ Session Pipeline`; `/mb graph` / `/mb map` / jq → `§ Code Graph — usage`; `/mb profile` → `§ Rule profiles`; subagents → `§ Subagents`; tests → `§ Tests — Testing Trophy`; ADR → `§ Architecture`.

Project-specific overrides live in `<project-root>/RULES.md` (or `.memory-bank/RULES.md`). Read them **in addition to** the global ones, not instead.
