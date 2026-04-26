# Plan: refactor — v4-audit-remediation

**Baseline commit:** 1613889a6bcfc937df8f6be13d027aa89d2a23ea

## Context

**Problem:** Полный аудит skill'а v4.0.0 (2026-04-25) выявил расхождения по 4 осям:

1. **Doc drift (HIGH)** — `SKILL.md` декларирует «18 commands / 14 scripts / 4 agents», по факту шипится 24 / 41 / 16. Hook-таблицы нет вовсе. 31 скрипт и 10 агентов не упомянуты.
2. **Memory Bank own state (HIGH)** — `.memory-bank/status.md` в одном файле говорит и «v4.0.0 RELEASED» (line 4), и `VERSION: 3.1.2` + `pytest 246/246` + roadmap «Gate v3.0 — in progress» (lines 95-159). I-028 помечен open, в `backlog.md` уже DONE.
3. **Repo hygiene (MED)** — `.memory-bank/.session-lock` не в `.gitignore`, дирtит `git status` каждую сессию. CHANGELOG содержит orphan-секцию `[3.2.0] — unreleased — staged on main` без тега. Branch `main` отслеживает мёртвый `old-origin`. 2 flaky CLI-теста (passed isolated, fail when run together) — `test_cli.py::test_cli_install_uninstall_smoke_with_cursor_global` и `test_cli.py::test_uninstall_non_interactive_flag_works_without_stdin`.
4. **Code/security hardening (MED)** — `BaseException` глотает `KeyboardInterrupt` в 2 местах; общий `_lib.sh` без `set -euo pipefail`; `mb-idea.sh` интерполирует TITLE в regex; `mb-search.sh` без `--` пропускает запросы-флаги; `hooks/file-change-log.sh` пишет лог без `chmod 600` и rotate'ит non-atomic.

Корневой урок (`lessons.md` 2026-04-25): **declarative intent ≠ contract**. Документация без CI-проверки = накапливающийся drift. Поэтому каждое восстановление чисел сопровождается pytest-проверкой соответствия doc ↔ реальность — иначе через 2 спринта SKILL.md снова разойдётся.

Миграция `plan.md → roadmap.md` уже произошла; в этом плане только убираем оставшиеся следы упоминания `plan.md` в проектных файлах (глобальный `~/.claude/CLAUDE.md` — личная настройка пользователя, **out of scope**).

**Expected result:**

