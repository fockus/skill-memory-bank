# claude-skill-memory-bank — Progress Log

## 2026-04-19

### Аудит skill v1
- Проведён полный аудит: SKILL.md, 7 shell-скриптов, 4 агента, 2 хука, `merge-hooks.py`, install/uninstall, settings, references
- Выявлено 36 проблем, сгруппированы: 6 критических, 16 существенных, 8 улучшений эффективности, 8 gaps
- Ключевые находки: orphan-агент `codebase-mapper` (GSD), конфликт с native Claude Code memory, хардкод Python/pytest, 0% тестов при лозунге TDD, SKILL.md в 276 строк
- Следующий шаг: составить план рефактора

### План рефактора v2
- Составлен 10-этапный план `plans/2026-04-19_refactor_skill-v2.md`
- SMART DoD на каждый этап, TDD-first подход, риски с mitigation, Gate-критерии
- Этап 0 (dogfood init), Этап 1 (_lib.sh), Этапы 2-4 параллельно, Этапы 5-7 параллельно, 8-9 финал
- Решено: сохранить `codebase-mapper` как `mb-codebase-mapper` (адаптация, не удаление) — требование пользователя
- Следующий шаг: выполнить Этап 0

### Этап 0: Dogfood init
- Создана структура `.memory-bank/` в корне репозитория (experiments, plans/done, notes, reports, codebase)
- Написаны core-файлы: STATUS.md (фаза + roadmap на 9 этапов), plan.md (active plan link), checklist.md (все задачи ⬜ по этапам), RESEARCH.md (5 гипотез H-001..H-005), BACKLOG.md (4 HIGH идеи + 3 ADR), lessons.md (header)
- План рефактора сохранён в `plans/2026-04-19_refactor_skill-v2.md`
- Skill теперь дог-фудит сам себя
- Тесты: манипуляции файловые, smoke-check через `ls .memory-bank/` даёт 7 файлов + 5 директорий
- Коммит: `637dd84 chore: dogfood — init .memory-bank for skill v2 refactor`
- Следующий шаг: Этап 1 (TDD red → green)

### Этап 1: DRY-утилиты + language detection
- **TDD red**: создан `tests/bats/test_lib.bats` с 36 тестами для 7 функций; начальный прогон — 36 skipped
- **Fixtures**: `tests/fixtures/{python,go,rust,node,multi,unknown}/` — реальные манифесты (pyproject.toml, go.mod, Cargo.toml, package.json)
- **TDD green**: создан `scripts/_lib.sh` (150 строк) с функциями `mb_resolve_path`, `mb_detect_stack`, `mb_detect_test_cmd`, `mb_detect_lint_cmd`, `mb_detect_src_glob`, `mb_sanitize_topic`, `mb_collision_safe_filename`
- Первый прогон: 35/36 passed. Баг — brace-pattern `*.{ts,tsx,js,jsx}` не содержал литерал `*.ts` → фикс на space-separated patterns
- Финальный прогон: **36/36 green**
- **Refactor**: mb-context.sh, mb-search.sh, mb-note.sh, mb-plan.sh, mb-index.sh → source `_lib.sh`. Удалено ~50 строк дублирующего workspace-resolver кода
- mb-plan.sh получил `<!-- mb-stage:N -->` маркеры в шаблоне (подготовка к Этапу 4)
- mb-note.sh: коллизия имени теперь → `_2`/`_3` суффикс (раньше был exit 1)
- **Shellcheck**: `shellcheck -x --source-path=SCRIPTDIR scripts/*.sh` → 0 warnings
- **Smoke tests**: все 5 рефакторенных скриптов работают на self-bank и temp-директориях; collision handling проверен
- Тесты: 36 bats green, 0 shellcheck warnings, 5 smoke-тестов зелёных
- Следующий шаг: Этап 2 (language-agnostic `/mb update` и `mb-doctor`) + коммит Этапа 1
