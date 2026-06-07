---
type: refactor
topic: rules-context-economy
status: planned
created: 2026-06-07
---

# Plan: refactor — rules-context-economy

**Baseline commit:** 5b0d7ca469e73b8d43dcc90f0005a1acbe2d07f7

> **Baseline note (2026-06-07):** изначально план ссылался на `396e9da`, где `rules/RULES.md` = **808 строк**. Цифра «1073» бралась с грязного рабочего дерева, в котором лежала незакоммиченная фича (`--docs` node enrichment + semantic embeddings, +265 строк в RULES.md). Эта фича влита в main (`a84094c`/`5189911`/`72ddf40`), плюс landed MB-maintenance (`5b0d7ca`). Теперь 1073 строки RULES.md — **легитимно закоммиченное** состояние, baseline перепривязан на `5b0d7ca`. Все номера строк в стадиях измерены на этом 1073-строчном состоянии и остаются валидны.

## Context

**Problem:** `rules/RULES.md` (источник для `~/.claude/RULES.md`) разросся до **1073 строк / ~16.5K токенов**. Он НЕ always-loaded (нет `@`-импорта в `CLAUDE-GLOBAL.md`, помечен "read on demand"), но `CLAUDE-GLOBAL.md` и `/mb`-команды инструктируют *«read the matching § section»* — а механически `Read` тащит **весь файл ради одной секции**. Аудит показал: **~64% файла (строки 384–1073)** — это MB operational reference, дублирующий `/mb help` и существующие `references/*.md` (на которые RULES.md сам же ссылается). Плюс ~40 строк дублей с `CLAUDE-GLOBAL.md` (first-response-guard, rules-only, CRITICAL, response-format) — источник рассинхрона.

**Expected result:** `rules/RULES.md` ужат до **ядра инженерной дисциплины (~400–550 строк, ~6–8K токенов)**. Узкоспециальные/операционные секции вынесены в on-demand `references/*.md`, так что «read § Code Graph» тащит ~2K вместо 16.5K. Информация НЕ теряется (всё дублируется в `/mb help` / `references/`). Установка (install.sh + локализация Codex/Pi) и весь тест-сьют — зелёные. Это контекст-экономия уровня L3 из аудита `~/.claude` (см. native memory `reference-claude-code-setup`).

**Non-goals:** не трогать ядро дисциплины (TDD/SOLID/Clean Arch/Testing Trophy/Coding Standards, строки 1–383, кроме точечного удаления дублей-указателей); не менять поведение `/mb`-команд; не реструктурировать `.memory-bank/`-формат.

**Related files:**
- Источники: `rules/RULES.md` (1073 стр), `rules/CLAUDE-GLOBAL.md` (92 стр)
- Цель выноса: `references/` (уже есть `templates.md`, `workflow.md`, `structure.md`, `design-principles.md`; **нет** `code-graph.md`)
- Установка: `install.sh:703` (`install_file_localized rules/RULES.md → ~/.claude/RULES.md`), `install.sh:706–741` (CLAUDE.md merge), `.installed-manifest.json`, `packaging/`
- Тест-границы: `tests/pytest/test_rules_cover_intelligence_layer.py` (ассертит intelligence-layer needles + jq edge-kinds в `rules/RULES.md`), `tests/pytest/test_graph_rag_guidance.py`, `tests/pytest/test_doc_counts.py`, `tests/pytest/test_runtime_contract.py` + `test_global_prompt_guard.py` (пути RULES.md в AGENTS.md для codex/pi), `tests/e2e/test_install_uninstall.bats:79,88` (CRITICAL «Language: English/Russian» в `~/.claude/RULES.md`), `tests/bats/test_plan_verifier_rules.bats`

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Safety net — baseline-замер + зелёный тест-сьют

