---
type: fix
topic: mb-work-cost-diet-sprint3
phase: mb-work-cost-diet
sprint: 3
status: planned
depends_on: [2026-09-05_fix_mb-work-cost-diet-sprint2.md]
parallel_safe: false
linked_specs: []
created: 2026-09-05
---
# Plan: fix — mb-work-cost-diet · Sprint 3 «instruction-diet + гигиена»

**Baseline commit:** 364164a928a8691d5582c228747c3e528c047726 (переснять при старте спринта)

## Context

**Problem:** до первого полезного действия модель получает 25–40k токенов инструкций: `commands/mb.md` 97 KB — вход любой `/mb`-подкоманды, `commands/work.md` 44 KB + `references/work-reference.md` 19 KB, блок `## Active Agreements` в `CLAUDE.md` 19 KB (36 записей) — в каждую сессию и каждого сабагента. Нормативный цикл `/mb work` (28 вызовов скриптов на item) модель держит в голове как прозу, а не получает от машины состояния. Переустановка (`settings/merge-hooks.py`) молча возвращает хуки, которые пользователь выключил (прецедент I-158). Цифры — [reports/2026-09-05_mb-work-cost-audit.md](../reports/2026-09-05_mb-work-cost-audit.md).

**Expected result:** инструкционная нагрузка `/mb work` (роутер + команда) ≤ 32 KB вместо 141 KB; блок Agreements ≤ 6 KB; следующий шаг цикла печатает `mb-work-next.sh` по `.work-state`, а `commands/work.md` ужимается до контракта ≤ 20 KB; выключенный хук не возвращается при `install.sh`.

**Related files:**
- `commands/mb.md` (роутер, 97 KB), `commands/{work,sdd,discuss,plan,done,brief,drive,config,pipeline,profile,groom}.md` (тела уже вынесены частично)
- `scripts/mb-agree.sh` (`cmd_sync`, рендер `## Active Agreements`), `tests/bats/test_mb_agree*.bats`
- `scripts/mb-work-state.sh` (`status`, `steps[]`, `phase`, `cycle`), `scripts/mb-workflow.sh --json` (`steps`, `loop`)
- `settings/merge-hooks.py`, `settings/hooks.json`, `install.sh` (release-sensitive: тесты идемпотентности обязательны — RULES.md § Protected Paths), `tests/pytest/test_merge_hooks.py`, `docs/hooks.md`, `references/hooks.md`
- Doc-контракты, которые могут держаться за текст `mb.md`: `tests/pytest/test_sdd_command_contract*.py`, `test_doc_counts.py`, `tests/bats/test_*_docs.bats` — инвентаризировать в Stage 2 **до** переноса текста

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Cap блока Agreements в `CLAUDE.md`

**Role:** developer

**What to do:**
- `scripts/mb-agree.sh sync`: рендерить в managed-блок `CLAUDE.md` не более `N` активных записей, новейшие первыми (`MB_AGREE_SYNC_MAX` → `.mb-config agreements_claude_md_max=` → default 12); при усечении — хвостовая строка `… +M more active — \`mb-agree.sh list\` / agreements.md`; `N=0` = без лимита (прежнее поведение). `agreements.md` остаётся полным SSOT, `list` не меняется.
- `references/agreements.md` и `commands/agree.md`: абзац про лимит и как его поднять.

**Testing (TDD):**
- расширить `tests/bats/test_mb_agree.bats` / `test_mb_agree_docs.bats`:
  - `sync with 36 active renders 12 newest + footer with count 24`
  - `MB_AGREE_SYNC_MAX=0 renders all (byte-identical to previous format)`
  - `.mb-config value honoured; env wins`
  - `superseded entries never counted as active`
  - `sync idempotent under the cap (second run no diff)`

**DoD:**
- [ ] `bash scripts/mb-agree.sh sync .memory-bank` → блок в `CLAUDE.md` ≤ 6 144 байт (сейчас 18 928), содержит AGR-038…AGR-027 и футер `+24 more`.
- [ ] 5 новых bats + существующий сьют `test_mb_agree*` зелёные; shellcheck чист.
- [ ] Доки обновлены (bats-doc в `test_mb_agree_docs.bats`).

**Code rules:** SSOT остаётся в `agreements.md`; рендер — чистая функция от списка; opt-out через `0`.

---

<!-- mb-stage:2 -->
### Stage 2: Тонкий роутер `commands/mb.md`

**Role:** developer

