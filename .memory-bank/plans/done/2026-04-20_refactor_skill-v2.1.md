# План: refactor — skill v2.1 → v2.2 → v3.0 (путь к public-ready product)

## Контекст

**Проблема:** v2.0.0 released, но обратная связь от внешнего ревью выявила пробелы vs mature memory-инструменты (claude-mem, agentmemory, mex, beads, Graphify). Для personal-use skill силён (TDD/Clean/Plan Verifier), но для public-release не хватает: (1) auto-capture — забыла `/mb done` → потеряна сессия, (2) PII-защиты — финтех-контекст чувствителен к утечке через `index.json`, (3) drift-diagnostics через AI дорого — 80% проблем ловятся bash-чекерами, (4) decay старых планов/заметок — со временем банк разбухает, (5) cold-start для новых проектов требует недель наработки, (6) keyword-only search не находит семантические совпадения, (7) code graph (`.memory-bank/codebase/`) сейчас markdown-only, без AST, (8) distribution = `git clone` → adoption kill, (9) без benchmarks skill теряется среди альтернатив.

**Профиль:** гибрид (C) — сначала polish для себя (v2.1 + v2.2), затем public release (v3.0).

**Ожидаемый результат:**
- **v2.1:** auto-capture + deterministic drift + PII safety + decay — zero-effort upkeep, data-hygiene
- **v2.2:** JSONL import + tree-sitter code graph + tags normalization — 10× reach по знаниям о проекте, cold-start за минуты
- **v3.0:** cross-agent (Cursor/Windsurf/Cline/Kilo/OpenCode/Pi) + pipx/PyPI distribution + Homebrew tap — public-ready с one-command install и простым upgrade
- **v3.1+ backlog:** benchmarks (LongMemEval + custom), sqlite-vec semantic search, native memory bridge — подтверждение конкурентоспособности цифрами после полевого использования

**Связанные файлы:**
- Hooks: `hooks/session-end-autosave.sh` (новый), `hooks/block-dangerous.sh`
- Scripts: `scripts/mb-drift.sh`, `mb-compact.sh`, `mb-import.py`, `mb-codegraph.py`, `mb-tags-normalize.sh` (все новые)
- Modify: `scripts/mb-index-json.py` (PII), `mb-search.sh` (PII replacement), `agents/mb-doctor.md` (drift-first), `agents/mb-manager.md` (compact)
- Install: `install.sh` (hooks, cross-agent), `settings/merge-hooks.py` (SessionEnd)
- Tests: `tests/bats/test_*.bats` + `tests/pytest/test_*.py` для каждого нового script
- Docs: `CHANGELOG.md` (2.1, 2.2, 3.0), `docs/MIGRATION-v2-v3.md`, `README.md` (benchmarks section)
- New: `benchmarks/` dir с LongMemEval harness, `package.json` для npm wrapper

---

## Этапы

<!-- mb-stage:1 -->
### Этап 1: Auto-capture через SessionEnd hook (v2.1)

