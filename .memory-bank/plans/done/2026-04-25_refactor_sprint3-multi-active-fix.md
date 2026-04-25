---
type: refactor
topic: sprint3-multi-active-fix
status: done
sprint: 3
phase_of: skill-v2
parallel_safe: false
covers_requirements: [I-028]
linked_specs: [specs/mb-skill-v2/]
created: 2026-04-25
---

# Refactor: Sprint 3 — Multi-Active Plan Checklist Collision Fix (I-028)

## Context

После Sprint 2 в `mb-plan-sync.sh` / `mb-plan-done.sh` heading-based ownership чеклист-секций. Если два активных плана содержат секцию с одинаковым именем (`## Task 1: Setup` / `## Stage 1: Setup`), они сливаются в одну секцию в `checklist.md`, а закрытие любого из них удаляет общую секцию — silent data loss для второго плана.

Phase 2 Sprint 1 (`/mb discuss`, EARS, context) гарантированно столкнётся с этим багом, поэтому Sprint 3 — baseline для Phase 2.

## Problem (repro)

```bash
# Plan A: Task 1: Setup
sync A.md → checklist gets `## Task 1: Setup` + `- ⬜ Setup`

# Plan B: Task 1: Setup (тот же name)
sync B.md → existing match → skip → checklist unchanged
            (Plan B's Task 1 ушёл в no-man's-land: задача активна, но в чеклисте секции под её именем нет)

# Close A
done A.md → удаляет `## Task 1: Setup` секцию целиком
            → Plan B теряет свою секцию
