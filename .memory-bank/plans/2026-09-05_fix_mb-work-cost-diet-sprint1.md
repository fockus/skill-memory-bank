---
type: fix
topic: mb-work-cost-diet-sprint1
phase: mb-work-cost-diet
sprint: 1
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-09-05
---
# Plan: fix — mb-work-cost-diet · Sprint 1 «context-diet + измерение»

**Baseline commit:** 364164a928a8691d5582c228747c3e528c047726

## Context

**Problem:** аудит [reports/2026-09-05_mb-work-cost-audit.md](../reports/2026-09-05_mb-work-cost-audit.md) показал, что стоимость `/mb work` ≈ *ходы × контекст на ход*, и обе половины раздуты самим скилом: `mb-context.sh` печатает core-файлы целиком без лимита (этот банк 112 KB ≈ 28k токенов, techflow 337 KB ≈ 84k), core-файлы растут вечно (`status.md` без ротации, `checklist.md` 596 строк при cap 120 — прунер не распознаёт структуру `<!-- mb-plan -->`/`## Stage N`), `COORDINATION.md` 204 KB велено читать каждому сабагенту, а governed-цикл стоит дефолтом в `pipeline.yaml` этого репо. Ни одна из этих цифр не измеряется штатно — `mb-session-spend.sh` считает только длины промптов.

**Expected result:** (1) стоимость видна: `mb-cost-report.py` даёт per-session / per-role / per-item цифры из транскриптов Claude Code и фиксирует baseline; (2) дешёвый путь — дефолт: `workflow.default: execution`, governed — opt-in; (3) старт сессии и чтение доски укладываются в бюджет: `mb-context.sh` ≤ 40 KB на этом банке, `mb-coord.sh active` ≤ 4 KB; (4) core-файлы перестают расти: ротация `status.md`, прунер `checklist.md` понимает реальную структуру и укладывает файл в 120 строк.

**Related files:**
- `scripts/mb-context.sh`, `scripts/mb-checklist-prune.sh`, `scripts/mb-agree.sh`, `scripts/mb-work-progress-append.sh` (locked append — переиспользуем для архивации)
- `.memory-bank/pipeline.yaml` (`workflow.default: codex-governed`, все роли `opus`)
- `agents/mb-engineering-core.md` §11, `agents/mb-manager.md` (action `done`), `references/coordination.md`
- `commands/mb.md`, `SKILL.md` § Tools (doc-count guard `test_doc_counts` — новый скрипт требует строки в SKILL.md в том же изменении, lesson 2026-06-09)
- Анализаторы аудита: `/tmp/mb_analyze{,2,3,4,5}.py` — прототип Stage 1
- Фикстура большого банка для тестов: `~/Apps/techflow/.memory-bank` (не трогать; копировать фрагменты в `tests/fixtures/`)

**Phase «mb-work-cost-diet» (3 спринта, зависимости строгие):**
1. **Sprint 1 — context-diet + измерение** (этот файл): cost-report · fast-lane конфиг · бюджет `mb-context.sh` · ротация `status.md` · прунер `checklist.md` · `mb-coord.sh active`.
2. Sprint 2 — work-loop-diet ([plan](2026-09-05_fix_mb-work-cost-diet-sprint2.md)): одна тест-улика на item · size-triage `mb-work-adapt.sh` + `--fast` · context pack для implementer (обещанный `--slim`) · раннер внешнего ревью без sleep-циклов.
3. Sprint 3 — instruction-diet + гигиена ([plan](2026-09-05_fix_mb-work-cost-diet-sprint3.md)): cap блока Agreements в `CLAUDE.md` · тонкий роутер `commands/mb.md` · `mb-work-next.sh` вместо 44 KB процедуры · переустановка уважает выключенные хуки.

Спринты 2–3 синкаются в `checklist.md` (`mb-plan-sync.sh`) только при старте — иначе чеклист выйдет за cap ещё до починки прунера.

**Осознанное отклонение от design-principles §1 «Default = unchanged behavior»:** Stage 2 и Stage 3 меняют дефолты (`workflow.default`, лимит вывода `mb-context.sh`). Это решение владельца по итогам аудита; старое поведение остаётся доступным (`--workflow codex-governed`, `mb-context.sh --full`), изменение фиксируется в CHANGELOG как Breaking.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: `mb-cost-report.py` — измерение и baseline

