# Global Rules

> Universal coding and process rules.
> Apply to ALL projects. Project-specific rules belong in the repository root `RULES.MD`.

---

## CRITICAL — violation means failure

1. **Language**: English — responses and code comments. Technical terms may remain in English.
2. **No placeholder code**: no `...`, `TODO`, or `pass` (exception: staged stubs behind a feature flag with a docstring)
3. **Destructive actions only after explicit "go"**
4. **Protected files** (`.env`, `ci/`**, Docker/K8s/Terraform) — do not touch without an explicit request
5. **New logic = tests FIRST** (TDD)
6. **Principles**: TDD / SOLID / DRY / KISS / YAGNI / Clean Architecture — no exceptions
7. **Contract-First**: interface → contract tests → implementation
8. **Fail Fast**: if you are unsure about direction, write a 3-5 line plan and ask
9. **RULES.md is a mandatory standard**: ALL work MUST follow this file plus the project `RULES.MD`. It is not a recommendation; it is a hard requirement.

---

## Mandatory first response guard

This is an output-format invariant for agents that load these rules into their prompt.

Before any substantive response in a project directory:
1. Resolve the active Memory Bank through `scripts/_lib.sh::mb_resolve_path`. The bank may be **local** (`<project>/.memory-bank/`), **global** (`<agent_config>/memory-bank/projects/<id>/.memory-bank/`, registered through `/mb init --storage=global --agent=<name>`), or **legacy** (`.claude-workspace`). Agent-agnostic global storage is the new recommended layout for personal use; local stays default and team-friendly.
2. If the resolver returns an existing bank, start with `[MEMORY BANK: ACTIVE]` and read the core files at session start.
3. If no bank is resolved, start with `[MEMORY BANK: ABSENT]`.
4. Do not silently initialize Memory Bank for meta/install/debug questions.
5. Print `[MEMORY BANK: INITIALIZED]` only after explicit `/mb init` or user request.
6. Distinguish global skill installation from project Memory Bank activation. A global install never implies an active bank.

### Rules-only mode

`[MEMORY BANK: ABSENT]` is a deliberate user choice for many third-party repositories. In rules-only mode:

- `/mb` lifecycle commands stay inactive — do not auto-initialize, do not write `.memory-bank/` files.
- All engineering rules above (TDD, SOLID, Clean Architecture / FSD, DRY/KISS/YAGNI, Testing Trophy, protected files, no placeholders, verification before completion) **still apply** to ordinary code work. The agent must NOT relax discipline because Memory Bank is absent.

---

## GraphRAG-lite retrieval routing

Use Memory Bank code intelligence in this order. `code_context is the default` for ambiguous code-understanding questions because it can combine semantic discovery, structural graph expansion, exact file reads, and test/impact hints.

| Question shape | Preferred entry point | Fallback | Reason |
|---|---|---|---|
| "where is the logic for X?", "find similar implementation", natural-language code search | `code_context` | `search_code` → `rg/read` | Semantic discovery first, then structural validation. |
| "who calls/imports/defines X?" | `graph_neighbors` | `rg/read` | Exact structural relationship; vector search adds noise. |
| "reverse deps" or impact of changing a symbol/file | `graph_impact` | `rg/read` | Impact analysis must be deterministic and explainable. |
| "what tests cover this file/symbol?" | `graph_tests` | `rg 'file|symbol' tests/` | Test links are structural evidence. |
| User explicitly asks "semantic search" | `search_code` | `code_context --semantic-only` | Respect explicit tool intent. |
| User explicitly asks for `rg` or exact text search | `rg/read` | `code_context` only if context remains unclear | Respect exact text-search intent. |

Agent examples:
- **Pi**: prefer native tools `code_context`, `graph_neighbors`, `graph_impact`, and `graph_tests` when installed; use CLI fallback otherwise.
- **Claude Code**: use slash-command guidance and CLI fallback through `scripts/mb-code-context.py` and `scripts/mb-graph-query.py`.
- **Codex**: follow `AGENTS.md` instructions and call the portable CLI scripts directly.
- **OpenCode**: prefer native plugin tools when installed; use the same CLI fallback when plugin/native tool support is unavailable.
- **generic AGENTS.md** agents: follow this routing table and call portable scripts directly.

Fail open / fail open behavior: if the graph is missing graph or stale graph is suspected, say so and suggest `/mb graph --apply`; if there is a missing semantic provider or unavailable native extension, continue with graph + `rg/read` instead of blocking the task. Never make Milvus, Ollama, Docker, or `claude-context` mandatory for Memory Bank core.

---

## Naming conventions

**Plan hierarchy:** Phase → Sprint → Stage. See `references/templates.md` § *Plan decomposition* for the size thresholds and when to use which level. Cyrillic «Этап / Спринт / Фаза» — legacy alias, allowed only in `plans/done/*.md` and historical archives. New work uses the English triple.

---

## Source of Truth — planning chain

If a project has Memory Bank (`.memory-bank/`), planning and implementation flow through one chain:

```
roadmap.md ("Active plan" field → link to file)
    ↓
plans/<file>.md  ← Source of truth: tasks, DoD, stages
    ↓
checklist.md     ← Tracking: ✅ done, ⬜ remaining
    ↓
status.md        ← Phase, blockers, audit findings
```

### Consistency rules

