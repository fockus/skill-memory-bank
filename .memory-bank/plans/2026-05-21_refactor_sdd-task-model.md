---
type: refactor
topic: sdd-task-model
status: done
depends_on: []
parallel_safe: false
linked_specs: []
sprint: 1
phase_of: sdd-unification
created: 2026-05-21
---

# Plan: refactor — sdd-task-model

**Baseline commit:** f16e5715854828431fe5820c10d0ad062e4f9892

## Context

**Problem:** `specs/<topic>/tasks.md` сейчас — это human-only artifact: `mb-sdd.sh` создаёт его в формате `## 1. ...` без `<!-- mb-task:N -->` маркеров. `/mb work` понимает только `plans/*.md` через `<!-- mb-stage:N -->`. Логика парсинга, role-detection и status-detection продублирована в `scripts/mb-work-plan.sh` и `scripts/mb-work-range.sh`. Это блокирует унификацию SDD-flow и делает `tasks.md` неисполняемым артефактом.

**Expected result:** Появляется единая модель work-item с поддержкой двух источников: `plans/*.md` (`<!-- mb-stage:N -->`, как сейчас) и `specs/<topic>/tasks.md` (новый формат `<!-- mb-task:N -->`). Введён общий Python-парсер `scripts/mb_work_items.py` с публичным API. `mb-sdd.sh` генерирует tasks.md в новом формате. Добавлен `scripts/mb-spec-validate.sh` для целостности spec triple. **`/mb work` в этом Sprint не меняется** — wiring отложен в Sprint 2.

**Phase split:** Phase `sdd-unification` = 3 Sprint:
- **Sprint 1 (этот файл)** — task model + shared parser + sdd generator + spec validator.
- **Sprint 2** — [refactor — sdd-work-engine](2026-05-21_refactor_sdd-work-engine.md) — `/mb work` integration.
- **Sprint 3** — [refactor — sdd-traceability-docs](2026-05-21_refactor_sdd-traceability-docs.md) — traceability + docs + migration.

**Related files:**
- `scripts/mb-sdd.sh` — генератор tasks.md, формат меняется.
- `scripts/mb-work-plan.sh`, `scripts/mb-work-range.sh` — содержат текущую логику role/status detection, будут потребителями `mb_work_items.py` в Sprint 2.
- `tests/pytest/test_sdd.py` — существующие тесты, расширяются.
- `scripts/mb-ears-validate.sh` — переиспользуется в spec-validate.
- `references/templates.md` — task template (обновится в Sprint 3).

## Architecture decision for this Sprint

1. **Marker model — два формата, parser общий:**
   - `<!-- mb-stage:N -->` — plan stage. Не трогаем (backward compat).
   - `<!-- mb-task:N -->` — spec task. Новый.
   - Оба парсятся одной моделью `WorkItem`.

2. **Shared parser в `scripts/mb_work_items.py`:**
   - Public API: `parse_work_items(path: Path) -> list[WorkItem]`.
   - `WorkItem` поля: `source` (`plan`|`spec`), `topic`, `item_no`, `kind` (`stage`|`task`), `heading`, `body`, `role`, `agent`, `status` (`pending`|`in-progress`|`done`), `covers` (tuple `REQ-NNN`), `dod_lines`.
   - Role auto-detect heuristics переносятся из `mb-work-plan.sh` (Sprint 2 уберёт оттуда дубликат).
   - CLI mode: `python3 scripts/mb_work_items.py <path>` → JSON Lines.

3. **Task template (новый):**

   ```markdown
   <!-- mb-task:N -->
   ## Task N: <title>

   **Covers:** REQ-NNN
   **Role:** <role>

   **What to do:**
   - <step>

   **Testing (TDD — tests BEFORE implementation):**
   - <unit / integration>

   **DoD:**
   - [ ] <criterion>
   - [ ] tests pass
   - [ ] lint clean
   ```

4. **Spec validator:**
   - `scripts/mb-spec-validate.sh <topic|path>` — exit 0 clean, 1 violations (stderr details).
   - Checks: EARS requirements valid; tasks parseable; каждый task имеет `Covers` + `DoD` + `Testing`; каждый REQ покрыт ≥1 task.

5. **No new deps:** stdlib only (`re`, `pathlib`, `dataclasses`, `json`).

## Requirements by example

