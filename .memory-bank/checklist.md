# claude-skill-memory-bank — Чеклист

## Этап 0: Dogfood init ✅
- ✅ Создать `.memory-bank/` структуру (experiments, plans/done, notes, reports, codebase)
- ✅ Написать `STATUS.md`, `plan.md`, `checklist.md`, `RESEARCH.md`, `BACKLOG.md`, `progress.md`, `lessons.md`
- ✅ Сохранить план рефактора в `plans/done/2026-04-19_refactor_skill-v2.md`
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
- ✅ Orphan-команды — решено **оставить** (они часть dev-toolkit). `implement.md`/`pipeline.md` остаются глобально (GSD-зависимость)
- ✅ Валидация SKILL.md frontmatter через agent-sdk-verifier — отложено в Этап 6 (CI)

## Этап 6: Tests + CI ✅
- ✅ bats tests/bats/ — 117 тестов покрывают _lib, metrics, context, plan-sync, upgrade
- ✅ `tests/pytest/test_merge_hooks.py` — 16 тестов (idempotent ×2, preservation, corrupt recovery, atomic write, dedup, direct-call). **92% coverage** на `settings/merge-hooks.py` (превышает порог 85%)
- ✅ `tests/e2e/test_install_uninstall.bats` — 15 тестов. Isolated HOME sandbox. Install + roundtrip + идемпотентность install × 2 + preservation user-hooks/CLAUDE.md
- ✅ Починены 2 бага найденные e2e: (1) install.sh не ставил `# [MEMORY-BANK-SKILL]` маркер при создании нового CLAUDE.md → uninstall не находил секцию; (2) uninstall.sh использовал GNU-only `realpath -m` → упадало на macOS. Fix: манифест уже хранит абсолютные пути, `realpath` не нужен
- ✅ `.github/workflows/test.yml` — matrix `[ubuntu-latest, macos-latest]` × (bats + e2e + pytest), fail-fast: false. `bats-core/bats-action@3.0.0` для bats install. Pytest `--cov-fail-under=85`
- ✅ Lint job: shellcheck + ruff (Ubuntu only). Ruff `settings/` + `tests/pytest/` → **All checks passed**
- ✅ `.coveragerc` создан: `include = settings/merge-hooks.py`, excl `if __name__ == "__main__":`
- ✅ `.gitignore` дополнен: `.coverage`, `.pytest_cache/`, `.ruff_cache/`
- ✅ Status badge в `README.md`
- ✅ Локальный прогон: **132 bats green** (117 unit + 15 e2e), **16 pytest green** (92% coverage), **0 shellcheck warnings**, **ruff all passed**

## Этап 7: Hooks fixes ✅
- ✅ `tests/bats/test_hooks.bats` — 11 тестов (TDD red → 5 фейлов, после фиксов — all green). Helper `run_hook` с subshell exit-capture через `__EXIT__` sentinel
- ✅ `file-change-log.sh` — переписан:
  - Убрано `pass\s*$` из placeholder-regex (false-positive на легитимный Python)
  - Placeholder-поиск теперь вне triple-quoted блоков (Python docstrings не триггерят). Awk-прекомпиляция через `index()` и `\b`-границы слов
  - Log rotation: если `~/.claude/file-changes.log > 10MB` → ротация `.log → .log.1 → .log.2 → .log.3`. Portable `stat -f%z || stat -c%s`
- ✅ `block-dangerous.sh` — env `MB_ALLOW_NO_VERIFY=1` bypass для `--no-verify`. Hint в error message
- ✅ `merge-hooks.py` dedup — пропущено (YAGNI): существующий content-based dedup работает, 16 тестов + 92% coverage в Этапе 6. Whitespace-normalize/id-маркер — оверинжиниринг для реальных use-cases
- ✅ Итог: **143 bats green** (117 unit + 15 e2e + 11 hooks), 16 pytest green, 0 shellcheck warnings (переписали awk без single-quote triple-escape чтобы SC1003 не триггерился)