1. **A new plan** (`/mb plan`) MUST be reflected in all three places:
  - `plans/<file>.md` — detailed plan with DoD
  - `roadmap.md` — link in the "Active plan" field + updated focus
  - `status.md` — updated roadmap ("In Progress" section)
  - `checklist.md` — plan tasks represented as ⬜ items
2. **Tasks come ONLY from the detailed plan**. Do not invent off-plan tasks.
3. `**checklist.md` reflects the plan**: each stage in `plans/<file>.md` = one ⬜ item in the checklist.
4. `**status.md` reflects facts**: update the roadmap on actual completion, not on planning.
5. **When the active plan changes**: update `roadmap.md` + `status.md` + `checklist.md`.
6. **When a plan is completed**: move it to `plans/done/`, then update `roadmap.md`, `status.md`, and `checklist.md`.

---

## Architecture

### Clean Architecture

**Dependency direction**: `Infrastructure → Application → Domain` (never backward).
Forbidden: imports from infrastructure into application/domain.

**Layers:**

- **Domain**: types, protocols, business logic. No dependencies on external libraries (except stdlib)
- **Application**: use cases, orchestrators. Depends on Domain
- **Infrastructure**: frameworks, DB, HTTP, filesystem. Depends on Application and Domain

Add `interfaces/` (console / http / telegram entry points) and `di/` (composition root — the ONLY place concrete collaborators are constructed) as outer layers when a project has multiple delivery channels. Imports flow strictly inward: `interfaces → infrastructure → application → domain`.

### Backend macro-architecture (pick one)

Choose ONE macro style per service and record it in the project `RULES.MD` / Memory Bank `status.md`:

- **Serverless (FaaS)** — functions as deploy units (Lambda / Cloud Functions / Workers). Keep each handler thin; business logic lives in Application/Domain so it is testable without the runtime. No shared mutable state between invocations.
- **Microservices** — independently deployable services, each owning its own data. Communicate over explicit contracts (HTTP / gRPC / events), never a shared database. One bounded context per service.
- **Modular monolith** — one deploy unit, internal modules by bounded context. **Modules MUST NOT depend on each other directly** — cross-module communication goes ONLY through a shared layer (`shared/`) or explicit published contracts/interfaces. A module imports `shared`, never a sibling module's internals. This keeps modules independently reasoned and extractable into services later.

In all three the Clean Architecture dependency direction holds **inside** each function / service / module. The macro style only decides the deploy + coupling boundary; it never licenses an Infrastructure→Domain import.

### DDD — domain-driven folder structure (backend + frontend)

Group modules into coherent sub-packages by **responsibility / bounded context** in **every** layer — not a flat dump of files.

- **Backend (Clean Architecture)**: `domain/` (0 external deps) · `application/` (use cases) · `infrastructure/` (port adapters) · `interfaces/` · `di/`. Inside each layer group by context (`domain/order/`, `domain/billing/`), not by technical type (`models/`, `utils/`).
- **Frontend (FSD)**: the slice IS the DDD grouping — `entities/<context>`, `features/<action>`, organised by business meaning, public API via `index.ts`.
- **KISS guard**: do NOT create a folder for a single file. Group only where it improves readability. Refactor into sub-packages via Strangler Fig — tests green at every step; leave a back-compat re-export façade on the old path or fix all imports at once.

### SOLID

- **SRP** (Single Responsibility): one module = one reason to change. More than 3 public methods of different kinds is a violation. A class with more than 300 lines is a split candidate
- **OCP** (Open/Closed): extend through composition and the Strategy pattern, not by modifying old code. New behavior = new class, not `if-else` inside old code
- **LSP** (Liskov Substitution): a subclass must work everywhere the parent works. Violation: overriding a method with different semantics
- **ISP** (Interface Segregation): Protocol/Interface ≤5 methods. A client must not depend on methods it does not use. A fat interface should be split into thinner ones
- **DIP** (Dependency Inversion): depend on Protocol/ABC, not concrete classes. Constructors accept abstractions; factories create concrete implementations

### DRY / KISS / YAGNI

- **DRY**: duplication more than 2 times → extract function/class. BUT do not extract if the similarity is accidental (different domains, different reasons to change)
- **KISS**: simple solutions beat complex ones. Three repeated lines are better than premature abstraction. If a solution requires a lot of explanation, it is too complex
- **YAGNI**: do not write code for hypothetical future needs. Do not add feature flags, config, or abstractions for imagined requirements. Add only what is needed NOW

### Training / Inference separation (ML projects)

- `nn.Module` = only `forward()`, `act()`, `evaluate()`. No training logic
- `Trainer` = `update()`, `train_epoch()`. Uses modules through a Protocol
- A module must not import its own Trainer. The Trainer imports the module

### Frontend — Feature-Sliced Design (FSD)

For frontend projects (React/Vue/Angular/Svelte), use FSD instead of classical Clean Architecture. FSD is specialized for UI composition.

**Layers (top → bottom, imports strictly downward):**


| Layer       | What belongs there                                 | Example                                              |
| ----------- | -------------------------------------------------- | ---------------------------------------------------- |
| `app/`      | Initialization, providers, router, global styles   | `<AppProviders>`, `App.tsx`, `index.css`             |
| `pages/`    | Individual application pages                       | `pages/product/`, `pages/checkout/`                  |
| `widgets/`  | Independent composable UI blocks                   | `Header`, `Sidebar`, `ProductCard`                   |
| `features/` | User actions with business value                   | `auth-by-email`, `add-to-cart`                       |
| `entities/` | Business entities (data model + UI representation) | `user`, `product`, `order`                           |
| `shared/`   | Reusable primitives with no business context       | `shared/ui/Button`, `shared/lib/dayjs`, `shared/api` |


