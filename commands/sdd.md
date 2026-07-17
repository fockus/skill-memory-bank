---
description: Create a Kiro-style spec triple — specs/<topic>/{requirements,design,tasks}.md
allowed-tools: [Bash, Read, Write]
---

# /mb sdd <topic>

Create a Kiro/Kilo-compatible spec triple under `.memory-bank/specs/<topic>/`. Each file has a single concern: **requirements** (Kiro User Stories + EARS acceptance criteria — hybrid format), **design** (architecture + interfaces + decisions), **tasks** (numbered checkbox work items).

## Hybrid requirements format

`requirements.md` pairs the two industry conventions instead of choosing one:

- **Kiro User Story** per requirement — `### Requirement N` + `**User Story:** As a <role>, I want <feature>, so that <benefit>.` (the "who / why").
- **EARS acceptance criteria** under each — a `#### Acceptance Criteria` heading with `- **REQ-NNN**: WHEN ... THE SYSTEM SHALL ...` bullets in the 5 EARS patterns, uppercase keywords (the testable "what"). `mb-ears-validate.sh` is case-insensitive and validates only these bullets; User-Story lines are ignored, so the two layers coexist with zero tooling conflict.

REQ-IDs stay unique and traceable; `mb-traceability-gen.sh` and `**Covers:** REQ-NNN` in `tasks.md` are unaffected by the grouping.

## Why split into three?

- Parallel work — requirements / design / tasks evolve at different speeds.
- `requirements.md` stays self-contained and exportable to Kiro.
- `tasks.md` is checkbox-compatible with downstream tools.
- `mb-traceability-gen.sh` (Phase 1 Sprint 2) automatically picks up REQ-IDs from `specs/*/requirements.md` for the REQ → Plan → Test matrix.

## When to use

After `/mb discuss <topic>` produced an EARS-validated `context/<topic>.md`, when the work is large enough to need a dedicated spec triple (multi-sprint feature, cross-cutting refactor, new subsystem). For small fixes, `/mb plan` alone is enough.

## Arguments

- `<topic>` — short slug (kebab-case). Becomes the directory name `specs/<topic>/`.
- `--force` — overwrite existing spec triple. Without `--force`, the script refuses if `specs/<topic>/` already exists.

## Behavior

1. Resolve `<mb>` (skip if `.memory-bank/` is missing — suggest `/mb init`).
2. Sanitize topic to ASCII slug.
3. Refuse if `specs/<safe_topic>/` already exists and `--force` was not given.
4. Create `specs/<safe_topic>/` and write three files:
   - `requirements.md` — header + EARS reference + `## Requirements (EARS)` with a `### Requirement 1` **User Story** scaffold and a `#### Acceptance Criteria` block. If `<mb>/context/<safe_topic>.md` exists, the `## Functional Requirements (EARS)` block is copied verbatim into the acceptance criteria (REQ-IDs preserved); the author groups the bullets under user stories and splits into more `### Requirement N` blocks as needed.
   - `design.md` — Architecture / Interfaces / Decisions / Risks scaffold with a Protocol example.
   - `tasks.md` — numbered tasks with `**Covers:** REQ-NNN` placeholders and unchecked checkboxes.
5. Print the three created paths to stdout.

## Underlying script

```bash
bash scripts/mb-sdd.sh <topic> [--force] [mb_path]
```

## Typical flow

```
User: /mb discuss inventory-sync
→ produces context/inventory-sync.md (EARS-validated)

User: /mb sdd inventory-sync
→ writes:
  specs/inventory-sync/requirements.md   # EARS copied from context
  specs/inventory-sync/design.md         # blank design scaffold
  specs/inventory-sync/tasks.md          # numbered tasks scaffold

User: /mb plan feature inventory-sync --sdd
→ plan with `## Linked context` section pointing at context/inventory-sync.md
  (--sdd refuses to create plan unless EARS-valid context exists)

User: edits design.md / tasks.md by hand, then runs:
      /mb plan feature inventory-sync-stage-1 --sdd
→ next plan in the same Phase, also linked to the spec
```

## tasks.md format — executable task blocks

The generated `tasks.md` uses `<!-- mb-task:N -->` HTML comment markers so that
`mb_work_items.py` (and `/mb work <topic>`) can parse tasks as structured work items:

```markdown
<!-- mb-task:1 -->
## 1. <task title>