**Role:** developer

**What to do:**
- Перенести прототипы `/tmp/mb_analyze*.py` в `scripts/mb-cost-report.py` (stdlib only, Python 3.11): вход — каталог транскриптов (`--project <dir>`, по умолчанию `~/.claude/projects/<slug cwd>`), фильтр `--since <days>`; выход `--json` или таблица.
- Метрики: per session — ходы, tool-calls, Task-диспатчи, `output`/`cache_creation`/`cache_read` токены, пик контекста, компакции; per subagent role (implementer/verifier/reviewer/judge/other по маркерам промпта) — n, avg ходов, avg tool-calls, avg прогонов тестов (regex `pytest|bats|go test|ya make -t`), avg output, avg peak ctx, avg длительность; per work-item — сегмент `mb-work-state.sh init → mb-work-checkbox.sh flip`: длительность, диспатчи, output оркестратора.
- Логика парсинга в функциях (`iter_records`, `session_stats`, `subagent_stats`, `item_segments`), CLI отдельно (RULES.md § Architecture).
- Роутер-строка `cost [--project <dir>] [--since N] [--json]` в `commands/mb.md` + строка в `SKILL.md` § Tools.
- Снять baseline на этом проекте и сохранить `.memory-bank/reports/2026-09-05_cost-baseline.json` (по нему меряются гейты спринтов 2–3).

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_mb_cost_report.py` на синтетических фикстурах `tests/fixtures/cost-report/` (main-транскрипт с 2 Task-диспатчами и одним `init→flip`-сегментом; 2 сабагентских jsonl с ролями implementer/verifier; один битый JSON-line):
  - `test_session_stats_counts_tokens_tools_and_tasks`
  - `test_subagent_role_detected_from_prompt_markers`
  - `test_subagent_test_runs_counted_by_command_regex`
  - `test_item_segment_bounded_by_init_and_flip`
  - `test_malformed_line_skipped_without_crash`
  - `test_since_filter_excludes_old_sessions`
  - `test_json_output_schema_has_sessions_roles_items`
  - `test_doc_counts` (существующий) остаётся зелёным после строки в SKILL.md.

**DoD (Definition of Done):**
- [x] `python3 scripts/mb-cost-report.py --project tests/fixtures/cost-report --json` печатает JSON с ключами `sessions`, `roles`, `items`; числа совпадают с фикстурой (утверждения в тестах).
- [x] На реальном каталоге `~/.claude/projects/-Users-anton-one-Apps-skill-memory-bank` отрабатывает < 10 s и без трейсбэка.
- [x] `.memory-bank/reports/2026-09-05_cost-baseline.json` записан; `progress.md` получил строку с ключевыми цифрами baseline.
- [x] `commands/mb.md` (роутер) и `SKILL.md` § Tools содержат `cost`/`mb-cost-report.py`; `pytest tests/pytest/test_doc_counts.py tests/pytest/test_mb_cost_report.py` зелёный.
- [x] `ruff check scripts/mb-cost-report.py` = 0 замечаний.

**Code rules:** KISS (stdlib, без pandas), SRP — парсинг отдельно от CLI, Testing Trophy — интеграционные тесты на фикстурах, а не моки.

---

<!-- mb-stage:2 -->
### Stage 2: Fast lane без кода — дефолт `execution`, governed opt-in

**Role:** developer

**What to do:**
- `.memory-bank/pipeline.yaml` этого репо: `workflow.default: codex-governed` → `execution`; блок `codex-governed` остаётся как именованный пресет; комментарий с датой и ссылкой на аудит. Роли/модели не трогать (AGR-028/029 действуют для группы sdd-vision-pipeline — её прогоны запускаются явно `--workflow codex-governed`).
- `docs/mb-work.md` и `commands/work.md`: раздел «Лестница стоимости» — таблица `implement-only | execution | codex-governed | governed-execution` с колонками *диспатчей на item · прогонов тестов · когда выбирать*, с цифрами baseline из Stage 1 (обновить после Sprint 2).
- `CHANGELOG.md` `[Unreleased]` → `### Changed — BREAKING (this bank only)`: дефолтный workflow банка репозитория.

