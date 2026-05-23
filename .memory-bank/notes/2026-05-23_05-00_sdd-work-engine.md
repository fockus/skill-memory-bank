---
type: note
tags: [sdd, work-engine, mb-work, spec-tasks, plan-wrapper, sprint-closeout]
importance: high
sprint: 2
created: 2026-05-23
---

# sdd-work-engine — Sprint 2 closeout

**Phase:** sdd-unification (3 sprints). **Sprint 2 of 3 — DONE.**

**Closed:** Stages 1-6.
- resolver: `mb-work-resolve.sh` Form 3 (topic→spec tasks.md with markers), Form 4 candidates extended
- range: `mb-work-range.sh` auto-detects mb-stage/mb-task, mixed-format rejection
- plan: `mb-work-plan.sh` refactored — inline parser deleted, uses `mb_work_items.py` SSOT, plan-as-wrapper via linked_spec frontmatter
- docs: `commands/work.md` documents 5 resolution forms + plan-wrapper UX + new JSON schema

**Lessons:**
- Wrapper bash scripts orchestrate; parsing lives in one Python module (SSOT). Resist re-adding inline parsing for "performance" — one subprocess call per target is negligible.
- Plan-as-wrapper (`linked_spec` + `tasks` range) is the right primitive for sprint slicing of large specs without duplicating tasks into multiple plans.
- Backward-compatible JSON evolution: keep old field as alias (`stage_no` ↔ `item_no`), ADD new fields rather than rename.

**Next:** Sprint 3 `sdd-traceability-docs` (5 stages) — traceability matrix task-level coverage, `mb-spec-tasks-migrate.sh`, final docs update, end-to-end Phase gate.
