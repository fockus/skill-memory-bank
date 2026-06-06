# Global Rules

> Universal coding and process rules.
> Apply to ALL projects. Project-specific rules belong in the repository root `RULES.MD`.

---

## CRITICAL — violation means failure

1. **Language**: follow the configured project/install language preference. English is the default. Technical terms may remain in English.
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
**Subagent**: MB Manager (sonnet) — for mechanical actualization. Prompt: `~/.claude/skills/memory-bank/agents/mb-manager.md`
**Plan Verifier**: `~/.claude/skills/memory-bank/agents/plan-verifier.md`

---

## `/mb` Commands


| Command                   | Description                                                                                                  |
| ------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `/mb` or `/mb context`    | Gather project context (status, checklist, plan)                                                             |
| `/mb start`               | Extended session start (context + full active plan)                                                          |
| `/mb search <query>`      | Search the bank by keywords                                                                                  |
| `/mb note <topic>`        | Create a note for the topic                                                                                  |
| `/mb update`              | Actualize core files (`checklist`, `plan`, `status`)                                                         |
| `/mb tasks`               | Show unfinished tasks                                                                                        |
| `/mb index`               | Registry of all bank entries (core files + notes/plans/experiments/reports with counts)                      |
| `/mb done`                | End the session (actualize + note + progress)                                                                |
| `/mb plan <type> <topic>` | Create a plan (`type`: `feature`, `fix`, `refactor`, `experiment`)                                           |
| `/mb verify`              | Verify plan execution (plan vs code, all DoD items). **MANDATORY** before `/mb done` if work followed a plan |
| `/mb init`                | Initialize Memory Bank in a new project                                                                      |


---

## `.memory-bank/` Structure

**Core (read every session):**


| File           | Purpose                                             | When to update                                          |
| -------------- | --------------------------------------------------- | ------------------------------------------------------- |
| `status.md`    | Where we are, roadmap, key metrics, gates           | Stage completed, roadmap shifted, metrics changed       |
| `checklist.md` | Current tasks ✅/⬜                                   | Every session, immediately when a task is completed     |
| `roadmap.md`      | Priorities and direction                            | When the focus/vector changes                           |
| `research.md`  | Hypothesis registry + findings + current experiment | When hypothesis status changes or a new finding appears |


**Detailed records (read on demand):**


| File / Folder  | Purpose                                           | When to update                                    |
| -------------- | ------------------------------------------------- | ------------------------------------------------- |
| `backlog.md`   | Ideas, ADRs, rejected items                       | When a new idea or architectural decision appears |
| `progress.md`  | Completed work by date                            | End of session (append-only)                      |
| `lessons.md`   | Repeated mistakes, anti-patterns                  | When a pattern is noticed                         |
| `experiments/` | `EXP-NNN_<n>.md` — detailed ML experiment records | When an experiment is completed                   |
| `plans/`       | `YYYY-MM-DD_<type>_<n>.md` — detailed plans       | Before complex work                               |
| `reports/`     | `YYYY-MM-DD_<type>_<n>.md` — reports              | When useful for future sessions                   |
| `notes/`       | `YYYY-MM-DD_HH-MM_<topic>.md` — task notes        | After completing a task                           |
| `codebase/`    | Codebase map: `STACK.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `CONCERNS.md` (+ `graph.json`, `god-nodes.md`). Generated by `mb-codebase-mapper` subagent via `/mb map` / `/mb graph`, consumed by `/mb context` | After `/mb init`, stack change, or major refactor (`/mb map [focus]`) |


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

## Code Graph — usage

`.memory-bank/codebase/graph.json` encodes the structural layer of the project (module/function/class nodes + import/call edges) in JSON Lines format. Use it in place of `grep -rn` for **structural** questions — deterministic, fast, and semantically grounded.

### Data schema

```jsonc
// Nodes
{"type":"node", "kind":"module",   "name":"path/to/file.ext", "file":"...", "line":1}
{"type":"node", "kind":"function", "name":"FuncName",         "file":"...", "line":N}
{"type":"node", "kind":"class",    "name":"ClassName",        "file":"...", "line":N}
// Optional: "community":N — Louvain cluster id, added when networkx is installed.

