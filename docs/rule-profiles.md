# Rule Profiles & Stack Presets

Comprehensive guide to Memory Bank rule profiles: what they are, how they compose, and how to use them.

---

## What and why

**Problem:** A single hard-coded ruleset cannot fit Go microservices, React/FSD frontends, Android UDF apps, Python data services, and Java DDD services equally well. These stacks have genuinely different best practices.

**Solution:** Rule profiles let you add configurable, stack-specific guidance on top of the always-on immutable safety baseline. You pick a role, stack, architecture, and delivery method; Memory Bank applies the matching built-in presets. Nothing in the configurable layer can weaken the safety baseline.

**Immutable baseline:** Always active. See the full list in the [Immutable Baseline](#immutable-baseline) section below.

**Configurable layer:** role presets, stack presets, architecture presets, delivery presets — all optional. Skipping a profile means only the immutable baseline applies, which is a safe and valid choice.

---

## Precedence model

Resolution order (strongest last — later layers override earlier ones):

```
built-in configurable defaults
  │
  ▼
user global profile
  (<agent-config>/memory-bank/rules-profile.json)
  │
  ▼
project Memory Bank profile
  (<resolved-mb>/rules-profile.json)
  │
  ▼
task instruction
  (this run only; cannot weaken immutable baseline)

+ IMMUTABLE SAFETY BASELINE  ← always wins, non-overridable
```

- **No Memory Bank:** user global profile + immutable baseline. No project files exist; `[MEMORY BANK: ABSENT]` is printed.
- **Local or global Memory Bank:** project profile overrides user profile for every dimension it sets. Unset dimensions inherit from the user profile.
- **Task instruction:** can adjust `strictness` for a single run only. Cannot disable any immutable rule.

---

## Schema

Full specification: `references/rules-profile.schema.md`.

**Top-level fields:**

| Field | Type | Required | Allowed values |
|-------|------|----------|----------------|
| `schema_version` | int | yes | `1` |
| `scope` | string | yes | `user`, `project` |
| `role` | string | yes | `backend`, `frontend`, `mobile` |
| `stack` | string | yes | `go`, `python`, `javascript`, `typescript`, `java`, `generic` |
| `architecture` | string | yes | `clean`, `hexagonal`, `modular-monolith`, `microservices`, `ddd`, `fsd`, `mobile-udf`, `event-driven`, `custom` |
| `delivery` | string | yes | `tdd`, `contract-first`, `api-first`, `sdd`, `legacy-safe`, `exploratory` |
| `strictness` | string | no (default `warn`) | `advisory`, `warn`, `block` |
| `extras` | object | no | free-form; unknown keys ignored by consumers |

**Example JSON profile:**

```json
{
  "schema_version": 1,
  "scope": "project",
  "role": "backend",
  "stack": "go",
  "architecture": "microservices",
  "delivery": "contract-first",
  "strictness": "warn"
}
```

**JSON is canonical runtime format.** YAML examples appear in documentation only and must be converted to JSON by `mb-profile.sh` before storage. The runtime parser uses Python stdlib `json` — no runtime YAML dependency.

---

## Built-in presets

All preset files live under `references/rules-presets/`. Each preset defines rule IDs, severity defaults, and compact guidance text. Resolved prompt summaries stay under 4 KB.

### Role presets

| File | Description |
|------|-------------|
| `references/rules-presets/roles/backend.json` | Backend service developer: interface boundaries, DI, repository abstractions, integration tests. |
| `references/rules-presets/roles/frontend.json` | Frontend developer: component composition, public-API boundaries, accessibility, component tests. |
| `references/rules-presets/roles/mobile.json` | Mobile developer: UDF, immutable UI state, offline-first, viewmodel/usecase/repo separation. |

### Stack presets

| File | Description |
|------|-------------|
| `references/rules-presets/stacks/go.json` | Go stack: context propagation, goroutine safety, small interfaces, table-driven tests, error wrapping. |
| `references/rules-presets/stacks/python.json` | Python stack: type hints, DI, pytest naming, no business logic in mocks, fail-fast tracebacks. |
| `references/rules-presets/stacks/javascript.json` | JavaScript stack: ESM imports, strict mode, no implicit coercions, colocated test files. |
| `references/rules-presets/stacks/typescript.json` | TypeScript stack: strictNullChecks, no any, branded types where useful, type tests for public API. |
| `references/rules-presets/stacks/java.json` | Java stack: package boundaries, interfaces for repositories/gateways, immutable DTOs, JUnit naming. |
| `references/rules-presets/stacks/generic.json` | Language-agnostic safety baseline: always present when stack is unrecognized or mixed. |

### Architecture presets

| File | Description |
|------|-------------|
| `references/rules-presets/architecture/clean.json` | Clean Architecture: Infra→App→Domain layer direction, pure domain, DIP. |
| `references/rules-presets/architecture/hexagonal.json` | Hexagonal (Ports & Adapters): ports in domain, adapters in infra, no framework leakage into core. |
| `references/rules-presets/architecture/modular-monolith.json` | Modular Monolith: explicit module contracts, no cross-module internal access. |
| `references/rules-presets/architecture/microservices.json` | Microservices: service boundaries, contract checks, distributed tracing, no cross-service DB sharing. |
| `references/rules-presets/architecture/ddd.json` | Domain-Driven Design: bounded contexts, aggregates, repositories as interfaces. |
| `references/rules-presets/architecture/fsd.json` | Feature-Sliced Design: layer direction app→pages→widgets→features→entities→shared, public slice API. |
| `references/rules-presets/architecture/mobile-udf.json` | Mobile UDF: View→ViewModel→UseCase→Repository→DataSource layering, single source of truth. |
| `references/rules-presets/architecture/event-driven.json` | Event-Driven Architecture: event versioning, idempotency, dead-letter handling. |

### Delivery presets

| File | Description |
|------|-------------|
| `references/rules-presets/delivery/tdd.json` | Test-Driven Development: tests before code, RED→GREEN→REFACTOR, naming convention. |
| `references/rules-presets/delivery/contract-first.json` | Contract-First: define proto/openapi/asyncapi contract, write contract tests, then implement. |
| `references/rules-presets/delivery/api-first.json` | API-First: schema before client/server, schema versioning, backward compatibility policy. |
| `references/rules-presets/delivery/sdd.json` | Spec-Driven Development: REQ ids, specs/tasks traceability, covers_requirements in plans. |
| `references/rules-presets/delivery/legacy-safe.json` | Legacy-Safe: characterize-before-change, golden tests, test-after-remediation allowed for existing code. |
| `references/rules-presets/delivery/exploratory.json` | Exploratory prototype: time-boxed, no production wiring, must end with a plan or be discarded. |

---

## Examples

### 1. Backend Go microservice + contract-first

```bash
mb-profile.sh init \
  --scope=project \
  --role=backend \
  --stack=go \
  --architecture=microservices \
  --delivery=contract-first
```

Expected `.memory-bank/rules-profile.json`:

```json
{
  "schema_version": 1,
  "scope": "project",
  "role": "backend",
  "stack": "go",
  "architecture": "microservices",
  "delivery": "contract-first",
  "strictness": "warn"
}
```

Resolved prompt summary includes: context propagation, goroutine safety, small interfaces, service ownership, contract before impl, no cross-service DB sharing, interface boundaries, integration tests primary.

---

### 2. Frontend TypeScript + FSD + SDD

```bash
mb-profile.sh init \
  --scope=project \
  --role=frontend \
  --stack=typescript \
  --architecture=fsd \
  --delivery=sdd
```

Expected `.memory-bank/rules-profile.json`:

```json
{
  "schema_version": 1,
  "scope": "project",
  "role": "frontend",
  "stack": "typescript",
  "architecture": "fsd",
  "delivery": "sdd",
  "strictness": "warn"
}
```

Resolved prompt summary includes: public slice API, import direction (app→pages→widgets→features→entities→shared), strictNullChecks, no any, REQ ids and traceability, specs before tasks.

---

### 3. Mobile generic + UDF + API-first

```bash
mb-profile.sh init \
  --scope=user \
  --role=mobile \
  --stack=generic \
  --architecture=mobile-udf \
  --delivery=api-first
```

Expected `~/.claude/memory-bank/rules-profile.json`:

```json
{
  "schema_version": 1,
  "scope": "user",
  "role": "mobile",
  "stack": "generic",
  "architecture": "mobile-udf",
  "delivery": "api-first",
  "strictness": "warn"
}
```

Resolved prompt summary includes: UDF flow (View→ViewModel→UseCase→Repository→DataSource), immutable UI state, single source of truth in Repository, schema before client/server, backward compatibility.

---

### 4. Python data service + modular-monolith + TDD

```bash
mb-profile.sh init \
  --scope=project \
  --role=backend \
  --stack=python \
  --architecture=modular-monolith \
  --delivery=tdd
```

Expected `.memory-bank/rules-profile.json`:

```json
{
  "schema_version": 1,
  "scope": "project",
  "role": "backend",
  "stack": "python",
  "architecture": "modular-monolith",
  "delivery": "tdd",
  "strictness": "warn"
}
```

Resolved prompt summary includes: type hints, pytest naming, explicit module boundaries, no cross-module internal access, tests-first (RED→GREEN→REFACTOR), no business logic in mocks.

---

### 5. Java DDD service + API-first

```bash
mb-profile.sh init \
  --scope=project \
  --role=backend \
  --stack=java \
  --architecture=ddd \
  --delivery=api-first
```

Expected `.memory-bank/rules-profile.json`:

```json
{
  "schema_version": 1,
  "scope": "project",
  "role": "backend",
  "stack": "java",
  "architecture": "ddd",
  "delivery": "api-first",
  "strictness": "warn"
}
```

Resolved prompt summary includes: bounded contexts, aggregates, repositories as interfaces, package boundaries, schema before code, schema versioning, backward compatibility.

---

## Rules-only mode

A **user-global profile** applies personalized rules even when no project Memory Bank exists:

```
Project state: [MEMORY BANK: ABSENT]
User-global profile: ~/.claude/memory-bank/rules-profile.json
Result: backend/go/microservices rules active + immutable baseline active
        No project files created; /mb lifecycle stays inactive
```

Usage:

```bash
# Initialize once, applies to all projects on this machine:
mb-profile.sh init --scope=user --role=backend --stack=go \
  --architecture=clean --delivery=tdd

# Verify active profile:
mb-profile.sh show
```

The user-global profile is purely additive — it does not create any files in the project directory and does not activate Memory Bank lifecycle commands. Run `/mb init` separately when you want to activate Memory Bank in a project.

---

## Migration

Existing repositories with `RULES.md` or `.memory-bank/RULES.md` keep working without any changes. Rule profiles are an additive layer — they do not modify, replace, or disable existing `RULES.md` files. The immutable baseline from `RULES.md` continues to apply as-is; profiles add configurable stack/architecture guidance on top.

To add a profile to an existing project:

```bash
mb-profile.sh init --scope=project --role=backend --stack=python
```

---

## Immutable baseline

The following 7 rules are always active. They **cannot be disabled** by any profile, task instruction, or user choice. A profile that attempts to disable any of them is rejected at validation time.

| Rule ID | What it enforces | Rationale |
|---------|-----------------|-----------|
| `no-placeholders` | No `TODO`, `...`, or pseudocode in production code | Placeholders shipped to production cause silent failures and waste review cycles |
| `protected-files` | `.env`, `ci/`, Docker/K8s/Terraform require explicit user request | Accidental infra changes can take down production |
| `destructive-confirm` | Force-push, hard-reset, mass-delete require explicit confirmation | Destructive operations cannot be undone; human confirmation is non-negotiable |
| `fail-fast` | Uncertain implementation → stop and propose a short plan | Guessing wastes time and creates subtle bugs that are hard to trace |
| `dry-kiss-yagni` | DRY/KISS/YAGNI baseline | Code written for imagined futures adds maintenance cost with no present benefit |
| `verification-before-completion` | Claim "done" only after running declared verification commands | Unverified "done" means the next session starts with broken code |
| `explicit-storage-choice` | Tooling never silently writes profiles or banks outside the chosen scope | Surprise writes to `~/.claude/` or the project tree violate user trust |

A profile may **strengthen** these rules (e.g. set `strictness=block` for a configurable rule) but never weaken them.

---

## JSON canonical vs YAML docs-only

**Canonical machine format is JSON.** Runtime files (`rules-profile.json`, `rules-presets/*.json`) use JSON parsed through Python stdlib `json` — no runtime YAML dependency is added.

**YAML is for documentation only.** YAML examples may appear in docs or inline command help. Before a YAML example can be stored as a profile, it must be converted to JSON by `mb-profile.sh` or an equivalent tool.

This decision is intentional and explicit. Mixing JSON and YAML as equivalent runtime formats would require adding `PyYAML` as a mandatory runtime dependency, which conflicts with the skill's zero-extra-dependency design.
