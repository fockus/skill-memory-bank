# План: refactor — skill-v2

## Контекст

**Проблема:** skill `memory-bank` v1 работает только с Python-проектами, скрипты дублируют workspace-resolver логику, агент `codebase-mapper` не интегрирован (orphan GSD-артефакт, пишет в `.planning/`), нет тестов (0% coverage при декларируемом TDD), `Task(...)` вместо современного `Agent`, SKILL.md невалидный frontmatter (`user-invocable: false`), конфликтует с native Claude Code memory без документации, `/mb init` и `/mb:setup-project` дублируют функциональность, `index.json` декларирован но не реализован.

**Ожидаемый результат:** language-agnostic skill v2 с DRY-утилитами (`_lib.sh`), интегрированным `mb-codebase-mapper`, CI-покрытыми скриптами (bats+pytest на macOS+Ubuntu), единым init-flow, корректным Agent-tool, документированной integration с экосистемой, автоматизированной consistency-chain (plan↔checklist↔STATUS↔plan.md).

**Связанные файлы:**
- `SKILL.md` (сократить <150 строк)
- `agents/mb-manager.md`, `agents/mb-doctor.md`, `agents/plan-verifier.md`, `agents/codebase-mapper.md` → `mb-codebase-mapper.md`
- `scripts/mb-context.sh`, `mb-search.sh`, `mb-note.sh`, `mb-plan.sh` (+ новые: `_lib.sh`, `mb-plan-sync.sh`, `mb-plan-done.sh`, `mb-index-json.py`)
- `hooks/block-dangerous.sh`, `hooks/file-change-log.sh`
- `settings/merge-hooks.py`
- `install.sh`, `uninstall.sh`, `commands/mb.md`, `commands/setup-project.md` (удаляется)
- `README.md`, `rules/CLAUDE-GLOBAL.md`
- Новые: `.github/workflows/test.yml`, `tests/bats/`, `tests/pytest/`, `tests/fixtures/`, `docs/MIGRATION-v1-v2.md`, `CHANGELOG.md`

---

## Этапы

<!-- mb-stage:0 -->
### Этап 0: Dogfood — init `.memory-bank/` в этом репо

**Что сделать:**
- Запустить mb-init логику в корне репозитория
- Заполнить core-файлы: STATUS, plan, checklist, RESEARCH, BACKLOG, progress, lessons
- Сохранить этот план в `plans/`

**Тестирование:** smoke — `bash scripts/mb-context.sh` возвращает ненулевой вывод, `ls .memory-bank/` показывает 7 файлов + 5 директорий

**DoD:**
- [x] `.memory-bank/` создан со всей структурой (experiments, plans/done, notes, reports, codebase)
- [x] все 7 core-файлов заполнены осмысленным содержимым
- [x] этот план в `plans/2026-04-19_refactor_skill-v2.md`
- [x] progress.md содержит запись за 2026-04-19
- [ ] коммит `chore: dogfood — init .memory-bank for skill v2 refactor`

---

<!-- mb-stage:1 -->
### Этап 1: DRY-утилиты + language detection

**Что сделать:**
- Создать `scripts/_lib.sh` с функциями:
  - `resolve_mb_path()` — workspace resolution (перенос из 4 скриптов)
  - `detect_stack()` → `python|go|rust|node|multi|unknown`
  - `detect_test_cmd()` — pytest/go test/cargo test/npm test
  - `detect_lint_cmd()` — ruff/golangci-lint/cargo clippy/eslint
  - `detect_src_glob()` — `src/**/*.py` / `**/*.go` etc.
  - `sanitize_topic()` — единая реализация slug
  - `collision_safe_filename()` — `_2`, `_3` при конфликте
- Рефакторить `mb-context.sh`, `mb-search.sh`, `mb-note.sh`, `mb-plan.sh` → `source _lib.sh`
- POSIX-совместимость: cross-platform `stat` helper, без GNU-isms

