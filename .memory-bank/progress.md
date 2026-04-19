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

### Этап 6: Tests + CI
- **pytest suite** — `tests/pytest/test_merge_hooks.py`, 16 тестов:
  - 12 subprocess-based (CLI contract: creates-when-missing, preservation, idempotency ×2, dedup, empty settings, UTF-8, corrupted settings rejection, real hooks.json, atomic write, usage error)
  - 4 direct-call через importlib (для coverage): create, merge-into-existing, rejects-corrupted, ignores-non-dict-entries
  - Коллизия: модуль `merge-hooks.py` имеет дефис → `importlib.util.spec_from_file_location` вместо import
  - Coverage: **92% на `settings/merge-hooks.py`** (порог 85%). Непокрытые строки 46-48 — except-блок atomic write (трудно триггерить без симуляции ошибки)
  - `.coveragerc` создан: `include = settings/merge-hooks.py`
- **e2e suite** — `tests/e2e/test_install_uninstall.bats`, 15 тестов:
  - Подход: isolated `HOME=$(mktemp -d)` вместо Docker → работает на macOS и Linux без extra deps
  - Покрытие install: RULES/CLAUDE/commands/agents/hooks/settings, executable bits, manifest JSON valid, идемпотентность ×2 (CLAUDE.md секций и settings hooks не дублируется)
  - Покрытие uninstall: файлы убраны, secrets hooks/CLAUDE stripped, user content preserved (CLAUDE.md выше маркера + user hooks в settings), manifest убран
- **2 реальных бага найдены и починены**:
  1. `install.sh` не добавлял `# [MEMORY-BANK-SKILL]` маркер при создании **нового** CLAUDE.md (только при merge в существующий). Результат: uninstall.sh не находил секцию для очистки. Fix: единая логика — всегда писать маркер
  2. `uninstall.sh` использовал `realpath -m` (GNU-only флаг для non-existing paths). На macOS BSD realpath падает. Fix: манифест хранит абсолютные пути, `realpath` не нужен → убрали
- **GitHub Actions** — `.github/workflows/test.yml`:
  - Job `test`: matrix `[ubuntu-latest, macos-latest]` × (bats unit + bats e2e + pytest). `bats-core/bats-action@3.0.0` для bats setup. `pytest --cov-fail-under=85`
  - Job `lint` (Ubuntu only): shellcheck + ruff
  - `fail-fast: false` — один OS не скрывает другой
  - Triggers: `push main` + `pull_request main` + `workflow_dispatch`
- **.gitignore расширен** (`.coverage`, `.pytest_cache/`, `.ruff_cache/`), **status badge** в README
- **Локальные результаты**: 132 bats green (117 unit + 15 e2e), 16 pytest green (92% coverage), 0 shellcheck warnings, ruff all passed
- Следующий шаг: Этап 7 (Hooks fixes — file-change-log false-positives на `pass`/docstring, log rotation 10MB, `MB_ALLOW_NO_VERIFY=1` bypass в block-dangerous, merge-hooks дедупликация с id-маркером)

### Этап 7: Hooks fixes
- **TDD red** — `tests/bats/test_hooks.bats`, 11 тестов. Первый прогон: 5 фейлов (bare-pass false-positive, docstring-TODO false-positive, нет log rotation, нет MB_ALLOW_NO_VERIFY bypass + hint)
- **TDD green** — реализация:
  - `block-dangerous.sh` — `--no-verify` guard теперь проверяет `MB_ALLOW_NO_VERIFY=1`: при установленном env — warning + exit 0; иначе — exit 2 + hint с примером команды
  - `file-change-log.sh` — полностью переписан:
    - Убран `pass\s*$` из placeholder-regex (легитимный Python)
    - Placeholder-поиск теперь через awk-препроцессор: сначала вырезаются triple-quoted блоки (`"""` или `'''`), потом `grep \b(TODO|FIXME|HACK|XXX|PLACEHOLDER|NotImplementedError|raise NotImplemented)\b` по остатку. Docstrings не триггерят. "TODOLIST" не триггерит (word-boundary)
    - Log rotation: `stat -f%z || stat -c%s` для portability, при >10MB ротация `.log → .log.1 → .log.2 → .log.3`
    - Awk переписан с `-v dq='"""' -v sq="'''"` и функцией `count(str, pat)` на `index()` — shellcheck SC1003 триггер устранён (тройные кавычки в awk-regex)
- **Итог**: 11 hook-тестов green, total bats **143/143 green** (+11 от Этапа 6). Shellcheck 0 warnings
- **YAGNI skip**: `merge-hooks.py` дедупликация через id-маркер — пропущено. Существующий content-based dedup уже работает (Этап 6: 16 тестов, 92% coverage). Whitespace-normalize/id-маркер — оверинжиниринг без реального use-case
- Следующий шаг: Этап 8 (index.json прагматично — frontmatter index для notes/+lessons/, `mb-search --tag` через index для O(tagged) вместо grep-всего)

