---
type: note
tags: [sdd, phase-closeout, mb-work, spec-tasks, plan-wrapper, traceability, migration]
importance: high
phase: sdd-unification
created: 2026-05-23
---

# Phase `sdd-unification` — DONE

**Phase scope:** Make `specs/<topic>/tasks.md` a first-class executable artifact for `/mb work`, with `plan.md` as optional thin execution wrapper. Single SDD-flow: `discuss → sdd → spec-validate → work → verify → traceability-gen → done`.

**Sprints (all DONE):**
1. **`sdd-task-model`** — shared `mb_work_items.py` parser, new `<!-- mb-task:N -->` format in `mb-sdd.sh`, `mb-spec-validate.sh` integrity checks.
2. **`sdd-work-engine`** — `/mb work` executes spec tasks; plan-as-wrapper via `linked_spec`/`tasks` frontmatter; new JSON schema (additive: source/kind/covers/item_no).
3. **`sdd-traceability-docs`** — Spec Task column in traceability matrix, legacy migration script, unified SDD docs.

**Key architectural lessons:**
- **Single parser SSOT** — `mb_work_items.py` is the only source. Wrappers (`mb-work-plan.sh`, `mb-traceability-gen.sh`, `mb-spec-validate.sh`) call its CLI. Resist inline parsing for "perf" — one subprocess per target is negligible.
- **Plan-as-wrapper primitive** — thin plan with `linked_spec` + `tasks: A-B` enables sprint slicing of large specs without task duplication. Plan basename stays in JSON `plan` field for traceability.
- **Backward-compat JSON evolution** — alias old fields, ADD new ones. `stage_no` lives on as alias of `item_no`.
- **Migration UX** — dry-run-default + atomic write + timestamped backup + marker-based idempotency.

**Migration story for legacy projects:**
`bash scripts/mb-spec-tasks-migrate.sh <topic> --apply` upgrades `## N. Title` → `<!-- mb-task:N --> ## Task N: Title` without touching body. Existing `plans/*.md` with `<!-- mb-stage:N -->` markers continue working (backward compat preserved).

**Phase E2E gate:** `mb-sdd → mb-spec-validate → mb-work-plan (dry-run + range) → mb-traceability-gen → mb-spec-tasks-migrate (idempotent)` — all green on tmp project.

**Sprint plans (archived):**
- [done/2026-05-21_refactor_sdd-task-model.md](../plans/done/2026-05-21_refactor_sdd-task-model.md)
- [done/2026-05-21_refactor_sdd-work-engine.md](../plans/done/2026-05-21_refactor_sdd-work-engine.md)
- [done/2026-05-21_refactor_sdd-traceability-docs.md](../plans/done/2026-05-21_refactor_sdd-traceability-docs.md)

**Next candidates:** v5.0.0 release cut, I-005 `/mb graph`, I-003 native auto-memory bridge.
