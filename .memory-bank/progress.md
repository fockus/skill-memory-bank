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
- Коммит: `722fbc5 feat(stage-1): _lib.sh + bats tests + language detection`
- Следующий шаг: Этап 2

### Этап 2: Language-agnostic /mb update и mb-doctor
- **TDD red**: `tests/bats/test_metrics.bats` — 10 тестов для нового `mb-metrics.sh` (detect, unknown fallback, src_count, override, --run mode); red-прогон: 10 skipped
- **TDD green**: создан `scripts/mb-metrics.sh` — language-agnostic сборщик метрик, выводит `key=value` строки
  - Priority 1: `.memory-bank/metrics.sh` override если существует → `source=override`
  - Priority 2: auto-detect через `mb_detect_stack` → `source=auto`
  - Unknown стек → warning на stderr, exit 0 (graceful)
  - `--run` режим: выполняет test_cmd, записывает `test_status=pass|fail`
  - `count_files()` helper с per-stack exclude patterns (`__pycache__`, `vendor`, `target`, `node_modules`, `dist`)
- **Финальный прогон**: 10/10 green. Total bats: **46/46**
- **Удалён хардкод**:
  - `commands/mb.md` `/mb update`: `.venv/bin/python -m pytest`, `ruff check src/` → `bash scripts/mb-metrics.sh`
  - `agents/mb-doctor.md`: `src/taskloom/`, `.venv/bin/python` → `mb-metrics.sh`
- **Документация**: `references/templates.md` — секция про custom `metrics.sh` override с полным примером
- **Smoke tests**:
  - `mb-metrics.sh .` (этот репо без манифеста) → `stack=unknown`, warning, exit 0
  - `mb-metrics.sh tests/fixtures/python` → `pytest -q`, `ruff check .`, `src_count=1`
  - `mb-metrics.sh tests/fixtures/go` → `go test ./...`, `go vet ./...`, `src_count=1`
- **Shellcheck**: 0 warnings
- **Grep-проверка**: 0 вхождений `.venv/bin`/`src/taskloom`/`pytest -q` в `commands/` и `agents/` (legitimate references остались только в `_lib.sh` как return values и в `.memory-bank/` как планирование)
- Следующий шаг: Этап 2.1 → 2.2 → 3

### Этап 2.1: Java/Kotlin/Swift/C++ (коммит 69f9422)
- Расширение language coverage: 4 новых стека добавлены в `_lib.sh`
- Java: `pom.xml`/`build.gradle` → mvn test + checkstyle
- Kotlin: `build.gradle.kts` (приоритет) → gradle test + detekt
- Swift: `Package.swift` → swift test + swiftlint
- C/C++ (unified `cpp` tag): `CMakeLists.txt`/`meson.build` → ctest + cppcheck
- Fixtures: java/kotlin/swift/cpp — все прошли detection + src_count
- Tests: 46 → 66 (+20), все green

### Этап 2.2: Ruby/PHP/C#/Elixir (коммит 4ad08aa)
- Ещё 4 стека — теперь **12 общих** (+ multi + unknown)
- Ruby: `Gemfile` → rspec + rubocop
- PHP: `composer.json` → phpunit + phpstan
- C#: glob-matching `*.csproj`/`*.sln` через compgen → dotnet test + dotnet format
- Elixir: `mix.exs` → mix test + credo
- Tests: 66 → 86 (+20), все green

### Этап 3: mb-codebase-mapper (memory-bank-native)
- **TDD red**: `tests/bats/test_context_integration.bats` — 7 тестов для `mb-context.sh --deep` и integrated codebase summary
- Первый прогон: 5 red (includes/summary/--deep), 2 green (graceful без codebase/)
- **TDD green**: обновлён `scripts/mb-context.sh`
  - Новый флаг `--deep` (парсится перед path-arg)
  - Секция "Codebase summary" при наличии `.memory-bank/codebase/*.md`
  - Default mode: 1-строчный summary каждого MD (первая не-заголовочная строка)
  - --deep mode: полное содержимое
  - Graceful: без codebase/ — секция пропускается
- Финальный прогон: 7/7 green
- **Адаптация агента**:
  - `agents/codebase-mapper.md` (770 строк, orphan GSD) → `agents/mb-codebase-mapper.md` (316 строк, -59%)
  - Frontmatter: `name: mb-codebase-mapper`, color: cyan, MB-native description
  - Output path: `.planning/codebase/` → `.memory-bank/codebase/`
  - Шаблоны: 6 → 4 (STACK+INTEGRATIONS объединены; ARCH+STRUCTURE объединены; CONVENTIONS+TESTING объединены; CONCERNS)
  - Каждый шаблон ≤70 строк (закреплено в `<critical_rules>`)
  - Агент вызывает `mb-metrics.sh` для детекции стека — leveraging Этап 2
  - Forbidden files list сохранён (security: .env, credentials, *.pem и т.д.)
- **Команда `/mb map [focus]`** в `commands/mb.md`: stack|arch|quality|concerns|all (default: all)
- **Обновления экосистемы**: install.sh banner, uninstall.sh manual cleanup list, README.md agents-таблица — всё ссылается на `mb-codebase-mapper`
- Total bats: **93/93 green** (86 + 7 context-integration)
- Shellcheck: 0 warnings
- **Устранено**: пункт #1 из аудита (orphan codebase-mapper). `.planning/codebase/` refs больше нет в skill-коде (только 1 legitimate reference в `codebase/map-codebase.md` — GSD command template, не skill-файл)
- Следующий шаг: Этап 4 (`mb-plan-sync.sh` — автоматизация consistency-chain)