- `SKILL.md`/`README.md`/`status.md`/`CHANGELOG.md` точно отражают v4.0.0
- pytest **628/628** зелёный (нет flake'ов на 3 прогонах подряд)
- ruff/shellcheck/bats clean
- `mb-drift.sh` exit 0 + новые doc-vs-реальность проверки в pytest
- `git status` чистый сразу после `/mb done`
- `mb-idea.sh` / `mb-search.sh` / `file-change-log.sh` отвердевают по новым bats-тестам
- `BaseException` устранён, `_lib.sh` + 3 топ-скрипта получают `set -euo pipefail`

**Related files:**

- Аудит-репорт — outputs выше в этой сессии (4 параллельных audit agent'а)
- `SKILL.md` (строки 12, 54-75, 82-88, 223-229)
- `README.md` (строки 185-232, 413, 421)
- `.memory-bank/status.md` (строки 4-43, 92-174)
- `.memory-bank/backlog.md` (I-028 status), `.memory-bank/checklist.md`
- `CHANGELOG.md` (orphan `[3.2.0]` section)
- `.gitignore`, `.git/config` (remote `old-origin`)
- `tests/pytest/test_cli.py` (`test_cli_install_uninstall_smoke_with_cursor_global`, `test_uninstall_non_interactive_flag_works_without_stdin`)
- `memory_bank_skill/_io.py:23`, `settings/merge-hooks.py:147`
- `scripts/_lib.sh`, `scripts/mb-plan-done.sh`, `scripts/mb-rules-check.sh`, `scripts/mb-compact.sh`
- `scripts/mb-idea.sh`, `scripts/mb-search.sh`
- `hooks/file-change-log.sh`
- `lessons.md` (паттерн "declarative intent ≠ contract")

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: SKILL.md/README.md realignment + doc-vs-reality test

**What to do:**

- Переписать в `SKILL.md`:
  - line 12 — заменить «18 commands» на актуальный счётчик
  - таблицу `## Tools — shell scripts` (lines 54-75) — расширить **всеми** 41 скриптами с одной строкой назначения каждого. Сгруппировать по семьям: `mb-context`, `mb-search`, `mb-note/plan/idea/adr` (lifecycle), `mb-work-*` (Phase 3 work pipeline), `mb-pipeline*`, `mb-migrate*`, `mb-drift/doctor`, `mb-compact`, `mb-tags*`, `mb-deps*`, `mb-test-run`, `mb-rules-check`, `mb-roadmap-sync`, `mb-traceability-gen`, `mb-ears-validate`, `mb-req-next-id`, `mb-checklist-prune`, `mb-auto-commit`, `mb-session-spend`, `mb-reviewer-resolve`, `mb-init-bank`, `mb-config`, `mb-sdd`, `mb-upgrade`, `_lib`. **Источник истины** — `ls scripts/*.sh scripts/*.py | wc -l`.
  - таблицу `## Agents — subagents` (lines 82-88) — добавить 10 role-агентов: `mb-developer`, `mb-architect`, `mb-backend`, `mb-frontend`, `mb-ios`, `mb-android`, `mb-devops`, `mb-qa`, `mb-analyst`, `mb-reviewer`. По одной строке когда вызывать (взять из `agents/<name>.md` frontmatter).
  - добавить новую секцию **`## Hooks`** между Agents и Host-specific notes — таблица всех 9 хуков с триггером (PreToolUse/PostToolUse/SessionEnd/PreCompact/PreUserPromptSubmit) и одной строкой назначения.
  - расширить `## References` (lines 223-229) ссылками на `references/hooks.md`, `references/adapter-manifest-schema.md`, `references/tags-vocabulary.md`, `references/command-template.md`, `references/claude-md-template.md`.
- В `README.md`:
  - line 185 «18 top-level slash-commands» → актуальный счётчик
  - блок lines 208-232 — пересчитать sub-команды `/mb` против реального списка в `commands/mb.md`
  - line 413 FAQ entry «`3.0.0` is the first stable 3.x release» → дополнить упоминанием v4.0.0
  - убрать упоминание `plan.md` если оно есть (grep'нуть README на `plan\.md`)

**Testing (TDD — tests BEFORE implementation):**

- Новый `tests/pytest/test_doc_counts.py`:
  - `test_skill_md_command_count_matches_filesystem` — парсит `SKILL.md` (regex `(\d+)\s*commands?`) или таблицу commands и сверяет с `len(glob('commands/*.md'))`
  - `test_skill_md_script_table_lists_all_scripts` — извлекает имена скриптов из таблицы `## Tools — shell scripts` и сверяет с `glob('scripts/*.sh') + glob('scripts/*.py')`
  - `test_skill_md_agents_table_lists_all_agents` — то же для `agents/*.md`
  - `test_skill_md_hooks_table_lists_all_hooks` — извлекает из новой `## Hooks` секции и сверяет с `glob('hooks/*.sh')`
  - `test_skill_md_references_link_existing_files` — все `references/<x>.md` упомянутые в `## References` существуют, и все `references/*.md` упомянуты
  - `test_readme_command_count_matches_filesystem` — то же что для SKILL, но для README
- Все 6 тестов **сначала RED** (текущее состояние их валит).

**DoD (Definition of Done):**

- [ ] 6 новых pytest тестов в `tests/pytest/test_doc_counts.py` — RED → GREEN
- [ ] `pytest tests/pytest/test_doc_counts.py -q` — `6 passed`
- [ ] `SKILL.md` содержит секцию `## Hooks` с таблицей из 9 строк
- [ ] `SKILL.md` script-таблица содержит ровно `len(glob('scripts/*.sh,*.py'))` строк
- [ ] `SKILL.md` agents-таблица содержит ровно `len(glob('agents/*.md'))` строк
- [ ] `README.md` не содержит литерала «18 commands» / «18 top-level» / отсылок к несуществующим файлам
- [ ] `ruff check .` clean

**Code rules:** SOLID (тест на одно поведение), DRY (общая fixture для glob-counters), KISS (минимум regex'а — предпочесть структурный парсинг таблиц)

---

<!-- mb-stage:2 -->
### Stage 2: status.md / CHANGELOG / project-CLAUDE realignment

**What to do:**

- Переписать `.memory-bank/status.md`:
  - **Текущая фаза** (lines 1-8) — оставить «Skill v2 — RELEASED (v4.0.0, 2026-04-25)», убрать хедж «tagging v4.0.0 в git если ещё не сделано» (тег `v4.0.0` уже шипится — `git tag -l v4.0.0` подтверждает)
  - **Open backlog** (lines 39-43) — убрать I-028, оставить только реально open items из `backlog.md` (greppнуть `^### I-\d+` + `\[.*HIGH|MED, OPEN`)
  - **Ключевые метрики** (lines 92-100) — обновить: scripts 41, agents 16, commands 24, tests `pytest 628/628 + bats <N> + e2e <M>`, `VERSION: 4.0.0`
  - **Roadmap** (lines 102-128) — собрать v2.0/v2.1/v2.2/v3.0/v3.1/v4.0 в архивную таблицу «Released», новая секция `## Next iteration` ссылается на `_None — open via /mb idea_`
  - **Gate v2/v2.1/v2.2/v3.0** (lines 130-159) — переместить в `## Историч. gates (passed)` или удалить совсем (gate'ы уже passed)
  - **Open questions** (lines 171-174) — удалить obsolete вопросы про v2.2/v3.0
- `CHANGELOG.md`:
  - удалить orphan-секцию `[3.2.0] — 2026-04-21 (unreleased — staged on main)` (содержимое уже absorbed в [4.0.0])
  - проверить что `[Unreleased]` пуст или содержит только post-v4 work (на момент аудита I-004 уже в [4.0.0])
- Project-level `CLAUDE.md` (root):
  - заменить упоминание `plan.md` на `roadmap.md`
- Все project-level `references/*.md` и `commands/*.md` — `grep -l "plan\.md\b" references/ commands/ docs/ rules/`, заменить на `roadmap.md` где уместно (но не трогать `mb-plan.sh`/`/mb plan` команду — это про планы, не про файл `plan.md`)

**Testing (TDD):**

- Новый `tests/pytest/test_status_drift.py`:
  - `test_status_md_version_matches_version_file` — VERSION в `## Ключевые метрики` == содержимое `./VERSION`
  - `test_status_md_no_obsolete_v3_gates_in_active_section` — после `## Текущая фаза` нет строк `Gate v3.0 — in progress` или `VERSION: 3.1.2`
  - `test_status_md_open_backlog_consistent_with_backlog_md` — каждый I-NNN в `## Open backlog` имеет статус `OPEN` в `backlog.md`
- Новый `tests/pytest/test_changelog_no_orphan_section.py`:
  - `test_changelog_no_unreleased_orphan_minor_section` — нет секций вида `\[\d+\.\d+\.\d+\] — \d{4}-\d{2}-\d{2} \(unreleased`
  - `test_changelog_versions_match_git_tags_or_unreleased` — каждая `[X.Y.Z]` секция (кроме [Unreleased]) либо имеет git-tag `vX.Y.Z`, либо помечена как `unreleased` (но не staged-на-main)
- Новый `tests/pytest/test_no_orphan_plan_md_references.py`:
  - `test_no_project_doc_references_plan_md` — `git grep "plan\.md"` в `references/`, `commands/`, `docs/`, `rules/`, root `*.md` (исключая CHANGELOG history) даёт 0 матчей вне команды `/mb plan`

**DoD:**

- [ ] 5 новых pytest тестов RED → GREEN
- [ ] `bash scripts/mb-drift.sh .` — `drift_warnings=0`
- [ ] `cat .memory-bank/status.md | grep -c "VERSION: 3"` = 0 в active секциях (исключая Архив)
- [ ] `git grep "plan\.md\b"` в project root (исключая `CHANGELOG.md`, `.memory-bank/`, `scripts/mb-plan*`, `commands/mb.md`/`plan.md`) = 0
- [ ] CHANGELOG не содержит `[3.2.0] — unreleased — staged on main`
- [ ] Все остальные pytest тесты (628 + новые) green

**Code rules:** DRY (одна `read_status_section()` helper для всех тестов status), KISS (regex-парсинг — простой; не строить полный markdown AST)

---

<!-- mb-stage:3 -->
### Stage 3: Git/repo hygiene — gitignore, remote, dist cleanup

**What to do:**

- `.gitignore`:
  - добавить строку `.memory-bank/.session-lock`
  - проверить присутствие `dist/` (по аудиту gitignored, но локально лежат stale `3.0.0rc1` wheels — `rm -rf dist/` локально, в репо ничего)
- Снять lock из tracking-индекса (если когда-то добавлялся): `git rm --cached -f --ignore-unmatch .memory-bank/.session-lock`
- В `.git/config`:
  - удалить мёртвый remote: `git remote remove old-origin`
  - проверить `git config --get branch.main.remote` → должно быть `origin`; если `old-origin` — `git branch --set-upstream-to=origin/main main`
- `rm -rf dist/` локально
- `notes/2026-04-25_HH-MM_repo-remote-cleanup.md` — короткая заметка о выводе `old-origin` (5-10 строк, для будущих сессий)

**Testing (TDD):**

- Новый `tests/pytest/test_gitignore_invariants.py`:
  - `test_session_lock_is_gitignored` — `git check-ignore .memory-bank/.session-lock` exit 0
  - `test_dist_directory_is_gitignored` — `git check-ignore dist/foo` exit 0
  - `test_installed_manifest_is_gitignored` — `.installed-manifest.json` всё ещё gitignored
- Manual verification (нет dedicated теста):
  - `git remote -v | grep -c old-origin` == 0
  - `git config --get branch.main.remote` == `origin`

**DoD:**

- [ ] 3 новых pytest теста RED → GREEN
- [ ] `git status --porcelain` после `/mb done` = пусто (нет `.session-lock` в выводе)
- [ ] `git remote` показывает только `origin`
- [ ] `git config --get branch.main.remote` = `origin`
- [ ] `dist/` локально удалён
- [ ] `notes/2026-04-25_*_repo-remote-cleanup.md` создан

**Code rules:** YAGNI (не автоматизировать `git remote remove` в скрипте — разовая операция), explicit > implicit

---

<!-- mb-stage:4 -->
### Stage 4: Flaky CLI tests — root-cause + isolation fix

**What to do:**

- Root cause:
  - Запустить `pytest tests/pytest/test_cli.py -p no:randomly --tb=short -v` 5 раз подряд, найти order-dependency
  - Запустить парами падающих тестов: `pytest tests/pytest/test_cli.py::test_cli_install_uninstall_smoke_with_cursor_global tests/pytest/test_cli.py::test_uninstall_non_interactive_flag_works_without_stdin`
  - Проверить какие тесты используют `~/.cursor/` / `~/.claude/` / `~/.codex/` без `tmp_path` или без cleanup
  - Скорее всего: какой-то тест install не делает teardown → следующий test_uninstall видит residual state
- Fix:
  - Если есть `HOME=tmp_path` override в одних тестах но не в других — выровнять
  - Добавить `autouse=True` fixture `_isolated_home(monkeypatch, tmp_path)` для всего `test_cli.py` который ставит `HOME`/`XDG_CONFIG_HOME` в `tmp_path`
  - Альтернатива: добавить `cleanup` шаги в падающих тестах
- Запустить `pytest tests/pytest/test_cli.py -q` 3 раза подряд — все green

**Testing (TDD — тесты УЖЕ есть, чиним их):**

- Цель: 0 failures across **3 consecutive full runs** of `pytest tests/pytest -q`
- НЕ удалять тесты, НЕ skip'ать, НЕ ослаблять assertions
- Если корень — отсутствие HOME-override — добавить regression-проверку `test_cli_tests_isolate_home`:
  - `os.environ['HOME']` внутри теста ≠ исходный `os.environ['HOME']` (доказывает изоляцию через autouse fixture)

**DoD:**

- [ ] `for i in 1 2 3; do pytest tests/pytest -q || break; done` — 3 runs, все 628/628 passed
- [ ] Никакой тест не помечен `@pytest.mark.skip` или `@pytest.mark.xfail` для обхода проблемы
- [ ] `HOME` фактически isolated в `test_cli.py` (regression test зелёный)
- [ ] Root cause кратко документирован в `lessons.md` под секцией `### Test isolation — shared filesystem state`

**Code rules:** TDD (RED-фаза = воспроизведённый flake; GREEN-фаза = 3 чистых run'а; никакого green-by-skip), Testing Trophy (это integration, нужен реальный fs — tmp_path)

---

<!-- mb-stage:5 -->
### Stage 5: Critical code-quality fixes — BaseException + set -euo pipefail

**What to do:**

- `memory_bank_skill/_io.py:23` — `except BaseException:` → `except Exception:` (если ловится `OSError`/`UnicodeError` — указать явно)
- `settings/merge-hooks.py:147` — то же
- `scripts/_lib.sh` — добавить `set -euo pipefail` сразу после shebang
- `scripts/mb-plan-done.sh` — `set -euo pipefail` (если ещё нет)
- `scripts/mb-rules-check.sh` — `set -euo pipefail`
- `scripts/mb-compact.sh` — `set -euo pipefail`
- Проверить что `_lib.sh` consumers (все скрипты которые его `source` — grep `source.*_lib.sh`) не сломались от теперь-падающих ошибок

**Testing (TDD):**

- `tests/pytest/test_io_exception_narrowing.py`:
  - `test_io_KeyboardInterrupt_propagates` — функция в `_io.py` при искусственно подброшенном `KeyboardInterrupt` пробрасывает его наверх (не глотает)
  - `test_io_normal_OSError_caught` — `OSError`/`FileNotFoundError` всё ещё обрабатывается gracefully
- `tests/pytest/test_settings_merge_hooks_exception.py`:
  - аналогично для `settings/merge-hooks.py`
- bats: `tests/bats/test_lib_strict_mode.bats`:
  - `_lib.sh sourced and undefined var fails` — при `source _lib.sh; echo $UNDEFINED_VAR` exit ≠ 0
- Прогон всех существующих bats — должны остаться green (regression suite)

**DoD:**

- [ ] 4 новых теста (3 pytest + 1 bats) RED → GREEN
- [ ] `git grep -n "except BaseException" memory_bank_skill/ settings/ scripts/` = 0 (за исключением документации)
- [ ] `head -3 scripts/{_lib,mb-plan-done,mb-rules-check,mb-compact}.sh | grep -c "set -euo pipefail"` = 4
- [ ] `pytest tests/pytest -q` 628 passed (старые тесты + 3 новых = 631)
- [ ] `bats tests/bats tests/e2e` — green (старые passes + 1 новый pass)
- [ ] `ruff check .` clean

**Code rules:** Fail-fast (strict mode); SOLID-ISP (узкий exception вместо catch-all); robustness — не глотать сигналы

---

<!-- mb-stage:6 -->
### Stage 6: Security hardening — mb-idea/mb-search/file-change-log

**What to do:**

- `scripts/mb-idea.sh:37-41`:
  - заменить `grep -qE "^### I-[0-9]{3} — ${TITLE} "` на `grep -qF -- "— $TITLE "` ИЛИ эскейпать TITLE через `printf '%s\n' "$TITLE" | sed 's/[][\\.*^$()+?{|]/\\&/g'` если regex обязателен
  - аналогично исправить awk регексы в том же файле (lines 39-41) — либо `index()` либо escape
- `scripts/mb-search.sh:142,145,150,153`:
  - добавить `--` перед `"$QUERY"` в каждом `rg`/`grep` вызове: `rg --color=never -n -i --type md --heading -- "$QUERY" "$MB_PATH"`
- `hooks/file-change-log.sh:27-33`:
  - переписать rotation: `local tmp=$(mktemp "${LOG_FILE}.XXXXXX")` → `mv "$LOG_FILE" "${LOG_FILE}.1"` → атомарно
  - после первого `>>` создания файла — `chmod 600 "$LOG_FILE"`. Сделать это идемпотентно (не падать если уже 600)
- `hooks/file-change-log.sh:38`:
  - аналогичный `chmod 600` сразу после создания

**Testing (TDD):**

- bats `tests/bats/test_mb_idea_regex_safety.bats`:
  - `mb-idea.sh ".* matches everything"` — title с regex-метасимволом не должен ломать idempotency: первый вызов создаёт I-NNN, второй с тем же title — DUPLICATE detected (а не false-match через `.*`)
  - `mb-idea.sh "[bug]"` — square brackets не должны давать `grep` parsing error
- bats `tests/bats/test_mb_search_arg_safety.bats`:
  - `mb-search.sh "--no-config"` — query начинающаяся с `--` не должна парситься как флаг rg/grep; должен либо вернуть результат, либо «no matches», но не «unknown option»
- bats `tests/bats/test_file_change_log_perms.bats`:
  - после первой записи `stat -f %Mp%Lp ~/.claude/file-changes.log` (macOS) / `stat -c %a` (Linux) = `600`
  - rotation тест: `LOG_FILE` >50K → проверить что после rotation `${LOG_FILE}.1` существует с perms 600 и `LOG_FILE` empty
- Все 5 новых bats RED → GREEN

**DoD:**

- [ ] 5 новых bats тестов RED → GREEN
- [ ] `bats tests/bats tests/e2e` — старые + 5 новых, все green
- [ ] `shellcheck -S warning scripts/mb-idea.sh scripts/mb-search.sh hooks/file-change-log.sh` clean
- [ ] `chmod 600` фактически применён (manual smoke: `~/.claude/file-changes.log` после создания имеет perms 600)
- [ ] `mb-idea.sh ".* foo"` дважды → второй вызов `[skip] DUPLICATE` (а не «matched by regex»)
- [ ] `mb-search.sh -- --foo` — exit 0 без `unknown option` ошибки

**Code rules:** Defense-in-depth (даже если RCE невозможен — устраняем corner case); KISS (`grep -F` лучше эскейпинга если literal достаточно); explicit `--` end-of-flags везде

---

<!-- mb-stage:7 -->
### Stage 7: Terminology canonicalization — Phase/Sprint/Stage SSoT propagation

**What to do:**

- **SSoT остаётся** `references/templates.md` § «Plan decomposition» — содержимое не трогаем (правило уже корректно сформулировано на lines 107-160).
- **Propagate ссылку в 5 surface'ов** (по 1-3 строки каждый, без дублирования содержимого):
  - `rules/RULES.md` — новый раздел `## Naming conventions` сразу после `## Coding`: одна-две строки «Plan hierarchy: Phase → Sprint → Stage. См. `references/templates.md` § Plan decomposition. Cyrillic Этап/Спринт/Фаза — legacy, разрешено только в `plans/done/*.md`.»
  - `SKILL.md` — после `## Quick start` или в Workflow-секции: 1-line «Plan hierarchy: see `references/templates.md` § Plan decomposition for Phase/Sprint/Stage definitions.»
  - `commands/plan.md` — между «Validate arguments» и «Preparation»: 1-line «Hierarchy reminder: Phase → Sprint → Stage; details — `references/templates.md`.»
  - `commands/mb.md` — секция про `/mb plan`: 1-line ссылка на тот же reference
  - `references/planning-and-verification.md` — header или intro: 1-line cross-link
- **Enforce через drift-чекер** (новый чекер в `scripts/mb-drift.sh`):
  - `drift_check_terminology` — `git grep -inE "\\b(Этап|Эпик|Спринт|Фаза)\\b"` в `references/`, `commands/`, `rules/`, `docs/`, `SKILL.md`, `README.md`, `.memory-bank/status.md`, `.memory-bank/checklist.md`, `.memory-bank/roadmap.md`, `.memory-bank/research.md`, `.memory-bank/lessons.md`, `.memory-bank/backlog.md`, `.memory-bank/plans/*.md` (исключая `.memory-bank/plans/done/`). Hits > 0 → `warn`.
  - Регистрировать в выводе `mb-drift.sh` — `drift_check_terminology=ok|warn`.
- **Soft-validate в `scripts/mb-plan.sh`**:
  - Если `<topic>` содержит regex `(Этап|Эпик|Спринт|Фаза)` (case-insensitive) — печатать stderr-warning «[mb-plan] WARN: topic contains legacy Cyrillic naming; use Phase/Sprint/Stage», но **не блокировать** (создание плана продолжается). Контракт: warn только; пользователь может игнорировать.
- **Запись в `lessons.md`** в существующей секции `## Meta / Skill Design`, новый блок `### Single-source rule + propagation gap (2026-04-25)` — суть: правило существует в одном файле, не propagated → читателю выглядит как хаос; antidote = SSoT + 1-line refs в каждом surface'е + drift test + soft validate в creator script. Расширение паттерна «declarative intent ≠ contract» (там же в lessons).

**Testing (TDD — tests BEFORE implementation):**

- bats `tests/bats/test_mb_plan_legacy_terminology_warn.bats`:
  - `mb-plan.sh refactor "Этап 1 — auth"` — exit 0, stderr содержит «WARN»; файл создан
  - `mb-plan.sh refactor "phase-X-auth"` — exit 0, stderr НЕ содержит WARN
- bats `tests/bats/test_mb_drift_terminology_check.bats`:
  - подготовить tmp-проект с файлом `commands/foo.md` содержащим «Этап 1» → `mb-drift.sh` печатает `drift_check_terminology=warn` и exit 1
  - clean tmp-проект → `drift_check_terminology=ok` и exit 0
  - проверить что `plans/done/legacy.md` с «Этап 1» **не** триггерит warn (frozen archive exclusion)
- pytest `tests/pytest/test_terminology_canonicalization.py`:
  - `test_rules_md_has_naming_conventions_section` — `rules/RULES.md` содержит heading `## Naming conventions`
  - `test_skill_md_links_to_terminology_reference` — `SKILL.md` упоминает `references/templates.md` в контексте «Plan hierarchy» / «Phase/Sprint/Stage»
  - `test_commands_plan_md_has_hierarchy_reminder` — `commands/plan.md` ссылается на `references/templates.md`
  - `test_no_cyrillic_planning_terms_outside_archive` — `git grep -inE "\\b(Этап|Эпик|Спринт|Фаза)\\b"` в whitelisted scope'ах (см. список выше) = 0; разрешённые исключения: `plans/done/`, `CHANGELOG.md`, `progress.md`, сама секция в `lessons.md`, `templates.md` (где правило явно цитирует «Этап»)
- 6 новых тестов RED → GREEN

**DoD (Definition of Done):**

- [ ] `references/templates.md` § Plan decomposition не изменён (SSoT остался)
- [ ] `rules/RULES.md` содержит `## Naming conventions` секцию ссылающуюся на `references/templates.md`
- [ ] `SKILL.md`, `commands/plan.md`, `commands/mb.md`, `references/planning-and-verification.md` — каждый содержит 1-line cross-link на терминологическое правило (всего +5 одно-строчных правок)
- [ ] `scripts/mb-drift.sh` содержит новый чекер `drift_check_terminology`; вывод `bash scripts/mb-drift.sh .` включает строку `drift_check_terminology=ok`
- [ ] `scripts/mb-plan.sh` warns на legacy-Cyrillic в topic, но не блокирует создание
- [ ] `lessons.md` § Meta / Skill Design содержит блок `### Single-source rule + propagation gap (2026-04-25)`
- [ ] 6 новых тестов (2 bats + 4 pytest) — RED → GREEN
- [ ] `bash scripts/mb-drift.sh .` exit 0
- [ ] Все остальные тесты остаются green
- [ ] `git grep -inE "\\b(Этап|Эпик|Спринт|Фаза)\\b" -- ':!**/plans/done/' ':!CHANGELOG.md' ':!.memory-bank/progress.md' ':!.memory-bank/lessons.md' ':!references/templates.md'` = 0 строк

**Code rules:** SSoT (одно правило — один файл; остальное — refs); soft-validate > hard-block (warn в creator script, не отказываем — UX); contract via test (правило enforced тестом, не decree)

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Doc-vs-реальность тесты слишком хрупкие — ломаются при добавлении любого скрипта | M | Парсить таблицы структурно (markdown rows), не подсчёты в prose; failure message говорит «add row to table» а не «count mismatch» |
| `set -euo pipefail` в `_lib.sh` ломает молча работавшие consumers (там может быть `var=${X-default}` без quotes) | M | Перед добавлением: `git grep "source.*_lib.sh"` → прогон каждого consumer вручную; запускать pytest+bats после **каждого** добавления `set -euo` (по одному скрипту за коммит) |
| Flaky test fix не работает — корневая причина не в HOME, а где-то ещё (порядок плагинов, временные побочные ресурсы) | M | Stage 4 **первый шаг** = воспроизведение через `--count=20` или `pytest-repeat`; если корень не найден за 30 минут — Stage 4 пометить blocked, документировать в backlog как I-035, не блокировать остальные стадии |
| `git remote remove old-origin` не разрешён hook'ом или CI | L | Локальная операция, не пушится; если есть pre-commit guard — выполнить вручную и пометить в notes |
| `.session-lock` сейчас показывает `D` — может быть в индексе. После `git rm --cached` следующий `/mb done` снова создаст | L | Stage 3 включает обе операции: `git rm --cached` + `.gitignore`. После — реальный `/mb done` smoke в конце спринта проверит чистоту |
| `chmod 600` ломает уже работающие deploys где user читает лог как root но writes как user | L | Лог в `$HOME` — owner-only по дизайну; единственный тест на perms = bats, не CI integration. Если кто-то жалуется — opt-out через env `MB_LOG_PERMS=644` (но не сейчас, YAGNI) |
| Fix регулярок в `mb-idea.sh` ломает legacy backlog с уже сматченными ID | L | Идемпотентность сейчас на `grep -qE` — переход на `grep -qF` сужает match, не расширяет; на legacy-данных будет либо тот же match либо **меньше** false-positive — что мы и хотим |
| `drift_check_terminology` ловит false-positive в комментарии «historic Этап» в живом коде | L | Whitelist explicit: `plans/done/`, `CHANGELOG.md`, `progress.md`, `lessons.md`, `templates.md`. Если новое легитимное упоминание (цитата правила) — добавлять в whitelist, не отключать чекер |
| Soft-warn в `mb-plan.sh` пропускает Cyrillic topic незаметно для пользователя | L | Stderr-вывод виден в обычном CLI; drift-чекер ловит факт через session — двойной safety net. Hard-block отвергнут (UX: пользователь имеет право назвать как хочет) |

## Gate (plan success criterion)

**Все семь условий одновременно:**

1. ✅ `pytest tests/pytest -q` зелёный **3 раза подряд** — `628 + 27 новых = 655 passed, 0 failed, 0 flaky` (Stage 1=6, Stage 2=5, Stage 3=3, Stage 5=2, Stage 7=4 pytest = 20 pytest + 7 bats = 27 новых)
2. ✅ `bats tests/bats tests/e2e` — old + 7 новых (Stage 5=1 + Stage 6=5 + Stage 7=2) = green; `shellcheck -S warning` — exit 0; `ruff check .` — clean
3. ✅ `bash scripts/mb-drift.sh .` — `drift_warnings=0`; **включая новый `drift_check_terminology=ok`**; новые `test_doc_counts.py` + `test_status_drift.py` + `test_changelog_no_orphan_section.py` + `test_no_orphan_plan_md_references.py` + `test_gitignore_invariants.py` + `test_terminology_canonicalization.py` — все green
4. ✅ `git status --porcelain` пусто **сразу после** `/mb done`; `git remote` показывает только `origin`
5. ✅ `grep -c "VERSION: 3" .memory-bank/status.md` = 0 в active sections (Архив отдельно); `CHANGELOG.md` без orphan `[3.2.0]`
6. ✅ Manual smoke: `mb-idea.sh ".*"` дважды → DUPLICATE; `mb-search.sh -- --x` exit 0; `~/.claude/file-changes.log` perms = 600
7. ✅ Terminology SSoT: `git grep -inE "\\b(Этап|Эпик|Спринт|Фаза)\\b" -- ':!**/plans/done/' ':!CHANGELOG.md' ':!.memory-bank/progress.md' ':!.memory-bank/lessons.md' ':!references/templates.md'` = **0 строк**; 5 surface'ов (RULES/SKILL/commands/references) ссылаются на `references/templates.md` § Plan decomposition; `mb-plan.sh` warns на Cyrillic topic; `lessons.md` содержит запись `### Single-source rule + propagation gap (2026-04-25)`

`/mb verify` (через `plan-verifier` subagent) до `/mb done`. После закрытия: `notes/2026-04-25_*_v4-audit-remediation.md` суммирует key-takeaways в `lessons.md` под `### Documentation drift requires CI enforcement` (расширение существующего паттерна 2026-04-25 + cross-ref на новый `### Single-source rule + propagation gap`).