// Edges
{"type":"edge", "kind":"import", "src":"path/to/src.file", "dst":"pkg/import/path"}
{"type":"edge", "kind":"call",   "src":"path/to/src.file", "dst":"FuncOrMethodName"}
// Opt-in edge kinds (off by default — base graph stays byte-identical):
{"type":"edge", "kind":"co_change", "src":"file/a", "dst":"file/b", "weight":N}                       // git history (--cochange)
{"type":"edge", "kind":"semantic",  "src":"file/a", "dst":"file/b", "confidence":0.0-1.0, "rationale":"..."}  // LLM wiki (/mb wiki)
// IMPORTANT: src = source file path; dst = function name / import path
// IMPORTANT: inherit edges — Python stdlib-ast only. Tree-sitter extractors for Go/JS/TS/Rust/Java do NOT emit inherit edges (type inference is absent).
```

### Basic jq queries

```bash
# 1. Which files call function X?
jq -r 'select(.type=="edge" and .kind=="call" and .dst=="X") | .src' \
  .memory-bank/codebase/graph.json | sort -u

# 2. All functions defined in a directory
jq -c 'select(.type=="node" and .kind=="function" and (.file|startswith("src/service/")))' \
  .memory-bank/codebase/graph.json | head -20

# 3. What does a specific file import?
jq -r 'select(.type=="edge" and .kind=="import" and .src=="src/service/context.py") | .dst' \
  .memory-bank/codebase/graph.json

# 4. Which files import a particular package?
jq -r 'select(.type=="edge" and .kind=="import" and .dst=="my_project/utils") | .src' \
  .memory-bank/codebase/graph.json | sort -u

# 5. Top god-nodes for refactoring
head -25 .memory-bank/codebase/god-nodes.md
```

### Practical use cases

```bash
# IMPACT ANALYSIS — how many files would be affected by changing a signature?
jq -r 'select(.type=="edge" and .kind=="call" and .dst=="WriteFile") | .src' \
  .memory-bank/codebase/graph.json | sort -u | wc -l

# ONBOARDING — survey an unfamiliar module
MODULE="src/service/codeagent"
jq -c 'select(.type=="node" and (.file|startswith("'$MODULE'/")))' .memory-bank/codebase/graph.json
jq -r 'select(.type=="edge" and .kind=="import" and (.src|startswith("'$MODULE'/"))) | .dst' \
  .memory-bank/codebase/graph.json | sort -u   # external deps of the module

# DEAD CODE — functions with no incoming call edges (removal candidates)
jq -r 'select(.type=="node" and .kind=="function") | .name' .memory-bank/codebase/graph.json \
  | sort -u > /tmp/defined.txt
jq -r 'select(.type=="edge" and .kind=="call") | .dst' .memory-bank/codebase/graph.json \
  | sort -u > /tmp/called.txt
comm -23 /tmp/defined.txt /tmp/called.txt | head
# CAVEAT: exported funcs may be called from outside, main/init/Test* have special lifecycles

# HYBRID (graph → grep) — find callers via graph, then read context via rg
files=$(jq -r 'select(.type=="edge" and .kind=="call" and .dst=="WriteFile") | .src' \
  .memory-bank/codebase/graph.json | sort -u)
for f in $files; do rg "WriteFile\(" "$f" -n | head -1; done

# REVERSE DEPENDENCIES — who depends on a given package (1-hop transit)
jq -r 'select(.type=="edge" and .kind=="import" and (.dst|contains("internal/core/toolnames"))) | .src' \
  .memory-bank/codebase/graph.json | sort -u
