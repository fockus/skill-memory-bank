---
type: refactor
topic: sdd-work-engine
status: queued
depends_on: [2026-05-21_refactor_sdd-task-model.md]
parallel_safe: false
linked_specs: []
sprint: 2
phase_of: sdd-unification
created: 2026-05-21
---

# Plan: refactor — sdd-work-engine

**Baseline commit:** f16e5715854828431fe5820c10d0ad062e4f9892

## Context

**Problem:** После Sprint 1 (`sdd-task-model`) есть общий парсер `scripts/mb_work_items.py` и `specs/<topic>/tasks.md` уже создаётся в новом формате `<!-- mb-task:N -->`. Но `/mb work` всё ещё исполняет только plan-стадии:
- `scripts/mb-work-resolve.sh` резолвит `<topic>` → `specs/<topic>/tasks.md`, но дальше `mb-work-range.sh` и `mb-work-plan.sh` ищут только `<!-- mb-stage:N -->`.
- Plan-файл сейчас — единственный executable artifact; нет способа сделать его тонкой "execution wrapper" поверх spec tasks.

**Expected result:** `/mb work <topic>`, `/mb work` (empty target), `/mb work <plan-path>` понимают spec tasks как first-class executable source. Plan-файл становится опциональным execution wrapper через frontmatter `linked_spec: specs/<topic>` + `tasks: 1-3`. Все три скрипта (`mb-work-resolve.sh`, `mb-work-range.sh`, `mb-work-plan.sh`) переписаны на общий парсер из Sprint 1, дубликат role-detection удалён. Backward-compat для plan-only flow сохранён.

**Phase split:** Sprint 2 of Phase `sdd-unification`. Sprint 1 ([sdd-task-model](2026-05-21_refactor_sdd-task-model.md)) даёт парсер. Sprint 3 ([sdd-traceability-docs](2026-05-21_refactor_sdd-traceability-docs.md)) подключит traceability + docs + миграцию.

**Related files:**
- `scripts/mb-work-resolve.sh` — резолвер target → path.
- `scripts/mb-work-range.sh` — range parser (`--range A-B`).
- `scripts/mb-work-plan.sh` — JSON Lines emitter для `/mb work`.
- `scripts/mb_work_items.py` — общий парсер из Sprint 1 (dependency).
- `commands/work.md` — runtime guide для агента.
- `tests/pytest/test_mb_work_resolve.py`, `test_mb_work_range.py`, `test_mb_work_plan.py` — расширяются.

## Architecture decision for this Sprint

1. **Single source of truth для парсинга — `mb_work_items.py`:**
   - `mb-work-plan.sh` и `mb-work-range.sh` инлайн-Python заменяется на вызов `python3 -m scripts.mb_work_items` или `python3 scripts/mb_work_items.py <path>`.
   - Дублирующая role-detection логика удаляется из `mb-work-plan.sh`.

2. **Resolver приоритеты (новые):**

   ```text
   1. Existing path (plan или spec tasks.md)
   2. Substring match in plans/*.md (как сейчас)
   3. Topic → specs/<topic>/tasks.md  (как сейчас, но теперь действительно executable)
   4. Freeform ≥3 words → exit 3 с candidates (plans + specs)
   5. Empty → first plan в <!-- mb-active-plans -->
   ```

   Form 3 теперь возвращает `specs/<topic>/tasks.md` и `mb-work-plan.sh` сможет его исполнить.

3. **Range auto-detect формата:**
   - `mb-work-range.sh <file>` определяет формат по первому маркеру (`mb-stage` или `mb-task`).
   - Index space одинаковый (1..max), синтаксис `N`, `A-B`, `A-` не меняется.

4. **Plan-as-wrapper (новая опциональная роль plan-файла):**
   - Frontmatter:
     ```yaml
     linked_spec: specs/inventory-sync
     tasks: 1-3       # range over spec tasks
     ```
   - При наличии `linked_spec` + `tasks` `mb-work-plan.sh` резолвит работу из `specs/<spec>/tasks.md`, применяет range, эмитит JSON с `source=spec`, но `plan` остаётся basename plan-файла (для traceability).
   - Если frontmatter отсутствует — старое поведение (plan stages).

5. **JSON Lines schema (обратно совместима):**
   - Существующие поля: `plan`, `stage_no`, `heading`, `role`, `agent`, `status`, `dod_lines` — остаются.
   - Новые: `source` (`plan`|`spec`), `kind` (`stage`|`task`), `covers` (list), `item_no` (alias for stage_no при `source=plan`).
   - Существующие consumers (driver `commands/work.md`) продолжают читать `stage_no` (значение = `item_no`).

6. **No new deps.**

## Requirements by example