| Scenario | Input | Expected |
|----------|-------|----------|
| Parse plan stages | plan с 3× `<!-- mb-stage:N -->` | 3 WorkItem, `source=plan`, `kind=stage`. |
| Parse spec tasks | tasks.md с 3× `<!-- mb-task:N -->` | 3 WorkItem, `source=spec`, `kind=task`. |
| Extract covers | `**Covers:** REQ-001, REQ-002` в body | `covers=("REQ-001","REQ-002")`. |
| Explicit role | `**Role:** qa` | `role=qa`, `agent=mb-qa`. |
| Role auto-detect | task с `pytest` в body, без Role | `role=qa`. |
| Status detection | DoD из 3× `- [x]` | `status=done`. |
| sdd generates new format | `mb-sdd.sh foo` | tasks.md содержит `<!-- mb-task:1 -->`. |
| spec-validate orphan REQ | REQ-001 в requirements, ни одного task с Covers REQ-001 | exit 1, stderr `REQ-001 orphan`. |
| spec-validate clean spec | well-formed triple | exit 0. |

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: RED contract tests for shared work-item parser

**What to do:**
- Создать `tests/pytest/test_work_items_parser.py`.
- Зафиксировать публичный API: `parse_work_items(path) -> list[WorkItem]` + dataclass `WorkItem`.
- Фикстуры в `tmp_path`: один plan-файл с `<!-- mb-stage:N -->`, один spec `tasks.md` с `<!-- mb-task:N -->`, один файл без маркеров.
- ≥ 10 параметризованных кейсов, имена `test_<what>_<condition>_<result>`, AAA-структура.
- Покрыть: оба формата, оба `kind`, status (pending/in-progress/done), `covers` parsing, explicit Role vs auto-detect, dod_lines count, file без маркеров → пустой list, mixed-markers file → `ValueError`.

**Testing (TDD — tests BEFORE implementation):**
- `pytest tests/pytest/test_work_items_parser.py -v` — RED, падает с `ModuleNotFoundError: scripts.mb_work_items` (или ImportError).
- RED-output snapshot подтверждает, что тесты падают по причине отсутствия модуля, а не по syntax-error в тестах.
- Тесты не зависят от рабочего `.memory-bank/` (все через `tmp_path`).

**DoD (Definition of Done):**
- [ ] `tests/pytest/test_work_items_parser.py` существует, ≥ 10 тест-кейсов.
- [ ] RED run падает на `ModuleNotFoundError` / `ImportError`, не на syntax.
- [ ] Имена тестов следуют `test_<what>_<condition>_<result>`.
- [ ] Ни один production-файл не изменён в этом Stage.
- [ ] `ruff check tests/pytest/test_work_items_parser.py` чисто.
- [ ] Stage воспроизводим за < 30 секунд (`pytest -v` локально).

**Code rules:** TDD red phase, Specification by Example, naming convention, AAA, no mocks (используем real tmp files).

---

<!-- mb-stage:2 -->
### Stage 2: Implement `scripts/mb_work_items.py`

**What to do:**
- Создать `scripts/mb_work_items.py` (Python 3.12+, stdlib only).
- Реализовать dataclass `WorkItem` (`frozen=True`) с полями из Architecture decision §2.
- Реализовать `parse_work_items(path)`:
  - Detect формат по первому маркеру (`mb-stage` vs `mb-task`); mixed → `ValueError`.
  - Split body по маркерам, capture heading + content до следующего маркера или EOF.
  - Извлечь `topic` из basename (plan: drop date prefix; spec: имя parent dir).
  - Парсинг `**Covers:** REQ-NNN[, REQ-MMM]` (case-insensitive).
  - Парсинг `**Role:** <name>`.
  - Auto-detect role при отсутствии `Role:` (heuristics: ios/android/frontend/backend/devops/qa/architect/analyst → developer fallback).
  - Status detection: count `- [⬜✅xX ]` bullets.
- `agent` = `mb-<role>`.
- CLI mode: `python3 scripts/mb_work_items.py <path>` → JSON Lines stdout.
- Type hints полные, docstrings на public API.

**Testing (TDD):**
- RED-тесты из Stage 1 переходят в GREEN: `pytest tests/pytest/test_work_items_parser.py -v` → exit 0.
- Добавить ≥ 3 интеграционных кейса для CLI: `subprocess.run(["python3", "scripts/mb_work_items.py", str(path)])` возвращает валидный JSONL.
- `ruff check scripts/mb_work_items.py` чисто.
- Module ≤ 300 строк (SRP cap).

**DoD:**
- [ ] `scripts/mb_work_items.py` существует, исполняемый, ≤ 300 строк.
- [ ] Все Stage 1 тесты GREEN.
- [ ] ≥ 3 CLI integration теста зелёные.
- [ ] `ruff check scripts/mb_work_items.py` чисто.
- [ ] `bash scripts/mb-rules-check.sh --files scripts/mb_work_items.py --diff-files scripts/mb_work_items.py --out json` → `violations=[]`.
- [ ] No new dependencies в `pyproject.toml`.

