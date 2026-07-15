# Engineering rules

Memory Bank ships an opinionated, non-negotiable engineering baseline that the
agent applies to every project — with or without an active bank. This page is
a condensed map of that baseline; the full text (with rationale, examples,
and edge cases) lives in [`rules/RULES.md`](../../rules/RULES.md), and it is
the tie-breaker whenever this page and the source disagree.

## Rules-only mode

`[MEMORY BANK: ABSENT]` is a valid, deliberate state — many projects (or
third-party repos you're just visiting) don't want `.memory-bank/`. In that
state the `/mb` lifecycle commands (`/mb start`, `/mb done`, …) stay inactive,
but **every rule below still applies** to ordinary code work: TDD, SOLID,
Clean Architecture / FSD, DRY/KISS/YAGNI, Testing Trophy, protected files, no
placeholders, verification before completion. The agent must not relax
discipline just because there is no bank to write to.

## Contract-First and TDD

1. **Contract-First**: define the interface (Protocol/ABC/type signature)
   first, write contract tests that verify the contract — not a specific
   implementation — then implement. Contract tests must pass for *any*
   correct implementation.
2. **TDD** (deterministic modules): Red → Green → Refactor — a failing test
   before the code, the minimum implementation to pass it, then refactor with
   tests green throughout.
3. **ML modules** use a variant: contract tests before implementation (shape,
   gradients, determinism, no NaN/Inf), statistical tests after (convergence,
   sanity checks, marked `slow`).
4. **Allowed skips**: typos, formatting, exploratory prototypes. Nothing else.

## Clean Architecture (backend)

Dependency direction is one-way: `Infrastructure → Application → Domain`,
never backward. **Domain** holds types/protocols/business logic with zero
external dependencies; **Application** holds use cases and depends on Domain;
**Infrastructure** holds frameworks/DB/HTTP/filesystem and depends on both.
Add `interfaces/` (delivery channels) and `di/` (the single composition root)
as outer layers when a project serves more than one channel. Pick one backend
macro-architecture per service — serverless, microservices, or modular
monolith — and record it; inside each, Clean Architecture's direction still
holds. In a modular monolith, sibling modules never import each other's
internals — only through a shared layer or a published contract.

## Feature-Sliced Design (frontend)

For React/Vue/Angular/Svelte, layers stack top-down and imports only flow
downward:

```
app → pages → widgets → features → entities → shared
```

Cross-slice imports within the same layer are forbidden (`features/auth` must
not import `features/cart` — compose in a `widget` or `page` instead); every
slice exposes its public surface through `index.ts`, never a deep import into
`model/` or `lib/`.

## SOLID thresholds

- **SRP**: more than 3 public methods of clearly different natures, or a class
  over ~300 lines, is a split candidate.
- **OCP**: extend via composition/Strategy, don't reopen old code with more
  `if/else`.
- **LSP**: a subtype must be substitutable everywhere the parent is used.
- **ISP**: an interface/Protocol should expose ≤5 methods; split fat
  interfaces.
- **DIP**: constructors accept abstractions (Protocol/ABC); factories build
  the concrete collaborators.

## DRY / KISS / YAGNI

Duplicate the same logic more than twice → extract (unless the similarity is
accidental — different domains, different reasons to change). Prefer three
repeated lines over a premature abstraction that needs a paragraph to explain.
Do not add config, flags, or layers for a need that doesn't exist yet.

## Testing Trophy

```
integration (primary focus) > unit > e2e
static analysis — always, every commit
```

Mock only external boundaries (DB, HTTP, filesystem, third-party services);
more than 5 mocks in one test is a signal you actually want an integration
test. Tests are named `test_<what>_<condition>_<result>` and assert a
business fact, not `result is not None`. Prefer `@parametrize` over
copy-pasted variations. E2E stays targeted to critical flows — it is
expensive and brittle by nature.

## Coverage targets

| Scope | Target |
|---|---|
| Overall | 85%+ |
| Core / business logic | 95%+ |
| Infrastructure / adapters | 70%+ |

Project-specific per-layer targets, if any, belong in the project's own
`RULES.md`, layered on top of — never below — these floors.

## Universal hygiene (always on)

- No placeholders: no `TODO`, `...`, or pseudocode in code presented as done
  (a staged stub behind a feature flag, with a docstring, is the one
  exception).
- Protected files (`.env`, `ci/**`, Docker/K8s/Terraform) are never touched
  without an explicit request.
- Destructive actions only after explicit confirmation.
- A multi-file change gets a short plan before implementation, not
  improvisation file-by-file.
- Significant architectural decisions get an ADR (context → decision →
  alternatives → consequences), recorded in `backlog.md` when a bank exists.

See [`rules/RULES.md`](../../rules/RULES.md) for the full text, mobile
(iOS/Android) architecture rules, and the ML-specific hygiene rules (device
handling, seeding, checkpoints, numerical stability) not repeated here.