**Covers:** REQ-NNN
**Role:** <implementer role>
**What:** <concrete actions>
**Testing:** <unit / integration tests>
**DoD:**
- [ ] concrete criterion
- [ ] tests pass
- [ ] lint clean
<!-- /mb-task:1 -->
```

Each `<!-- mb-task:N -->` block is a first-class executable artifact — it is NOT
a scaffold for humans only. `/mb work <topic>` resolves and executes these blocks
in order.

## Validate & migrate

After editing `tasks.md`, validate the spec triple with:

```bash
bash scripts/mb-spec-validate.sh <topic>
```

This checkpoint verifies EARS integrity, parseable `<!-- mb-task:N -->` markers,
per-task Covers/DoD/Testing presence, no orphaned REQ-IDs, and that any present
GIVEN/WHEN/THEN scenarios are well-formed. Run it before invoking
`/mb work <topic>` to catch format errors early.

**Scenario gate (opt-in).** If the resolved `pipeline.yaml` sets
`sdd.require_scenarios: true`, run the stricter form so every REQ must have at
least one GIVEN/WHEN/THEN scenario:

```bash
bash scripts/mb-spec-validate.sh --require-scenarios <topic>
```

The default is off (`require_scenarios: false`), so EARS-only specs stay valid.
Inspect the active value with
`bash scripts/mb-pipeline.sh show .memory-bank | grep require_scenarios`.

To upgrade a legacy `tasks.md` that uses the old `## N. ...` heading style (without
`<!-- mb-task:N -->` markers), use:

```bash
# Dry-run first (default) — shows what would change:
bash scripts/mb-spec-tasks-migrate.sh <topic>

# Apply — writes a backup then rewrites tasks.md in-place (idempotent):
bash scripts/mb-spec-tasks-migrate.sh <topic> --apply
```

## Generation self-check (MANDATORY before declaring the spec ready)

`mb-spec-validate.sh` checks structure, not semantics — a spec can pass it and
still be unexecutable. Whoever fills the triple (human or LLM) MUST run every
artifact through its **real consumer** and MUST NOT report the spec as ready
until all five checks pass. Lesson source: the 2026-07-17 group review — 8/8
specs passed the validator and still collected 96 findings, because none of
these checks ran at generation time.

1. **Structure** — `bash scripts/mb-spec-validate.sh <topic>` (plus
   `--require-scenarios` when the spec carries gated SHALL/MUST requirements).
2. **Scenario parity** — `python3 scripts/mb-scenario-extract.py
   <mb>/specs/<topic>/requirements.md | wc -l` MUST equal the number of
   `### Scenario:` headings. Zero extracted with headings present means the
   blocks lack `<!-- mb-scenario:N -->` markers or `**Covers:**` lines — the
   validator will NOT catch this (its scenario check is a no-op when no marker
   blocks exist). Scenario **names must be ASCII/English**: `test_id` slugs drop
   non-ASCII, so Cyrillic names collapse into colliding ids.
3. **Task parse & role routing** — `python3 scripts/mb_work_items.py
   <mb>/specs/<topic>/tasks.md`: every task parses; every resolved `agent`
   exists. `Role:` takes a **bare role name** (`backend`, `qa`, `architect` —
   see `references/templates.md`); the parser prefixes `mb-` itself, so
   `Role: mb-backend` silently routes to a nonexistent `mb-mb-backend`.
4. **Eval red run** — execute every `**Eval:**` command now. Every one MUST
   exit non-zero (red) on the current tree. An already-green eval is a fake red;
   a `grep -q '<word>'` eval that any mention satisfies tests vocabulary, not
   behavior — rewrite it against the declared contract (bats/pytest under
   `tests/bats/` / `tests/pytest/`).
5. **Cross-spec contracts** — for every interface this spec consumes from or
   provides to another spec, open the other spec and verify both sides state
   the same command, fields, and exit codes, and that the dependency appears in
   `blocked_by`. A contract "to be revised later" that a dependent spec is
   already built on is a defect, not an open question.

Do not write formats from memory: copy the task-block shape from
`references/templates.md` and the scenario shape from an existing green spec.

## Out of scope

- Does not run `/mb discuss` — call that first if no context yet.
- Does not validate that every REQ in `requirements.md` has an implementing task — that's `/mb verify`'s job (or `/mb work` review-loop, Phase 3).
- Does not auto-generate `design.md` / `tasks.md` content — they start as scaffolds for the user to fill.

## Related

- `/mb discuss <topic>` — produces the EARS-validated context that feeds into `requirements.md`.
- `/mb plan <type> <topic> --context <path>` — create a plan that links to either the spec's requirements.md or directly to `context/<topic>.md`.
- `/mb plan <type> <topic> --sdd` — strict mode, refuses without an EARS-valid context.
- `/mb traceability-gen` — regenerate `traceability.md` after edits to `specs/*/requirements.md`.
- `bash scripts/mb-req-next-id.sh --spec <topic>` — emit the next per-spec-local REQ-NNN (omit `--spec` for a project-wide max+1).
- `bash scripts/mb-ears-validate.sh <file>|-` — verify REQ lines.
