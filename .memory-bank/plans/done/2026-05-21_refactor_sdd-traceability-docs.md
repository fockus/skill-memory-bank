---
type: refactor
topic: sdd-traceability-docs
status: done
depends_on: [2026-05-21_refactor_sdd-work-engine.md]
parallel_safe: false
linked_specs: []
sprint: 3
phase_of: sdd-unification
created: 2026-05-21
---

# Plan: refactor — sdd-traceability-docs

**Baseline commit:** f16e5715854828431fe5820c10d0ad062e4f9892

## Context

**Problem:** После Sprint 1 (`sdd-task-model`) и Sprint 2 (`sdd-work-engine`) `specs/<topic>/tasks.md` — полноценный executable artifact, `/mb work` его исполняет. Но:
- `scripts/mb-traceability-gen.sh` сканирует только `plans/*.md` (frontmatter `covers_requirements` + inline `<!-- covers: REQ-NNN -->`), игнорируя `specs/*/tasks.md:**Covers:** REQ-NNN`. Реальное task-coverage REQ не видно в matrix.
- Документация (`SKILL.md`, `commands/{sdd,work,plan}.md`, `references/templates.md`) описывает старую модель: tasks.md как scaffold, plan-файл как единственный executable artifact.
- Legacy `specs/*/tasks.md` (если есть в проектах) сделаны в старом формате `## 1. ...` без `<!-- mb-task:N -->` маркеров — нужна миграция.

**Expected result:** Traceability matrix включает task-level coverage (`REQ → Spec → Spec Task → Plan → Tests`). Документация описывает единый SDD-flow с `/mb work <topic>` UX. Появляется идемпотентный migration script `scripts/mb-spec-tasks-migrate.sh` для апгрейда legacy tasks.md без потери данных. Phase `sdd-unification` закрывается end-to-end gate-сценарием.

**Phase split:** Sprint 3 of Phase `sdd-unification`. Зависит от Sprint 1 ([sdd-task-model](2026-05-21_refactor_sdd-task-model.md)) и Sprint 2 ([sdd-work-engine](2026-05-21_refactor_sdd-work-engine.md)).

**Related files:**
- `scripts/mb-traceability-gen.sh` — основной target изменений.
- `SKILL.md`, `commands/sdd.md`, `commands/work.md`, `commands/plan.md`, `references/templates.md` — документация.
- Новый `scripts/mb-spec-tasks-migrate.sh` — migration helper.
- `scripts/mb_work_items.py` — reused parser (Sprint 1 dependency).
- `tests/pytest/test_traceability_gen.py` — extended.

## Architecture decision for this Sprint

1. **Traceability matrix расширяется новой колонкой:**

   ```text
   | REQ | Spec | Spec Task | Plan / Stage | Tests | Status |
   ```

   - **Spec Task** — путь к task: `specs/<topic>/tasks.md#task-N`.
   - **Plan / Stage** — как раньше (frontmatter `covers_requirements` или inline marker в plan).
   - REQ считается `tested` если есть Spec Task **или** Plan stage **и** тестовый файл с `REQ_NNN`/`REQ-NNN`.

2. **Task scanning:**
   - `mb-traceability-gen.sh` использует `scripts/mb_work_items.py` для парсинга `specs/*/tasks.md`.
   - Для каждого WorkItem собирает `covers` → mapping `REQ → [(spec, task_no)]`.

3. **Status legend (расширенный):**

   | Status | Условие |
   |--------|---------|
   | ✅ | task + (plan ИЛИ tests) |
   | 🏗️ | task ИЛИ plan, но нет tests |
   | ⬜ | только в requirements, нет покрытия |

4. **Migration:**
   - `scripts/mb-spec-tasks-migrate.sh <topic\|path> [--apply\|--dry-run]`.
   - Парсит старый формат (`## 1. <title>` без mb-task маркера).
   - Эмитит новый формат с `<!-- mb-task:N -->`, добавляет placeholder `**Covers:** REQ-NNN` если отсутствует.
   - Не теряет существующий content: `What to do`, `DoD`, `Testing` сохраняются 1-в-1.
   - Pre-write backup `<tasks.md>.bak.<unix-ts>`.
   - Идемпотентно: rerun на уже-мигрированном файле = no-op.

