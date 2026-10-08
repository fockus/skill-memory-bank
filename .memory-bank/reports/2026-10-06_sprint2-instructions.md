# Sprint 2 «CLAUDE.md» — verification notes (2026-10-06)

## Stage 2 · `/mb init --full` template render (W4)

Rendered `references/claude-md-template.md` for a tmp Python project (pyproject: fastapi + sqlalchemy, ruff, uv):
37 lines, 0 unfilled `{PLACEHOLDER}`s, sections Project → Commands → Stack & conventions → Architecture →
Project rules → Memory Bank. Rendered deterministically (placeholder substitution) — the LLM-driven `/mb init --full`
flow fills the same placeholders; a live interactive run in a fresh session is still recommended.

## Stage 3 · CLAUDE-GLOBAL lines dropped on purpose (W3)

17 non-blank lines of the 84-line baseline are not present verbatim anywhere in SKILL.md / references / rules.
None carries a rule that is lost — each is a heading or a duplicate whose meaning lives elsewhere:

| Baseline line(s) | Content | Where the meaning lives now |
|---|---|---|
| 36, 45, 48, 58, 65, 70, 76, 81 | section headings / framing sentence | removed with their sections; "Detailed rules:" pointer kept |
| 40 | TDD + No placeholders restated | `# Engineering rules` (once) · `rules/RULES.md` § Coding Standards → General |
| 46 | Testing Trophy + Coverage restated | `# Engineering rules` (once); static-analysis part kept as a bullet |
| 49 | Plans restated (second copy) | `# Engineering rules` → Plans · `rules/RULES.md` § Session Pipeline → Phase 2 |
| 54 | three-in-one + design contract | SKILL.md intro · `rules/RULES.md` § Design contract |
| 56 | subagents roster line | `rules/RULES.md` § Subagents · `references/agents.md` |
| 74 | pointer to code-graph reference | the text itself now lives in `references/code-graph.md` |
| 77, 78, 79 | rule profiles · `<private>` · native auto-memory | `rules/RULES.md` § Rule profiles, § Private content, § `.memory-bank/` vs native auto-memory · `references/privacy-and-capture.md` |

## Verifier follow-ups fixed

- ruff E741 in `tests/pytest/test_claude_md_template.py` — renamed.
- Hollow mid-test `[[ … ]]` asserts (bash 3.2) → `assert_substring`/`refute_substring`:
  `tests/bats/test_mb_agree_block_budget.bats` (6), `tests/bats/test_migrate_structure.bats:99` (1).
  Mutation proof: changing the expected `AGR-004: Replacement.` makes test 5 fail; restored → green.

## Stage 4 · repo CLAUDE.md / AGENTS.md budget (P2, P3)

- Guard `tests/pytest/test_repo_instruction_budget.py`: `AGENTS.md` ≤ 32 768 B (Codex default
  `project_doc_max_bytes`; skipped when the gitignored file is not rendered), `CLAUDE.md` ≤ 200 lines and ≤ 10 240 B.
  2 passed; with the limits lowered to 1 000 B / 50 lines both tests fail.