**Тестирование (TDD — тесты ПЕРЕД реализацией):**
- `tests/bats/test_lib.bats`:
  - `resolve_mb_path` default при отсутствии `.claude-workspace`
  - `resolve_mb_path` external: `~/.claude/workspaces/{id}/.memory-bank`
  - `detect_stack` для fixtures: python, go, rust, node, multi (package.json + go.mod), unknown
  - `sanitize_topic "Foo Bar!@#"` → `foo-bar`
  - `collision_safe_filename` для существующего → `_2`
  - `detect_test_cmd` корректен для каждого стека
- CI matrix: macos-latest + ubuntu-latest

**DoD:**
- [x] `_lib.sh` создан (150 строк), bats 36/36 green (100% функций покрыты)
- [x] 5 скриптов используют `_lib.sh` (mb-context, mb-search, mb-note, mb-plan, mb-index), дублирующий код удалён (~50 строк)
- [x] `detect_stack` правильно определяет все 6 fixture-стеков (python, go, rust, node, multi, unknown)
- [x] `shellcheck -x --source-path=SCRIPTDIR scripts/*.sh` → 0 warnings
- [x] `_lib.sh` = 150 строк (ISP OK)

**Правила кода:** SRP (одна функция — одна задача), POSIX-совместимость, без bash-isms где возможно

**Итог:** все 5 пунктов DoD выполнены. Bonus — `mb-index.sh` тоже рефакторен (не было в изначальном списке, но был тот же duplicate). Collision handling в `mb-note.sh` (`_2`, `_3` суффикс) устранил класс багов "exit 1 при повторной заметке в ту же минуту".

---

<!-- mb-stage:2 -->
### Этап 2: Language-agnostic `/mb update` и `mb-doctor`

**Что сделать:**
- `commands/mb.md:70-103` (/mb update): заменить `.venv/bin/python -m pytest`, `.venv/bin/ruff check`, `find src/*.py` на `_lib.sh::detect_test_cmd` + `detect_lint_cmd`
- `agents/mb-doctor.md:125-132`: аналогично, убрать `src/taskloom/`
- Graceful fallback: стек не определён → warning, не error
- Опциональный `.memory-bank/metrics.sh` override: если существует — вызывается вместо auto-detect

**Тестирование:**
- `tests/bats/test_update.bats`:
  - fixtures/python → вызывается pytest-like команда
  - fixtures/go → `go test ./...`
  - fixtures/node → `npm test` или `vitest`
  - fixtures/unknown → warning на stderr, exit 0
- Integration: реальный Go-проект (tests/fixtures/integration/go-project) даёт корректные метрики

**DoD:**
- [ ] 0 упоминаний `pytest`/`ruff`/`taskloom` вне `tests/fixtures/`
- [ ] `/mb update` на unknown-стеке не падает
- [ ] `.memory-bank/metrics.sh` override работает
- [ ] 4 стека дают валидные метрики в integration tests

**Правила кода:** Fail-safe (warning, не crash на missing stack), Open/Closed (новый стек = добавление в `detect_*` без правки core-логики)

---

<!-- mb-stage:3 -->
### Этап 3: `mb-codebase-mapper` — memory-bank-native

**Что сделать:**
- Переименовать `agents/codebase-mapper.md` → `agents/mb-codebase-mapper.md`
- Frontmatter: `name: mb-codebase-mapper`, description обновить под MB context
- Output path: `.planning/codebase/` → `.memory-bank/codebase/`
- Сократить 6 шаблонов → 4 (STACK, ARCHITECTURE, CONVENTIONS, CONCERNS), каждый ≤70 строк
- Создать команду `/mb map [focus]` (`stack|arch|quality|concerns|all`, default `all`)
- Интегрировать output в `/mb context`: если `.memory-bank/codebase/` существует, добавить 1-строчный summary каждого MD в context-вывод
- `/mb context --deep` — полный codebase-контент

**Тестирование (TDD):**
- `tests/bats/test_map.bats`:
  - fixtures/python → 4 MD в `.memory-bank/codebase/`
  - fixtures/multi → обрабатывает оба стека корректно
  - idempotent: повторный `/mb map` обновляет, не дублирует (diff после 2-го запуска = empty)
- `tests/bats/test_context_integration.bats`:
  - `/mb context` после `/mb map` содержит codebase-summary section
  - `/mb context --deep` включает полные файлы