5. **Docs scope (что обновляется):**
   - `SKILL.md` — общая модель + новые scripts в Tools table.
   - `commands/sdd.md` — упоминание `mb-task` формата, validator, migration.
   - `commands/work.md` — уже обновлён в Sprint 2; этот Sprint синхронизирует SDD-секцию.
   - `commands/plan.md` — описание plan-as-wrapper UX, frontmatter `linked_spec` + `tasks`.
   - `references/templates.md` — template для `specs/<topic>/tasks.md` в новом формате + раздел "Plan as execution wrapper".

6. **Phase gate сценарий (end-to-end):**

   ```bash
   /mb discuss inventory-sync     # context/<topic>.md
   /mb sdd inventory-sync          # specs/<topic>/{req,design,tasks}.md (new format)
   bash scripts/mb-spec-validate.sh inventory-sync   # clean
   /mb work inventory-sync --dry-run                 # видит tasks
   /mb work inventory-sync --range 1                 # исполняет task 1
   /mb verify
   bash scripts/mb-traceability-gen.sh .memory-bank  # matrix содержит Spec Task column
   ```

## Requirements by example

| Scenario | Input | Expected |
|----------|-------|----------|
| Traceability scan task covers | `tasks.md` с Task 1 `**Covers:** REQ-001` | Matrix row REQ-001 имеет Spec Task column = `specs/<topic>/tasks.md#task-1`. |
| REQ covered tasks + plan + tests | REQ покрыт task'ом, plan'ом, есть `REQ_001` в тестах | Status = ✅ |
| REQ только task, нет plan | Task с Covers REQ-002, plan не упоминает | Status = 🏗️ |
| REQ orphan | REQ-003 в requirements, никто не covers | Status = ⬜, попадает в Orphans section. |
| Migrate legacy tasks.md | Файл с `## 1. Foo`, `## 2. Bar` без маркеров | Backup создан, файл получает `<!-- mb-task:1 -->\n## Task 1: Foo`, `## Task 2: Bar`. |
| Migrate idempotent | Rerun на уже-мигрированном | exit 0, файл не изменён, backup не создан. |
| Migrate dry-run | `--dry-run` flag | Печатает план изменений в stdout, ничего не пишет. |
| Docs reflect unified flow | grep `mb-task` в `commands/sdd.md` | ≥ 1 match. |

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: RED tests for traceability spec-tasks scan

**What to do:**
- Создать `tests/pytest/test_traceability_spec_tasks.py` (≥ 8 кейсов):
  - `test_traceability_includes_spec_task_column`
  - `test_traceability_marks_req_covered_by_spec_task`
  - `test_traceability_status_done_when_task_plan_and_tests_present`
  - `test_traceability_status_building_when_only_task_no_tests`
  - `test_traceability_orphan_when_no_task_no_plan`
  - `test_traceability_handles_multiple_tasks_covering_same_req`
  - `test_traceability_handles_spec_without_tasks_file`
  - `test_traceability_idempotent_after_task_scan`
- Extend `tests/pytest/test_traceability_gen.py` 1–2 regression-кейсами (старое поведение без specs/tasks).
- Использовать tmp_path fixtures, `mb_work_items.py` парсер (как dependency).

**Testing (TDD — tests BEFORE implementation):**
- Запуск `pytest tests/pytest/test_traceability_spec_tasks.py -v` → RED.
- Причина: ожидаемая колонка `Spec Task` отсутствует или Matrix не содержит ожидаемых rows.
- Старые `test_traceability_gen.py` остаются GREEN.

**DoD:**
- [ ] `tests/pytest/test_traceability_spec_tasks.py` существует, ≥ 8 кейсов.
- [ ] RED-фаза подтверждена.
- [ ] `test_traceability_gen.py` остаётся GREEN (regression).
- [ ] `ruff check tests/pytest/test_traceability_spec_tasks.py` clean.
- [ ] Production не тронут.

**Code rules:** TDD red, AAA, naming convention, изоляция через tmp_path.

---

<!-- mb-stage:2 -->
### Stage 2: Update `scripts/mb-traceability-gen.sh`

