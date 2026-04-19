# claude-skill-memory-bank — Чеклист

## Этап 0: Dogfood init
- ✅ Создать `.memory-bank/` структуру (experiments, plans/done, notes, reports, codebase)
- ✅ Написать `STATUS.md`, `plan.md`, `checklist.md`, `RESEARCH.md`, `BACKLOG.md`, `progress.md`, `lessons.md`
- ✅ Сохранить план рефактора в `plans/2026-04-19_refactor_skill-v2.md`
- ⬜ Зафиксировать коммит `chore: dogfood — init .memory-bank for skill v2 refactor`

## Этап 1: DRY-утилиты + language detection
- ⬜ Написать bats-тесты для `_lib.sh` (TDD red)
- ⬜ Создать `scripts/_lib.sh` с `resolve_mb_path`, `detect_stack`, `detect_test_cmd`, `detect_lint_cmd`, `sanitize_topic`, `collision_safe_filename`
- ⬜ Создать fixtures: `tests/fixtures/{python,go,node,rust,multi}/`
- ⬜ Рефакторить `mb-context.sh` → source `_lib.sh`
- ⬜ Рефакторить `mb-search.sh` → source `_lib.sh`
- ⬜ Рефакторить `mb-note.sh` → source `_lib.sh`, collision-safe filename
- ⬜ Рефакторить `mb-plan.sh` → source `_lib.sh`
- ⬜ `shellcheck scripts/*.sh` → 0 warnings
- ⬜ Bats coverage ≥90% для `_lib.sh`

## Этап 2: Language-agnostic /mb update и mb-doctor
- ⬜ Bats-тесты для `detect_test_cmd` / `detect_lint_cmd` на всех fixtures
- ⬜ Переписать `/mb update` в `commands/mb.md` — убрать Python-хардкод, использовать `_lib.sh`
- ⬜ Переписать `agents/mb-doctor.md` — убрать `src/taskloom/` и `.venv/bin/python`
- ⬜ Реализовать fallback на `.memory-bank/metrics.sh` если существует
- ⬜ Integration test: `/mb update` на Go-fixture даёт валидные метрики
- ⬜ 0 вхождений `pytest`/`ruff`/`taskloom` вне fixtures

## Этап 3: mb-codebase-mapper — memory-bank-native
- ⬜ Bats-тесты для `/mb map` на fixtures (python, go, multi)
- ⬜ Переименовать `agents/codebase-mapper.md` → `agents/mb-codebase-mapper.md`
- ⬜ Сменить frontmatter (`name: mb-codebase-mapper`) + description
- ⬜ Сменить output path `.planning/codebase/` → `.memory-bank/codebase/`
- ⬜ Сократить шаблоны до ≤70 строк каждый (STACK, ARCHITECTURE, CONVENTIONS, CONCERNS)
- ⬜ Создать команду `/mb map [focus]` (stack|arch|quality|concerns|all)
- ⬜ Интегрировать codebase-summary в `/mb context`
- ⬜ `/mb context --deep` для полного codebase-контекста
- ⬜ Idempotency test: повторный `/mb map` обновляет, не дублирует

## Этап 4: Автоматизация consistency-chain
- ⬜ Bats-тесты для `mb-plan-sync.sh` (creation, modification, idempotent)
- ⬜ Создать `scripts/mb-plan-sync.sh` — парсит план, обновляет 4 файла
- ⬜ Bats-тесты для `mb-plan-done.sh`
- ⬜ Создать `scripts/mb-plan-done.sh` — переносит в done/, closes checklist, updates STATUS
- ⬜ Ввести маркеры `<!-- mb-stage:N -->` в шаблон плана
- ⬜ Обновить `/mb plan` → авто-вызов `mb-plan-sync.sh`
- ⬜ Обновить `mb-doctor` — фикс через `mb-plan-sync.sh`

## Этап 5: Ecosystem integration
- ⬜ `SKILL.md`: убрать `user-invocable: false`, переписать description
- ⬜ Заменить все `Task(...)` → `Agent(subagent_type=...)` в skill-файлах
- ⬜ Добавить секцию "Coexistence with native Claude Code memory" в README + SKILL.md
- ⬜ Слить `/mb init` + `/mb:setup-project` → `/mb init [--minimal|--full]`
- ⬜ Удалить `commands/setup-project.md`
- ⬜ Вынести orphan-команды (adr, observability, db-migration и др.) в отдельный plugin или удалить
- ⬜ Валидация SKILL.md frontmatter через agent-sdk-verifier

## Этап 6: Tests + CI
- ⬜ Создать `tests/bats/` с покрытием всех shell-скриптов
- ⬜ Создать `tests/pytest/test_merge_hooks.py` (idempotent, preservation, corrupt recovery)
- ⬜ Создать `tests/e2e/test_install_uninstall.sh` (Docker roundtrip)
- ⬜ Создать `.github/workflows/test.yml` (macos + ubuntu matrix)
- ⬜ Добавить shellcheck + ruff в CI
- ⬜ Pytest coverage ≥85% для Python
- ⬜ CI зелёный на main

## Этап 7: Hooks fixes
- ⬜ Bats-тесты для `file-change-log.sh` (false-positives на `pass`, docstring TODO)
- ⬜ Убрать `pass\s*$` из placeholder-regex
- ⬜ Пропускать TODO внутри docstring/комментария-строки
- ⬜ Log rotation: >10MB → `.log.1`/`.log.2`
- ⬜ `block-dangerous.sh`: env-var `MB_ALLOW_NO_VERIFY=1` как bypass
- ⬜ `merge-hooks.py`: дедупликация по id-маркеру `# [memory-bank-skill:N]`
- ⬜ Pytest для merge-hooks: idempotent merge

## Этап 8: index.json — прагматично
- ⬜ Pytest для `mb-index-json.py` (frontmatter extract, lessons parsing, coverage ≥90%)
- ⬜ Создать `scripts/mb-index-json.py`
- ⬜ Интегрировать в `mb-manager.md` action `actualize`
- ⬜ `mb-search.sh --tag <tag>` — фильтрация через index.json
- ⬜ Бенчмарк: `--tag` быстрее grep-по-всему на банке 50+ файлов

## Этап 9: Финализация
- ⬜ Написать `CHANGELOG.md` (v1.0.0 → v2.0.0)
- ⬜ Написать `docs/MIGRATION-v1-v2.md`
- ⬜ Переписать `README.md` — quick-start, ecosystem section
- ⬜ Сократить `SKILL.md` до ≤150 строк (детали → references/)
- ⬜ `.memory-bank/VERSION` маркер, `install.sh` пишет версию
- ⬜ Roundtrip тест migration guide на существующем `.memory-bank/`

## Gate v2
- ⬜ Все 9 этапов завершены, DoD выполнен
- ⬜ Критерии Gate из плана достигнуты (4 стека, CI зелёный, 0 legacy Task, etc.)
- ⬜ План перенесён в `plans/done/`