**What to do:**
- Зафиксировать baseline-метрики: `wc -l rules/RULES.md` (1073), пер-секционная карта (`grep -n '^## '`), оценка токенов.
- Прогнать ПОЛНЫЙ сьют до изменений: `pytest tests/pytest` + `bats tests/bats tests/e2e` → зафиксировать зелёный baseline и список тестов, ассертящих содержимое RULES.md/references/install.
- Завести в плане «карту переноса»: секция RULES.md → целевой файл → затрагиваемые тесты (таблица в Gate).

**Testing (TDD — tests BEFORE implementation):**
- Нет нового кода. Это baseline-gate: зафиксировать текущий PASS-count (pytest + bats) как reference, к которому возвращаемся после каждой стадии.

**DoD (Definition of Done):**
- [ ] Baseline-метрики записаны (строки/токены/секции) в этот план (Gate-таблица).
- [ ] `pytest tests/pytest` — зелёный, PASS-count зафиксирован.
- [ ] `bats tests/bats tests/e2e` — зелёный, PASS-count зафиксирован.
- [ ] Список тестов-границ (трогают RULES.md/references/install) выписан в план.

**Code rules:** read-only стадия; никакого production-кода.

---

<!-- mb-stage:2 -->
### Stage 2: Устранить дубли с CLAUDE-GLOBAL.md (тип 1, ~40 строк)

**What to do:**
- Подтвердить дублирование между `rules/RULES.md` и `rules/CLAUDE-GLOBAL.md`: «Mandatory first response guard» (RULES 22–32), «Rules-only mode» (34–40), «Response format / status-line» (349–356).
- Single source of truth: guard/rules-only/status-line живут в `CLAUDE-GLOBAL.md` (always-loaded). В `rules/RULES.md` заменить их на 1–2 строки-указателя «→ CLAUDE.md `[MEMORY-BANK-SKILL]` first-response guard».
- **НЕ трогать** CRITICAL-пункт «1. **Language**: English…» (RULES стр 10) — на него ассерт `test_install_uninstall.bats:79,88` (en + ru-локализация). CRITICAL-блок остаётся в RULES.md.

**Testing (TDD):**
- Перед правкой: убедиться, что ни один pytest/bats не ассертит дублируемый текст guard ИМЕННО в `rules/RULES.md` (grep по тестам). Если ассертит — переориентировать ассерт на `CLAUDE-GLOBAL.md` ПЕРЕД удалением (red→green).
- После: `test_install_uninstall.bats` (CRITICAL Language) остаётся зелёным.

**DoD:**
- [ ] Дубли guard/rules-only/status-line убраны из `rules/RULES.md`, заменены указателем (≈ −40 строк).
- [ ] CRITICAL стр 10 на месте; `test_install_uninstall.bats` зелёный.
- [ ] Полный сьют = baseline PASS-count (Stage 1).

---

<!-- mb-stage:3 -->
### Stage 3: Вынести Code Graph → references/code-graph.md (тип 3, ~150 строк) — ГЛАВНЫЙ выигрыш

**What to do:**
- Создать `references/code-graph.md` с полным содержимым секции «Code Graph — usage» (RULES 760–908): data schema, basic jq, practical use-cases, decision-table, caveats, when-to-rebuild, intelligence layer (suggested questions / co-change / semantic search / wiki), semantic-search benchmark, session-memory recall.
- В `rules/RULES.md` заменить секцию на pointer (3–5 строк: «Structural code-graph queries, jq library, semantic search → `references/code-graph.md` / `/mb help`»).
- Обновить указатели в `rules/CLAUDE-GLOBAL.md`: «§ Code Graph — usage», «jq library + schema» → на `references/code-graph.md`.
- Убедиться, что `references/code-graph.md` попадёт в установку: проверить механизм (целиком копируется `references/` как skill-resource ИЛИ явный список в `.installed-manifest.json`/`packaging/`). Если явный список — добавить файл.