**What to do:**
- В Python-блоке внутри `mb-traceability-gen.sh`:
  - После сбора `reqs` (T1) и `covered` из plans (T2): добавить новый шаг T2.5 — сканирование `specs/*/tasks.md` через `mb_work_items.py` (subprocess или import-as-module).
  - Для каждого WorkItem с `covers` → обновлять `reqs[req_id]["spec_tasks"]` (новое поле, list `(spec, task_no)`).
- Расширить status-функцию:
  - `✅` если есть spec_tasks OR planned, И есть tests.
  - `🏗️` если spec_tasks OR planned, но нет tests.
  - `⬜` иначе.
- Расширить Matrix table новой колонкой `| Spec Task |`:
  - Формат: `specs/<topic>/tasks.md#task-N` (multiple = comma-separated).
  - `—` если нет.
- Coverage summary: добавить `Tasks-covered: M`.
- Orphans section: REQ без spec_tasks AND без planned.

**Testing (TDD):**
- RED тесты Stage 1 → GREEN.
- Старые `test_traceability_gen.py` тесты:
  - Если упали из-за изменения структуры columns — обновить ожидаемые assertions (вместе с Stage 1 тестами) so it reflects new contract; пометить как expected breakage в reviewer notes.
  - Если все остались GREEN — отлично.
- `shellcheck scripts/mb-traceability-gen.sh` clean.
- `ruff` на inline Python (через `python3 -` шаблон).

**DoD:**
- [ ] `mb-traceability-gen.sh` сканирует `specs/*/tasks.md` через `mb_work_items.py`.
- [ ] Matrix table содержит колонку `Spec Task`.
- [ ] Coverage summary показывает `Tasks-covered: M`.
- [ ] Status logic учитывает spec_tasks.
- [ ] Все Stage 1 тесты GREEN.
- [ ] Старые `test_traceability_gen.py` тесты либо GREEN, либо обновлены явно (с обоснованием в plan-verifier notes).
- [ ] `shellcheck` clean.

**Code rules:** SRP, DIP (использовать `mb_work_items.py`), no new deps, backward-compat там, где разумно.

---

<!-- mb-stage:3 -->
### Stage 3: Migration script `scripts/mb-spec-tasks-migrate.sh`

**What to do:**
- Создать `scripts/mb-spec-tasks-migrate.sh <topic|path> [--apply|--dry-run] [mb_path]` (default `--dry-run`).
- Парсинг legacy формата:
  - Найти заголовки `^## (\d+)\. (.+)$` (без `mb-task` маркера).
  - Для каждого: capture body до следующего `^## ` или EOF.
- Эмитить новый формат:
  - `<!-- mb-task:N -->` + `## Task N: <title>` + сохранённый body.
  - Если в body отсутствует `**Covers:**` строка — добавить `**Covers:** REQ-NNN` placeholder перед `**What to do**` (или в начало body).
  - Не дублировать существующие маркеры (idempotency).
- Pre-write backup: `<tasks.md>.bak.<unix-ts>` (только при `--apply`).
- Dry-run: печатает unified-diff-like план изменений в stdout, ничего не пишет.
- Idempotency: если файл уже содержит `<!-- mb-task:` маркеры — exit 0, "already migrated".

**Testing (TDD):**
- Создать `tests/pytest/test_mb_spec_tasks_migrate.py` (≥ 8 кейсов):
  - `test_migrate_legacy_two_tasks_apply`
  - `test_migrate_preserves_body_content`
  - `test_migrate_adds_covers_placeholder_when_missing`
  - `test_migrate_does_not_duplicate_covers_when_present`
  - `test_migrate_creates_backup_on_apply`
  - `test_migrate_dry_run_does_not_write`
  - `test_migrate_idempotent_on_already_migrated`
  - `test_migrate_handles_empty_tasks_file`
- RED первой, затем имплементация.
- `shellcheck -x scripts/mb-spec-tasks-migrate.sh` clean.

**DoD:**
- [ ] `scripts/mb-spec-tasks-migrate.sh` существует, исполняемый.
- [ ] ≥ 8 pytest тестов GREEN.
- [ ] `--dry-run` default, `--apply` опт-ин.
- [ ] Backup создаётся только при `--apply`.
- [ ] Idempotent: rerun на migrated файле → exit 0, no changes.
- [ ] `shellcheck -x` clean.
- [ ] Content (`What to do`, `DoD`, `Testing`) сохраняется 1-в-1.

