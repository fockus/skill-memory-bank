---
status: done
type: refactor
sprint: I-033
created: 2026-04-25
closed: 2026-04-25
---

# I-033 — `mb-checklist-prune.sh` + checklist hard-cap enforcement

## Context

`checklist.md` previously grew to 534 lines across 7 sprints. Spec §3 declared the file as **rotating** ("section disappears once `/mb done` runs"); spec §13 planned `mb-checklist-auto-update.sh` from `/mb done` — but nothing physically enforced rotation. Each closed sprint left its full block in checklist forever, duplicating `progress.md` + `roadmap.md "Recently completed"` + `plans/done/`. Lesson recorded in `lessons.md` (2026-04-25): declarative spec ≠ contract; contract = code + CI test.

## Goal

Build the missing enforcement: a script that idempotently collapses fully-✅ sections linking to `plans/done/...` into one-liners, wired into the natural lifecycle points, plus a CI cap-test that fails when the file exceeds 120 lines.

## DoD (SMART)

- [x] `scripts/mb-checklist-prune.sh [--dry-run|--apply] [--mb <path>]` — bash dispatcher + python parser. Pre-write `.checklist.md.bak.<unix-ts>` backup on `--apply`. ≤120-line warn to stderr after prune. Idempotent.
- [x] Wired into `commands/done.md` step 4 (between plan-close and session-lock).
- [x] Wired into `scripts/mb-plan-done.sh` chain (after roadmap-sync + traceability-gen).
- [x] Wired into `scripts/mb-compact.sh` `--apply` flow (after `.last-compact` touch).
- [x] `tests/pytest/test_mb_checklist_prune.py` — 11 tests covering: dry-run plan, dry-run no-mutate, apply collapse, in-flight preservation, no-plans-done preservation, partial-done preservation, backup creation, idempotency, hard-cap warn, missing-file no-op, unknown-flag error.
- [x] `tests/pytest/test_checklist_cap.py` — 1 CI test enforcing ≤120 lines on the repo's own `.memory-bank/checklist.md` (skipped when file absent in checkout).
- [x] Repo's own checklist re-pruned via `--apply`: 39 → 36 lines, fully one-liner format for closed sprints.
- [x] `shellcheck -x` clean on new + modified scripts.
- [x] Full pytest suite green: 584 → 596 (+12).

## Stages

### Stage 1: tests RED
- Wrote `test_mb_checklist_prune.py` (11 cases) before any script existed. Verified script-not-found exit code 127.

### Stage 2: implement script
- `scripts/mb-checklist-prune.sh` — bash arg parsing + python heredoc for section parsing.
- Algorithm: walk `### ` headings outside protected `## ⏳ In flight`/`## ⏭ Next planned` H2 blocks; collapse if body has `plans/done/...md` link AND no `⬜`/`[ ]`. Emit `### <heading> — Plan: [<basename>](<path>)` + blank line. Drop accidental triple-blanks.
- 11/11 tests green on first run.

### Stage 3: wire into lifecycle
- `commands/done.md`: added step 4 prune call (`--apply --mb .memory-bank`), bumped subsequent step numbers.
- `scripts/mb-plan-done.sh`: appended best-effort prune to existing roadmap-sync/traceability-gen chain.
- `scripts/mb-compact.sh`: added prune call inside `--apply` branch after `.last-compact` touch.

### Stage 4: CI cap-test + dogfood
- `test_checklist_cap.py`: pytest enforcing ≤120 lines on `.memory-bank/checklist.md`. `pytest.skipif` when file absent.
- Real checklist re-pruned via `--apply`: 39 → 36 lines. Phase 4 Sprint 1+2 + Phase 3 Sprint 3 entries now in compact one-liner form pointing to `plans/done/`.

## Retrospective

**What went right.** TDD discipline held — RED tests landed before the script. Python heredoc kept multi-paragraph parsing readable while preserving the bash dispatcher convention (matches `mb-pipeline-validate.sh`). Wired into all three lifecycle points (`/mb done`, `mb-plan-done.sh`, `mb-compact.sh`) so manual prune is rarely needed. CI cap-test locks in the convention so future regressions surface in pytest, not in user complaints.

**What could be smoother.** The protected-block heuristic walks upward to nearest `##` — fine for current structure, but if someone introduces a `## ✅ Recently completed` containing `### ` items that should NOT be collapsed (e.g. notes without plan-link), the rule already protects those (no `plans/done/` link → skip). Validated by the no-plans-done preservation test.

**Antidote applied.** lessons.md "rotating artifact without enforcement" entry now has concrete delivery: companion script + 3 wire-ins + CI cap-test. Pattern usable as template for any future rotating artifact in the spec.
