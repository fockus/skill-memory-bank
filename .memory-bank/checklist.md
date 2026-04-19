# claude-skill-memory-bank — Чеклист

## Этап 0: Dogfood init ✅
- ✅ Создать `.memory-bank/` структуру (experiments, plans/done, notes, reports, codebase)
- ✅ Написать `STATUS.md`, `plan.md`, `checklist.md`, `RESEARCH.md`, `BACKLOG.md`, `progress.md`, `lessons.md`
- ✅ Сохранить план рефактора в `plans/2026-04-19_refactor_skill-v2.md`
- ✅ Зафиксировать коммит `chore: dogfood — init .memory-bank for skill v2 refactor` (637dd84)

## Этап 1: DRY-утилиты + language detection ✅
- ✅ Написать bats-тесты для `_lib.sh` (TDD red) — 36 тестов в `tests/bats/test_lib.bats`
- ✅ Создать `scripts/_lib.sh` с 7 функциями: `mb_resolve_path`, `mb_detect_stack`, `mb_detect_test_cmd`, `mb_detect_lint_cmd`, `mb_detect_src_glob`, `mb_sanitize_topic`, `mb_collision_safe_filename`
- ✅ Создать fixtures: `tests/fixtures/{python,go,node,rust,multi,unknown}/`
- ✅ Рефакторить `mb-context.sh` → source `_lib.sh`
- ✅ Рефакторить `mb-search.sh` → source `_lib.sh`
- ✅ Рефакторить `mb-note.sh` → source `_lib.sh`, collision-safe filename
- ✅ Рефакторить `mb-plan.sh` → source `_lib.sh` + `<!-- mb-stage:N -->` маркеры в шаблоне
- ✅ Рефакторить `mb-index.sh` → source `_lib.sh` (bonus — тоже использовал дублирующий workspace resolver)
- ✅ `shellcheck -x --source-path=SCRIPTDIR scripts/*.sh` → 0 warnings
- ✅ Bats 36/36 зелёные (100% coverage функций `_lib.sh`)
- ✅ Smoke-tests: collision handling, mb-stage markers, search — все работают

## Этап 2: Language-agnostic /mb update и mb-doctor ✅
- ✅ Bats-тесты для metrics: 10 тестов (`tests/bats/test_metrics.bats`), все green
- ✅ Создан `scripts/mb-metrics.sh` — language-agnostic сборщик метрик (`source=auto`, key=value output)
- ✅ Переписан `/mb update` в `commands/mb.md` — использует `mb-metrics.sh` + `--run` опцию
- ✅ Переписан `agents/mb-doctor.md` — убран `src/taskloom/` и `.venv/bin/python`, использует `mb-metrics.sh`
- ✅ Fallback на `.memory-bank/metrics.sh` реализован (priority 1), протестирован bats
- ✅ Template `metrics.sh` задокументирован в `references/templates.md`
- ✅ Smoke: 4 стека (python/go/rust/node) → валидные метрики; unknown → warning + exit 0
- ✅ 0 вхождений `.venv/bin`/`src/taskloom`/`pytest -q` в `commands/` и `agents/` (только в `_lib.sh` как return value стека)

## Этап 3: mb-codebase-mapper — memory-bank-native ✅
- ✅ Bats-тесты для `/mb context` integration: `test_context_integration.bats` (7 тестов)
- ✅ Переименован `agents/codebase-mapper.md` → `agents/mb-codebase-mapper.md` (orphan удалён)
- ✅ Frontmatter обновлён: `name: mb-codebase-mapper` + MB-native description
- ✅ Output path `.planning/codebase/` → `.memory-bank/codebase/`
- ✅ Сокращено с 6 шаблонов до 4 (STACK, ARCHITECTURE, CONVENTIONS, CONCERNS), файл 770 → 316 строк (−59%)
- ✅ Все 4 шаблона ≤70 строк (заложено в `<critical_rules>` агента)
- ✅ Команда `/mb map [focus]` добавлена в `commands/mb.md` (stack|arch|quality|concerns|all)
- ✅ Codebase summary интегрирован в `/mb context`: 1-строчный summary каждого MD
- ✅ `/mb context --deep` → полное содержимое codebase-документов
- ✅ Интеграция с `mb-metrics.sh` — агент вызывает его для детекции стека первым шагом
- ✅ Updated install.sh, uninstall.sh, README.md — всё ссылается на `mb-codebase-mapper`
- ✅ Idempotent by design: агент использует Write tool, который перезаписывает (не append)

## Этап 4: Автоматизация consistency-chain ✅
- ✅ Bats-тесты `test_plan_sync.bats` — 18 тестов (11 sync + 7 done), TDD red-first
- ✅ Создан `scripts/mb-plan-sync.sh` — парсер `<!-- mb-stage:N -->` (+ fallback regex), append отсутствующих секций в checklist, update Active plan блока в plan.md
- ✅ Создан `scripts/mb-plan-done.sh` — `⬜→✅` в секциях плана, `mv` в plans/done/, очистка Active plan блока
- ✅ Маркеры `<!-- mb-stage:N -->` уже были в шаблоне `scripts/mb-plan.sh` (Этап 1) — задокументированы в `/mb plan`
- ✅ Обновлён `/mb plan` в `commands/mb.md` — явная инструкция запускать `mb-plan-sync.sh` после создания
- ✅ Обновлён `agents/mb-doctor.md` — фикс через `mb-plan-sync.sh`/`mb-plan-done.sh` приоритетно, Edit только для семантических рассинхронов
- ✅ Идемпотентность подтверждена тестом (двойной запуск sync → 0 diff)
- ✅ Smoke-test на реальном плане репо: 10 этапов распарсены, Active plan блок создан в plan.md
- ✅ Shellcheck 0 warnings, bats 117/117 green (+18 новых)

## Этап 5: Ecosystem integration ✅
- ✅ Добавлены правила для frontend (FSD) и mobile (iOS/Android UDF + Clean) в `rules/RULES.md` и `rules/CLAUDE-GLOBAL.md`
- ✅ `SKILL.md` frontmatter: убран невалидный `user-invocable: false`, добавлен `name: memory-bank`, description отражает three-in-one
- ✅ 4× `Task(...)` → `Agent(subagent_type=..., ...)` в `commands/mb.md` (2) и `SKILL.md` (2). Grep `Task(` → 0
- ✅ Секция "Coexistence with native Claude Code memory" добавлена в `SKILL.md` и `README.md`
- ✅ `/mb init` объединён с `/mb:setup-project` → `/mb init [--minimal|--full]`. `--full` (default): структура + RULES + CLAUDE.md автодетект + `.planning/` symlink. `--minimal`: только структура
- ✅ `commands/setup-project.md` удалён; install.sh/uninstall.sh/README/CLAUDE.md/claude-md-template обновлены (18 команд теперь)
- ✅ README.md переписан: three-in-one concept (MB + RULES + dev toolkit) + coexistence секция + frontend FSD + mobile правила
- ⬜ Orphan-команды — решено **оставить** (они часть dev-toolkit). `implement.md`/`pipeline.md` остаются глобально (GSD-зависимость)
- ⬜ Валидация SKILL.md frontmatter через agent-sdk-verifier — отложено в Этап 6 (CI)

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