**Code rules:** Idempotency, fail-safe (backup перед write), no destructive default, atomic writes.

---

<!-- mb-stage:4 -->
### Stage 4: Update docs (SKILL.md, commands, references/templates.md)

**What to do:**
- `SKILL.md`:
  - В Tools table добавить новые scripts: `mb_work_items.py`, `mb-spec-validate.sh`, `mb-spec-tasks-migrate.sh`.
  - Обновить раздел Quick start с unified flow: `discuss → sdd → work <topic> → verify → done`.
  - Заменить упоминания "tasks.md остаётся scaffold" на актуальное "tasks.md — executable spec артефакт".
- `commands/sdd.md`:
  - Описать новый формат `tasks.md` с `<!-- mb-task:N -->`.
  - Упомянуть `bash scripts/mb-spec-validate.sh <topic>` как часть SDD-flow.
  - Упомянуть migration script.
- `commands/work.md`:
  - Подтвердить (если уже сделано Sprint 2) описание spec-task execution.
  - Добавить раздел "When to use plan-as-wrapper vs direct spec".
- `commands/plan.md`:
  - Добавить раздел "Plan as execution wrapper" с frontmatter `linked_spec` + `tasks` примером.
  - Обновить decomposition guidance: plan = sprint slice; spec tasks = canonical decomposition.
- `references/templates.md`:
  - Добавить раздел `Spec Tasks (specs/<topic>/tasks.md) — executable task format` с новым template.
  - Добавить раздел `Plan as execution wrapper` с frontmatter примером.
  - Обновить раздел "Plan decomposition" чтобы explicit упомянуть, что spec tasks — canonical, plan — execution wrapper или standalone.

**Testing (TDD):**
- Создать `tests/pytest/test_sdd_docs_unified.py` (≥ 6 кейсов):
  - `test_skill_md_documents_mb_task_marker`
  - `test_skill_md_lists_mb_work_items_in_tools`
  - `test_skill_md_lists_mb_spec_validate_in_tools`
  - `test_commands_sdd_md_references_spec_validate`
  - `test_commands_plan_md_documents_linked_spec_wrapper`
  - `test_templates_md_has_spec_tasks_template`
- Содержательные assertion'ы (substring проверки + counts).
- Bats: extend `test_mb_work_command_doc.bats` (если создан Sprint 2) или новый `tests/bats/test_sdd_docs.bats` с ≥ 3 assertions.

**DoD:**
- [ ] `SKILL.md` обновлён: Tools table содержит 3 новых скрипта, Quick start описывает unified flow.
- [ ] `commands/sdd.md`, `commands/plan.md`, `commands/work.md` отражают новую модель.
- [ ] `references/templates.md` содержит template для нового `tasks.md` и `linked_spec` wrapper.
- [ ] ≥ 6 pytest doc-тестов GREEN.
- [ ] ≥ 3 bats doc-assertion GREEN.
- [ ] Нет упоминаний "tasks.md — scaffold only" или "plans/*.md is the only executable source" в актуальных разделах.

**Code rules:** Documentation as code (всё покрыто тестами), no dead claims, examples runnable, single source of truth для тонких различий.

---

<!-- mb-stage:5 -->
### Stage 5: Sprint 3 + Phase verification + Phase gate

**What to do:**
- Полный test-run: `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json` → `tests_pass=true`.
- `bash scripts/mb-rules-check.sh --files "$CHANGED" --diff-files "$CHANGED" --out json` → `violations=[]`.
- `ruff` + `shellcheck` clean.
- **Phase gate end-to-end scenario** в tmp проекте:
  ```bash
  # tmp project setup with .memory-bank
  bash scripts/mb-init-bank.sh --lang=en --mb-root=$TMP
  cat > $TMP/.memory-bank/context/demo.md <<EOF
  ## Functional Requirements (EARS)
  - **REQ-001** (ubiquitous): The system shall do X.
  - **REQ-002** (event-driven): When Y, the system shall Z.
  EOF
  bash scripts/mb-sdd.sh demo $TMP/.memory-bank
  # отредактировать tasks.md (или сразу пользоваться scaffold + добавить Covers)
  bash scripts/mb-spec-validate.sh demo $TMP/.memory-bank
  bash scripts/mb-work-plan.sh --target demo --mb $TMP/.memory-bank --dry-run
  bash scripts/mb-traceability-gen.sh $TMP/.memory-bank
  # matrix содержит Spec Task column, REQ-001/002 → tasks demo
  ```