## Этап 8: index.json — прагматично ✅
- ✅ Pytest `tests/pytest/test_index_json.py` — 19 тестов: frontmatter parse (valid, missing, malformed, list-root), lessons H3, atomic write (leftover/rollback on failure), generated_at, CLI, fallback YAML, single-tag-as-string, comment-skip, empty-dir
- ✅ Создан `scripts/mb-index-json.py` — atomic write, PyYAML opt-in + fallback, structure `{notes, lessons, generated_at}`
- ✅ `agents/mb-manager.md` action `actualize` → переписан: вместо ручного Write — вызов `mb-index-json.py <MB_PATH>`
- ✅ `scripts/mb-search.sh` расширен флагом `--tag <tag>`: читает `index.json`, фильтрует. Auto-gen index если отсутствует. Порядок: --tag сначала проверяется, legacy grep-mode — default
- ✅ `tests/bats/test_search_tag.bats` — 5 тестов (finds, empty, auto-gen, multi-match, legacy grep mode)
- ✅ `install.sh` копирует `scripts/*.py` и chmod +x для `.py` (помимо `.sh`)
- ✅ **Итоги**: bats **148/148 green** (включая 5 search-tag), pytest **35/35 green** (16 merge-hooks + 19 index-json), **total coverage 94%**, 0 shellcheck warnings

## Этап 9: Финализация
- ✅ Написать `CHANGELOG.md` (v1.0.0 → v2.0.0)
- ✅ Написать `docs/MIGRATION-v1-v2.md`
- ✅ Переписать `README.md` — quick-start, ecosystem section
- ✅ Сократить `SKILL.md` до ≤150 строк (детали → references/)
- ✅ `.memory-bank/VERSION` маркер, `install.sh` пишет версию
- ✅ Roundtrip тест migration guide на существующем `.memory-bank/`

## Gate v2 ✅
- ✅ Все 9 этапов завершены, DoD выполнен
- ✅ Критерии Gate из плана достигнуты (12 стеков, CI зелёный, 0 legacy Task, etc.)
- ✅ План перенесён в `plans/done/`
- ✅ VERSION 2.0.0, GitHub Release, tag `v2.0.0`

---

# v2.1 → v2.2 → v3.0 Refactor (активно)

Полный план: `plans/2026-04-20_refactor_skill-v2.1.md`