- Codex limit source: `project_doc_max_bytes = 32768` in
  https://github.com/openai/codex/blob/main/codex-rs/config/defaults.toml; the docs say "32 KiB by default"
  (https://developers.openai.com/codex/guides/agents-md).
- Now: `AGENTS.md` 7 987 B, `CLAUDE.md` 8 352 B / 82 lines. Before/after table: `reports/2026-10-06_agents-md-baseline.md` § Stage 5.
- `scripts/mb-drift.sh .`: `drift_warnings=1`, only `plan_vs_git` (12 plans shipped-but-not-closed). The HEAD
  snapshot (`git archive HEAD`) gives the same warning and the same 12 plans, so there are no new findings.

## I-253 · живой `/mb init --full` (2026-10-07)

Прогон: tmp-проект (`mktemp -d`; `pyproject.toml` с pytest, `src/pkg/__init__.py`, `tests/test_x.py`, `git init`),
команда `claude -p "/mb init --full --storage=local --lang=en …(ответы по умолчанию: map N, CLAUDE.md да, profile N)"
--permission-mode acceptEdits --max-budget-usd 5 --output-format stream-json --verbose` (Claude Code 2.1.288,
установленный скил — симлинк на этот репозиторий).

**Прогон 1 (до фикса)** — 6 ходов, $2.10, 40 с. `CLAUDE.md`: 36 строк, 1 846 B, без плейсхолдеров. Найдено:
- нет блока `## Key rules` (AGR-083): Step 4 в `commands/mb.md` не вызывал `mb-rules.sh sync --scope=project`;
- раздел Project rules указывал на глобальный `~/.claude/RULES.md`, а локальный — «when present» (против AGR-066);
- `scripts/mb-coord.sh active` — путь, которого в проекте пользователя нет (скрипт лежит в скиле).

**Фикс (TDD):** 3 теста в `tests/pytest/test_claude_md_template.py` (красные → зелёные, файл 27 passed);
`references/claude-md-template.md` — указатель на локальный `RULES.md`, `mb-coord.sh` как скрипт скила, заметка о sync;
`commands/mb.md` Step 4 — описание раздела Project rules + шаг `mb-rules.sh sync --scope=project` после записи.

**Прогон 2 (после фикса)** — 11 ходов, $1.45, 60 с. Модель сама вызвала `mb-rules.sh sync --scope=project`.
`CLAUDE.md`: 44 строки, 1 893 B. `AGENTS.md` не создаётся (`/mb init` его не генерирует).

~~~markdown
<!-- mb-key-rules:start -->
## Key rules

Global Key rules apply; this project has no overrides.

Your own rules: create `RULES.md` in the project root.
<!-- mb-key-rules:end -->

## Project

**pkg** — Tiny demo package for the /mb init live run

## Commands

```bash
pip install -e '.[dev]'    # build / install
pytest -q                  # run tests
ruff check .               # lint
```

## Stack & conventions

- Python 3.11+, no runtime dependencies; dev: pytest>=8; packaging via `pyproject.toml` (src layout)
- pytest runs from `tests/` with `pythonpath = ["src"]` — no install needed to run tests
- Full stack, naming and code style: `.memory-bank/codebase/STACK.md`, `.memory-bank/codebase/CONVENTIONS.md`

## Architecture

Single package `src/pkg/` (public API in `__init__.py`: `add`); tests in `tests/` (`test_<what>_<condition>_<result>` naming).

## Project rules

Detailed rules: the project's `RULES.md` (repo root, else `.memory-bank/RULES.md`). List only this project's overrides here.

No project overrides yet.

## Memory Bank

- Size the task first — memory-bank skill § Task routing (`references/effort-tiers.md`); trivial and small tasks need no plan.
- `/mb work` runs when the task refers to an existing plan or spec in `.memory-bank/`; planned work: `/mb plan <type> <topic>` → `/mb work` → `/mb verify` → `/mb done`.
- Run `/mb verify` before `/mb done` when work followed a plan — it checks every DoD item against the code.
- Parallel sessions in one working tree: read `.memory-bank/COORDINATION.md` via the memory-bank skill's `mb-coord.sh active` before stages and commits; scoped `git add` only.
- Key files: `status.md` (current state), `checklist.md` (active tasks), `roadmap.md` (priorities), `plans/` (stage plans), `progress.md` (append-only log).
- Code graph & search → memory-bank skill (`/mb graph`, `mb-graph.sh`; opt-in `/mb wiki`).
~~~

| Ожидание | Итог |
|---|---|
| ≤ 80 строк | ✅ 44 строки (прогон 1 — 36) |
| команды под стек | ✅ `pip install -e '.[dev]'`, `pytest -q`, `ruff check .`; run-строка опущена (точки входа нет) |
| нет плейсхолдеров | ✅ 0 `{…}`, 0 `<!-- generator` |
| условный gate `/mb work` | ✅ «runs when the task refers to an existing plan or spec» |
| указатель на локальный `RULES.md` (AGR-066) | ✅ раздел Project rules; в блоке Key rules — `Details: .memory-bank/RULES.md` при наличии файла (проверено `mb-rules.sh sync` на копии прогона 1), иначе подсказка создать `RULES.md` |
| блок Key rules проекта (AGR-083) | ✅ после фикса; delta: «this project has no overrides» |

Замечания вне шаблона (не исправлял — не мои файлы):
- `mb-metrics.sh` для Python отдаёт `lint_cmd=ruff check .`, даже если ruff не объявлен; модель оставила строку
  (в прогоне 1 — с пометкой «not declared»), хотя Step 4 велит не угадывать команды.
- Прогон 2: копирование `~/.claude/RULES.md` в `.memory-bank/RULES.md` (Step 2) заблокировал headless-режим
  («sensitive file»), поэтому указатель в Key rules — подсказка создать `RULES.md`. В прогоне 1 тот же `cp` прошёл;
  в интерактивной сессии пользователь подтверждает. Это ограничение `-p`, не баг шаблона.
- `mb-init-bank.sh` не создаёт `plans/done/`, хотя Step 1 его перечисляет (модель в прогоне 2 создала вручную).
- В сгенерированном файле нет заголовка `#` — тело шаблона начинается с `##`; на работу не влияет.