**DoD:**
- [ ] `agents/codebase-mapper.md` удалён
- [ ] `agents/mb-codebase-mapper.md` пишет только в `.memory-bank/codebase/`
- [ ] `/mb map` работает на 3+ стеках
- [ ] `/mb context` интегрирует codebase-docs (1-строчный summary)
- [ ] 0 упоминаний `.planning/` в skill-коде
- [ ] Каждый шаблон ≤70 строк

**Правила кода:** YAGNI (убираем избыточные шаблоны из GSD-версии), интеграция через существующий `/mb context`

---

<!-- mb-stage:4 -->
### Этап 4: Автоматизация consistency-chain

**Что сделать:**
- `scripts/mb-plan-sync.sh <plan-file>`:
  - парсит этапы через маркеры `<!-- mb-stage:N -->` (fallback: `### Этап N:`)
  - генерирует/обновляет ⬜ пункты в `checklist.md` (секция с именем плана)
  - обновляет `plan.md` поле `**Active plan:**`
  - обновляет `STATUS.md` секцию "В работе"
- `scripts/mb-plan-done.sh <plan-file>`:
  - `mv plans/<file>.md plans/done/`
  - ⬜ пункты плана в checklist → ✅
  - убирает Active plan из plan.md
  - перемещает в "Завершено" в STATUS.md
- `/mb plan` → auto-вызов `mb-plan-sync.sh` после создания
- `mb-doctor` фикс через `mb-plan-sync.sh` (не руками)

**Тестирование (TDD):**
- `tests/bats/test_sync.bats`:
  - создание плана → 4 файла синхронизированы
  - модификация этапов в плане → checklist обновлён без дублирования
  - `mb-plan-done.sh` → план в done/, все ⬜ → ✅, STATUS обновлён
  - idempotency: двойной вызов = тот же результат (diff empty)
- `tests/bats/test_doctor_integration.bats`:
  - искусственно рассинхронизируем (правим plan.md) → `mb-doctor` фиксит через sync

**DoD:**
- [ ] новый план автоматически отражается в 4 файлах
- [ ] `mb-doctor` находит 0 inconsistency после sync
- [ ] idempotency guaranteed
- [ ] маркеры `<!-- mb-stage -->` работают + fallback regex

**Риск:** парсинг хрупкий — **Mitigation:** structured marker + integration test с реальным планом этого же рефактора.

---

<!-- mb-stage:5 -->
### Этап 5: Ecosystem integration

**Что сделать:**
- `SKILL.md`: убрать невалидный `user-invocable: false`, переписать description под реальную activation pattern
- `commands/mb.md`, `SKILL.md`: заменить все `Task(...)` → `Agent(subagent_type=..., ...)`
- Новая секция в `SKILL.md` + `README.md`: "Coexistence with native Claude Code memory":
  - различие: `.memory-bank/` = проектная память; native `auto memory` = user cross-project
  - рекомендация: использовать оба
- Слить `/mb init` + `/mb:setup-project` → единая `/mb init [--minimal|--full]`:
  - `--minimal`: только структура
  - `--full` (default): + CLAUDE.md + RULES copy + stack detection
- Удалить `commands/setup-project.md`
- Orphan-команды (`adr.md`, `observability.md`, `db-migration.md`, `api-contract.md`, `contract.md`, `refactor.md`, `security-review.md`, `changelog.md`, `catchup.md`): либо удалить, либо вынести в отдельный plugin `memory-bank-dev-commands` (решение: удалить в v2, создание отдельного плагина → BACKLOG)

**Тестирование:**
- Manual: `/mb init` на чистом проекте → CLAUDE.md с автодетектом создан
- Manual: `/mb init --minimal` только структуру
- Lint SKILL.md frontmatter через agent-sdk-verifier-ts (или python — зависит от skill-tooling)

**DoD:**
- [ ] 0 вхождений `Task(` в skill-файлах
- [ ] SKILL.md frontmatter валиден (verifier OK)
- [ ] Секция "Coexistence with native memory" в README + SKILL.md
- [ ] Единая `/mb init` с флагами
- [ ] `commands/setup-project.md` удалён
- [ ] Orphan-команды вынесены или удалены (решение задокументировано)