**Code rules:** SRP (≤ 300 строк), KISS, stdlib only, полные type hints, docstrings, `@dataclass(frozen=True)`.

---

<!-- mb-stage:3 -->
### Stage 3: Update `mb-sdd.sh` to emit `<!-- mb-task:N -->` format

**What to do:**
- В `scripts/mb-sdd.sh` обновить heredoc для `tasks.md`:
  - Каждый task начинается с `<!-- mb-task:N -->` маркера.
  - Заголовок `## Task N: <!-- title -->`.
  - Поля `**Covers:** REQ-NNN`, `**Role:** developer`, `**What to do:**`, `**Testing (TDD — tests BEFORE implementation):**`, `**DoD:**` с ≥ 1 `- [ ]`.
  - Создавать минимум 2 task-блока в шаблоне (как сейчас 2 секции).
- `--force` поведение, idempotency guard — без изменений.
- При наличии `<mb>/context/<topic>.md` EARS-блок по-прежнему копируется в `requirements.md` (как сейчас); `tasks.md` остаётся scaffold с REQ-NNN placeholder.

**Testing (TDD):**
- Расширить `tests/pytest/test_sdd.py` (RED-фаза первой):
  - `test_sdd_tasks_template_has_mb_task_marker` — содержит `<!-- mb-task:1 -->`.
  - `test_sdd_tasks_template_has_role_field` — содержит `**Role:**`.
  - `test_sdd_tasks_template_has_testing_section` — содержит `**Testing`.
  - `test_sdd_tasks_template_dod_uses_checkboxes` — содержит `- [ ]`.
  - `test_sdd_tasks_parseable_by_work_items` — `parse_work_items()` возвращает ≥ 2 WorkItem из созданного tasks.md.
- Запустить полный `pytest tests/pytest/test_sdd.py -v` — все green.
- `shellcheck scripts/mb-sdd.sh` clean.

**DoD:**
- [ ] `mb-sdd.sh` шаблон `tasks.md` использует `<!-- mb-task:N -->` маркеры.
- [ ] 5 новых тестов в `test_sdd.py` GREEN.
- [ ] Все существующие тесты `test_sdd.py` GREEN (нет регрессий).
- [ ] `shellcheck scripts/mb-sdd.sh` clean.
- [ ] Idempotency guard сохранён: `mb-sdd.sh foo` дважды → второй раз exit 1 без `--force`.
- [ ] Существующие `test_traceability_gen.py` тесты не упали (covers-парсинг внешний).

**Code rules:** YAGNI (no auto-link Covers сейчас), TDD (новые тесты RED→GREEN), idempotency, обратная совместимость для CLI.

---

<!-- mb-stage:4 -->
### Stage 4: Implement `scripts/mb-spec-validate.sh`

**What to do:**
- Создать `scripts/mb-spec-validate.sh <topic|path> [mb_path]` (исполняемый bash).
- Резолвинг входа:
  - Если `<topic>` — путь к существующему dir/file → используется напрямую.
  - Иначе → `<mb>/specs/<topic>/`.
- Проверки (каждая → запись в violations[]):
  1. `requirements.md` существует и `mb-ears-validate.sh requirements.md` exit 0.
  2. `tasks.md` существует и `mb_work_items.py tasks.md` возвращает ≥ 1 WorkItem.
  3. Каждый WorkItem имеет `covers` непустой → иначе `task N missing Covers`.
  4. Каждый WorkItem имеет `dod_lines >= 1` → иначе `task N missing DoD`.
  5. Body каждого task содержит слово `Testing` (case-insensitive heuristic) → иначе `task N missing Testing section`.
  6. Каждый REQ-NNN из requirements.md упомянут в covers ≥ 1 task → иначе `REQ-NNN orphan`.
- Exit 0 если violations пустой, 1 иначе; stderr — список violations.
- Поддержать `--json` для structured output (`{"violations":[...]}`).

**Testing (TDD — tests BEFORE implementation):**
- Создать `tests/pytest/test_mb_spec_validate.py` (RED первой):
  - `test_spec_validate_passes_on_well_formed_spec`
  - `test_spec_validate_fails_when_req_orphan`
  - `test_spec_validate_fails_on_task_without_covers`
  - `test_spec_validate_fails_on_task_without_dod`
  - `test_spec_validate_fails_on_task_without_testing_section`
  - `test_spec_validate_fails_on_invalid_ears_in_requirements`
  - `test_spec_validate_resolves_topic_via_mb_path`
  - `test_spec_validate_json_mode_emits_structured_output`
- ≥ 8 кейсов, AAA-структура, real tmp_path fixtures.
- `shellcheck -x scripts/mb-spec-validate.sh` clean.