```

## Solution

**Marker-based ownership:** каждая секция чеклиста, добавленная sync'ом, получает маркер `<!-- mb-plan:<basename> -->` непосредственно перед heading. Sync создаёт по одной секции на (plan, stage_id) пару. Done удаляет только секции с маркером своего basename.

**Backward compatibility:** секции без маркера = legacy. Sync такие не трогает (не считает их «своими» матчами идемпотентности — пишет новую marker-секцию). Done использует legacy heading-only fallback ТОЛЬКО когда в чеклисте нет ни одной marker-секции с этим heading (иначе legacy heading-cleanup может прибить чужой плановый stage).

## Format

Каждая marker-секция в `checklist.md`:

```
<!-- mb-plan:2026-04-25_refactor_sprint3-multi-active-fix.md -->
## Stage 1: Setup
- ⬜ Setup
```

Маркер на отдельной строке непосредственно перед heading. Granularity — по одной marker-line на каждую stage-section (не один маркер на весь план — иначе removing logic усложняется).

## Definition of Done (SMART)

- ✅ pytest 289+ → 289+ (новые collision tests добавлены, ничего не регрессирует)
- ✅ shellcheck `scripts/*.sh` → 0 warnings
- ✅ ruff `check .` → All checks passed
- ✅ Bats `tests/bats/test_plan_*_multi.bats` зелёные (включая починку legacy plan.md→roadmap.md fixture)
- ✅ Repro-test: 2 плана с identical `## Task 1: Setup`, sync обоих, close одного → второй чеклист intact
- ✅ Backward-compat test: legacy секция без маркера + новый план с тем же heading → legacy не теряется
- ✅ I-028 помечен DONE в `backlog.md`
- ✅ `CHANGELOG.md` обновлён с entry под `[Unreleased]`

## Stages

<!-- mb-stage:1 -->
## Stage 1: Failing collision tests (RED)

**Цель:** написать pytest-тест и обновлённый bats-тест, которые failят на текущем коде, но описывают желаемый contract.

**TDD:**
1. Новый pytest `tests/pytest/test_plan_multi_active_collision.py`:
   - Fixture: 2 плана с одинаковыми `## Task 1: Setup` headings.
   - Test 1: после `sync A` + `sync B` checklist содержит **2** разные секции (одна под marker A, одна под marker B).
   - Test 2: после `done A` секция Plan B сохраняется (heading + checklist item).
   - Test 3: idempotency — `sync A` + `sync A` produces single A-marker section (no dupe).
   - Test 4: backward-compat — pre-existing legacy section без маркера + sync нового плана с тем же heading → legacy intact, new marker section добавлена.
2. Обновить bats fixture: `plan.md` → `roadmap.md`, `STATUS.md` → `status.md`, `BACKLOG.md` → `backlog.md` (исправление legacy v1-имён в `test_plan_sync_multi.bats` + `test_plan_done_multi.bats`).
3. Запустить — collision tests fail, остальные bats зелёные.

**DoD:**
- ✅ pytest `test_plan_multi_active_collision.py::*` → 4 failed (RED state — expected!)
- ✅ bats `test_plan_sync_multi.bats` + `test_plan_done_multi.bats` → green после fixture fix
- ✅ Старые pytest 289 → green (не сломали ничего)

<!-- mb-stage:2 -->
## Stage 2: Marker emission в mb-plan-sync.sh (GREEN, часть 1)

**Цель:** sync пишет маркер перед каждой новой секцией.

**Изменения в `scripts/mb-plan-sync.sh`:**
1. `append_missing_stages()`:
   - Новая идемпотентность: matched only if file contains BOTH `<!-- mb-plan:$BASENAME -->` AND следующая строка == точный heading.
   - При записи новой секции: marker → heading → item.

**TDD:**
1. Запустить collision tests → Test 1 (2 секции после sync обоих) и Test 3 (idempotency) должны проходить.
2. Test 2 (preserve B after done A) и Test 4 (backward-compat) ещё failят (done не починен).
3. Старые тесты должны остаться зелёными.

**DoD:**
- ✅ pytest `test_plan_multi_active_collision::test_two_plans_get_separate_sections` PASSED
- ✅ pytest `test_plan_multi_active_collision::test_resync_idempotent` PASSED
- ✅ pytest 289+ baseline зелёный

<!-- mb-stage:3 -->
## Stage 3: Marker-based removal в mb-plan-done.sh (GREEN, часть 2)

**Цель:** done удаляет только секции с маркером своего basename.

**Изменения в `scripts/mb-plan-done.sh`:**
1. `remove_stage_section()` переписан:
   - Primary path: для текущего basename найти marker line `<!-- mb-plan:$BASENAME -->` + соседний heading; удалить блок до следующего `## ` или `<!-- mb-plan:` или EOF.
   - Fallback path (legacy): если marker этого basename отсутствует, но есть heading match И в чеклисте нет НИ ОДНОГО marker для этого heading у других planов — удалить legacy секцию.
2. Нужен счётчик удалённых секций (для report `removed_sections=N`).

**TDD:**
1. Test 2 (preserve B) → PASSED.
2. Test 4 (backward-compat) → PASSED.
3. Старые `test_plan_done_multi.bats` тесты → PASSED.

**DoD:**
- ✅ Все 4 collision-теста PASSED
- ✅ Bats `test_plan_done_multi.bats` зелёный
- ✅ `pytest -q` 289+4 = 293+ passed, 0 failed

<!-- mb-stage:4 -->
## Stage 4: Regression suite + lint + memory bank close-out

**Цель:** убедиться что ничего не сломали, обновить bank.

1. Запустить полный pytest, shellcheck, ruff.
2. Запустить полный bats suite (526 tests).
3. Обновить `backlog.md`: I-028 → DONE.
4. Обновить `CHANGELOG.md`: новая entry под `[Unreleased]` с описанием fix'а.
5. Обновить `checklist.md` Sprint 3 секцию (отметить пункты ✅).
6. Обновить `status.md`: пометить Phase 2 unblocked.
7. Bulk commit + push к origin.
8. После push — обновить real global skill `~/.claude/skills/skill-memory-bank/` (`git pull` или `bash install.sh`).

**DoD:**
- ✅ pytest всё green
- ✅ bats всё green
- ✅ shellcheck зелёный
- ✅ ruff зелёный
- ✅ Bank artifacts актуальны (backlog/changelog/checklist/status)
- ✅ Origin pushed
- ✅ Global skill updated