**Testing (TDD):**
- `tests/pytest/test_docs_cost_ladder.py`: `test_mb_work_docs_have_cost_ladder_table` (обе доки содержат заголовок и 4 строки пресетов), `test_pipeline_default_is_execution_in_repo_bank`.
- `bash scripts/mb-pipeline-validate.sh .memory-bank/pipeline.yaml` — exit 0.
- `bash scripts/mb-workflow.sh --mb .memory-bank --json` → `entrypoint=plan_or_spec`, `steps=[implement,verify,done]`; `--workflow codex-governed` → шесть шагов (проверяется в том же pytest через subprocess).

**DoD:**
- [ ] `mb-workflow.sh --json` без флагов возвращает `execution`; с `--workflow codex-governed` — прежний governed-цикл (assert в тесте).
- [ ] `mb-pipeline-validate.sh` exit 0; `mb-drift.sh .` не добавляет новых находок против baseline.
- [ ] Таблица «Лестница стоимости» есть в `docs/mb-work.md` и `commands/work.md` (pytest).
- [ ] CHANGELOG-запись добавлена.

**Code rules:** YAGNI — только конфиг и доки, никаких новых флагов.

---

<!-- mb-stage:3 -->
### Stage 3: Бюджет вывода `mb-context.sh`

**Role:** developer

**What to do:**
- В `scripts/mb-context.sh` добавить лимит на файл: `MB_CONTEXT_MAX_BYTES` (env) → `.mb-config context_max_bytes=` → default `16384`; флаг `--full` = прежний вывод байт-в-байт.
- Обрезка «по смыслу», не по байту: `status.md` — целые `## `-секции сверху вниз, пока влезают; `checklist.md` — сначала выбрасываются строки с `✅`, затем хвост; `roadmap.md`/`research.md` — head по границе строки. После обрезанного файла — одна строка `[context] <file>: shown N of M lines — full: <path> or --full`.
- Секцию «Codebase summary»/«Code graph»/«Latest note» не трогать (уже лаконичны).
- Тест-фикстура `tests/fixtures/context-budget/` — банк с `status.md` 60 KB (6 секций), `checklist.md` 300 строк (половина ✅).

**Testing (TDD):**
- `tests/bats/test_context_budget.bats`:
  - `under cap → output byte-identical to --full`
  - `status.md over cap → whole sections kept, marker line present`
  - `checklist.md over cap → ✅ lines dropped before ⬜ lines`
  - `--full restores unbounded output`
  - `MB_CONTEXT_MAX_BYTES=0 disables the cap`
  - `.mb-config context_max_bytes honoured, env wins over file`
  - `symlink/out-of-bank core file still skipped` (регресс I-082)
  - существующий `test_context_integration.bats` зелёный.

**DoD:**
- [ ] `bash scripts/mb-context.sh .memory-bank | wc -c` ≤ 40 000 на этом банке (сейчас 111 655); `bash scripts/mb-context.sh ~/Apps/techflow/.memory-bank | wc -c` ≤ 60 000 (сейчас 336 887).
- [ ] `mb-context.sh --full` даёт байт-идентичный вывод с baseline-версией скрипта (сравнение в тесте через фикстуру).
- [ ] 8/8 bats зелёные, `shellcheck -x scripts/mb-context.sh` чист.
- [ ] `commands/mb.md` (строки `context`/`start`) и `docs/` упоминают `--full` и `context_max_bytes`.

**Code rules:** KISS — обрезка в одной python-heredoc-функции по образцу `mb-checklist-prune.sh`; fail-open — ошибка обрезки → печатаем файл целиком.

---

<!-- mb-stage:4 -->
### Stage 4: `mb-status-rotate.sh` — ротация `status.md`

**Role:** developer

**What to do:**
- Новый `scripts/mb-status-rotate.sh [--keep N] [--dry-run|--apply] [--mb <path>]`: датированные `## `-секции (заголовок содержит `YYYY-MM-DD`) сверх первых `N` (default 3) переносятся в `progress.md` блоком `## [status archive] <исходный заголовок>` через `mb-work-progress-append.sh --text` (locked, append-only); недатированные секции (`## Current phase`, `## Open backlog`, `## ⏭ …`) остаются на месте; порядок оставшихся не меняется.
- `--apply` пишет backup `.status.md.bak.<ts>` и атомарно перезаписывает (`_lib.sh` atomic write); `--dry-run` (default) печатает план.
- Подключение: `agents/mb-manager.md` action `done` шаг «Actualize core files» → перед записью `status.md` вызвать `mb-status-rotate.sh --apply`; `commands/done.md` — одна строка; `mb-doctor` (`scripts/mb-drift.sh`) — WARN «status.md > 24 KB — run mb-status-rotate.sh».
- `.gitignore`: `.memory-bank/.status.md.bak.*`.