**Что сделать:**
- Создать `hooks/session-end-autosave.sh` — lightweight actualize (core files + progress append), без создания note
- Lock-файл `.memory-bank/.session-lock` пишется командой `/mb done` (ручной путь) → hook видит lock → skip и удаляет
- Флаг `MB_AUTO_CAPTURE=strict|auto|off` в env (читается hook'ом), default `auto` для новых установок
- `install.sh` регистрирует SessionEnd hook в `~/.claude/settings.json` через `settings/merge-hooks.py` (расширить существующий скрипт)
- Внутри hook — `Agent(subagent_type="mb-manager", model="haiku", action="auto-actualize")` для cost-эффективности
- Документация: новая секция в `SKILL.md` + `CHANGELOG.md`

**Тестирование (TDD — тесты ПЕРЕД реализацией):**
- `tests/bats/test_auto_capture.bats` (TDD red, ≥8 тестов):
  - lock-файл создан → hook skip + removes lock
  - нет lock-файла + `MB_AUTO_CAPTURE=auto` → hook runs
  - `MB_AUTO_CAPTURE=off` → hook noop
  - `MB_AUTO_CAPTURE=strict` → hook требует lock (warning если нет)
  - не `.memory-bank/` → hook noop (нет проекта с MB)
  - lock-файл >1h old → считается stale, hook runs
  - concurrent invocation (2 hook'а параллельно) → один добивает lock, второй skip
  - idempotent: 2 запуска подряд → нет дубликатов в progress.md
- Расширение `tests/pytest/test_merge_hooks.py` — SessionEnd event регистрируется в settings.json

**DoD (SMART):**
- [ ] `hooks/session-end-autosave.sh` создан, ≤80 строк, shellcheck 0 warnings
- [ ] bats 8+/8+ green (100% веток включая error paths)
- [ ] Lock-файл mechanism работает: `/mb done` пишет `.session-lock`, auto-hook его видит и пропускает
- [ ] install.sh регистрирует SessionEnd в `~/.claude/settings.json` через merge-hooks.py, идемпотентно
- [ ] uninstall.sh удаляет SessionEnd hook (e2e тест добавлен в `test_install_uninstall.bats`)
- [ ] Документация: `SKILL.md` секция "Auto-capture" + пример `MB_AUTO_CAPTURE=off` для opt-out
- [ ] Smoke-test: при фейковой SessionEnd инъекции `progress.md` получает запись за текущую дату без `/mb done`

**Правила кода:** SRP (hook делает одно — actualize), DRY (переиспользует `_lib.sh`), KISS (lock-файл вместо IPC)

**Риски:**
- Haiku может некорректно актуализировать сложные проекты → mitigation: в auto-режиме обновляет ТОЛЬКО progress.md (append-only, безопасно), полный actualize — только ручной `/mb done`

---

<!-- mb-stage:2 -->
### Этап 2: Drift checkers без AI (`mb-drift.sh`) (v2.1)

**Что сделать:**
- Создать `scripts/mb-drift.sh` — 8 deterministic чекеров (bash-only, 0 AI-токенов):
  1. `path` — все ссылки вида `notes/X.md`, `plans/X.md` в core-файлах проверить `test -e`
  2. `staleness` — файл в `.memory-bank/` не обновлялся >30 дней / >50 коммитов с последнего edit → warn
  3. `script-coverage` — команды из `plan.md` (формата `npm run X`, `make X`, `bash scripts/X`) проверить что существуют
  4. `dependency` — версии из documented stack (например "Python 3.12" в STATUS) vs реальные из `package.json`/`go.mod`/`pyproject.toml`
  5. `cross-file` — одна и та же версия dep в разных файлах `.memory-bank/` (не расходится)
  6. `index-sync` — `index.json` mtime свежее всех `notes/*.md` (иначе нужно `mb-index-json.py`)
  7. `command` — `npm run X` / `make X` из workflow-файлов существуют в package.json/Makefile
  8. `frontmatter` — все `notes/*.md` имеют валидный YAML frontmatter (вызываем `mb-index-json.py --dry-run`)
- Output format: `key=value` (совместимо с `mb-metrics.sh`), секция `drift_warnings=N` + перечень
- Рефакторинг `agents/mb-doctor.md`: шаг 1 — `mb-drift.sh`, шаг 2 — AI вызов ТОЛЬКО если `drift_warnings > 0`
- Опциональный pre-commit hook: `scripts/mb-drift-precommit.sh` (wrapper, exit 1 если critical warnings)

**Тестирование (TDD):**
- `tests/bats/test_drift.bats` (≥16 тестов — по 2 на чекер):
  - Для каждого чекера: 1 positive (чистый кейс) + 1 negative (broken кейс) → warning
  - `mb-drift.sh` на чистом `.memory-bank/` → `drift_warnings=0`
  - `mb-drift.sh` с broken symlink в notes/ → `warnings includes "path"`
  - `mb-drift.sh` с stale STATUS.md (touched 60 дней назад) → warning
  - Exit code: 0 если 0 warnings, 1 если ≥1 warning (для pre-commit integration)

**DoD (SMART):**
- [ ] `scripts/mb-drift.sh` создан, ≤200 строк, shellcheck 0 warnings
- [ ] 8 чекеров работают, каждый покрыт ≥2 bats-тестами (≥16 total)
- [ ] `agents/mb-doctor.md` обновлён: шаг 1 — drift, шаг 2 — AI-call-if-needed (диффом ≤30 строк)
- [ ] На фикстуре `tests/fixtures/broken-mb/` drift находит ≥5 из 8 категорий (smoke)
- [ ] На живом `.memory-bank/` этого репо drift выдаёт 0 warnings (dogfood)
- [ ] Экономия AI-токенов: на чистом банке `mb-doctor` не вызывает LLM (verified via log)
- [ ] `references/templates.md` — новая секция "Drift checks"

**Правила кода:** SRP (каждая функция — один чекер), DRY (`_lib.sh` для detect_*), POSIX (`stat -f%m || stat -c%Y` cross-platform)

---

<!-- mb-stage:3 -->
### Этап 3: PII markers `<private>...</private>` (v2.1)

**Что сделать:**
- Расширить `scripts/mb-index-json.py` — парсер блоков `<private>...</private>`:
  - Содержимое НЕ попадает в `summary` entry
  - НЕ попадает в поле `tags` (если теги внутри блока — игнорируются)
  - Флаг `has_private: true` в entry для downstream фильтрации
- Расширить `scripts/mb-search.sh`:
  - При read из файла с `<private>` блоками → заменять содержимое на `[REDACTED]` перед выводом
  - `--show-private` флаг (explicit opt-in) для показа без redaction (требует `MB_SHOW_PRIVATE=1` env для double-confirmation)
- Расширить `hooks/file-change-log.sh`: если коммит содержит `<private>...</private>` → warning (не блокировать, чтобы не ломать workflow)
- Documentation: секция "Private content" в `SKILL.md` с примерами

**Тестирование (TDD):**
- `tests/pytest/test_index_json.py` — ≥6 новых тестов:
  - `<private>секрет</private>` в body → НЕ попадает в summary
  - `<private>tag1, tag2</private>` в frontmatter tags section → игнорируется parser'ом
  - entry получает `has_private: true` флаг
  - Multiple `<private>` блоков в одном файле → все redacted
  - Unclosed `<private>` (нет `</private>`) → fail gracefully (parser не падает, warning в stderr)
  - Nested markdown внутри `<private>` (код, списки) → корректно вырезается до закрывающего тега
- `tests/bats/test_search_private.bats` — ≥4 тестов:
  - `mb-search.sh query` на файле с private → вывод содержит `[REDACTED]`
  - `mb-search.sh --show-private` без env → отказ с hint
  - `MB_SHOW_PRIVATE=1 mb-search.sh --show-private` → полный вывод
  - search по тексту внутри private блока → не находит (since not indexed)

**DoD (SMART):**
- [ ] `mb-index-json.py` парсит `<private>` корректно, pytest 6+/6+ green
- [ ] `mb-search.sh` делает REDACTED replacement, bats 4+/4+ green
- [ ] Total coverage `mb-index-json.py` остаётся ≥85%, `mb-search.sh` ≥75%
- [ ] Documentation: `SKILL.md` секция + `references/metadata.md` пример
- [ ] Dogfood: создать `.memory-bank/notes/` запись с тестовым `<private>` → verify в search
- [ ] Security smoke-test: grep `<private>` на `index.json` → ничего (содержимое не утекло)

**Риски:**
- Пользователь забыл `</private>` → utility parser должен fail-safe (treat как plain text с warning)

---

<!-- mb-stage:4 -->
### Этап 4: Compaction decay `/mb compact` (v2.1)

**Корректировка (2026-04-20):** план архивируется только если **статус = done** (явный сигнал завершённости). Одной только давности недостаточно — старый план может быть всё ещё актуальным (long-running feature). Критерий "done" берём из 3 источников (OR):
1. Файл уже физически в `plans/done/` (перемещён `mb-plan-done.sh`) — primary signal
2. В `checklist.md` строка с путём плана содержит `✅` или `[x]`
3. В `STATUS.md` или `progress.md` есть запись вида `план ... завершён|done|closed|shipped` с ссылкой на план

Если план активный (не done) — **НЕ ТРОГАТЬ** даже при mtime >180 дней. Для note'ов основной сигнал — `importance: low` + нет активных референсов.

**Что сделать:**
- Создать `scripts/mb-compact.sh`:
  - **Plans:** кандидаты — файлы в `plans/done/**/*.md` ИЛИ `plans/*.md` помеченные как done в checklist/STATUS. Если file в `plans/done/` + mtime >60 дней → компрессия через Haiku (`mb-manager`) в 1 строку `BACKLOG.md` секция `## Archived plans` (формат: `- YYYY-MM-DD: <type> — <topic> → <outcome summary> (was: plans/done/<file>.md)`) → delete file
  - **Active plans (не в done/):** пропускать всегда, даже >180 дней. Вместо этого — warning "plan <file> старше 180 дней, но не done — проверь актуальность"
  - **Notes:** `notes/*.md` с `importance: low` И mtime >90 дней И нет референсов в `plan.md`/`STATUS.md`/`checklist.md`/`RESEARCH.md` → move в `notes/archive/` + сжать body в 3-строчный summary
  - `index.json` расширить: archived entries получают `archived: true` (findable через `--include-archived`, исключены из default)
- Команда `/mb compact` в `commands/mb.md`:
  - `/mb compact --dry-run` (default) — показывает что будет сжато + reasoning per candidate ("✓ archive: reason=done_in_checklist + mtime=65d")
  - `/mb compact --apply` — выполняет
- Интеграция в `/mb done`: раз в 7 дней (check mtime `.memory-bank/.last-compact`) автоматически запускать dry-run и показывать user prompt "X plans, Y notes ready for compact, run /mb compact?"

**Тестирование (TDD):**
- `tests/bats/test_compact.bats` (≥15 тестов):
  - plan в `plans/done/` <60 дней → не трогать (age too low)
  - plan в `plans/done/` =61 день → компрессия + BACKLOG entry + delete
  - plan в `plans/` (active) даже >180 дней → **НЕ трогать** + warning "старый но не done"
  - plan отмечен `✅` в checklist.md + mtime >60d → считается done → компрессия
  - plan отмечен `⬜` в checklist.md + mtime >180d → **НЕ трогать** (active)
  - plan в `plans/` и в progress.md запись "план X завершён" + mtime >60d → считается done → компрессия
  - low-importance note >90d → archived
  - medium-importance note >90d → не тронуто
  - note упомянута в `plan.md` → не тронуто (safety-net) даже если low+>90d
  - `--dry-run` → 0 file changes, stdout reasoning
  - double run `--apply` → idempotent
  - archived entries в index.json имеют `archived: true`
  - default `mb-search` НЕ находит archived
  - `.last-compact` timestamp обновляется после `--apply`
  - broken frontmatter note → skip с warning, не блокирует batch

**DoD (SMART):**
- [ ] `scripts/mb-compact.sh` создан, ≤300 строк, shellcheck 0 warnings
- [ ] bats 15+/15+ green
- [ ] `commands/mb.md` содержит `/mb compact` с examples + описание status-based логики
- [ ] `index.json` schema расширен `archived: bool` (пример в `references/metadata.md`)
- [ ] `/mb done` интеграция: раз в неделю prompt через stdout в `mb-context.sh`
- [ ] Dogfood: создать note с `importance: low` + artificial mtime >90d + done-signal → verify archival
- [ ] Safety #1: создать active plan с >180d mtime в `plans/` → verify **НЕ** archive-ится
- [ ] Safety #2: создать note с референсом в `plan.md` → verify **НЕ** archive-ится

**Риски:**
- LLM compression (Haiku) может потерять факты → mitigation: сохранять ссылку на исходник в BACKLOG (`was: plans/done/<file>.md`), файл УДАЛЯТЬ только в `--apply`. Плюс git history.
- Ложное срабатывание "done detection" на старом плане → mitigation: требовать ≥2 signals (в `plans/done/` + checklist ✅) или явный пометки в STATUS

---

<!-- mb-stage:5 -->
### Этап 5: Import from Claude Code JSONL (v2.2)

**Что сделать:**
- Создать `scripts/mb-import.py`:
  - Читает `~/.claude/projects/<project-path>/*.jsonl` (поиск по cwd → project-dir mapping)
  - Парсит события: `user_message`, `assistant_message` (с `tool_use` блоками), `tool_result`
  - Extraction strategy:
    - `progress.md`: даты из timestamp → группировка по дням, каждый день = H3 секция с top-5 инструментов (Write/Edit/Bash) + 1-2 строки summary через Haiku
    - `notes/`: architectural discussions detected via Heuristic (≥3 consecutive assistant messages >1K chars без tool_use) → compressed в note с auto-tag
    - `lessons.md`: debug-sessions detected (паттерн "error → fix → explain") → single-line lesson
    - `STATUS.md`: seed только если `.memory-bank/STATUS.md` пустой (первая строка + "Текущая фаза: определить" default)
- Команда `/mb import [--since YYYY-MM-DD] [--project <path>] [--dry-run]`
- Duplicate detection: SHA256 от (timestamp + first 500 chars) → skip если уже есть entry с тем же hash
- Resume on failure: `.memory-bank/.import-state.json` с прогрессом (last processed session ID)

**Тестирование (TDD):**
- `tests/pytest/test_import.py` (≥15 тестов):
  - Sample fixture JSONL (3 сессии, ~50 событий) → корректный parse
  - Dry-run: 0 file changes
  - Apply: progress.md получает N entries, notes/ N файлов
  - Duplicate detection: 2 запуска → idempotent
  - `--since 2026-01-01` → только события после даты
  - Resume: прервать после 1 сессии, restart → продолжает со 2-й (mock timestamp)
  - Broken JSONL line → skip + warning, продолжает
  - Пустая sessions → no-op, exit 0
  - PII в user-message (email, API key patterns) → auto-wrap в `<private>` (integration с Этапом 3)
  - Note importance default = `medium` (пользователь потом вручную меняет)
  - Tags auto-derived из топ-5 слов (простой TF-IDF, без LLM)
  - Long session (>100 events) → sampling (не грузить все в контекст LLM для compression)

**DoD (SMART):**
- [ ] `scripts/mb-import.py` создан, ≤400 строк, ruff 0 errors, type hints
- [ ] pytest 15+/15+ green, coverage ≥85%
- [ ] Cold-start: на пустом `.memory-bank/` + реальных JSONL этого репо → bootstrapped банк с осмысленными entries
- [ ] Duplicate detection работает: 2 запуска → 0 добавленных entries
- [ ] Команда `/mb import` документирована в `commands/mb.md`
- [ ] PII auto-wrap (интеграция с Этапом 3): email/API-key regex → `<private>` wrap
- [ ] Smoke: import для реального проекта пользователя → осмысленный `progress.md` за последние 30 дней

**Риски:**
- JSONL формат Anthropic может меняться → mitigation: schema validation + fallback, warning на unknown event types
- LLM compression на старые сессии дорого → mitigation: Haiku only, sampling >100 events, `--since` обязателен для первого run (пользователь сам выбирает горизонт)

---

<!-- mb-stage:6 -->
### Этап 6: Tree-sitter code graph в `codebase/` (v2.2)

**Что сделать:**
- Добавить зависимость `tree-sitter` + language grammars (python, go, rust, javascript, typescript, java, kotlin, swift, cpp, ruby) — как opt-in через `pip install memory-bank[codegraph]`
- Создать `scripts/mb-codegraph.py`:
  - Парсит все source-файлы проекта (detect stack через `_lib.sh`)
  - Строит граф: nodes = funcs/classes/modules, edges = imports/calls/inherits
  - Output: `.memory-bank/codebase/graph.json` (JSON Lines для incremental)
  - Генерирует `.memory-bank/codebase/god-nodes.md` — топ-20 узлов по `degree` (in+out) с file:line ссылками
  - Генерирует `.memory-bank/codebase/wiki/<node-name>.md` для top-N (default 10) "важных" узлов: signature, callers, callees, 1-строчный purpose (Haiku)
- SHA256 cache в `.memory-bank/codebase/.cache/` (file-hash → parsed AST) → incremental update (парсить только изменённые)
- Git post-commit hook (optional, opt-in): `scripts/mb-codegraph-precommit.sh` — incremental refresh
- Интеграция с `mb-codebase-mapper`: агент ПЕРВЫМ шагом вызывает `mb-codegraph.py`, затем консультируется по graph.json вместо grep

**Тестирование (TDD):**
- `tests/pytest/test_codegraph.py` (≥20 тестов):
  - Python fixture (10 файлов, 30 funcs, 50 imports) → корректный graph.json
  - Go fixture → corresponding nodes/edges
  - JS/TS mixed fixture → unified graph
  - Incremental: change 1 file, rerun → только 1 файл переparsed (via cache)
  - god-nodes.md: топ-20 сортировка по degree desc
  - wiki/ генерится только для opt-in top-N
  - Broken syntax file → skip с warning, не падает
  - Cross-language calls (Python calls Rust via FFI) → отдельные subgraphs, link by name match
  - Token budget: на repo 500 файлов генерация ≤60 сек (performance)
  - JSON schema validation (jsonschema library)

**DoD (SMART):**
- [ ] `scripts/mb-codegraph.py` создан, ≤500 строк, ruff 0 errors, type hints
- [ ] pytest 20+/20+ green, coverage ≥85%
- [ ] 10+ языков supported (tree-sitter grammars bundled as opt-in)
- [ ] На этом repo `mb-codegraph.py` строит graph за ≤30 сек, god-nodes выдаёт осмысленный топ
- [ ] Incremental работает: change 1 file → rerun ≤3 сек
- [ ] `mb-codebase-mapper` агент обновлён: читает `graph.json` вместо grep (diff ≤40 строк в агенте)
- [ ] Замер экономии токенов: сравнить "объясни auth в проекте" без graph (grep-ориентированный) vs с graph → ≥5× экономия в tokens (реальная метрика, пусть не 71.5×)
- [ ] Documentation: `references/codegraph.md` новый файл с schema + examples
- [ ] Optional install: `install.sh --with-codegraph` флаг

**Правила кода:** SRP (отдельный file per языковой parser-wrapper), DRY (shared AST→graph transformer), KISS (JSON Lines вместо SQLite/NetworkX — plain text для grep-compat)

**Риски:**
- tree-sitter grammars = C-extensions → установка heavy на некоторых платформах → mitigation: opt-in через extras, default skill работает без codegraph
- Большие repo → graph.json тяжёлый → mitigation: JSON Lines (stream-friendly), `--max-files` cap

---

<!-- mb-stage:7 -->
### Этап 7: Tags normalization (v2.2)

**Что сделать:**
- Создать `scripts/mb-tags-normalize.sh`:
  - Сканирует все `notes/*.md` frontmatter tags
  - Сравнивает с closed vocabulary в `.memory-bank/tags-vocabulary.md` (user-editable)
  - Detect синонимы через Levenshtein distance ≤2 (sqlite-vec, sqlite_vec, sqlite-db → consolidate)
  - Detect множественное vs единственное (tests vs test) → normalize to lemma
  - Interactive mode: выводит предлагаемые consolidations, user confirm → apply через `sed`-like rewrite
  - Batch mode: `--auto-merge` применяет только high-confidence (distance ≤1)
- Template `tags-vocabulary.md` с default-vocabulary (30 common tags: auth, bug, perf, arch, test, ...)
- Интеграция в `mb-doctor`: drift check "unknown tags" (тег not in vocabulary → warning)
- `mb-index-json.py` расширение: при индексации — автоматический lowercasing + hyphenation (camelCase → kebab-case, `FooBar` → `foo-bar`)

**Тестирование (TDD):**
- `tests/bats/test_tags_normalize.bats` (≥10 тестов):
  - 2 note'ы с tags `sqlite-vec` и `sqlite_vec` → auto-merge к `sqlite-vec`
  - `tests` vs `test` → consolidate to single (whatever is in vocabulary)
  - camelCase tag в note → при index.json стал kebab-case
  - `--dry-run` → 0 file modifications
  - `--auto-merge` распространяется только на distance ≤1
  - distance 2 → interactive prompt (в тесте mock'ается input)
  - `tags-vocabulary.md` absent → use default from template
  - тег НЕ в vocabulary + distance >2 → warning (drift check)

**DoD (SMART):**
- [ ] `scripts/mb-tags-normalize.sh` создан, ≤150 строк, shellcheck 0 warnings
- [ ] `tags-vocabulary.md` template в `references/` с 30 default tags
- [ ] bats 10+/10+ green
- [ ] `mb-index-json.py` auto-lowercase + kebab-case с pytest покрытием
- [ ] `mb-doctor` drift check "unknown tag" добавлен и ловит искусственный bad tag
- [ ] Dogfood: прогнать на этом banks → 0 конфликтов (т.к. мало tags) или применить consolidation

---

<!-- mb-stage:8 -->
### Этап 8: Cross-agent output — Cursor, Windsurf, Cline, Kilo, OpenCode, Pi Code (v3.0)

**Что сделать:**
- Разделить контент на слои:
  - **Universal**: `rules/RULES.md`, `.memory-bank/` markdown структура — одинаковы для всех клиентов
  - **Client-specific**: config-файл, slash-команды, hook-формат
- Adapter per client в `adapters/`:
  - `adapters/cursor.sh` → `.cursorrules` (converted from CLAUDE.md)
  - `adapters/windsurf.sh` → `.windsurfrules`
  - `adapters/cline.sh` → `.clinerules/` директория
  - `adapters/kilo.sh` → `.kilorules` (подтвердить формат — по коду Kilo Code репо)
  - `adapters/opencode.sh` → `AGENTS.md`
  - `adapters/pi.sh` → native Pi Skill package (`~/.pi/skills/memory-bank/`) — Pi имеет extensibility через Skills API (Mario Zechner, badlogic/pi-mono). Preferred path: публикация как Pi Skill, не просто rules-file. Fallback: `AGENTS.md`-формат если Skill API нестабилен
- Расширить `install.sh`:
  - Interactive prompt "Which clients?" (multi-select) — default только Claude Code
  - Генерит только выбранные
  - manifest отслеживает сгенерированные файлы (для uninstall)
- Slash-команды: генерим markdown-wrappers где возможно, иначе документация "В этом клиенте /mb не поддерживается, используйте manual workflow"
- Hooks: для non-CC клиентов hooks недоступны — SessionEnd auto-capture graceful degrade to "pre-commit git hook на изменения в `.memory-bank/`". Для Pi — использовать его native session-save в `~/.pi/agent/sessions/` как сигнал

**Тестирование:**
- `tests/e2e/test_cross_agent_install.bats` (≥14 тестов — 2 per client × 7 clients = 14):
  - Isolated HOME sandbox, install.sh с `--clients cursor,windsurf,opencode,pi`
  - Проверка генерации правильных config-файлов/skill-packages
  - uninstall roundtrip: всё удалено
  - manifest содержит все созданные файлы
  - Pi adapter: либо skill зарегистрирован в `~/.pi/skills/`, либо `AGENTS.md` fallback

**DoD (SMART):**
- [ ] 6 adapters созданы и работают: Cursor, Windsurf, Cline, Kilo, OpenCode, Pi Code
- [ ] e2e 14+/14+ green, manifest roundtrip чистый для всех 6
- [ ] `install.sh` interactive mode работает, `--clients <list>` non-interactive (valid values: claude-code, cursor, windsurf, cline, kilo, opencode, pi)
- [ ] `uninstall.sh` корректно удаляет client-specific артефакты (через manifest)
- [ ] Documentation: `docs/cross-agent-setup.md` — example per client + скриншот где применимо
- [ ] Smoke test: установка skill + Cursor → `.cursorrules` в Cursor работает; установка в Pi → `~/.pi/skills/memory-bank/` регистрируется и `/mb context` работает
- [ ] Research upfront: за 1-2 часа перед началом этапа проверить актуальный формат конфигов всех 6 клиентов (формат меняется) — результат в `notes/2026-XX-XX_cross-agent-research.md`

---

<!-- mb-stage:9 -->
### Этап 9: pipx/PyPI distribution (v3.0) — primary `pipx install memory-bank-skill`

**Контекст выбора distribution:**
У skill mix-stack (88% bash + 12% Python). Рассмотрены варианты:
- **npm** — требует Node.js, overhead без value (bash скрипты не requires Node runtime)
- **pipx + PyPI** — Python уже in-stack, `pipx` изолирует env, `pipx upgrade` решает update story out-of-the-box, standard для CLI tools с mix deps
- **Homebrew tap** — native macOS UX, но only macOS/linuxbrew
- **curl | bash** — простейший one-liner, но security concerns

**Выбор:** pipx/PyPI как **primary** + Homebrew tap как **secondary для macOS** + `claude plugin install` (Anthropic marketplace) как **tertiary** для нативного Claude Code UX. Фиксируется в ADR-008.

**Что сделать:**
- Создать `pyproject.toml` в корне:
  - `[project]` name = `memory-bank-skill` (PyPI-свободно ✓), version = читается из `VERSION` файла
  - `[project.scripts]` entry point `memory-bank = memory_bank_skill.cli:main`
  - Python dep minimum: `PyYAML` (optional), `tree-sitter-languages` (extras `[codegraph]`)
  - `[tool.hatch.build]` включает все `scripts/*.sh`, `agents/*.md`, `commands/*.md`, `hooks/*.sh`, `rules/*.md` как `package_data`
- Создать `memory_bank_skill/` Python package:
  - `cli.py` — argparse wrapper с sub-commands: `install`, `uninstall`, `init`, `version`, `self-update`
  - `cli install` экспортирует bundled bash в `~/.claude/skills/memory-bank/` и вызывает существующий `install.sh` внутри изолированной temp dir
  - `cli uninstall` — zeroes install
  - `cli self-update` — `pipx upgrade memory-bank-skill` wrapper с human message
  - Detects platform (macos/linux/windows); Windows → graceful exit с "Use WSL" hint
  - Flags: `--minimal`, `--full`, `--clients <list>`, `--with-codegraph`
- `README.md` quick-start обновить: `pipx install memory-bank-skill && memory-bank install`
- Homebrew tap `fockus/homebrew-tap/memory-bank.rb`:
  - Formula использует PyPI release как upstream (`url "https://files.pythonhosted.org/..."`, авто-версия)
  - `brew install fockus/tap/memory-bank` → `brew upgrade` работает
- Anthropic plugin manifest `claude-plugin.json`:
  - Parallel path: `claude plugin install fockus/memory-bank` (когда marketplace доступен нативно)
- Publish automation:
  - GitHub Action `.github/workflows/publish.yml` на git tag `v*`: `python -m build` → `twine upload` → `brew bump-formula-pr` для homebrew tap
  - PyPI trusted publisher (OIDC, без токенов в secrets)

**Тестирование:**
- `tests/e2e/test_pipx_install.bats` (≥10 тестов):
  - `pipx install --editable .` в tmp → `memory-bank --version` возвращает текущий VERSION
  - `memory-bank install` в tmp project → `.memory-bank/` создан, `~/.claude/skills/memory-bank/` наполнен
  - `memory-bank uninstall` → чисто (ничего не осталось)
  - `--minimal` флаг работает
  - `--clients cursor,windsurf` интеграция с Этапом 8
  - `memory-bank self-update` (mock pipx) → вызывает правильную команду
  - Windows → graceful exit с hint "Use WSL"
  - Старая локальная установка + pipx install → detect existing, warn, offer migrate
  - `pipx upgrade memory-bank-skill` → новая версия подхватывается
  - Reinstall idempotent: 2 install подряд → 0 дубликатов в settings.json
- CI matrix расширить: `[ubuntu-latest, macos-latest]` + Python 3.11 + 3.12
- `tests/pytest/test_cli.py` (≥8 unit-тестов): argparse handling, platform detect, version read

**DoD (SMART):**
- [ ] `pyproject.toml` + `memory_bank_skill/` package созданы, `python -m build` passes без warnings
- [ ] `pipx install memory-bank-skill` (из test PyPI или local wheel) работает macos + ubuntu
- [ ] e2e 10+/10+ green, pytest cli 8+/8+ green, coverage CLI ≥85%
- [ ] CI `.github/workflows/publish.yml` auto-publishes на git tag `v*` к PyPI через trusted publisher (OIDC)
- [ ] Homebrew tap `fockus/homebrew-tap` создан, formula работает: `brew install fockus/tap/memory-bank`
- [ ] README.md quick-start = `pipx install memory-bank-skill && memory-bank install`
- [ ] Anthropic plugin manifest `claude-plugin.json` валиден (подготовлено на будущее, когда marketplace расширится)
- [ ] Documentation: `docs/install.md` — три варианта (pipx / homebrew / `claude plugin`), upgrade story per каждому
- [ ] Smoke: clean tmp home → `pipx install` → `memory-bank install` → `/mb init` → всё работает → `pipx upgrade` lifts version

**Риски:**
- pipx package size с bundled bash scripts — OK (<2MB)
- Windows support — нет bash → explicit skip с hint (не блокер, как и было раньше)
- Anthropic plugin API может ещё меняться → `claude-plugin.json` прикладываем but not requiring, main путь через pipx
- Homebrew tap — требует отдельный репозиторий `homebrew-tap` → создать перед первым release

---

## Риски и mitigation (общие)

| Риск | Вероятность | Mitigation |
|------|------------|------------|
| Scope creep — 9 этапов переходит в 15+ | H | Жёстко следовать приоритизации. Доп. идеи → BACKLOG, не в план |
| Этап 6 (tree-sitter) blocks всё — heavy deps | M | opt-in через extras, skill работает без него |
| User-adoption на cross-agent низкий — форматы конфигов у клиентов меняются | M | Research upfront в начале Этапа 8, smoke-test per client вручную |
| Pi Code Skill API нестабилен — format может меняться | M | Fallback на `AGENTS.md`-формат если native Skill не подходит |
| Regression в v2.0 при v2.1 изменениях | L | Полный CI matrix, e2e roundtrip в каждом этапе |
| Haiku (auto-capture) деградирует progress.md | L | Auto-mode ТОЛЬКО append к progress.md, никогда не edit/delete. Полный actualize — только manual `/mb done` |
| PyPI trusted publisher setup fail | L | Fallback — `twine upload` с API token в GH secrets (стандартный путь) |

## Gate v2.1 (после этапов 1-4)

- [ ] Auto-capture работает end-to-end: симуляция SessionEnd → progress.md обновлён без `/mb done`
- [ ] `mb-drift.sh` ловит ≥5 категорий на искусственно broken fixture, 0 warnings на live banks
- [ ] `<private>` PII: security smoke test — grep на `index.json` не находит содержимое private блоков
- [ ] `/mb compact` dogfood: перенёс старые plans/done в BACKLOG archive
- [ ] CI matrix `[macos, ubuntu]` × (bats + e2e + pytest) green
- [ ] VERSION 2.1.0, CHANGELOG.md обновлён, git tag `v2.1.0`

## Gate v2.2 (после этапов 5-7)

- [ ] `/mb import` bootstrapped реальный проект из JSONL за ≤30 сек, осмысленные entries
- [ ] `mb-codegraph.py` строит граф этого repo ≤30 сек, god-nodes осмысленный топ
- [ ] Tags normalization: `mb-doctor` warning для неизвестного тега, auto-merge distance ≤1
- [ ] Benchmark токен-экономии для code-graph vs grep: ≥5× (внутренний, не publish — это про другое)
- [ ] VERSION 2.2.0, CHANGELOG.md, git tag `v2.2.0`

## Gate v3.0 (после этапов 8-9)

- [ ] 6 client adapters работают с e2e coverage (Cursor, Windsurf, Cline, Kilo, OpenCode, Pi Code)
- [ ] `pipx install memory-bank-skill && memory-bank install` работает из clean env на macos + ubuntu
- [ ] Homebrew tap `fockus/homebrew-tap/memory-bank` работает: `brew install fockus/tap/memory-bank`
- [ ] `memory-bank self-update` → `pipx upgrade memory-bank-skill` lifts версию
- [ ] PyPI auto-publish на git tag через OIDC trusted publisher
- [ ] VERSION 3.0.0, CHANGELOG.md migration guide v2→v3, git tag `v3.0.0`, GitHub Release
- [ ] Public announcement готов (Twitter/blog — optional, user decides, не блокирует Gate)

## Deferred to v3.1+ backlog

- **Benchmarks (LongMemEval + custom 10 scenarios)** — отложено по решению пользователя 2026-04-20. Вернуться когда: (a) v3.0 released и реально используется 1+ месяц для сбора baseline; (b) найдётся alternative memory skill для fair comparison. ADR-008 фиксирует решение
- **sqlite-vec semantic search** — после Gate v3.0 если keyword + tags + code-graph окажутся недостаточны на реальных use cases
- **Native memory bridge** — программная синхронизация с Claude Code auto memory (сейчас документирован coexistence)

## Решённые вопросы (2026-04-20)

1. ✅ **"Pi" в cross-agent** = [Pi Code от Mario Zechner](https://github.com/badlogic/pi-mono), terminal coding harness с Skills API. Станет 6-м adapter (preferred: native Pi Skill; fallback: `AGENTS.md`)
2. ✅ **Distribution** — `pipx install memory-bank-skill` primary (PyPI scope свободен ✓), Homebrew tap secondary, Anthropic plugin — tertiary. npm убран (overhead без value). ADR-008
3. ✅ **Benchmarks** — deferred to v3.1+ backlog (пользователь подтвердил)
4. ✅ **npm scope** — не актуально после отказа от npm. `@fockus/memory-bank` свободен на случай возврата

## Новые open questions

1. Создать ли отдельный repo `fockus/homebrew-tap` заранее (для Этапа 9) или только перед v3.0 release?
2. PyPI trusted publisher (OIDC) — нужно однократно настроить в PyPI project settings перед первым auto-publish. Кто делает: пользователь вручную в PyPI web UI после создания проекта
3. Windows support — explicit skip (hint "Use WSL") или попробовать совместимость через Git Bash / MSYS2? Default: explicit skip как было