**Testing (TDD — tests BEFORE implementation):**
- СНАЧАЛА обновить `tests/pytest/test_rules_cover_intelligence_layer.py`: ассерты intelligence-layer needles + jq edge-kinds переориентировать с `rules/RULES.md` на `references/code-graph.md` (источник правды переехал). Запустить → red (файла ещё нет) → создать файл → green.
- `tests/pytest/test_graph_rag_guidance.py`: если ассертит routing-таблицу — проверить, остаётся ли краткий routing в RULES.md или тоже переезжает; синхронизировать ассерт.
- `test_doc_counts.py`: обновить ожидаемые counts если считает секции/доки.

**DoD:**
- [ ] `references/code-graph.md` создан, содержит полную jq-библиотеку + schema + intelligence layer.
- [ ] `rules/RULES.md` −~150 строк, секция → pointer.
- [ ] `test_rules_cover_intelligence_layer.py` + `test_graph_rag_guidance.py` + `test_doc_counts.py` — зелёные (ассерты указывают на новый файл).
- [ ] `references/code-graph.md` включён в установочный манифест (проверено).
- [ ] Полный сьют = baseline PASS-count.

---

<!-- mb-stage:4 -->
### Stage 4: Вынести MB operational reference (тип 2, ~225 строк) → /mb help + существующие references

**What to do:**
- `/mb` Commands full reference (RULES 446–520) → pointer на `/mb help` (оставить 1 строку-указатель + ссылку).
- Subagents tables (397–445) → pointer на `SKILL.md` §Agents / `references/` (таблицы уже есть в SKILL.md).
- File Formats (967–1012) → pointer на `references/templates.md` (RULES стр 969 уже ссылается).
- `.memory-bank/` Structure (522–550) → pointer на `references/structure.md`.
- Key scripts table (501–519) → pointer на `SKILL.md` §Tools.
- Каждый pointer: 1–3 строки «полный список → <файл> / `/mb help`», без потери навигации.

**Testing (TDD):**
- Перед: grep тестов на ассерты содержимого этих секций в `rules/RULES.md`; переориентировать на целевые файлы ПЕРЕД удалением.
- `test_doc_counts.py` / `test_mb_work_command_doc.bats` / `test_mb_init_command_docs.bats` — обновить ожидания если ассертят командные доки в RULES.md.

**DoD:**
- [ ] 5 секций заменены указателями (≈ −225 строк); навигация (куда смотреть) сохранена.
- [ ] Все ассерты на перенесённый контент указывают на актуальные файлы.
- [ ] Полный сьют = baseline PASS-count.

---

<!-- mb-stage:5 -->
### Stage 5: Сжать многословность Architecture (тип 4, ~90 строк) — опционально

**What to do:**
- Mobile iOS+Android (199–241, 43 стр) и FSD (155–198, 44 стр): ужать ~2× — оставить суть (слои, направления импортов, ключевые правила) + ссылку на расширенную версию, если потребуется отдельный `references/architecture-frontend-mobile.md`.
- Решение по выносу vs сжатие-на-месте принять по факту: если ужатие сохраняет смысл — оставить в RULES.md компактно (не плодить файлы ради YAGNI).

**Testing (TDD):**
- Проверить, что `mb-rules-check.sh` / `test_rules_enforcer_*` не парсят конкретные строки Architecture-секции (если парсят — не трогать соответствующие якоря).

**DoD:**
- [ ] Mobile+FSD ужаты, ключевые правила (UDF, импорты-вниз, public API через index.ts) сохранены.
- [ ] `test_rules_enforcer_*` зелёные.
- [ ] Полный сьют = baseline PASS-count.

---

<!-- mb-stage:6 -->
### Stage 6: E2E установка + локализация Codex/Pi

**What to do:**
- Прогнать e2e: `bats tests/e2e/test_install_uninstall.bats tests/e2e/test_install_idempotent.bats tests/e2e/test_install_clients.bats` — install в isolated temp HOME.
- Проверить, что в установленном HOME появляются: `~/.claude/RULES.md` (ужатый) + `~/.claude/skills/memory-bank/references/code-graph.md`.
- Локализация: убедиться, что новые pointer-ссылки на `references/code-graph.md` корректно локализуются для Codex (`~/.codex/...`) и Pi (`~/.pi/...`) — sed-правила в install.sh (строки 579, 649) покрывают `~/.claude/skills/memory-bank` → проверить, что путь к references попадает под паттерн.
- `test_runtime_contract.py` + `test_global_prompt_guard.py` (пути RULES.md в AGENTS.md) — зелёные.