**What to do:**
- Инвентаризация: `command grep -rln 'commands/mb.md' tests/` → список тестов-контрактов; для каждого — какие строки `mb.md` они читают. Перенос текста делается так, чтобы каждое утверждение либо нашло тот же текст в новом файле (обновить путь в тесте), либо осталось валидным (роутер-строка).
- `commands/mb.md` → только: статус-гард, таблица роутинга (одна строка на подкоманду: синтаксис · одно предложение · `→ commands/<sub>.md`), «Aliases», GraphRAG-routing (≤ 15 строк). Тела подкоманд без собственного файла (`recall`, `recap`, `conflicts`, `consolidate`, `research`, `context/search/note/tasks`, `update`, `doctor`, `index`, `verify`, `map`, `upgrade`, `graph`, `wiki`, `agree`, `cost`, `coord`, …) переезжают в `commands/<sub>.md` (по одному файлу, шаблон `references/command-template.md`); файлы ≤ 8 KB каждый.
- Целевой размер `commands/mb.md` ≤ 12 KB. Guard-тест на размер и на то, что каждая роутер-строка указывает на существующий файл.
- `install.sh`/адаптеры: убедиться, что новые `commands/*.md` попадают в установку (счётчик команд в `SKILL.md`/`test_doc_counts`, адаптеры `adapters/*.sh` копируют `commands/*`).

**Testing (TDD):**
- `tests/pytest/test_mb_router_thin.py`:
  - `test_mb_md_under_12kb`
  - `test_every_router_row_points_to_existing_command_file`
  - `test_no_h3_subcommand_bodies_left_in_router` (нет `### <sub>` секций длиннее 20 строк)
  - `test_moved_bodies_keep_their_contract_phrases` (параметризовано по инвентаризации: фраза → новый файл)
- Полный прогон `pytest tests/pytest/test_sdd_command_contract*.py tests/pytest/test_doc_counts.py` + `bats tests/bats/test_*_docs.bats` зелёные после переноса.

**DoD:**
- [ ] `wc -c commands/mb.md` ≤ 12 288; все роутер-строки резолвятся (pytest).
- [ ] Ни один существующий doc-контракт не удалён — только обновлены пути (diff тестов показывает лишь замену `commands/mb.md` → `commands/<sub>.md`).
- [ ] `bash install.sh --dry-run`/e2e-тест установки показывают новые командные файлы в манифесте; `test_doc_counts` зелёный.
- [ ] `mb-drift.sh .` без новых находок; `mb-cost-report.py` на тестовой сессии показывает `invoked_skills mb` ≤ 12 KB.

**Code rules:** Strangler Fig — переносить по одной подкоманде с зелёными тестами на каждом шаге; никаких правок смысла команд.

---

<!-- mb-stage:3 -->
### Stage 3: `mb-work-next.sh` — машина состояний вместо 44 KB прозы

**Role:** developer

**What to do:**
- Новый `scripts/mb-work-next.sh [--run-id <id>] [--mb <bank>] [--json]`: читает `mb-work-state.sh status` (phase, item_no, `steps[]`, cycle, eval-record) и `mb-workflow.sh --json` (`steps`, `loop`, `fast`), печатает **ровно один** следующий шаг: имя (`eval-red|contract-declare|contract-build|contract-red|implement|protected-check|eval-green|contract-verify|verify|review|judge|fix|done|flip|graph-catchup|end`), точную команду/диспатч-шаблон (агент, модель, thinking, файл промпта), и условия остановки (hard stops из таблицы `work.md`). Логика — таблица переходов в `scripts/mb-work-next-lib.sh`; при неконсистентном state — exit 2 с диагностикой, без «угадывания».
- `commands/work.md` → контракт ≤ 20 KB: резолв цели, инвариант «после каждого шага вызвать `mb-work-next.sh` и выполнить ровно его», формат диспатча, hard stops, resume; вся пошаговая проза §5a0–5g переезжает в `references/work-reference.md` § Loop (как справка, не как инструкция).
- `hooks`/`docs/mb-work.md`: пример сессии в 6 строк.

**Testing (TDD):**
- `tests/bats/test_work_next.bats` (state-фикстуры в `tests/fixtures/work-state/`):
  - `fresh state + execution → implement`
  - `implement recorded, eval declared → eval-green before verify`
  - `verify PASS + governed → review; review parsed → judge`
  - `judge NO_GO + cycle < max → fix; cycle exhausted → on_max_cycles branch`
  - `judge GO → done → flip → graph-catchup → end`
  - `contract task: declare → build → red gate → implement`
  - `fast:true → implement → done (no verifier dispatch)`
  - `inconsistent state (phase done, steps empty) → exit 2`
  - `--json emits {step, command, stop_conditions}`
