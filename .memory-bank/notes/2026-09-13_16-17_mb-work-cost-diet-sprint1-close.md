---
type: note
tags: [mb-work-cost-diet, sprint1, plan-closure, core-cap, checklist-v2, status-rotate, mb-coord]
related_features: [mb-work-cost-diet]
sprint: 1
importance: medium
source: manual
---

# mb-work-cost-diet-sprint1-close
Date: 2026-09-13 16:17

## What was done
- Closed `plans/2026-09-05_fix_mb-work-cost-diet-sprint1.md` (7/7 stages, 26/26 DoD ✅) via `mb-plan-done.sh` after whole-plan `/mb verify` PASS (44 agreements checked, 0 violated) and done-gates forced past pre-existing unrelated test failures (NOTE in `progress.md`, 2026-09-13).
- `mb-plan-done.sh` moved the plan to `plans/done/`, archived the checklist v2 block verbatim into `progress.md` (`## [checklist archive] 2026-09-13 — 2026-09-05_fix_mb-work-cost-diet-sprint1.md`) and dropped it from `checklist.md` (89/100 lines), removed the plan from `roadmap.md`/`status.md` `mb-active-plans`, prepended `mb-recent-done`, and ran `mb-roadmap-sync.sh`/`mb-traceability-gen.sh` as side effects.
- Updated `status.md` Current phase/Focus and `roadmap.md`'s `Phase: mb-work-cost-diet` table row to `✅ done`; `mb-core-cap.sh check` confirms both core files under cap (status 54/60, checklist 89/100, exit 0).

## New knowledge
- Sprint 1 shipped its own closure tooling (`mb-status-rotate.sh`, `mb-checklist-v2.py`, `mb-coord.sh`, `mb-core-cap.sh`) and this session dogfooded all four during its own close — no manual core-file surgery was needed, only `mb-plan-done.sh` + one scoped `roadmap.md` edit for the phase table (which `mb-plan-done.sh` does not touch — it only clears `Now`/`mb-active-plans`, not phase-tracking tables further down the file).
- `mb-plan-done.sh`'s `mb-recent-done` prepend is a hard 10-cap trim, not an archive-then-trim — the entry pushed off the bottom (`2026-05-23 sdd-traceability-docs`) was silently dropped from `status.md` with no verbatim copy to `progress.md`; distinct from I-191 and not filed as a new item since the plan file itself still lives in `plans/done/`.