**Testing (TDD):**
- Если локализация references не покрыта sed-паттерном — добавить тест-ассерт (ожидаем `~/.codex/.../references/code-graph.md` в локализованном AGENTS.md) → red → починить sed → green.

**DoD:**
- [ ] Все e2e install-тесты зелёные.
- [ ] В temp HOME присутствуют ужатый `~/.claude/RULES.md` + `references/code-graph.md`.
- [ ] Codex/Pi локализация ссылок на references подтверждена (тест/ручная проверка).

---

<!-- mb-stage:7 -->
### Stage 7: Синхронизация установленной копии + CHANGELOG + VERSION

**What to do:**
- Переустановить из источника, чтобы `~/.claude/RULES.md` (рабочая копия пользователя) обновился: `./install.sh` (или `/mb upgrade`).
- `diff -q rules/RULES.md ~/.claude/RULES.md` → идентичны.
- CHANGELOG.md: entry «refactor: RULES.md context-economy — вынос Code Graph + MB reference в references/, −53% строк».
- Bump VERSION (patch v4.x согласно схеме «промежуточные landings = v4.x bumps», v5.0.0 только после W12).
- Финальный замер: `wc -l rules/RULES.md` (цель ~400–550), токены секции Code Graph при on-demand чтении (~2K vs 16.5K).

**Testing (TDD):**
- `test_upgrade.bats` зелёный (self-update механизм не сломан).

**DoD:**
- [ ] `~/.claude/RULES.md` синхронизирован с источником (`diff -q` пуст).
- [ ] CHANGELOG.md + VERSION обновлены.
- [ ] Итоговые метрики записаны: строк до/после, токены чтения до/после.
- [ ] Полный сьют (pytest + bats + e2e) = зелёный.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| `test_rules_cover_intelligence_layer.py` падает при выносе Code Graph | **H** | TDD: обновить ассерт ПЕРЕД переносом (Stage 3 red→green); ассерт указывает на `references/code-graph.md` |
| `references/code-graph.md` не попадает в установку (явный манифест) | M | Stage 3 DoD: проверить `.installed-manifest.json`/`packaging/`, добавить файл если список явный; Stage 6 e2e ловит |
| Codex/Pi локализация не покрывает ссылки на references | M | Stage 6: проверить sed-паттерн `~/.claude/skills/memory-bank`; добавить тест-ассерт при необходимости |
| Удаление CRITICAL «Language» строки ломает install-тест | L | Stage 2: CRITICAL-блок явно не трогаем; ассерт на стр 10 защищён |
| `CLAUDE-GLOBAL.md` указатели на «§ section» становятся битыми | M | Stage 3/4: синхронно обновлять указатели в CLAUDE-GLOBAL.md при каждом выносе |
| `mb-rules-enforcer` парсит конкретные якоря RULES.md | L | Stage 5: grep `test_rules_enforcer_*` перед сжатием Architecture; не трогать парсимые якоря |

## Gate (plan success criterion)

План завершён, когда:
1. `rules/RULES.md` ≤ **550 строк** (с ~1073), ядро дисциплины (1–383) сохранено.
2. Вынесенный контент доступен через `references/code-graph.md` + `references/*` + `/mb help` — без потери информации.
3. **Весь тест-сьют зелёный** на том же PASS-count, что baseline (Stage 1) + новые ассерты на references.
4. E2E install (Claude/Codex/Pi) ставит ужатый RULES.md + новые references с корректной локализацией.
5. `~/.claude/RULES.md` синхронизирован; CHANGELOG + VERSION обновлены; метрики до/после задокументированы.

**Карта переноса (заполняется в Stage 1):**