**Slice structure (business layers except shared/app):**

```text
features/auth-by-email/
  ├── ui/          # React components for the feature
  ├── model/       # state (Redux/Zustand/MobX), hooks, selectors
  ├── api/         # HTTP requests, tRPC/RTK Query endpoints
  ├── lib/         # helpers, pure functions
  └── index.ts     # public API — ONLY what external code should use
```

**Rules:**

- **Imports go strictly downward by layer**: `page` → `widget` → `feature` → `entity` → `shared`. Reverse imports are forbidden.
- **Cross-slice imports within the same layer are forbidden**: `features/auth` must NOT import from `features/cart`. Compose in `widget` or `page`.
- **Slice public API goes through `index.ts`**: external imports only through `@/features/auth-by-email`, never `@/features/auth-by-email/model/store.ts`.
- **UI kit lives in `shared/ui/`**: dumb components with no business logic (Button, Input, Modal).
- **Pages = composition**: a page should not contain business logic; it only assembles widgets/features.

**Linter**: `@feature-sliced/eslint-config` + `steiger` for validation.

**What is NOT FSD** (common mistakes):

- `src/components/` / `src/pages/` / `src/utils/` — this is structure-by-type, anti-FSD
- Features importing each other directly → route through `widget` or `shared/model`
- Components importing concrete slice files instead of going through `index.ts`

### Mobile — iOS / Android

For native mobile applications, use platform patterns built around Unidirectional Data Flow (UDF) and clean layers.

**iOS (Swift/SwiftUI):**

- **UI**: SwiftUI + Observation (`@Observable`, `@State`, `@Binding`) for iOS 17+. UIKit + MVVM+Coordinator for legacy apps
- **Concurrency**: `async/await` + `Actor`, not GCD/Combine in new code
- **Persistence**: SwiftData (iOS 17+) or Core Data
- **Layers**: `View → ViewModel → UseCase → Repository → DataSource(network/local)`. Domain = protocols + Entity, with no UIKit/SwiftUI dependencies
- **Modularity**: SPM feature modules (`FeatureAuth`, `CoreUI`, `CoreNetwork`)
- **Large apps**: The Composable Architecture (TCA) — Redux-like for SwiftUI, justified when screens share state
- **Tests**: XCTest + `swift-snapshot-testing` for UI

**Android (Kotlin/Compose):**

