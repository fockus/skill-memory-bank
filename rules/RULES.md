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

## Source of Truth — planning chain

If a project has Memory Bank (`.memory-bank/`), planning and implementation flow through one chain:

```
plan.md ("Active plan" field → link to file)
    ↓
plans/<file>.md  ← Source of truth: tasks, DoD, stages
    ↓
checklist.md     ← Tracking: ✅ done, ⬜ remaining
    ↓
STATUS.md        ← Phase, blockers, audit findings
```

### Consistency rules

1. **A new plan** (`/mb plan`) MUST be reflected in all three places:
  - `plans/<file>.md` — detailed plan with DoD
  - `plan.md` — link in the "Active plan" field + updated focus
  - `STATUS.md` — updated roadmap ("In Progress" section)
  - `checklist.md` — plan tasks represented as ⬜ items
2. **Tasks come ONLY from the detailed plan**. Do not invent off-plan tasks.
3. `**checklist.md` reflects the plan**: each stage in `plans/<file>.md` = one ⬜ item in the checklist.
4. `**STATUS.md` reflects facts**: update the roadmap on actual completion, not on planning.
5. **When the active plan changes**: update `plan.md` + `STATUS.md` + `checklist.md`.
6. **When a plan is completed**: move it to `plans/done/`, then update `plan.md`, `STATUS.md`, and `checklist.md`.

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
- If Memory Bank exists → put ADRs in `.memory-bank/BACKLOG.md`

### Response format

- Structure: **Goal → Action → Result**
- If Memory Bank is active: start with `[MEMORY BANK: ACTIVE]`
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
| `STATUS.md`    | Where we are, roadmap, key metrics, gates           | Stage completed, roadmap shifted, metrics changed       |
| `checklist.md` | Current tasks ✅/⬜                                   | Every session, immediately when a task is completed     |
| `plan.md`      | Priorities and direction                            | When the focus/vector changes                           |
| `RESEARCH.md`  | Hypothesis registry + findings + current experiment | When hypothesis status changes or a new finding appears |


**Detailed records (read on demand):**


| File / Folder  | Purpose                                           | When to update                                    |
| -------------- | ------------------------------------------------- | ------------------------------------------------- |
| `BACKLOG.md`   | Ideas, ADRs, rejected items                       | When a new idea or architectural decision appears |
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

1. Check whether `.memory-bank/` exists → `[MEMORY BANK: ACTIVE]`
2. Read the 4 core files:
  - `STATUS.md` → where we are in the project, roadmap, gates
  - `checklist.md` → current tasks (⬜/✅)
  - `plan.md` → priorities and direction
  - `RESEARCH.md` → which hypotheses are active, current experiment
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
| A stage / milestone is completed | `STATUS.md`: update roadmap and metrics                          |
| Roadmap changed                  | `STATUS.md`: move items between sections                         |
| Key metrics changed              | `STATUS.md`: update the metrics section                          |
| New hypothesis                   | `RESEARCH.md`: add a table row (`📋 PLANNED`)                    |
| Start of an ML experiment        | `experiments/EXP-NNN_<n>.md` + status 🔬 in `RESEARCH.md`        |
| Experiment completed             | `RESEARCH.md`: status ✅/🔴/⚠️ + finding. `experiments/`: results |
| Architectural decision           | `BACKLOG.md`: ADR-NNN (context → decision → alternatives)        |
| Detailed multi-stage work        | `plans/`: create a file via `/mb plan <type> <topic>`            |
| Anti-pattern noticed             | `lessons.md`: add an entry with context                          |
| Focus/priorities changed         | `plan.md`: update it                                             |


### `/mb done` — end of session

1. **If work followed a plan** → run `/mb verify` **MANDATORILY** before `/mb done`:
  - Plan Verifier rereads the plan, checks `git diff`, and finds mismatches
  - CRITICAL → must be fixed
  - WARNING → optional / user decision
2. `checklist.md`: mark completed items ✅, add new items ⬜
3. `progress.md`: append to the end (APPEND-ONLY, never delete old entries)
4. `STATUS.md`: update if a milestone completed or the roadmap changed
5. `RESEARCH.md`: update if there are ML results (hypothesis status, finding)
6. `lessons.md`: add an entry if an anti-pattern was found
7. `BACKLOG.md`: add an item if there is a new idea or ADR
8. `plan.md`: update if the focus changed
9. `notes/`: create a note for the completed work

### `/mb update` — intermediate actualization

Subset of `/mb done`: updates only the core files (`checklist`, `plan`, `status`).
No note creation and no `progress` entry.
Use when: an intermediate stage is finished but the session continues.

### Before compaction

Run `/mb update` to save current progress BEFORE context compression.

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
- The information is already captured in `lessons.md` or `RESEARCH.md`

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
| Architectural decisions (ADR)                                                   | Main agent formulates → MB Manager stores in `BACKLOG.md` |
| ML result interpretation                                                        | Main agent interprets → MB Manager updates `RESEARCH.md`  |


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

### STATUS.md

```markdown
# <Project>: Status

## Current Phase
## Key Metrics
## Roadmap (✅ Done / 🔄 In Progress / 📋 Next / 🔮 Horizon)
## Gates (phase transition criteria)
## Known Constraints
```

### RESEARCH.md

```markdown
# Research Log

## Hypotheses
| ID | Hypothesis | Status | Metric | Target | Result | EXP |
Statuses: 📋 PLANNED → 🔬 TESTING → ✅ CONFIRMED / 🔴 REFUTED / ⚠️ INCONCLUSIVE

## Confirmed Findings
## Current Experiment
```

### BACKLOG.md

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