- `/mb verify` PASS, CRITICAL=0, WARNING=0 для Sprint 3 scope.
- Обновить frontmatter всех 3 Sprint планов на `done` через `/mb done` workflow.
- Создать Phase-level note `notes/2026-05-21_HH-MM_sdd-unification-phase-done.md`:
  - Summary всех 3 Sprint.
  - Архитектурные решения (mb-task marker, shared parser, plan-as-wrapper).
  - Migration story.
  - Links на 3 plan/done файла.
- Append `progress.md` секцию `## 2026-05-21 (Phase sdd-unification — done)`.
- Обновить `status.md` "Current phase" + `roadmap.md` "Recently completed".

**Testing (TDD):**
- N/A — verification stage.
- E2E scenario выше — фактический gate.

**DoD:**
- [ ] `mb-test-run` `tests_pass=true`, total ≥ Sprint 2 baseline + 22 (Stage 1 + Stage 3 + Stage 4 тесты).
- [ ] `mb-rules-check` violations=[].
- [ ] `ruff`/`shellcheck` clean.
- [ ] `/mb verify` PASS, CRITICAL=0, WARNING=0 для Sprint 3.
- [ ] Phase gate E2E scenario выполнен и documented в Phase-level note.
- [ ] 3 plan-файла Sprint 1/2/3 в `plans/done/`.
- [ ] Phase note + progress + status + roadmap обновлены.
- [ ] Phase `sdd-unification` исчезает из active plans roadmap-блока.

**Code rules:** Evidence-based completion, E2E gate перед закрытием Phase, no claim без выполненной команды.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Существующий `test_traceability_gen.py` упадёт после расширения Matrix | H | Stage 2 явно перечисляет обновление тестов как часть DoD; reviewer notes должны explicit обосновать. |
| Migration teряет content при сложных custom-formats legacy tasks.md | M | Stage 3 покрывает 8 кейсов; pre-write backup гарантирует rollback; dry-run default. |
| Docs дрейфуют от реального поведения после merge | M | Stage 4 покрывает все changes doc-тестами; `mb-rules-check tdd/delta` ловит изменения без тестов. |
| Phase gate E2E падает на CI из-за tmp-dir permissions | L | Использовать `mktemp -d` + cleanup в `trap`; запускать локально перед /mb done. |
| Coverage статус неверно классифицирован для REQ только с tests, без task/plan | M | Stage 1 тест `test_traceability_status_*` покрывает все 3 комбинации; Stage 2 implementation проверяется этими тестами. |

## Gate (Sprint 3 + Phase success criterion)

Sprint 3 закрыт, когда:
- `mb-traceability-gen.sh` сканирует `specs/*/tasks.md` и matrix содержит колонку `Spec Task`.
- `scripts/mb-spec-tasks-migrate.sh` существует, идемпотентен, dry-run default, ≥ 8 тестов GREEN.
- Документация (`SKILL.md`, `commands/{sdd,work,plan}.md`, `references/templates.md`) описывает unified SDD-flow и покрыта doc-тестами.
- `/mb verify` PASS, full `mb-test-run` PASS, total ≥ Sprint 2 baseline + 22.

**Phase `sdd-unification` закрыт, когда (cumulative gate):**
- Все 3 Sprint в `plans/done/`.
- E2E сценарий (`/mb discuss → /mb sdd → /mb spec-validate → /mb work <topic> → /mb verify → traceability-gen`) проходит на tmp-проекте.
- В `roadmap.md` "Recently completed" есть Phase-level summary; `status.md` обновлён.
- Phase-level note существует и summary'ит все 3 Sprint.
- Никаких остатков upper-case "Task N." legacy формата в bundled `mb-sdd.sh` template.
- Backward-compat для plain plans (`mb-stage:N`) сохранён: existing global-storage plans продолжают работать без изменений.