**DoD:**
- [ ] `scripts/mb-spec-validate.sh` существует, исполняемый.
- [ ] ≥ 8 pytest тестов в `test_mb_spec_validate.py` GREEN.
- [ ] Exit 0 на well-formed spec, exit 1 на каждом из 5 violation cases.
- [ ] `--json` mode возвращает валидный JSON с `violations` array.
- [ ] `shellcheck -x scripts/mb-spec-validate.sh` clean.
- [ ] `bash scripts/mb-rules-check.sh --files scripts/mb-spec-validate.sh --diff-files scripts/mb-spec-validate.sh --out json` → `violations=[]`.

**Code rules:** SRP, fail-fast on violations, clear stderr messages, no new deps, переиспользование `mb-ears-validate.sh` и `mb_work_items.py` (DIP).

---

<!-- mb-stage:5 -->
### Stage 5: Sprint 1 verification + handoff

**What to do:**
- Запустить полный test-run: `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json`.
- Запустить `bash scripts/mb-rules-check.sh --files "$CHANGED" --diff-files "$CHANGED" --out json` для всех изменённых файлов.
- `ruff check scripts/ tests/pytest/` clean.
- `shellcheck -x scripts/mb-sdd.sh scripts/mb-spec-validate.sh` clean.
- Smoke regression: `bash scripts/mb-work-plan.sh --target .memory-bank/plans/2026-05-21_feature_global-storage.md --dry-run --mb .memory-bank` отрабатывает как раньше (Sprint 2 ещё не интегрировал).
- `/mb verify` PASS, CRITICAL=0, WARNING=0 для Sprint 1 scope.
- Обновить frontmatter плана: `status: queued` → `status: done`.
- Создать note `notes/2026-05-21_HH-MM_sdd-task-model.md` (5–15 строк): что закрыто, какие артефакты добавлены, links на Sprint 2.
- Append `progress.md` секцию `## 2026-05-21 (sdd-task-model — Sprint 1)`.

**Testing (TDD):**
- N/A для verification stage; финальный прогон — это сам gate.
- Все ранее RED тесты остаются GREEN (no regression).

**DoD:**
- [ ] `mb-test-run` → `tests_pass=true`, `tests_total ≥ 708 + 18` (baseline + новые тесты Stage 1/3/4).
- [ ] `mb-rules-check` → `violations=[]`.
- [ ] `ruff` и `shellcheck` clean.
- [ ] `/mb verify` PASS, CRITICAL=0, WARNING=0.
- [ ] Note создана, progress дополнен, plan frontmatter обновлён.
- [ ] Существующий `/mb work` dry-run на любом active plan работает без изменений.
- [ ] Sprint 2 unblocked: `mb_work_items.py` готов к интеграции в `mb-work-plan.sh`.

**Code rules:** Verification before completion (evidence > assertions), no claim без выполненной команды.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Дублирование role-detection логики между `mb_work_items.py` и `mb-work-plan.sh` | M | В Sprint 2 удалить дубликат из `mb-work-plan.sh`; Sprint 1 оставляет обе копии для backward compat. |
| `mb-sdd.sh` template-change ломает существующие `test_sdd.py` | M | Stage 3 пишет 5 новых тестов первыми и прогоняет полный `test_sdd.py` перед DoD. |
| Spec-validator слишком строгий → ложные negatives на legacy specs | M | Запускается explicit (не auto-hook); legacy specs не валидируются автоматически. Sprint 3 добавит миграцию. |
| Mixed-marker file (одновременно mb-stage и mb-task) | L | Parser кидает `ValueError`; покрыто Stage 1 тестом. |
| Регрессия в `/mb work` через скрытую зависимость | L | Stage 5 явно прогоняет smoke на active plan; Sprint 2 интеграция изолирована. |

## Gate (Sprint 1 success criterion)

Sprint 1 закрыт, когда **все** ниже выполнено:
- `scripts/mb_work_items.py` существует, имеет public API из §2, ≥ 13 тестов GREEN.
- `mb-sdd.sh` создаёт `tasks.md` с `<!-- mb-task:N -->` маркерами; `parse_work_items()` возвращает ≥ 2 WorkItem из созданного шаблона.
- `scripts/mb-spec-validate.sh` существует, ≥ 8 тестов GREEN, exit-коды соответствуют контракту.
- `/mb verify` PASS, CRITICAL=0, WARNING=0.
- Полный `mb-test-run` PASS, `tests_total` вырос ≥ +18 от baseline 708.
- Поведение `/mb work` не изменилось (regression check Stage 5).
- Sprint 2 (`sdd-work-engine`) разблокирован: `mb_work_items.py` готов как dependency.