```

### Decision table — graph vs grep/code-read

| Question | Tool | Why |
|---|---|---|
| "Where is X called?" | **graph** | Deterministic, no noise from strings/comments |
| "What does Y import?" | **graph** | Exact structure, transitive via repeated queries |
| "How many callers does a function have?" | **graph** | Count edges |
| "Where is the string 'TODO: legacy'?" | **rg/grep** | Not a structural question |
| "Who implements interface I?" | **rg/grep + Read** | Graph does not resolve interface-implements (no type inference) |
| "What methods does struct S have?" | **rg/grep + Read** | Methods-on-receiver are not graph edges |
| "Complexity hotspots" | **`god-nodes.md` + `wc -l`** | Ready-made top-20 + real LoC |
| "Diff between branch and main" | **`git diff`** | Graph does not track VCS |

### Caveats

- **Name-only resolution.** The graph matches calls by name only (no type inference). Generic names (`Error`, `New`, `String`, `Run`, `Close`, `Background`, `Now`, `Execute`) in `god-nodes.md` are lexical false-positives — they catch stdlib interface calls. Filter generics when analysing top-degree nodes.
- **Vendored code.** By default `skip_dirs = {.venv, __pycache__, node_modules, .git, target, dist, build}`. Projects with `vendor/` or `third_party/` (e.g. Go projects vendoring langchaingo) need a **project-local patched copy** in `.memory-bank/scripts/mb-codegraph-local.py` that adds those paths to `skip_dirs`. Run with: `PYTHONPATH="$HOME/.claude/skills/memory-bank" python3 .memory-bank/scripts/mb-codegraph-local.py --apply`.
- **Language coverage.** Python always works (stdlib `ast`). Go / JS / TS / Rust / Java require `pip install tree-sitter tree-sitter-<lang>` (opt-in). Without tree-sitter, non-Python files are silently skipped (graceful degradation).
- **Rebuild cost.** Incremental via SHA256 cache in `.cache/` — unchanged files are skipped. First run on a 1000-file project: ~3-5 min. Subsequent runs: seconds.

### When to rebuild

- Major refactor / new modules / moved packages → `/mb graph --apply && /mb map`
- Weekly or when you notice drift → `/mb map`
- Per focus area after a feature → `/mb map concerns` or `/mb map arch`

### Automation

For repeated queries, create project-local aliases/scripts under `.memory-bank/scripts/` — keep them project-scoped, never globalize.

### Intelligence layer (opt-in) — suggested questions · semantic search · wiki

Beyond the deterministic structural graph, three **opt-in** layers add what plain AST/import edges cannot see. All are off by default — base `/mb graph` output stays byte-identical, and none add a mandatory dependency (graceful degradation when an optional one is absent).

- **Suggested questions** — `/mb graph --apply --questions`. Appends a *"Suggested questions"* section to `god-nodes.md`: deterministic, $0 starting points derived from graph structure (highest-degree symbols, bridge files by betweenness, large / low-cohesion clusters, co-changing pairs). Use it to orient in an unfamiliar codebase before diving in.
- **Co-change edges** — `/mb graph --apply --cochange`. Adds `co_change` edges from **git history** (files that change together across commits) — coupling the static graph misses. Query: `jq -c 'select(.type=="edge" and .kind=="co_change")' .memory-bank/codebase/graph.json`. High co-change with **no** structural edge = hidden/implicit coupling worth a second look.
- **Semantic search** — `python3 ~/.claude/skills/memory-bank/scripts/mb-semantic-search.py "<query>" [--backend auto|bm25|embeddings] [--k N]`. Answers *"where is the logic for X?"* by ranking graph symbols (+ wiki articles, if built) by relevance. Default backend is pure-Python **BM25** ($0, zero deps, deterministic); `--backend embeddings` uses local `sentence-transformers` when installed, else falls back to BM25. Use it for fuzzy/intent queries; use `jq`/structural queries for exact "who-calls-X".
- **Wiki + surprising connections** — `/mb wiki` (LLM, via host subagents — **no API key**). **Haiku** writes one article per community → `codebase/wiki/community-<N>.md` + `index.md`; **Sonnet** finds *surprising connections* (semantically related files with **no** import/call/inherit edge) and merges them as `semantic` edges (`confidence` + `rationale`, validated + **idempotent**). The wiki articles also feed semantic search. Run/refresh after a major feature when you want a navigable map + the non-obvious links the static graph cannot derive. `--dry-run` previews the dispatch plan without spending tokens.

**Routing for the code-agent:** exact structural question ("who calls / imports / inherits X?") → `jq` over `graph.json`; intent/fuzzy ("where is the logic for X?", "find similar") → `mb-semantic-search.py`; "what else changes with this file?" → `co_change` edges; "give me a map / the non-obvious links" → `/mb wiki`. **Fail open:** missing/stale graph → suggest `/mb graph --apply`; missing optional dep (`networkx` for communities, `sentence-transformers` for embeddings) → degrade and surface the one-line install, never block the task.

### Session memory — cross-session recall

The skill logs every session to `.memory-bank/session/*.md` (git-tracked markdown) via lifecycle hooks (Stop → per-turn bullet, SessionEnd → Haiku summary + gated Sonnet auto-notes, SessionStart → injects recent sessions). This is **persistent project memory that carries across chats**, distinct from the codebase graph.

- **`/mb recall <query>`** — lexical recall (ripgrep) over `session/` + `notes/`. Use for *"did we discuss X before?"*, *"why did we choose Y?"*, *"have we hit this error?"* — before re-deriving something from scratch.
- Distinct from `/mb search` (searches core MB files) and from semantic code search (`mb-semantic-search.py`, searches the code graph). Session memory = conversation history; code graph = structure; core files = status/plan.
- **Off-switch:** `export MB_SESSION_CAPTURE=off` disables capture. Recall stays read-only and safe even when capture is off.

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