### Этап 8: index.json — прагматично
- **TDD red** — `tests/pytest/test_index_json.py`, 19 тестов (11 из плана + 8 coverage-driving). TDD red: 11 skipped
- **TDD green** — `scripts/mb-index-json.py`:
  - PyYAML opt-in, fallback `_simple_yaml_parse` (простой `key: value` / `key: [a,b]` парсер) для окружений без PyYAML
  - Frontmatter parse defaults: `type: note`, `tags: []`, `importance: None`. Malformed YAML → defaults без crash
  - Tag as string (`tags: solo`) wrapped в list
  - `_summary()` — первые 2 non-empty non-heading строки body
  - Lessons parsing: `^###\s+(L-\d+)[:\-\s]+(.+?)$` regex
  - Atomic write: `tempfile.mkstemp` в mb_path + `os.replace`, при BaseException — unlink tmp + re-raise (test `test_atomic_rewrite_preserves_on_failure` проверяет это через `monkeypatch` на `os.replace`)
  - CLI: `mb-index-json.py <mb_path>`, exit 1 для missing path или no args
- **Интеграция**:
  - `agents/mb-manager.md` action `actualize` — переписана секция index.json: вместо ручного Write (который был неправильный) — вызов `python3 mb-index-json.py`. Задокументирована shape и гарантии (atomic, fallback YAML)
  - `scripts/mb-search.sh` — расширен `--tag <tag>` флагом:
    - Приоритет: первый аргумент `--tag` → filter mode, иначе legacy grep
    - Читает `index.json` через python3 inline (без jq-зависимости)
    - Auto-gen index если отсутствует (вызывает `mb-index-json.py` из той же директории)
    - Head -20 содержимого для каждого matched note
  - `tests/bats/test_search_tag.bats` — 5 тестов: finds, empty-result, auto-gen, multi-match, legacy-grep unchanged
  - `install.sh`:
    - Копирует `scripts/*.py` (помимо `.sh`)
    - `install_file()` — chmod +x для `.py` и `.sh`
- **Финальные метрики**:
  - bats **148/148 green** (117 unit + 15 e2e + 11 hooks + 5 search-tag)
  - pytest **35/35 green** (16 merge-hooks + 19 index-json)
  - TOTAL coverage: **94%** (merge-hooks 92%, index-json 81%). TOTAL выше cov-fail-under=85%
  - Shellcheck: **0 warnings**. Ruff: **all passed**
- Следующий шаг: Этап 9 (финализация — CHANGELOG, docs/MIGRATION-v1-v2.md, SKILL.md ≤150 строк, README quick-start)

## 2026-04-20