**Testing (TDD):**
- `tests/bats/test_status_rotate.bats`:
  - `dated sections beyond --keep are moved to progress.md verbatim`
  - `undated sections are never moved`
  - `--keep 5 keeps five`
  - `dry-run writes nothing`
  - `apply writes backup and is idempotent (second run = no-op)`
  - `progress.md append goes through the locked helper (lock file respected)`
  - `status.md with fewer than N dated sections is untouched byte-for-byte`
  - `test_doc_counts` зелёный после строки в SKILL.md.

**DoD:**
- [ ] На копии `status.md` этого банка (12 датированных секций) `--apply --keep 3` оставляет 3 датированные + все недатированные; `progress.md` получает 9 блоков `[status archive]`.
- [ ] 7/7 bats, shellcheck чист; строка в `SKILL.md` § Tools и в `commands/mb.md` (`done`).
- [ ] `agents/mb-manager.md` и `commands/done.md` содержат шаг ротации (pytest-doc-assert в `test_docs_cost_ladder.py` или новом `test_status_rotate_docs.py`).

**Code rules:** append-only `progress.md` (инвариант банка), атомарная запись, fail-open при отсутствии `progress.md` (создать).

---

<!-- mb-stage:5 -->
### Stage 5: Прунер `checklist.md` под реальную структуру

**Role:** developer

**What to do:**
- `scripts/mb-checklist-prune.sh`: добавить к текущему правилу (`### ` + ссылка `plans/done/`) два новых:
  - (b) блок `<!-- mb-plan:<file> -->` + `## Stage N: …`, у которого все пункты `✅`/`[x]` **или** `<file>` лежит в `plans/done/` → схлопывается в одну строку `- ✅ <file>: Stage N — <title>` под секцией `## ✅ Done` (создать, если нет);
  - (c) секция `## ✅ Done` длиннее `--done-max` (default 12 пунктов) → лишние переносятся в `progress.md` блоком `## [checklist archive] <date>` через `mb-work-progress-append.sh`.
- Блоки с хотя бы одним `⬜`/`[ ]` не трогаются никогда; `## 🔄 Active`/`## ⏳ In flight`/`## ⏭ Next planned` защищены как раньше.
- `hooks/mb-checklist-autoprune.sh` (SessionEnd) уже вызывает прунер — поведение получает новые правила автоматически; hard-cap WARN остаётся.

**Testing (TDD):**
- расширить `tests/pytest/test_mb_checklist_prune.py`:
  - `test_stage_block_all_done_collapses_to_done_line`
  - `test_stage_block_with_open_item_untouched`
  - `test_stage_block_of_done_plan_collapses_even_with_open_items_marked_by_plan_move` (план в `plans/done/`)
  - `test_done_section_overflow_moved_to_progress`
  - `test_techflow_like_fixture_596_lines_ends_under_cap` (фикстура `tests/fixtures/checklist-big.md`, обезличенная копия структуры techflow)
  - `test_apply_idempotent_second_run_noop`
  - `test_backup_written_on_apply`
  - `test_protected_sections_untouched`

**DoD:**
- [ ] На фикстуре 596 строк `--apply` даёт ≤ 120 строк без потери ни одного `⬜`/`[ ]` (assert по множеству открытых пунктов до/после).
- [ ] На `checklist.md` этого банка `--dry-run` показывает кандидатами 6 блоков `spec-group-round3-remediation` (все ✅), а 5 блоков `graph-semantic-adoption` — нет.
- [ ] 8 новых pytest + существующие 12 зелёные; shellcheck чист; `hooks/tests` для autoprune зелёные.

**Code rules:** контракт = код (lesson «rotating без enforcement = накапливающийся»): hard-cap теперь достижим автоматически; никаких правок вне блоков-кандидатов.

---

<!-- mb-stage:6 -->
### Stage 6: `mb-coord.sh active` — доска без 200 KB

**Role:** developer