- doc-pytest: `commands/work.md` ≤ 20 KB, содержит `mb-work-next.sh`, не содержит `### 5a0.`…`### 5g` заголовков.

**DoD:**
- [ ] 9 bats зелёные; shellcheck; строка в `SKILL.md` § Tools; `commands/work.md` ≤ 20 480 байт.
- [ ] Прогон одного реального item через `/mb work` с `mb-work-next.sh` на каждом шаге совпадает по последовательности с прежним циклом (лог шагов приложен к `progress.md`).
- [ ] `mb-cost-report.py`: инструкционная нагрузка `/mb work` (mb.md + work.md) ≤ 32 KB.

**Code rules:** машина состояний детерминирована и тестируется на фикстурах; fail-closed на неконсистентном state (не чинить молча).

---

<!-- mb-stage:4 -->
### Stage 4: Переустановка уважает выключенные хуки

**Role:** developer

**What to do:**
- `settings/merge-hooks.py`: перед добавлением свежих записей читать `~/.claude/memory-bank/hooks.disabled` (путь через `MB_HOOKS_DISABLED_FILE`; одна строка = basename скрипта или точная подстрока команды; `#`-комментарии); совпавшие записи не добавляются; в stdout — `skipped disabled hooks: <list>`.
- `install.sh`: пробрасывает файл, печатает итог; `uninstall.sh` файл не трогает.
- `docs/hooks.md`, `references/hooks.md`, `docs/environment-variables.md`: раздел «Отключение хука навсегда» + связь с env-kill-switch'ами (`MB_FLOW_CLOSURE=off` и т.п.).

**Testing (TDD):**
- расширить `tests/pytest/test_merge_hooks.py`:
  - `test_disabled_basename_skipped_others_merged`
  - `test_disabled_substring_matches_full_command`
  - `test_missing_disabled_file_is_noop`
  - `test_comment_and_blank_lines_ignored`
  - `test_reinstall_idempotent_with_disabled_entry` (два прогона → одинаковый settings.json)
- e2e: существующий `test_cli_install_uninstall_smoke_*` с `HOME`-песочницей + файл `hooks.disabled` → хук отсутствует после install.

**DoD:**
- [ ] 5 pytest + e2e зелёные; `ruff` чист; `bash install.sh` в песочнице с `hooks.disabled=mb-flow-closure-guard.sh` не регистрирует этот хук (assert по `settings.json`).
- [ ] Доки обновлены (pytest-doc в `test_hooks_registration.py` или новом тесте).
- [ ] CHANGELOG `[Unreleased]` → `### Added`.

**Code rules:** protected path (`install.sh`) — только тестируемая идемпотентная правка; fail-open (битый файл → предупреждение, установка продолжается).

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Перенос текста из `mb.md` ломает doc-контракты | H | Инвентаризация до переноса, Strangler Fig по одной подкоманде, pytest-параметризация «фраза → файл» |
| `mb-work-next.sh` расходится с реальным циклом | M | Фикстуры состояний из реальных прогонов; DoD «последовательность совпадает» на живом item; fail-closed на неконсистентности |
| Обрезанный блок Agreements скроет действующее решение | L | Показываем новейшие; футер с числом и командой; `0` = без лимита; полный SSOT в `agreements.md` |
| `hooks.disabled` даст пользователю отключить security-guard | L | Документируем как осознанный opt-out; `block-dangerous.sh` в списке «не рекомендуется» в доке, но не запрещаем — правило «пользователь в контроле» |

## Gate (plan success criterion)

`commands/mb.md` ≤ 12 KB и `commands/work.md` ≤ 20 KB при зелёных doc-контрактах; блок Agreements в `CLAUDE.md` ≤ 6 KB; один реальный item пройден через `/mb work` с `mb-work-next.sh` на каждом шаге; `install.sh` в песочнице с `hooks.disabled` не возвращает выключенный хук; полная батарея зелёная; `/mb verify` PASS. Phase-гейт (все три спринта): `mb-cost-report.py` на недельном окне после раскатки показывает implementer ≤ 120 ходов avg, ≤ 3 полных прогона тестов на item и старт сессии ≤ 12k токенов — против baseline `reports/2026-09-05_cost-baseline.json`.
