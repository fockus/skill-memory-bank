---
type: feature
topic: phase2-sprint2-sdd-and-plan-lite
status: done
sprint: 2
phase_of: skill-v2-phase-2
parallel_safe: false
covers_requirements: []
linked_specs: [specs/mb-skill-v2/]
created: 2026-04-25
---

# Feature: Phase 2 Sprint 2 — `/mb sdd` + SDD-lite в `/mb plan`

## Context

Sprint 1 закрыл input-side traceability через `/mb discuss` → `context/<topic>.md` с EARS-валидированными REQ-ами. Sprint 2 поднимает следующий слой: полноценный Kiro-style spec triple `specs/<topic>/{requirements,design,tasks}.md` и интеграция context-файлов в `/mb plan`.

## Spec references

- `specs/mb-skill-v2/design.md` §6 — `/mb plan` SDD-lite
- §7 — `/mb sdd` Kiro-style triple

## Out of scope (deferred)

- Verifier что каждое REQ имеет implementing task **и** contract test (требует grep'а по plan stages → отложено к /mb work, Phase 3).
- Жёсткая валидация design.md содержит interface definitions (Protocol/ABC) — добавим когда появится `/mb work` review-loop.
- `mb-traceability-gen.sh` уже сканит `specs/*/requirements.md` — REQ-IDs из новых spec'ов автоматически попадут в матрицу. Доп.код не нужен.

## Definition of Done (SMART)

- ✅ `scripts/mb-sdd.sh <topic> [mb_path]` создаёт `specs/<topic>/{requirements,design,tasks}.md`
- ✅ Если `context/<topic>.md` существует — `requirements.md` копирует Functional Requirements (EARS) секцию as-is
- ✅ Идемпотентность: повторный вызов на existing topic → exit 1 с подсказкой использовать `--force`
- ✅ `scripts/mb-plan.sh` принимает `--context <path>` и `--sdd` флаги
- ✅ `--sdd` без context или с EARS-invalid context → exit 1
- ✅ Plan template получает опциональную `## Linked context` секцию с link к context file
- ✅ `commands/sdd.md` + router row + `### sdd <topic>` detail в `commands/mb.md`
- ✅ `references/templates.md` содержит requirements/design/tasks templates
- ✅ pytest 317+ → 317+N (новые tests добавлены)
- ✅ shellcheck + ruff clean
- ✅ Bank artifacts обновлены, plan → done/, CHANGELOG `[Unreleased]` Added

## Stages

<!-- mb-stage:1 -->
## Stage 1: RED tests

**TDD failing tests:**

1. `tests/pytest/test_sdd.py`:
   - Empty bank, no context → `mb-sdd.sh foo` создаёт `specs/foo/{requirements,design,tasks}.md`.
   - Existing context: `context/foo.md` с EARS секцией → `requirements.md` содержит EARS REQ-* строки.
   - Re-run на existing spec → exit 1 (idempotency guard).
   - `--force` flag перезаписывает existing.
   - Templates содержат правильные секции (requirements: EARS, design: Architecture/Interfaces/Decisions, tasks: numbered checkboxes).

2. `tests/pytest/test_plan_sdd_lite.py`:
   - `mb-plan.sh feature foo --context context/foo.md` → план содержит `## Linked context` с link.
   - Auto-detect: `mb-plan.sh feature foo` (без --context) + существующий `context/foo.md` → auto-link.
   - `mb-plan.sh feature foo --sdd` без context → exit 1.
   - `mb-plan.sh feature foo --sdd` с EARS-invalid context → exit 1.
   - `mb-plan.sh feature foo --sdd` с valid context → plan создан + Linked context секция.

3. `tests/pytest/test_phase2_sprint2_registration.py`:
   - `commands/sdd.md` существует с frontmatter
   - `commands/mb.md` router содержит `sdd <topic>` row
   - `commands/mb.md` содержит `### sdd <topic>` section
   - `references/templates.md` содержит "## Spec — Requirements", "## Spec — Design", "## Spec — Tasks" templates

**DoD:**
- ✅ Все 14+ tests fail (RED)
- ✅ pytest 317 baseline зелёный

<!-- mb-stage:2 -->
## Stage 2: GREEN — `scripts/mb-sdd.sh`

**Implementation:**
- Args: `<topic> [--force] [mb_path]`
- Resolve `MB_PATH`, sanitize topic.
- Check `specs/<topic>/` — если существует и нет `--force` → exit 1.
- Create `specs/<topic>/{requirements,design,tasks}.md` from inline templates.
- Если `context/<topic>.md` существует:
  - Извлечь блок между `## Functional Requirements (EARS)` и следующим `^## ` heading
  - Записать в `requirements.md` (под `## Requirements (EARS)` heading), preserving REQ-IDs as-is
- Print created paths.

**DoD:**
- ✅ pytest `test_sdd.py` всё PASSED
- ✅ shellcheck clean

<!-- mb-stage:3 -->
## Stage 3: GREEN — `scripts/mb-plan.sh` `--context` + `--sdd` флаги

**Implementation:**
- Расширить arg parsing: positional `<type> <topic>` остаются, добавить optional `--context <path>` и `--sdd` boolean.
- `mb_path` теперь может быть как 3rd positional или после flags.
- Auto-detect context: если `--context` не задан, проверить `context/<topic>.md` (sanitized topic).
- `--sdd` mode:
  - Context file required → exit 1 если absent.
  - Run `mb-ears-validate.sh "$context_file"` → exit 1 если non-zero.
- Plan template получает дополнительную `## Linked context` секцию с `[context/<topic>.md](context/<topic>.md)` link если context detected.

**DoD:**
- ✅ pytest `test_plan_sdd_lite.py` всё PASSED
- ✅ shellcheck clean

<!-- mb-stage:4 -->
## Stage 4: `commands/sdd.md` + router + templates + bank close-out

1. `commands/sdd.md` — slash command spec (mirrors specs/mb-skill-v2/design.md §7).
2. `commands/mb.md`:
   - Router table row: `| `sdd <topic> [--force]` | Create Kiro-style spec triple ... |`
   - `### sdd <topic>` section.
3. `references/templates.md`:
   - "## Spec Requirements (`specs/<topic>/requirements.md`)" — EARS-only template
   - "## Spec Design (`specs/<topic>/design.md`)" — Architecture / Interfaces / Decisions / Risks
   - "## Spec Tasks (`specs/<topic>/tasks.md`)" — numbered tasks with checkboxes, references to REQ-IDs

4. Update bank:
   - `checklist.md` — Phase 2 Sprint 2 ✅
   - `status.md` — pivot to Phase 3 (or Phase 2 Sprint 3 if any) or "all spec'd phases shipped"
   - `roadmap.md` — Recently completed entry
   - `CHANGELOG.md` `[Unreleased]` Added entry

5. Plan → `plans/done/`, status: done.
6. progress.md append.

**DoD:**
- ✅ Registration tests PASSED
- ✅ Full pytest + shellcheck + ruff green
- ✅ Bank актуален
- ✅ Commit + push origin