| Scenario | CLI | Expected |
|----------|-----|----------|
| Direct spec target | `mb-work-resolve.sh inventory-sync --mb .memory-bank` (есть `specs/inventory-sync/tasks.md` с mb-task) | Печатает абсолютный путь к `tasks.md`. |
| Spec tasks emission | `mb-work-plan.sh --target specs/inventory-sync/tasks.md --mb .memory-bank` | JSONL с `source=spec`, `kind=task`, корректные `covers`. |
| Range over spec tasks | `mb-work-plan.sh --target inventory-sync --range 2-3 --mb .memory-bank` | Только Task 2 и 3. |
| Plan as wrapper | Plan c `linked_spec: specs/foo` + `tasks: 1-2`, `mb-work-plan.sh --target <plan>` | JSONL с `source=spec`, items 1..2 из `specs/foo/tasks.md`, поле `plan` = basename wrapper-плана. |
| Plain plan (legacy) | Plan без `linked_spec`, `mb-work-plan.sh --target <plan>` | JSONL с `source=plan`, `kind=stage`, как сейчас. |
| Mixed markers в plan | Plan содержит и `mb-stage` и `mb-task` | exit 1, stderr ошибка о mixed-format. |
| Empty target, 1 active | `mb-work-plan.sh --mb .memory-bank` | Берёт первый active plan, эмитит как раньше. |
| Dry-run для spec | `mb-work-plan.sh --target inventory-sync --dry-run` | Header `## Execution Plan` + список task'ов без дальнейших задач. |

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: RED contract tests for `/mb work` spec-task integration

**What to do:**
- Создать `tests/pytest/test_mb_work_spec_tasks.py` с ≥ 12 кейсами:
  - resolve: topic `foo` → `specs/foo/tasks.md` (если он в новом формате).
  - resolve: path к spec tasks.md напрямую.
  - range на spec tasks: `--range 2-3` отдаёт только items 2–3.
  - plan-wrapper: plan c `linked_spec` + `tasks: 1-2` → JSONL из spec.
  - plan-wrapper: `tasks: 2-` open range.
  - plan-wrapper: указан `linked_spec`, нет `tasks` → весь spec.
  - plain plan без `linked_spec` → старое поведение (regression).
  - mixed-markers file → exit 1.
  - empty target + 1 active plan → как сейчас.
  - JSON schema: каждое emit имеет `source`, `kind`, `covers`, `item_no`.
  - Covers list корректно extracted.
  - Dry-run header содержит "Execution Plan".
- Extend `tests/pytest/test_mb_work_resolve.py` (≥ 3 новых кейса для spec resolution).
- Extend `tests/pytest/test_mb_work_range.py` (≥ 2 новых кейса для auto-detect mb-task формата).

**Testing (TDD — tests BEFORE implementation):**
- Запуск всех новых тестов → RED.
- RED-причина: `KeyError`/`AssertionError` на ожидаемых полях (`source`, `covers`), либо неверная резолюция Form 3.
- Старые тесты `test_mb_work_*.py` остаются GREEN (Stage 1 не трогает production).

**DoD:**
- [ ] `tests/pytest/test_mb_work_spec_tasks.py` существует, ≥ 12 параметризованных или одиночных тестов.
- [ ] `test_mb_work_resolve.py` дополнен ≥ 3 кейсами для spec формата.
- [ ] `test_mb_work_range.py` дополнен ≥ 2 кейсами для auto-detect.
- [ ] RED-фаза подтверждена: новые тесты падают, старые зелёные.
- [ ] `ruff check tests/pytest/test_mb_work_spec_tasks.py` clean.
- [ ] Ни один production-файл не изменён.

**Code rules:** TDD red phase, naming convention, AAA, изоляция через tmp_path, no production edits.

---

<!-- mb-stage:2 -->
### Stage 2: Update `scripts/mb-work-resolve.sh`

**What to do:**
- Расширить Form 3 (topic): возвращает `specs/<safe>/tasks.md` если файл существует И содержит ≥ 1 маркер (`mb-stage` или `mb-task`).
- Form 1 (existing path): если путь указывает на `specs/*/tasks.md` или `plans/*.md` — принимать.
- Form 4 (freeform) candidates: добавить в stderr список `specs/*/tasks.md` рядом с `plans/*.md`.
- Sanitize: тот же `mb_sanitize_topic`.
- Не ломать остальные формы.

**Testing (TDD):**
- RED-тесты из Stage 1 (resolve-часть) переходят в GREEN.
- Полный прогон `pytest tests/pytest/test_mb_work_resolve.py -v` — green.
- `shellcheck scripts/mb-work-resolve.sh` clean.

**DoD:**
- [ ] Form 3 возвращает spec tasks.md когда таковой существует.
- [ ] Form 1 принимает путь к spec tasks.md.
- [ ] Form 4 candidates включают specs.
- [ ] Все Stage 1 resolve-кейсы GREEN.
- [ ] Старые тесты `test_mb_work_resolve.py` остаются GREEN.
- [ ] `shellcheck scripts/mb-work-resolve.sh` clean.