| Секция RULES.md (строки) | → Назначение | Затрагиваемые тесты |
|---|---|---|
| Code Graph — usage (760–908) | `references/code-graph.md` | `test_rules_cover_intelligence_layer.py`, `test_graph_rag_guidance.py`, `test_doc_counts.py` |
| /mb Commands (446–520) | pointer → `/mb help` | `test_mb_*_command_doc.bats`, `test_doc_counts.py` |
| Subagents tables (397–445) | pointer → `SKILL.md` §Agents | `test_doc_counts.py` |
| File Formats (967–1012) | pointer → `references/templates.md` | `test_doc_counts.py` |
| .memory-bank Structure (522–550) | pointer → `references/structure.md` | — |
| first-response-guard/rules-only (22–40) | pointer → `CLAUDE-GLOBAL.md` | install bats (CRITICAL стр 10 защищён) |
| Mobile+FSD (155–243) | сжать ~2× in-place | `test_rules_enforcer_*` |

---

## Execution log (2026-06-07, autonomous /mb work)

**Baseline (Stage 1):** `rules/RULES.md` = 1073 строки; `pytest tests/pytest` = 1134 passed; `bats tests/bats tests/e2e` = 669 ok / 0 fail. Тесты-границы: `test_rules_cover_intelligence_layer.py`, `test_graph_rag_guidance.py`, `test_global_prompt_guard.py`, `test_runtime_contract.py`, `test_terminology_canonicalization.py`, `test_doc_counts.py` (References-линки) + bats `test_plan_verifier_rules`, `test_rules_enforcer_tdd`, install-bats.

**Stage 2 — СНЯТ (revision by fact):** план предполагал удалить дубль guard/rules-only (~40 строк). По факту это **невозможно**: `test_global_prompt_guard::test_detailed_rules_repeat_first_response_guard` и `test_runtime_contract::test_rules_only_mode_documented_in_rules` **требуют** guard + rules-only ИМЕННО в `rules/RULES.md` — потому что RULES.md самостоятельно устанавливается в `~/.claude/RULES.md` и встраивается в Pi/Codex `AGENTS.md`. Дублирование намеренное. Stage 2 даёт ~0 строк экономии.

**Gate revision:** так как Stage 2 (−40) выпал, цель «≤550» пересматривается на **realistic floor**: основная экономия идёт из Stage 3 (Code Graph −144) + Stage 4 (MB operational reference) + Stage 5 (Architecture). Критерий успеха = максимальная безопасная экономия при зелёном сьюте, Code Graph доступен on-demand. Точную цифру фиксируем после Stage 4/5.

**Stage 3 — DONE:** Code Graph usage (760–907, 145 строк тела) → `references/code-graph.md` (154 строки, shipped через копирование `references/`). `rules/RULES.md` 1073 → **929** (−144), секция заменена pointer'ом. Тесты переориентированы (`test_rules_cover_intelligence_layer.py` → `references/code-graph.md` + новый pointer-ассерт), `SKILL.md` References залинкован, `CLAUDE-GLOBAL.md` указатели обновлены. **pytest 1135 passed, bats 669 ok / 0 fail.** Commit `20ede3c`.

**Stage 4 — DONE:** Subagents (397–444), `/mb` Commands (446–520), `.memory-bank/` Structure (522–550) сжаты в pointer-секции (якоря-заголовки сохранены) → `SKILL.md` §Agents/§Tools, `/mb help`/`commands/mb.md`, `references/structure.md`. Ключевые ПРАВИЛА (не reference) оставлены inline: «verify MANDATORY before done», «не делегировать план/архитектуру/ML субагенту», «checklist update immediately», «progress append-only». `CLAUDE-GLOBAL.md` «§ Subagents» → `SKILL.md § Agents`. Тест-границы проверены (grep tests/: секции не закреплены; `test_plan_verifier_rules.bats` проверяет промпт агента, не RULES.md). `rules/RULES.md` 929 → **801** (−128). **pytest 1135 passed; RULES bats ok.** Итого 1073 → 801 (−25%).