---

<!-- mb-stage:6 -->
### Этап 6: Tests + CI

**Что сделать:**
- `tests/bats/` — покрытие shell-скриптов (результат этапов 1-4)
- `tests/pytest/test_merge_hooks.py`:
  - idempotent merge
  - preservation существующих user hooks
  - корректная дедупликация с id-маркером
  - recovery от corrupted settings.json
- `tests/pytest/test_index_json.py` (задел для Этапа 8)
- `tests/e2e/test_install_uninstall.sh` — Docker roundtrip:
  - `install.sh` → создаёт всё, merge hooks
  - `uninstall.sh` → полный rollback
- `.github/workflows/test.yml`:
  - matrix: `[macos-latest, ubuntu-latest]`
  - bats + pytest + e2e + shellcheck + ruff

**Тестирование:**
- pytest coverage ≥85% для Python
- bats покрывает все функции `_lib.sh` (≥90%)
- CI зелёный на main, оба ОС
- shellcheck 0 warnings

**DoD:**
- [ ] 0 shellcheck warnings
- [ ] pytest coverage ≥85%
- [ ] bats ≥90% на `_lib.sh`
- [ ] CI зелёный на main
- [ ] install/uninstall roundtrip тест проходит

---

<!-- mb-stage:7 -->
### Этап 7: Hooks — fixes

**Что сделать:**
- `hooks/file-change-log.sh`:
  - убрать `pass\s*$` из placeholder-regex
  - TODO/FIXME только вне комментариев-строк и docstrings
  - Log rotation: `~/.claude/file-changes.log > 10MB` → `.log.1`/`.log.2`
- `hooks/block-dangerous.sh`:
  - env `MB_ALLOW_NO_VERIFY=1` bypass для `--no-verify`
  - Error message включает hint про override
- `settings/merge-hooks.py`:
  - id-маркер `# [memory-bank-skill:hook-id]` для дедупликации
  - нормализация whitespace в commands перед сравнением

**Тестирование (TDD):**
- `tests/bats/test_hooks.bats`:
  - `pass` в except-блоке → не триггерит warning
  - TODO в docstring → не триггерит
  - TODO в коде → триггерит
  - `MB_ALLOW_NO_VERIFY=1 git commit --no-verify` → проходит
  - Log rotation после overflow
- `tests/pytest/test_merge_hooks_dedup.py`:
  - two identical hooks → один в output
  - whitespace-diff hooks → один

**DoD:**
- [ ] 0 false-positives на репе skill'а (тест на самом коде)
- [ ] Log не превышает 10MB (с rotation)
- [ ] merge-hooks идемпотентен (5 запусков подряд = тот же settings.json)
- [ ] env-override работает

---

<!-- mb-stage:8 -->
### Этап 8: `index.json` — прагматично

**Что сделать:**
- Минимальная реализация: только frontmatter index для notes/+lessons/
- `scripts/mb-index-json.py`:
  - скан `notes/` → frontmatter (tags, type, importance) + summary (первые 2 строки)
  - парсинг `lessons.md` по `###` маркерам → L-NNN entries
  - atomic write `.memory-bank/index.json`
- Интегрировать в `mb-manager.md` action `actualize` (вызов скрипта, не ручной Write)
- `mb-search.sh --tag <tag>` — фильтрация через index.json, затем grep в отфильтрованных

**Тестирование (TDD):**
- `tests/pytest/test_index_json.py`:
  - валидный frontmatter → корректный entry
  - invalid/missing frontmatter → defaults `type: note, tags: []`
  - lessons.md с N `###` → N entries
  - atomic write: partial failure не оставляет corrupted json
- `tests/bats/test_search_tag.bats`:
  - `/mb search --tag testing` возвращает только tagged files
  - бенчмарк: быстрее grep-по-всему на >50 файлов

**DoD:**
- [ ] `mb-index-json.py` coverage ≥90%
- [ ] `mb-manager actualize` вызывает скрипт
- [ ] `/mb search --tag <x>` работает и быстрее grep
- [ ] Atomic write (tmp file + rename)

---