**Code rules:** SRP, idempotent script, backward-compat, fail-fast на неоднозначности.

---

<!-- mb-stage:3 -->
### Stage 3: Update `scripts/mb-work-range.sh`

**What to do:**
- В plan-mode: при чтении файла определять формат по первому маркеру: `mb-stage` или `mb-task`.
- Использовать обнаруженный маркер при подсчёте `stages` (substitute `mb-stage` → `mb-task` если formats spec).
- Phase mode и `--range` синтаксис не меняются.
- При mixed-format в одном файле → exit 1 c понятной ошибкой.

**Testing (TDD):**
- RED-тесты из Stage 1 (range-часть) переходят в GREEN.
- `pytest tests/pytest/test_mb_work_range.py -v` green.
- Edge cases: file без маркеров → exit 1 (regression OK); mixed → exit 1 с явным сообщением.
- `shellcheck scripts/mb-work-range.sh` clean.

**DoD:**
- [ ] `mb-work-range.sh` detects mb-task и mb-stage равноценно.
- [ ] Range синтаксис `N`, `A-B`, `A-` работает для обоих форматов.
- [ ] Mixed-format → exit 1, error message в stderr.
- [ ] Все ранее зелёные тесты `test_mb_work_range.py` остаются green.
- [ ] Новые тесты Stage 1 (range) green.
- [ ] `shellcheck scripts/mb-work-range.sh` clean.

**Code rules:** SRP, KISS, fail-fast on mixed, минимальные изменения public интерфейса.

---

<!-- mb-stage:4 -->
### Stage 4: Update `scripts/mb-work-plan.sh` (uses `mb_work_items.py`)

**What to do:**
- Удалить inline Python-парсер из `mb-work-plan.sh` и role auto-detect heuristics.
- Заменить на вызов `python3 scripts/mb_work_items.py <path>` и обогащение результата:
  - Применить `--range` (через `mb-work-range.sh`).
  - Замэппить `role` → `agent` через `pipeline.yaml:roles.<role>.agent` (как сейчас).
- Добавить frontmatter parsing для plan-as-wrapper:
  - Если plan имеет `linked_spec: specs/<topic>` и `tasks: <range>` → резолвить `specs/<topic>/tasks.md`, применять `tasks` диапазон (override `--range`), эмитить JSON с `source=spec`, `plan=<wrapper basename>`.
  - Если есть `linked_spec` без `tasks` → весь spec.
  - Если нет `linked_spec` → старое поведение.
- JSON schema: добавить `source`, `kind`, `covers`, `item_no` (alias on `stage_no`).
- `--dry-run` header остаётся `## Execution Plan`.

**Testing (TDD):**
- Все RED-тесты Stage 1 GREEN после этого Stage.
- Существующий `test_mb_work_plan.py` — все тесты остаются green.
- `shellcheck scripts/mb-work-plan.sh` clean.
- `ruff check` для inline-Python (если останется) или `scripts/mb_work_items.py` clean.

**DoD:**
- [ ] `mb-work-plan.sh` использует `mb_work_items.py` через CLI (один вызов на target).
- [ ] Дублирующая role-detection логика удалена из bash-обёртки.
- [ ] Plan-as-wrapper c `linked_spec` + `tasks` исполняется как spec tasks.
- [ ] JSON содержит новые поля: `source`, `kind`, `covers`, `item_no`.
- [ ] Все Stage 1 тесты + старые `test_mb_work_plan.py` GREEN.
- [ ] `shellcheck scripts/mb-work-plan.sh` clean.
- [ ] Файл ≤ 300 строк (SRP cap).

**Code rules:** DRY (no duplicate parser logic), DIP (использовать `mb_work_items.py` через CLI), backward-compat для существующих consumers.

---

<!-- mb-stage:5 -->
### Stage 5: Update `commands/work.md` runtime guide

**What to do:**
- Документировать новый target resolution: `<topic>` теперь полноценно исполняется как `specs/<topic>/tasks.md`.
- Описать plan-as-wrapper UX: когда создавать тонкий plan-файл (Sprint slicing) vs прямой `/mb work <topic>` (отработка всех pending tasks).
- Документировать новые JSON поля (`source`, `kind`, `covers`, `item_no`) для downstream driver.
- Обновить раздел Examples:
  ```bash
  /mb work inventory-sync                 # все task'и из specs/inventory-sync/tasks.md
  /mb work inventory-sync --range 1-2     # только task 1–2
  /mb work plans/2026-XX-XX_feature_inventory-sync-sprint-1.md
                                          # plan-wrapper, читает tasks из linked_spec
  /mb work --auto                         # empty target → active plan из roadmap
  ```