**What to do:**
- Новый `scripts/mb-coord.sh active [--tail N] [--mb <path>]`: парсит `COORDINATION.md` по `## `-записям; печатает (1) активные FREEZE — записи с типом `FREEZE`, для которых нет более поздней записи `LIFT` с тем же scope-текстом, (2) HANDOVER без последующего `ACK`, ссылающегося на заголовок, (3) последние `N` записей (default 3) целиком, (4) строку `board: <total> entries, <bytes> bytes — full file: <path>`. Тип записи — первый тег заголовка `## FREEZE ·` / `## LIFT ·` / `## HANDOVER ·` / `## ACK ·` / `## STATUS ·`; записи без тега = `STATUS` (весь текущий legacy-корпус).
- Подкоманда `append --type <T> --title <t> [--body-file <f>]` — пишет запись в каноническом формате через locked append (тот же helper), чтобы новые записи были парсибельны.
- `references/coordination.md`: грамматика тегов + «читайте доску через `mb-coord.sh active`, полный файл — только при расследовании»; `agents/mb-engineering-core.md` §11 и `rules/CLAUDE-GLOBAL.md`/`CLAUDE.md` (строка про COORDINATION) — ссылка на команду вместо «read the board».

**Testing (TDD):**
- `tests/bats/test_mb_coord.bats`:
  - `untagged legacy entries are STATUS and never reported as active freeze`
  - `FREEZE without LIFT is active; with matching LIFT it is not`
  - `HANDOVER without ACK reported; with ACK not`
  - `--tail 2 prints exactly the last two entries`
  - `append writes a tagged entry parseable by active`
  - `output on a 200 KB board fixture is under 4 KB`
  - `missing board → exit 0 with "no board" line`
- pytest-doc-assert: `agents/mb-engineering-core.md` и `references/coordination.md` содержат `mb-coord.sh active`.

**DoD:**
- [ ] `bash scripts/mb-coord.sh active --mb .memory-bank | wc -c` ≤ 4 096 на текущей доске (203 955 байт); активный FREEZE «no rebase/reset/checkout/stash» (запись 2026-07-1x) в выводе есть.
- [ ] 7/7 bats, shellcheck чист; строка в `SKILL.md` § Tools и роутер `coord` в `commands/mb.md`.
- [ ] Ни один агентский/командный файл больше не велит «читать COORDINATION.md целиком» (`command grep -rn 'Read the board\|читать доску' agents commands references` → только ссылки на `mb-coord.sh active`).

**Code rules:** fail-open (нет доски → пустой вывод, exit 0), парсер в python-heredoc, детерминированный формат для тестов.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Обрезка контекста скроет важную запись `status.md` | M | Обрезаем целыми секциями сверху; маркер с путём и `--full`; ротация (Stage 4) держит в `status.md` только свежее, так что «важное» и есть верхние секции |
| Прунер/ротация испортят пользовательский банк | M | dry-run по умолчанию, backup при apply, идемпотентность в тестах, фикстура-копия techflow; открытые `⬜` под assert «множество до = после» |
| Legacy-записи доски без тегов не парсятся как FREEZE | H (по факту так) | Untagged = STATUS by design; единственный живой FREEZE переоформляется тегированной записью через `append` в этой же сессии |
| Смена `workflow.default` ломает прогоны группы sdd-vision-pipeline | L | Группа запускается явно `--workflow codex-governed`; пресет сохранён байт-в-байт; запись в CHANGELOG и `agreements` |
| `test_doc_counts`/drift-чекеры красные из-за новых скриптов | M | Строки в `SKILL.md`/`commands/mb.md` в том же изменении (lesson 2026-06-09); `mb-drift.sh` в DoD каждой стадии с новым файлом |
| Checklist переполнится от синка спринтов 2–3 до починки прунера | H | Синкать sprint2/3 только при их старте (после Stage 5) |

## Gate (plan success criterion)

На этом репозитории после Sprint 1: `mb-context.sh .memory-bank` ≤ 40 KB, `mb-coord.sh active` ≤ 4 KB, `checklist.md` ≤ 120 строк после `mb-checklist-prune.sh --apply`, `status.md` ≤ 3 датированных секций после `mb-status-rotate.sh --apply`, `mb-workflow.sh --json` по умолчанию = `execution`, `.memory-bank/reports/2026-09-05_cost-baseline.json` существует, а полная батарея (`bash scripts/mb-test-run.sh --dir . --out json` → `tests_pass: true`) зелёная. `/mb verify` PASS перед `/mb done`.