Follow the official [Android Recommended Architecture](https://developer.android.com/topic/architecture):

```text
UI Layer         (Composable + ViewModel + immutable UiState)
     ↓ UDF
Domain Layer     (UseCase — optional if logic is shared between VMs)
     ↓
Data Layer       (Repository = Single Source of Truth;
                  DataSource: Remote (Retrofit/Ktor) + Local (Room))
```

- **UI**: Jetpack Compose + Material 3. XML View system is legacy-only
- **Reactive**: Kotlin Coroutines + Flow. `StateFlow` for UI state, `SharedFlow` for one-off events
- **DI**: Hilt (on top of Dagger)
- **Persistence**: Room (SQL), DataStore (preferences), WorkManager (background work)
- **Modularity**: Gradle multi-module — `:feature:auth`, `:feature:cart`, `:core:ui`, `:core:network`, `:core:database`
- **Shared iOS+Android logic**: Kotlin Multiplatform (KMP) — domain/data layers in Kotlin, UI native per platform
- **Tests**: JUnit + Turbine (Flow), Paparazzi/Roborazzi for UI snapshots

**Shared rules (iOS + Android):**

- **UDF**: state flows downward (Repository → ViewModel → UiState → View), events flow upward (View → `VM.onEvent()`)
- **Immutable UI state**: always create a new object via `copy()` / `struct`, never mutate in place
- **Single Source of Truth**: Repository owns the data; ViewModel only exposes derived state
- **Testability**: dependencies go through protocols/interfaces; DI supplies fakes in tests
- **One ViewModel per screen**: do not share VMs across screens (composable state goes through a shared Repository)

---

## TDD — Test-Driven Development

### Two TDD modes

**Deterministic modules** (parsers, validators, business logic, routers):

```text
Red → Green → Refactor
```

1. Write a failing test BEFORE code
2. Add the minimum implementation needed to pass
3. Refactor (remove duplication, improve naming)
4. Repeat

**ML modules** (models, trainers, losses):

- **Contract tests (BEFORE implementation):** output shape, gradient flow, range invariants, determinism (seed), no NaN/Inf, device-agnostic behavior
- **Statistical tests (AFTER implementation):** convergence (`final_loss < initial * threshold`), sanity checks. Mark with `@pytest.mark.slow`

**When it is acceptable to skip TDD:** typos, formatting, exploratory prototypes.

### Contract-First Development

1. Define the interface (Protocol / ABC / type signatures)
2. Write contract tests (they verify the contract, not the implementation)
3. Implement
4. Contract tests must pass for ANY correct implementation

---

## Tests — Testing Trophy

### Priority (Testing Trophy)

```text
         /  E2E  \          ← targeted, critical flows
        / Integration \      ← PRIMARY FOCUS
       /    Unit Tests   \   ← pure logic, edge cases
      / Static Analysis    \ ← type checking and linting — always
```

- **Integration tests (primary focus):** real components together, mock only external services (DB, HTTP, filesystem). More than 5 mocks is a sign you likely need an integration test
- **Unit tests:** pure logic, edge cases, boundaries. Fast and isolated
- **E2E tests:** only critical user flows. Expensive and brittle — keep to a minimum
- **Static analysis:** type checking and linting — always, on every commit

### Test-writing rules

- **Name = business requirement**: `test_<what>_<condition>_<result>`. Example: `test_evidence_pack_caps_rel_facts_at_ten`
- **Assert = business fact**: every assert checks a specific requirement or edge case

```python
# Bad — meaningless assert
assert result is not None

# Good — verifies a business requirement
assert len(pack.rel_facts) <= 10
assert encoder.sigma > 0
assert loss < initial_loss * 0.8
```

- **Mock only external boundaries**: DB, HTTP APIs, filesystem, third-party services. Do NOT mock business logic — use in-memory implementations
- **Use `@parametrize`** for variations instead of copying tests
- **Each test = one scenario**: do not check five unrelated things in one test
- **A test should fail for one reason**: when it fails, it should be obvious what broke
- **Arrange-Act-Assert**: keep setup / action / verification clearly separated
- **Specification by Example**: requirements expressed as concrete inputs/outputs become ready-made test cases

### Markers

- `@pytest.mark.slow` — tests longer than 10 seconds (ML convergence, statistical)
- `@pytest.mark.gpu` — require a GPU
- Project-specific markers belong in the project `RULES.MD`

### Coverage

- Target: **85%+** overall
- Core/business logic: **95%+**
- Infrastructure/adapters: **70%+**
- Project-specific per-layer targets belong in the project `RULES.MD`

---

## Coding Standards

### General

- Full imports, valid syntax, complete functions — code must be copy-paste ready
- No placeholders: no `TODO`, `...`, or pseudocode
- No new libraries/frameworks without an explicit request
- Multi-file changes → plan first, then implement

### Refactoring

- **Strangler Fig**: new code wraps old code, then replaces it incrementally with tests
- Every refactoring step keeps tests passing. Never break tests "temporarily"
- Renames: find ALL usages (`grep`/IDE), do not guess

### Architectural decisions

- Significant decision → ADR (context → decision → alternatives → consequences)
- Before making an architectural change, check existing ADRs
- If Memory Bank exists → put ADRs in `.memory-bank/backlog.md`

### Response format

- Structure: **Goal → Action → Result**
- Before any substantive response in a project directory, check `./.memory-bank/` and start with the status line:
  - `[MEMORY BANK: ACTIVE]` when `./.memory-bank/` exists
  - `[MEMORY BANK: ABSENT]` when it does not exist
  - `[MEMORY BANK: INITIALIZED]` only after explicit initialization
- Do not confuse global skill installation with project `./.memory-bank/` activation
- Code: full functions, copy-paste ready, complete imports

---

## ML: device, reproducibility, numerical hygiene

**Device-agnostic:** `.cuda()` is forbidden. Use only `.to(config.device)`. Tests run on CPU.

**Seed:** fix the seed (`random`, `numpy`, `torch`, `cuda`) at the start of every run.

**Checkpoint:** save weights + optimizer + config + metrics + git hash. Model version mismatch on load = error.

**Numerics:** gradient clipping is mandatory. Enable NaN/Inf detection in debug. Use running mean/std for reward normalization.

**Fail-fast:** NaN in loss, entropy → 0 (policy collapse), or OOM → stop immediately.

**Experiment lifecycle:** hypothesis (SMART) → baseline → one change → run → compare (`p-value`, `Cohen's d`) → keep/rollback. Changing 2+ things without ablation is forbidden.

---

## Staged stubs (allowed)

A stub = a complete Protocol/Interface implementation + docstring (what it does, what replaces it, when).
A stub must be behind a feature flag. Without a feature flag, it is not a stub; it is production code.

---

## Memory Bank Operations

---

## Skill and Tools

**Skill**: `memory-bank` (`~/.claude/skills/memory-bank/`)
**Templates**: `~/.claude/skills/memory-bank/references/templates.md`
**Workflow**: `~/.claude/skills/memory-bank/references/workflow.md`
**Structure**: `~/.claude/skills/memory-bank/references/structure.md`

---

## Subagents

All subagents run on **sonnet** unless noted; prompts in `~/.claude/skills/memory-bank/agents/<name>.md`. **Full roster + when-to-invoke → `SKILL.md` § Agents** — lifecycle / quality-gate agents (`mb-manager`, `plan-verifier`, `mb-doctor`, `mb-codebase-mapper`, `mb-rules-enforcer`, `mb-test-runner`, `mb-reviewer`), the 9 `/mb work` dev-role agents (`mb-developer` / `mb-architect` / `mb-backend` / `mb-frontend` / `mb-ios` / `mb-android` / `mb-devops` / `mb-qa` / `mb-analyst`), and the `/mb wiki` agents.

`/mb work` prepends the **partial** `mb-engineering-core` before every dev-role agent (core + role + work-item): the core carries shared discipline (TDD, Contract-First, Clean Architecture, production-wiring, evidence-before-claims / Iron Law, escalation), each role file only its domain delta — a role file invoked standalone is discipline-thin by design.

Do **NOT** delegate plan creation, architectural decisions, or ML-result interpretation to a subagent — that is main-agent work.

---

## `/mb` Commands

The skill is **three-in-one**: long-term memory (`.memory-bank/`) + the engineering RULES in this file + a dev toolkit of 25 commands. **Full command reference → `/mb help` (or `commands/mb.md`); scripts table → `SKILL.md` § Tools.** Essentials:

- **Lifecycle / context:** `/mb` (context), `/mb start`, `/mb done`, `/mb update`, `/mb search`, `/mb recall`, `/mb index`, `/mb init` (`--storage=local` default | `--storage=global --agent=<name>`).
- **Planning / SDD:** `/mb plan <type> <topic>`, `/mb discuss`, `/mb sdd`, `/mb work`, `/mb verify` (**MANDATORY before `/mb done` when work followed a plan**), `/mb idea`, `/mb idea-promote`, `/mb adr`.
- **Codebase / housekeeping:** `/mb map`, `/mb graph --apply` (`--questions` / `--cochange`), `/mb wiki`, `/mb doctor`, `/mb compact`, `/mb config`, `/mb profile`, `/mb roadmap-sync`, `/mb traceability-gen`, `/mb upgrade`.
- **Standalone toolkit** (top-level, not under `/mb`): `/commit` · `/pr` · `/review` · `/test` · `/refactor` · `/doc` · `/changelog` · `/catchup` · `/contract` · `/security-review` · `/api-contract` · `/db-migration` · `/observability` — most mirror the `/mb` equivalents and also run `mb-rules-enforcer` / `mb-test-runner` where relevant.

---

## `.memory-bank/` Structure

**Full file/folder reference → `references/structure.md`.** Core (read every session): `status.md` (where we are, metrics, gates), `checklist.md` (tasks ✅/⬜ — update **immediately** on completion), `roadmap.md` (priorities / direction), `research.md` (hypotheses + findings). Detailed (read on demand): `backlog.md` (ideas / ADRs / rejected), `progress.md` (**append-only**, end of session), `lessons.md`, `experiments/`, `plans/`, `reports/`, `notes/`, `codebase/` (map + `graph.json` / `god-nodes.md`, via `/mb map` / `/mb graph`).

---

## Workflow

### `/mb start` — start of session

1. Check whether `.memory-bank/` exists:
  - if yes → `[MEMORY BANK: ACTIVE]`
  - if no → `[MEMORY BANK: ABSENT]`; initialize only after explicit `/mb init` or user request
2. Read the 4 core files:
  - `status.md` → where we are in the project, roadmap, gates
  - `checklist.md` → current tasks (⬜/✅)
  - `roadmap.md` → priorities and direction
  - `research.md` → which hypotheses are active, current experiment
3. Summarize the focus in 1-3 sentences
4. If there is an active plan in `plans/` → read it in full
5. Check `.memory-bank/codebase/`:
  - If missing or contains no `*.md` files → suggest `/mb map all` (subagent `mb-codebase-mapper`, sonnet). Default answer = skip; never auto-invoke the mapper
  - If populated → `mb-context.sh` already folded the per-doc summaries into the gathered context (use `/mb context --deep` to expand)

### During work — when to update files


| Event                            | Action                                                           |
| -------------------------------- | ---------------------------------------------------------------- |
| A checklist task is completed    | `checklist.md`: ⬜ → ✅ (immediately, do not postpone)             |
| A new task is discovered         | `checklist.md`: add a new ⬜ task                                 |
| A stage / milestone is completed | `status.md`: update roadmap and metrics                          |
| Roadmap changed                  | `status.md`: move items between sections                         |
| Key metrics changed              | `status.md`: update the metrics section                          |
| New hypothesis                   | `research.md`: add a table row (`📋 PLANNED`)                    |
| Start of an ML experiment        | `experiments/EXP-NNN_<n>.md` + status 🔬 in `research.md`        |
| Experiment completed             | `research.md`: status ✅/🔴/⚠️ + finding. `experiments/`: results |
| Architectural decision           | `backlog.md`: ADR-NNN (context → decision → alternatives)        |
| Detailed multi-stage work        | `plans/`: create a file via `/mb plan <type> <topic>`            |
| Anti-pattern noticed             | `lessons.md`: add an entry with context                          |
| Focus/priorities changed         | `roadmap.md`: update it                                             |


### `/mb done` — end of session

1. **If work followed a plan** → run `/mb verify` **MANDATORILY** before `/mb done`:
  - Plan Verifier rereads the plan, checks `git diff`, and finds mismatches
  - CRITICAL → must be fixed
  - WARNING → optional / user decision
2. `checklist.md`: mark completed items ✅, add new items ⬜
3. `progress.md`: append to the end (APPEND-ONLY, never delete old entries)
4. `status.md`: update if a milestone completed or the roadmap changed
5. `research.md`: update if there are ML results (hypothesis status, finding)
6. `lessons.md`: add an entry if an anti-pattern was found
7. `backlog.md`: add an item if there is a new idea or ADR
8. `roadmap.md`: update if the focus changed
9. `notes/`: create a note for the completed work

### `/mb update` — intermediate actualization

Subset of `/mb done`: updates only the core files (`checklist`, `plan`, `status`).
No note creation and no `progress` entry.
Use when: an intermediate stage is finished but the session continues.

### Before compaction

Run `/mb update` to save current progress BEFORE context compression.

---

## Session Pipeline (full cycle)

The complete lifecycle of a Memory Bank session. Use this as the canonical sequence — the per-command details above are reference material; this section is the agent's working flow.

**One-liner:**

```
/mb start  →  /mb plan <type> <topic>  →  [work]  →  /mb verify  →  /mb done
```

### Phase 1 — Context restoration

| Command | When |
|---|---|
| `/mb start` | New session — reads 4 core files (STATUS, plan, checklist, RESEARCH) + one-line summary from `codebase/*.md` |
| `/mb context` | Fast refresh during a session (lightweight) |
| `/mb context --deep` | Need **full** content of `codebase/*.md` (STACK/ARCHITECTURE/CONVENTIONS/CONCERNS) |
| `/mb search <query>` | Targeted keyword search across the bank |
| `/mb tasks` | Only unfinished checklist items |

**After `/mb start` the agent MUST output a 1-3 sentence focus summary**: "We are doing X, on stage Y, next step is Z."

### Phase 2 — Plan creation

```bash
/mb plan feature "add-cache-eviction"
# → creates .memory-bank/plans/YYYY-MM-DD_feature_add-cache-eviction.md from template
```

Allowed types: `feature | fix | refactor | experiment | architecture`.

Required plan structure:
- Stages with markers `<!-- mb-stage:N -->` — `mb-plan-sync.sh` automatically adds them to `checklist.md` and the active block of `roadmap.md`
- **SMART DoD** per stage (Specific, Measurable, Achievable, Relevant, Time-bound)
- **TDD requirements** — tests FIRST (red → green → refactor), explicitly written into each stage
- Atomicity + declared dependencies between stages

Alternative entry points:
- `/mb idea "<title>" [HIGH|MED|LOW]` → records the idea in `backlog.md` with auto-generated `I-NNN`
- `/mb idea-promote I-NNN <type>` → idea becomes an active plan (flips status `NEW|TRIAGED → PLANNED`, adds `**Plan:**` link)
- `/mb adr "<title>"` → Architecture Decision Record in `backlog.md` with auto-generated `ADR-NNN`

### Phase 3 — Work (atomic updates)

- `checklist.md` — flip ⬜ → ✅ **immediately** when a stage finishes (do not batch)
- `status.md` — on milestones / metric changes / roadmap shifts
- `research.md` — on hypothesis status changes (📋 PLANNED → 🔬 TESTING → ✅/🔴/⚠️)
- `notes/` — when reusable knowledge or patterns accumulate (5-15 lines, **not chronology**)

### Phase 4 — Verification (`/mb verify`)

**MANDATORY before `/mb done` whenever work followed a plan.**

`plan-verifier` subagent:
1. Rereads the active plan file in `plans/`
2. Inspects `git diff` (staged + unstaged)
3. Checks each DoD item against the **real code** (not the conversation memory)
4. Produces a report classifying each item as CRITICAL / WARNING / OK

Agent actions:
- **CRITICAL** — must be fixed before `/mb done`
- **WARNING** — ask the user whether to fix
- All OK — proceed to Phase 5

### Phase 5 — Session end (`/mb done`)

Sequence performed by the MB Manager subagent:
1. Actualize core files (`checklist`, `plan`, `STATUS` if needed)
2. Create a `notes/YYYY-MM-DD_HH-MM_<topic>.md` note about the session (knowledge, patterns, decisions)
3. Append to `progress.md` (**append-only!**)
4. If the plan is complete → move `plans/<file>.md` → `plans/done/<file>.md`

### Intermediate / housekeeping commands

| Command | When |
|---|---|
| `/mb update` | Before compaction or a long break — saves state without creating a note |
| `/mb doctor` | Suspected inconsistencies inside the bank (plan vs checklist vs STATUS) |
| `/mb compact --dry-run` | Inspect archival candidates (`plans/done/` >60d, notes >90d with `importance: low`) |
| `/mb compact --apply` | Actually archive them (into `backlog.md` and `notes/archive/`) |
| `/mb map [focus]` / `/mb graph --apply` | After a major refactor — refresh the codebase map and the graph |

---

## SDD — spec-driven flow

An alternative to the plan-based pipeline for features that deserve a written specification. The full cycle:

```
/mb start → /mb discuss <topic> → /mb sdd <topic> → /mb work <topic> → /mb verify → /mb done
```

### Phase A — `/mb discuss <topic>`

Requirements-elicitation interview. Output: `context/<topic>.md` with REQ bullets validated against the **5 EARS patterns** (ubiquitous / event-driven / state-driven / optional-feature / unwanted-behaviour). The `mb-ears-pre-write.sh` PreToolUse hook validates bullets before save; `mb-ears-validate.sh <file>` checks on demand. REQ ids are monotonic via `mb-req-next-id.sh` (`REQ-NNN`, prefixed schemes like `REQ-RS-008` supported).

### Phase B — `/mb sdd <topic>`

Creates the **spec triple** under `specs/<topic>/`:
- `requirements.md` — the EARS requirements (+ optional `## Scenarios` layer: `<!-- mb-scenario:N -->` blocks = `### Scenario:` + `**Covers:** REQ-x` + GIVEN/WHEN/THEN).
- `design.md` — the technical design.
- `tasks.md` — **first-class executable artifact**, NOT a scaffold. Each `<!-- mb-task:N -->` block is a work item resolved by `/mb work`. Every task must carry `Covers` / `DoD` / `Testing`.

Scenarios become a test-plan via `mb-scenario-extract.py` (JSON Lines: covers + steps + stable `test_id`). `/mb plan` links them and `/mb work` turns each into one real test in the project stack.

### Phase C — validation

- `mb-spec-validate.sh <topic>` — checks EARS validity, parseable tasks, per-task Covers/DoD/Testing, no REQ orphans. `--json` for structured output.
- `--require-scenarios` (opt-in) — enforce ≥1 scenario per REQ.
- `--require-tests` (opt-in) — enforce ≥1 covering test per REQ (scans `<repo>/tests`, `<mb>/tests`, or `MB_TEST_ROOTS`).
- EARS-only specs (no scenarios) stay valid by default — the scenario layer is opt-in.

REQ-ID grammar is single-sourced in `mb_req_id.py` (definition vs mention, slash-shorthand `REQ-RS-002/003`, pytest mapping `req_rs_008`) — shared by traceability / spec-validate / ears-validate.

### When SDD vs plan-based

- **Plan-based** (`/mb plan`): internal work, refactors, fixes — stages + DoD are enough.
- **SDD** (`/mb discuss` → `/mb sdd`): user-facing features where requirements traceability (REQ → task → test) matters, or where a teammate/stakeholder needs a readable spec.

---

## `/mb work` — execution engine

`/mb work <target>` is the executor that drives selected workflow modes from `pipeline.yaml`. In the default `execution` workflow, it drives **plan stages** (`<!-- mb-stage:N -->`) or **spec tasks** (`<!-- mb-task:N -->`) through a per-item loop with quality gates. `<target>` resolves to a plan or spec path via `mb-work-resolve.sh`.

### Per-item loop

For each stage/task in `execution`: **implement → verify → review → fix-loop → done**, with auto-selected role-agent (see `§ Subagents` → dev-role agents) preceded by the `mb-engineering-core` discipline prepend. Full-cycle workflows can prepend **discuss → sdd → plan**; planning-only and review-only workflows are also valid when declared in `pipeline.yaml:workflows`.

- **Verify** — `plan-verifier` checks EARS/DoD/TDD/architecture/no-placeholder evidence before review cycles are spent.
- **Review** — `mb-reviewer` reads the verified item diff + `pipeline.yaml:review_rubric` → APPROVED / CHANGES_REQUESTED with severity-classified issues (`mb-work-review-parse.sh` validates the output).
- **Severity gate** — `mb-work-severity-gate.sh --workflow <name>` applies the selected workflow loop policy plus `severity_gate` and `approval_required`; CHANGES_REQUESTED loops back to fix when the workflow includes `fix`, and every fix returns to the configured `returns_to` step before the next review.

### Hard stops (guardrails)

- **Protected paths** — `mb-work-protected-check.sh` matches files against `pipeline.yaml:protected_paths`; the `mb-protected-paths-guard.sh` PreToolUse hook blocks writes to them (e.g. `.env`, CI configs).
- **Token budget** — `/mb work --budget` tracked by `mb-work-budget.sh` + `mb-session-spend.sh`; the `mb-sprint-context-guard.sh` hook hard-stops subagent dispatch on budget exhaustion.

### Config — `pipeline.yaml`

Managed by `/mb config` (`mb-pipeline.sh`), validated by `mb-pipeline-validate.sh`, and resolved for work modes by `mb-workflow.sh`. Holds `workflow.default`, `workflows.*`, `review_rubric`, `protected_paths`, and the active reviewer (`mb-reviewer-resolve.sh`). Plan/sprint/stage decomposition follows the **Phase → Sprint → Stage** hierarchy (`references/templates.md § Plan decomposition`).

---

## Code Graph — usage

The full structural code-graph cookbook — jq query library, `graph.json` data schema (incl. the opt-in `co_change` / `semantic` edge kinds), the **intelligence layer** (`/mb graph --questions` / `--cochange` / `--docs`, `mb-semantic-search.py`, `/mb wiki`), benchmark-grounded semantic-search routing, and `/mb recall` session memory — lives in **[`references/code-graph.md`](references/code-graph.md)** (read on demand; also via `/mb help`). Loading it only for structural analysis keeps these rules ~145 lines lighter.

---

## Edge cases: `notes/` vs `reports/`

**Create `notes/` entries when:**

- A specific task or stage is completed
- Reusable knowledge is discovered (pattern, solution, workaround)
- Format: 5-15 lines, focused on **conclusions and patterns**, not chronology
- Name: `YYYY-MM-DD_HH-MM_<topic>.md`

**Do NOT create `notes/` entries when:**

- Changes are trivial (typos, formatting)
- An exploratory prototype produced no useful knowledge
- The information is already captured in `lessons.md` or `research.md`

**Create `reports/` when:**

- A full report is useful for future sessions (larger than a note)
- Experiment result analysis is needed (in addition to `experiments/`)
- Comparative analysis of approaches is needed
- An incident post-mortem is needed
- The content needs to be freer-form and more detailed than a note

---

## `/mb index` — entry registry

Shows: core files (with line count and modification date) + lists of `notes/`, `plans/`, `experiments/`, `reports/` with file counts.
Script: `~/.claude/skills/memory-bank/scripts/mb-index.sh`.

---

## Who updates files


| Work                                                                            | Owner                                                     |
| ------------------------------------------------------------------------------- | --------------------------------------------------------- |
| Mechanical actualization (`checklist` ⬜→✅, `progress` append, `STATUS` metrics) | MB Manager (sonnet subagent)                              |
| Plan creation (`plans/`)                                                        | Main agent (requires depth, DoD, TDD)                     |
| Architectural decisions (ADR)                                                   | Main agent formulates → MB Manager stores in `backlog.md` |
| ML result interpretation                                                        | Main agent interprets → MB Manager updates `research.md`  |


---

## Key Rules

- `progress.md` = **APPEND-ONLY** (never delete/edit old entries)
- Numbering is global: H-NNN, EXP-NNN, ADR-NNN (never reuse)
- `notes/` = knowledge and patterns (5-15 lines), **not chronology**
- `checklist`: ✅ = done, ⬜ = todo. Update **immediately** when a task is completed
- Each hypothesis must have: metric + threshold (`target`) + EXP reference after verification
- Forbidden: a hypothesis without a metric, an experiment without a hypothesis
- A Finding = a confirmed fact after a statistically significant result. Do not delete it

---

## File Formats (short)

Full templates → `~/.claude/skills/memory-bank/references/templates.md`

### status.md

```markdown
# <Project>: Status

## Current Phase
## Key Metrics
## Roadmap (✅ Done / 🔄 In Progress / 📋 Next / 🔮 Horizon)
## Gates (phase transition criteria)
## Known Constraints
```

### research.md

```markdown
# Research Log

## Hypotheses
| ID | Hypothesis | Status | Metric | Target | Result | EXP |
Statuses: 📋 PLANNED → 🔬 TESTING → ✅ CONFIRMED / 🔴 REFUTED / ⚠️ INCONCLUSIVE

## Confirmed Findings
## Current Experiment
```

### backlog.md

```markdown
## Ideas (HIGH / MEDIUM / LOW)
## Architectural Decisions (ADR)
## Rejected Ideas
```

### experiments/EXP-NNN

```markdown
## Meta (date, hypotheses, git hash, config, hardware)
## Setup (arms, epochs, parameters)
## Results (metrics table)
## Statistical Tests (Welch t-test, Cohen's d, p-value)
## Conclusions + Decision (Keep / Rollback / Repeat)
```

---

## Rule profiles

`/mb profile` (`mb-profile.sh`) personalizes the **configurable** rules layer per stack — the immutable safety baseline (TDD, no-placeholders, protected files, verification-before-completion) always stays.

```bash
/mb profile init --scope=project --role=backend --stack=go --architecture=microservices --delivery=contract-first
/mb profile init --scope=user --role=frontend --stack=typescript   # works even without a project bank
/mb profile show | path | validate | set
```

- **Dimensions**: `role`, `stack`, `architecture`, `delivery`.
- **Scopes**: `user` (cross-project) and `project` (precedence: project > user > skill defaults).
- Enforced through `mb-rules-check.sh` (profile-aware: `mb_rules_check_profile.sh` + `mb_rules_check_stack.sh` add stack/FSD-specific checks on top of the baseline).
- Schema: `references/rules-profile.schema.md`.

---

## Private content — `<private>…</private>`

Markdown syntax to exclude secrets / PII (client data, API keys, partner names) from indexing and search:

```markdown
Discussed with <private>Jane Doe, +1-555-***</private>; key <private>sk-abc123…</private>.
```

- Content inside `<private>…</private>` does **not** enter `index.json` (neither summary nor tags); the entry gets `has_private: true`.
- `mb-search` redacts it as `[REDACTED]` / `[REDACTED match in private block]`.
- An unclosed `<private>` makes the rest of the file private (fail-safe).
- `hooks/file-change-log.sh` warns when committing a file with `<private>` blocks.
- Reveal requires double opt-in: `MB_SHOW_PRIVATE=1 mb-search --show-private <query>`.
- **Caveat:** protects `index.json` / `mb-search`, NOT `git diff`. For full protection use `.gitattributes` filters or git hooks.

---

## `.memory-bank/` vs native auto-memory

Claude Code's built-in **auto memory** (`~/.claude/projects/.../memory/`) complements `.memory-bank/`; they do not replace each other.

| Aspect | `.memory-bank/` | Native auto-memory |
|--------|------------------|--------------------|
| Scope | Project | User, cross-project |
| Stores | Status, plans, checklists, research, ADRs, lessons | Preferences, role, feedback |
| Owner | Team (via git) | Individual user |

**Rule of thumb:** if it helps a teammate pick up the project tomorrow → `.memory-bank/`. If it helps *you* in another project → native memory. Do not duplicate one into the other.

---

## Design contract

Memory Bank rests on one inviolable promise — **agents remember** — and a stack of configurable, token-economical layers above it:

- **Defaults never change without explicit opt-in.** Base outputs (e.g. `/mb graph`) stay byte-identical when opt-in layers are off.
- **Expensive paths are off by default.** Embeddings, co-change edges, wiki, tree-sitter, scenario/test enforcement — all opt-in, with graceful degradation when an optional dependency is absent (never block the task).
- **User customisations survive upgrades.** Profiles, hooks tagged `_mb_owned`, project-local scripts are preserved.
- **Fail open.** Missing/stale graph, missing semantic provider, unavailable native extension → degrade to `rg`/read + surface a one-line fix hint; never hard-fail core memory.

Full contract: `references/design-principles.md`.