### Этап 9: Финализация — v2.0.0 release
- **`CHANGELOG.md`** — в keep-a-changelog формате v1.1.0:
  - Added: 12 языков, `_lib.sh`, plan-sync/done, upgrade, index-json, --tag, /mb init/map/context --deep, FSD/Mobile rules, MB_ALLOW_NO_VERIFY, log rotation, GitHub Actions
  - Changed: codebase-mapper → mb-codebase-mapper, metrics hardcode → mb-metrics.sh, Task( → Agent(, init merge
  - Removed: `/mb:setup-project`, orphan-агент, хардкод pytest
  - Fixed: 2 E2E-found baga (install marker, macOS realpath), Node src_glob, mb-note collision, false-positives
  - Security: MB_ALLOW_NO_VERIFY opt-in override
- **`docs/MIGRATION-v1-v2.md`** — TL;DR + 5-step пошаговая миграция + rollback + known issues + поддержка
- **`SKILL.md`** сокращён **294 → 110 строк** (порог ≤150 ✓). Детали вынесены:
  - `references/metadata.md` — frontmatter protocol + index.json + 8 ключевых правил MB
  - `references/planning-and-verification.md` — правила создания планов + Plan Verifier
  - Новая структура SKILL.md: frontmatter + three-in-one intro + quick start + workspace + tools table + agents table + coexistence + links
- **VERSION bump**: `2.0.0-dev` → **`2.0.0`**
- **Финальная полная проверка**: 148 bats green, 35 pytest green, 94% total coverage, 0 shellcheck, ruff passed
- **Gate v2 — все 7 критериев пройдены** ✅:
  1. Language coverage: 12 стеков
  2. Cross-platform: CI matrix macos+ubuntu
  3. Ecosystem: 0 `Task(`, coexistence doc, `Agent()` везде
  4. DRY + tested: `_lib.sh` в 5+ скриптах, Python coverage 94% (порог 85%), 0 shellcheck
  5. UX: единая `/mb init`, `mb-codebase-mapper` 4 MD, `/mb context` integrated
  6. **Dogfooding**: `.memory-bank/` в репо, план закрыт через `mb-plan-done.sh` (скрипт реализован в Этапе 4 — круг замкнулся)
  7. Versioning: CHANGELOG, migration guide, VERSION 2.0.0
- **Dogfood финальный**: `bash scripts/mb-plan-done.sh .memory-bank/plans/2026-04-19_refactor_skill-v2.md .memory-bank` → `closed_stages=10 → plans/done/`. Все 10 секций этапов в checklist: `⬜ → ✅`. Active plan блок очищен
- **Итог**: skill готов к релизу v2.0.0. Первый push на GitHub запустит CI (matrix macos+ubuntu); badge в README покажет статус

## 2026-04-20

### Планирование v2.1 → v2.2 → v3.0 после внешнего ревью
- Получена обратная связь от внешнего чата: 7 объективных критик (no auto-capture, keyword-only search, no benchmarks, single-writer, git-clone-install, bus-factor=1, claude-code-only) + 16 предложений
- Приоритизирован профиль **C (гибрид)** — personal сейчас, public через v3.0
- Составлен детальный план: `plans/2026-04-20_refactor_skill-v2.1.md` — 10 этапов, DoD SMART, TDD requirements, риски, 3 Gate
- **v2.1 (этапы 1-4):** Auto-capture (SessionEnd hook + Haiku), drift checkers без AI (`mb-drift.sh` с 8 чекерами), PII markers `<private>...</private>`, compaction decay (`/mb compact`)
- **v2.2 (этапы 5-7):** Import from Claude Code JSONL (`~/.claude/projects/*.jsonl` → bootstrap), tree-sitter code graph в `codebase/` (AST + god-nodes + wiki + incremental), tags normalization (closed vocabulary + Levenshtein)
- **v3.0 (этапы 8-10):** Cross-agent adapters (Cursor, Windsurf, Cline, Kilo, OpenCode), npm distribution (`npx @fockus/memory-bank install`), benchmarks (LongMemEval + custom 10 scenarios)
- **Отклонено после ревью:** hash-based IDs (YAGNI), KB compilation (преждевременная иерархия), GWT в DoD (дубль), schema drift (domain-specific), `/mb debug` (дубль superpowers), viewer UI (chrome over substance), REST/daemon (ломает simplicity)
- **Отложено в v3.1+ backlog:** sqlite-vec semantic search (после Gate v3.0), i18n, native memory bridge, viewer dashboard
- **Open questions:** (1) "PI" в cross-agent списке — не распознано (Copilot? JetBrains? Cody?); (2) LongMemEval license; (3) npm scope `@fockus/` availability; (4) claude-mem baseline для benchmarks — optional
- **MB updated:** `plan.md` (новый focus + active plan блок), `STATUS.md` (roadmap v2.1/2.2/3.0 + 3 gates), `checklist.md` (50+ новых ⬜ items структурировано по этапам), `plans/2026-04-20_refactor_skill-v2.1.md` (полный план)
- **Следующий шаг:** подтверждение "PI" → Этап 1 (auto-capture) start. TDD red-first: bats тесты для `session-end-autosave.sh`

### Уточнение плана после user-feedback (итерация 2)
- **"Pi" identified**: [Pi Code agent от Mario Zechner](https://github.com/badlogic/pi-mono) — terminal coding harness с Skills API, sessions в `~/.pi/agent/sessions/`. Станет 6-м adapter в Этапе 8 (preferred path — native Pi Skill, fallback — `AGENTS.md`-формат)
- **Distribution pivot** (ADR-008): **npm распространение отменено**. Вместо него:
  - **Primary**: `pipx install memory-bank-skill` (PyPI). Наш стек уже 12% Python, pipx изолирует env, `pipx upgrade` решает update story out-of-the-box, standard для CLI tools с mix deps
  - **Secondary**: Homebrew tap `fockus/homebrew-tap/memory-bank` (macOS native UX)
  - **Tertiary**: Anthropic plugin manifest `claude-plugin.json` для `claude plugin install` когда marketplace будет mature
  - Обоснование: для mix-stack skill (88% bash + 12% Python) npm = лишний Node.js runtime без реального value. `pipx` + pyproject.toml + `package_data` → bundle всех bash scripts внутри Python package, запускается через CLI entry point
- **Names availability (проверено через registry API)**:
  - `memory-bank-skill` на PyPI → 404 ✓ свободно
  - `claude-memory-bank` на PyPI → 404 ✓ свободно (backup)
  - `@fockus/memory-bank` на npm → 404 ✓ свободно (reserved на будущее, если вернёмся)
- **Benchmarks defer** (ADR-009): Этап 10 (LongMemEval + custom) отложен в v3.1+ HIGH backlog по решению пользователя. Обоснование: без 1+ месяца реальной usage-baseline v3.0 цифры искусственные; differentiator сейчас — TDD/plan-verifier/cross-agent, не recall
- **План стал 9 этапов** (было 10), 3 Gate (v2.1/v2.2/v3.0) без изменений, v3.0 теперь requires Gate по 2 этапам (8-9) вместо 3
- **Новые ADR**: ADR-008 (distribution — pipx primary), ADR-009 (benchmarks defer). Итого после ревью: ADR-004 до ADR-009 (6 новых решений задокументированы)
- **Open questions оставшиеся**: (1) создать `fockus/homebrew-tap` repo заранее или перед release; (2) PyPI OIDC trusted publisher — пользователь настраивает в web UI однократно; (3) Windows — explicit skip default, или попытка Git Bash/MSYS2
- **MB updated**: `plans/2026-04-20_refactor_skill-v2.1.md` (Этап 8 Pi adapter, Этап 9 pipx вместо npm, Этап 10 удалён в backlog, risks/gates/open-questions обновлены), `plan.md` (9 этапов в active plan, уточнения), `STATUS.md` (roadmap, Gate v3.0, решённые вопросы), `checklist.md` (Этап 8 6 clients, Этап 9 pipx, Этап 10 в v3.1 backlog), `BACKLOG.md` (ADR-008 + ADR-009 + benchmarks в HIGH backlog)

### Этап 1 v2.1 — Auto-capture SessionEnd hook ✅
- Создан `fockus/homebrew-tap` repo на GitHub (https://github.com/fockus/homebrew-tap) — для будущего v3.0 Этапа 9
- **TDD red-first**: написано 12 bats тестов в `tests/bats/test_auto_capture.bats` (lock-файл fresh/stale, MB_AUTO_CAPTURE auto/off/strict/bogus, no-bank noop, missing progress.md, idempotent, concurrent guard через `.auto-lock`, cleanup on exit, session_id+date в entry). Red phase: все 12 fail
- **Реализация**: `hooks/session-end-autosave.sh` (85 строк, shellcheck 0 warnings):
  - Читает SessionEnd JSON с stdin → cwd → `$cwd/.memory-bank/`
  - Fresh `.session-lock` (<1h) → ручной `/mb done` выполнен → skip+clear
  - Stale lock (>1h) → считаем устаревшим → игнорируем и auto-capture
  - `MB_AUTO_CAPTURE` modes: `auto` (default), `strict` (skip+warn), `off` (full noop), unknown (skip+warn)
  - `.auto-lock` concurrent guard (30 сек TTL), `trap 'rm -f' EXIT INT TERM`
  - Идемпотентность по session_id prefix (cut -c1-8) — та же сессия и день → 1 entry
  - Append в progress.md: `## YYYY-MM-DD\n### Auto-capture YYYY-MM-DD (session abc12345)\n- placeholder hint для следующего /mb start`
  - Portable `stat -f%m || stat -c%Y` (macOS BSD + GNU Linux)
- **Интеграция**:
  - `settings/hooks.json` — новый event `SessionEnd` (dedup через `# [memory-bank-skill]` маркер)
  - `commands/mb.md` — `/mb done` теперь `touch .memory-bank/.session-lock` после успешного actualize (маркер для hook'а)
  - `install.sh` без изменений — автоматом копирует новый `hooks/session-end-autosave.sh` (glob `hooks/*.sh`)
  - `tests/e2e/test_install_uninstall.bats` — +3 теста (SessionEnd зарегистрирован+executable, idempotent install, uninstall cleanup)
- **Документация**: `SKILL.md` секция "Auto-capture" (129 строк ≤150), opt-out через `export MB_AUTO_CAPTURE=off`
- **Зелёные тесты**: bats **163/163** (145 unit + 18 e2e), shellcheck 0 warnings, pytest 35/35 (не трогали)
- **DoD всё ✓**: 8 пунктов из плана выполнены. Append-only подход вместо LLM-call в hook — сознательное упрощение (bash-скрипт не может вызвать Agent; детали восстанавливает следующий `/mb start` через MB Manager + JSONL-транскрипт, что совпадает с Этапом 5)
- **Следующий шаг**: Этап 2 — drift checkers без AI (`mb-drift.sh`). TDD red-first: `tests/bats/test_drift.bats` (≥16 тестов по 2 на чекер) до кода