- Сохранить совместимость со старыми примерами (stages в plain plan).
- Добавить раздел "How `/mb work` resolves your input" с таблицей форм 1–5.

**Testing (TDD):**
- Контракт-тесты документации не нужны на этом Stage. Добавить интеграционный bats:
  - `tests/bats/test_mb_work_command_doc.bats` — проверяет, что `commands/work.md` упоминает `specs/<topic>/tasks.md`, `linked_spec`, `mb-task`, и не содержит устаревших claims о plan-only execution.
- ≥ 4 bats-assertions; запустить bats — green.

**DoD:**
- [ ] `commands/work.md` документирует spec-task execution и plan-as-wrapper.
- [ ] Таблица форм target resolution отражает поведение Stage 2.
- [ ] Примеры покрывают: прямой spec, range, plan-wrapper, empty target.
- [ ] `tests/bats/test_mb_work_command_doc.bats` создан, ≥ 4 assertion, GREEN.
- [ ] Нет упоминаний "plan-only execution" в актуальной части документа.

**Code rules:** Documentation as code (covered by tests), no dead claims, examples runnable.

---

<!-- mb-stage:6 -->
### Stage 6: Sprint 2 verification + handoff

**What to do:**
- Полный test-run: `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json` → `tests_pass=true`.
- `bash scripts/mb-rules-check.sh --files "$CHANGED" --diff-files "$CHANGED" --out json` → `violations=[]`.
- `ruff` + `shellcheck` clean для всех изменённых файлов.
- End-to-end smoke: создать в `tmp` тестовом проекте spec с 3 tasks, выполнить `bash scripts/mb-work-plan.sh --target <topic> --mb <tmp> --dry-run` → корректный execution plan.
- `/mb verify` PASS, CRITICAL=0, WARNING=0 для Sprint 2 scope.
- Обновить frontmatter: `status: queued` → `status: done`.
- Note `notes/2026-05-21_HH-MM_sdd-work-engine.md` (5–15 строк).
- Append `progress.md` секцию.

**Testing (TDD):**
- N/A — verification stage.
- Все ранее RED тесты остаются GREEN; total tests baseline ≥ Sprint 1 baseline + 17.

**DoD:**
- [ ] `mb-test-run` `tests_pass=true`, total ≥ Sprint 1 baseline + 17 новых.
- [ ] `mb-rules-check` violations=[].
- [ ] `ruff`/`shellcheck` clean.
- [ ] `/mb verify` PASS, CRITICAL=0, WARNING=0.
- [ ] E2E dry-run на tmp spec проходит, JSON содержит `source=spec`, `kind=task`, `covers`.
- [ ] Note + progress + frontmatter обновлены.
- [ ] Sprint 3 (`sdd-traceability-docs`) разблокирован: spec tasks полностью executable, осталось расширить traceability + docs.

**Code rules:** Evidence-based completion claims, smoke перед закрытием.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Регрессия в существующем `/mb work` на plain plans | H | Stage 1 покрывает regression (тесты на plain plan), Stage 4 сохраняет старое поведение когда нет `linked_spec`. |
| Двойной парсер (bash inline + Python module) накапливает drift | M | Stage 4 удаляет inline parser; единственный source — `mb_work_items.py`. |
| `pipeline.yaml:roles` mapping ломается при отсутствии новой роли | M | Использовать существующий fallback `role → mb-<role>`; не добавлять новых ролей в этом Sprint. |
| `linked_spec` в plan ссылается на отсутствующий spec | M | `mb-work-plan.sh` exit 1 с явным error; Stage 1 покрывает кейс. |
| Performance: вызов Python из bash на каждый stage медленнее inline | L | Один вызов на target (не на stage); измерять только если жалоба от пользователя — YAGNI. |
| Mixed-marker file (mb-stage + mb-task) в одном файле | L | Sprint 1 parser кидает `ValueError`; Stage 3 + 4 пробрасывают exit 1. |

## Gate (Sprint 2 success criterion)

Sprint 2 закрыт, когда:
- `/mb work <topic>` (для topic с spec в новом формате) исполняет tasks из `specs/<topic>/tasks.md`.
- `/mb work <plan-with-linked_spec>` исполняет range tasks из связанного spec, plan-файл выступает execution wrapper.
- `/mb work <plain-plan>` сохраняет старое поведение (`<!-- mb-stage:N -->` flow).
- Inline-парсер в `mb-work-plan.sh` удалён; единственный источник логики — `scripts/mb_work_items.py`.
- `commands/work.md` документирует все новые сценарии и покрыт bats-тестом.
- `/mb verify` PASS, full `mb-test-run` PASS, total tests ≥ Sprint 1 baseline + 17.
- Sprint 3 unblocked: traceability + docs + миграция могут идти параллельно с production использованием.