## Этап 1: Auto-capture через SessionEnd hook (v2.1) ✅
- ✅ bats тесты для `hooks/session-end-autosave.sh` (12 тестов, TDD red-first confirmed)
- ✅ Создать `hooks/session-end-autosave.sh` (85 строк, shellcheck 0)
- ✅ Lock-файл `.memory-bank/.session-lock` в `/mb done` (инструкция в commands/mb.md)
- ✅ `MB_AUTO_CAPTURE=strict|auto|off` env флаг (+ unknown → warning+skip)
- ✅ install.sh регистрирует SessionEnd через `merge-hooks.py` (settings/hooks.json + auto-copy hooks/*.sh)
- ✅ uninstall e2e тест roundtrip (+3 теста в tests/e2e/test_install_uninstall.bats)
- ✅ SKILL.md секция "Auto-capture" (129 строк ≤150)
- ✅ Append-only подход вместо LLM-call (hook bash-only, placeholder дочитывается в /mb start). LLM-upgrade в v2.1.1 backlog

## Этап 2: Drift checkers без AI (`mb-drift.sh`) (v2.1) ✅
- ✅ bats тесты для 8 чекеров (20 тестов: 3 smoke + 16 positive/negative pairs + 1 broken-fixture, TDD red-first confirmed 19/20 fail)
- ✅ `scripts/mb-drift.sh`: 8 checkers (path, staleness, script_coverage, dependency, cross_file, index_sync, command, frontmatter), 161 строка, shellcheck 0 warnings
- ✅ `agents/mb-doctor.md` рефакторинг: Шаг 0 = mb-drift.sh → ветвление по `drift_warnings`, Шаги 1-4 (AI) только если >0 или doctor-full
- ✅ Fixture `tests/fixtures/broken-mb/` — 5 категорий drift (stale progress 40d, broken path in checklist, broken frontmatter note, Python version mismatch, test count cross-file mismatch)
- ✅ `references/templates.md` — секция "Drift checks" с таблицей 8 checkers + pre-commit hook пример
- ⏭️ Pre-commit hook — документирован, реальный файл оставлен user opt-in (YAGNI — большинство не захочет блокирующий hook)
- ✅ Dogfood: на live `.memory-bank/` → 1 real drift найден (checklist ссылка на `plans/` вместо `plans/done/`), исправлено → 0 warnings

## Этап 3: PII markers `<private>...</private>` (v2.1) ✅
- ✅ pytest 7 новых тестов в `test_index_json.py` (TDD red-first: 5/7 fail до кода)
- ✅ Parser в `mb-index-json.py`: `PRIVATE_CLOSED_RE` + `PRIVATE_OPEN_RE` (fail-safe на unclosed), `_strip_private()` + tags filter + `has_private` флаг
- ✅ bats 5 новых тестов в `test_search_private.bats` (TDD red-first: 3/5 fail до кода)
- ✅ `mb-search.sh` переписан: span-aware Python filter, inline → `[REDACTED]`, multi-line → `[REDACTED match in private block]`
- ✅ `--show-private` + `MB_SHOW_PRIVATE=1` double-confirmation (exit 2 без env)
- ✅ `hooks/file-change-log.sh` warning на `<private>` в `.md` файлах при Write/Edit
- ✅ SKILL.md секция "Private content" (quick-start + защита + важное предупреждение про git)
- ✅ Security smoke: `TOP-SECRET-LEAK-CHECK` внутри `<private>` → НЕ появляется в `index.json` (dogfood verified)

## Этап 4: Compaction decay `/mb compact` (v2.1)
- ⬜ bats тесты (≥12, TDD red): plan>60d, note low>90d, dry-run, idempotent, archived flag
- ⬜ `scripts/mb-compact.sh` (≤250 строк)
- ⬜ Archive logic: plans → BACKLOG line, notes → `notes/archive/` summary
- ⬜ `index.json` extend `archived: true`
- ⬜ `/mb compact --dry-run|--apply` в `commands/mb.md`
- ⬜ Интеграция в `/mb done`: weekly check + prompt
- ⬜ Safety: note упомянута в `plan.md` → НЕ archive
- ⬜ Dogfood на этом banks

## Gate v2.1
- ⬜ Auto-capture end-to-end (симуляция SessionEnd → progress.md updated)
- ⬜ Drift ловит ≥5 категорий на broken fixture
- ⬜ PII: grep в `index.json` → 0
- ⬜ Compact dogfood выполнен
- ⬜ CI green, VERSION 2.1.0, tag `v2.1.0`

## Этап 5: Import from Claude Code JSONL (v2.2)
- ⬜ pytest тесты (≥15, TDD red): parse, dedup, resume, --since, PII auto-wrap
- ⬜ `scripts/mb-import.py` (≤400 строк, ruff 0, type hints)
- ⬜ Парсинг `~/.claude/projects/<path>/*.jsonl`
- ⬜ Extraction: progress (Haiku summarize), notes (heuristic), lessons (debug pattern)
- ⬜ Duplicate detection: SHA256 hash
- ⬜ Resume on failure: `.import-state.json`
- ⬜ PII auto-wrap (email/API-key regex → `<private>`)
- ⬜ `/mb import [--since] [--project] [--dry-run]` в `commands/mb.md`

## Этап 6: Tree-sitter code graph в `codebase/` (v2.2)
- ⬜ pytest тесты (≥20, TDD red): Python/Go/JS/TS fixtures, incremental cache, broken syntax
- ⬜ `scripts/mb-codegraph.py` (≤500 строк, type hints)
- ⬜ tree-sitter + grammars (opt-in extras)
- ⬜ Output: `codebase/graph.json` (JSON Lines), `god-nodes.md`, `wiki/<node>.md`
- ⬜ SHA256 cache в `.cache/` для incremental
- ⬜ Optional git post-commit hook
- ⬜ `mb-codebase-mapper` агент обновлён (читает graph.json)
- ⬜ Замер token-экономии vs grep ≥5×
- ⬜ `references/codegraph.md` + `install.sh --with-codegraph`

## Этап 7: Tags normalization (v2.2)
- ⬜ bats тесты (≥10, TDD red): synonym merge, case normalize, dry-run, auto-merge
- ⬜ `scripts/mb-tags-normalize.sh` (≤150 строк)
- ⬜ Closed vocabulary `.memory-bank/tags-vocabulary.md` (template в `references/`)
- ⬜ Levenshtein distance ≤2 detection
- ⬜ `mb-index-json.py` auto-lowercase + kebab-case
- ⬜ `mb-doctor` drift check "unknown tag"

## Gate v2.2
- ⬜ `/mb import` bootstrap JSONL ≤30 сек
- ⬜ `mb-codegraph.py` ≤30 сек на repo, ≥5× экономия токенов
- ⬜ Tags auto-merge + drift warn
- ⬜ CI green, VERSION 2.2.0, tag `v2.2.0`

## Этап 8: Cross-agent output — 6 clients (v3.0)
- ⬜ Research upfront: актуальные форматы конфигов для Cursor, Windsurf, Cline, Kilo, OpenCode, Pi (1-2 часа → `notes/`)
- ⬜ e2e тесты (≥14, 2 per client)
- ⬜ 6 adapters: Cursor (`.cursorrules`), Windsurf (`.windsurfrules`), Cline (`.clinerules/`), Kilo (`.kilorules`), OpenCode (`AGENTS.md`), Pi Code (native Pi Skill в `~/.pi/skills/`, fallback `AGENTS.md`)
- ⬜ Универсальный слой (RULES.md, MB) vs client-specific (configs)
- ⬜ install.sh interactive `--clients <list>` (valid: claude-code, cursor, windsurf, cline, kilo, opencode, pi)
- ⬜ uninstall: manifest roundtrip чистый для всех 6
- ⬜ `docs/cross-agent-setup.md` — per-client examples/screenshots
- ⬜ Pi Code: preferred native Skill path, fallback `AGENTS.md` если API нестабилен

## Этап 9: pipx/PyPI distribution + Homebrew tap (v3.0)
- ⬜ e2e тесты (≥10): `pipx install`, `--minimal`, `self-update`, Windows graceful, reinstall idempotent
- ⬜ pytest CLI тесты (≥8): argparse, platform detect, version read
- ⬜ `pyproject.toml` + `memory_bank_skill/` Python package
- ⬜ CLI entry point `memory-bank` с sub-commands: install, uninstall, init, version, self-update
- ⬜ Package включает весь bash/agents/commands/hooks/rules как `package_data`
- ⬜ `pipx install memory-bank-skill` работает macos+ubuntu, CI matrix Python 3.11+3.12
- ⬜ Homebrew tap `fockus/homebrew-tap/memory-bank.rb` (создать repo отдельно)
- ⬜ PyPI auto-publish через OIDC trusted publisher на git tag `v*`
- ⬜ Anthropic plugin manifest `claude-plugin.json` (tertiary path, ready но не блокирует)
- ⬜ `docs/install.md` — три варианта (pipx/homebrew/claude plugin) с upgrade story
- ⬜ README quick-start → `pipx install memory-bank-skill && memory-bank install`

## Gate v3.0
- ⬜ 6 adapters e2e green (включая Pi Code)
- ⬜ `pipx install` из clean env работает
- ⬜ `brew install fockus/tap/memory-bank` работает
- ⬜ `memory-bank self-update` lifts версию
- ⬜ CHANGELOG v2→v3, VERSION 3.0.0, tag `v3.0.0`, GitHub Release

## Deferred to v3.1+ backlog
- ⬜ Benchmarks (LongMemEval + custom) — отложено решением 2026-04-20, ADR-008
- ⬜ sqlite-vec semantic search
- ⬜ Native memory bridge