### Этап 4: Автоматизация consistency-chain
- **TDD red**: `tests/bats/test_plan_sync.bats` — 18 тестов (11 sync + 7 done), начальный прогон 18 skipped
- **TDD green**: создан `scripts/mb-plan-sync.sh` (5.7K, 120 строк):
  - Парсер `<!-- mb-stage:N -->` → следующая `### Этап N: <name>` строка (awk)
  - Fallback: если маркеров нет — regex-парсинг `### Этап N:` напрямую (exit code 42 сигнализирует fallback)
  - Checklist: append только отсутствующих секций `## Этап N: <name>` (идемпотентно, существующие не ломаются)
  - Plan.md: замена блока `<!-- mb-active-plan --> ... <!-- /mb-active-plan -->` на `**Active plan:** \`plans/<basename>\` — <title>`
  - Авто-создание маркеров, если их нет (insert после `## Active plan`)
- **TDD green**: создан `scripts/mb-plan-done.sh` (4.6K, 130 строк):
  - Парсер этапов — идентичный sync (общий контракт)
  - Для каждого этапа N: awk-диапазон `## Этап N:` → следующая `## ` → `⬜ → ✅`
  - Guard: файл должен лежать в `<mb>/plans/` не в `done/` (exit 3 иначе)
  - `mv <plan> <mb>/plans/done/<basename>` + очистка Active plan блока
- **Финальный прогон**: 18/18 green. Total bats: **117/117** (+18)
- **Интеграция**:
  - `commands/mb.md` → `/mb plan` теперь инструктирует: 1) `mb-plan.sh` → 2) заполнить план → 3) `mb-plan-sync.sh`
  - `agents/mb-doctor.md` → Шаг 4 исправления: приоритет `mb-plan-sync.sh`/`mb-plan-done.sh` над Edit. Semantic inconsistencies по-прежнему через Edit
- **Smoke-test на реальном плане**: `mb-plan-sync.sh .memory-bank/plans/2026-04-19_refactor_skill-v2.md` → `stages=10 added=0` (идемпотентно — все секции уже есть). Active plan блок автоматически создан в `plan.md`
- **Shellcheck**: 0 warnings (включая оба новых скрипта)
- install.sh копирует `scripts/*.sh` → новые скрипты подхватятся автоматически
- Следующий шаг: Этап 5 (Ecosystem integration — Task→Agent, SKILL.md frontmatter, coexistence с native memory, merge `/mb init` + `/mb:setup-project`)

### Этап 5: Ecosystem integration
- **Расширение rules** — skill теперь покрывает 3 платформенных слоя:
  - Backend: Clean Architecture (было)
  - Frontend: **FSD (Feature-Sliced Design)** — `app → pages → widgets → features → entities → shared`, правила импорта вниз, public API через `index.ts`, cross-slice через widget/page
  - Mobile: **iOS + Android** — UDF + Clean слои. iOS: SwiftUI + `@Observable`, `async/await`, SwiftData, SPM модули, TCA для крупных. Android: Google Recommended Architecture (Compose + ViewModel + StateFlow + Hilt + Room, Gradle multi-module). Общее: immutable UI state, SSOT в Repository, DI через protocols/interfaces
  - Всё добавлено в `rules/RULES.md` и компактно в `rules/CLAUDE-GLOBAL.md`
- **SKILL.md frontmatter fix**: убран невалидный `user-invocable: false`, добавлен `name: memory-bank`, description отражает three-in-one concept
- **Task→Agent migration**: 4 вхождения `Task(...)` → `Agent(subagent_type=..., model=..., description=..., prompt=...)` в `commands/mb.md` (2) и `SKILL.md` (2). Grep-проверка: **0 вхождений `Task(`** в skill-файлах
- **Merge `/mb init` + `/mb:setup-project`** в единую `/mb init [--minimal|--full]`:
  - `--minimal` — только структура `.memory-bank/` + 7 core файлов
  - `--full` (default) — + `RULES.md` copy + auto-detect стека (через `mb-metrics.sh` + фреймворки) + генерация `CLAUDE.md` + опциональный `.planning/` symlink
  - Удалён `commands/setup-project.md`
  - Обновлены: `install.sh` banner (19→18), `uninstall.sh` manual cleanup list, `README.md`, `CLAUDE.md`, `references/claude-md-template.md`
- **README переписан** — three-in-one concept в top секции: (1) Memory Bank, (2) Global dev rules, (3) 18 dev commands. Добавлена секция "Coexistence with Native Claude Code Memory" — таблица различий между `.memory-bank/` и native `auto memory`, правило выбора ("project vs user")
- **SKILL.md** также получил секцию coexistence
- **Git push скрипты** не трогались — Этап 5 чисто документационный
- **Orphan-команды**: решено **не удалять**. По уточнению пользователя skill = dev-toolkit + MB + RULES, 18 команд — часть skill'а (не orphan). `implement.md`/`pipeline.md` остаются глобально (GSD-зависимость)
- **Метрики**: bats 117/117 green (не изменилось — Этап 5 без новых скриптов), shellcheck 0 warnings, 0 `Task(` вхождений, 0 хардкода
- Следующий шаг: Этап 6 (Tests + CI — pytest для `merge-hooks.py`, e2e Docker roundtrip, GitHub Actions matrix macos+ubuntu)