<!-- mb-stage:9 -->
### Этап 9: Финализация — docs, CHANGELOG, versioning

**Что сделать:**
- `CHANGELOG.md` semver: v1.0.0 → v2.0.0 (breaking changes)
- `docs/MIGRATION-v1-v2.md`:
  - удалён `/mb:setup-project` → `/mb init --full`
  - `codebase-mapper` → `mb-codebase-mapper`
  - Breaking: output path `.planning/codebase/` → `.memory-bank/codebase/`
- README переписать: clearer quick-start, ecosystem section, ссылки на docs
- `SKILL.md` сократить до ≤150 строк (детали → `references/`)
- `.memory-bank/VERSION` маркер; `install.sh` пишет версию

**Тестирование:**
- Manual: follow quick-start на чистом проекте → работает
- Roundtrip: migration guide тестируется на snapshot existing `.memory-bank/` (без потери данных)

**DoD:**
- [ ] CHANGELOG соответствует semver
- [ ] SKILL.md ≤150 строк
- [ ] Migration guide протестирован roundtrip
- [ ] Version marker пишется install.sh
- [ ] README обновлён с ecosystem section

---

## Риски и mitigation

| Риск | Вероятность | Mitigation |
|------|-------------|------------|
| Breaking change для существующих пользователей skill v1 | H | Этап 9: migration guide + `v2` git tag; `install.sh` детектит старую структуру и мигрирует с backup |
| Парсинг этапов плана через regex хрупкий | M | Structured markers `<!-- mb-stage:N -->`, fallback regex `### Этап N:` |
| Bash-несовместимость macOS (BSD) vs Linux (GNU) | M | POSIX helpers в `_lib.sh`, CI matrix обоих ОС, shellcheck |
| Fixture-тесты не отражают реальные проекты | M | 1+ integration test на клонированном open-source проекте |
| Scope creep между этапами (много работы) | H | Каждый этап = отдельный PR; можно останавливаться на любом; явные зависимости |
| Этап 5 (slияние init) ломает существующий UX | M | Deprecation warning на `/mb:setup-project` в transition period |
| sqlite-vec в будущем требует глубокой переделки index.json | L | Этап 8 минимальный, без vector search — легко расширить в v3 |

## Gate (критерий успеха плана целиком)

Skill `memory-bank v2` считается завершённым когда:

1. **Language coverage:** Python, Go, Rust, Node/TypeScript корректно детектируются; `/mb update` / `mb-codebase-mapper` работают на каждом стеке без хардкода
2. **Cross-platform:** CI зелёный на `macos-latest` + `ubuntu-latest` (bats + pytest + e2e)
3. **Ecosystem:** 0 `Task(` legacy-вызовов; native memory coexistence документирован; orphan-команды убраны; `Agent(...)` повсеместно
4. **DRY + tested:** `_lib.sh` переиспользуется 4+ скриптами; coverage Python ≥85%; 0 shellcheck warnings
5. **UX:** единая `/mb init`; `mb-codebase-mapper` генерирует 4 MD в `.memory-bank/codebase/`; `/mb context` показывает integrated summary
6. **Dogfooding:** сам skill использует `.memory-bank/` в своём репозитории; этот план лежит в `plans/done/` по завершении всех этапов
7. **Versioning:** CHANGELOG.md отражает v1→v2, migration guide протестирован, `VERSION` marker пишется install.sh

---

## Последовательность и зависимости

```
Этап 0 (dogfood init)  ← ✅ В процессе
  ↓
Этап 1 (_lib.sh + detect_stack)  ← блокирует 2, 3, 4
  ↓
┌─ Этап 2 (update agnostic)
├─ Этап 3 (mb-codebase-mapper)     ← параллельно
└─ Этап 4 (sync automation)
  ↓
┌─ Этап 5 (ecosystem)
└─ Этап 7 (hooks fixes)             ← параллельно
  ↓
Этап 6 (tests + CI)  ← после основных изменений
  ↓
┌─ Этап 8 (index.json)
└─ Этап 9 (docs + versioning)       ← финал
```

**Оценка объёма:** 7-10 сессий по ~2-3 часа каждая; каждый этап = отдельный commit/PR для incremental delivery.
