---
type: fix
topic: agents-md-diet
status: done
depends_on: ["2026-10-06_feature_key-rules-onboarding.md"]
parallel_safe: false
linked_specs: []
created: 2026-10-06
---
# Plan: fix — agents-md-diet · always-loaded инструкции хостов без копии RULES.md

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem (исследование 2026-10-06).** `adapters/_lib_agents_md.sh::_agents_md_section` (стр. 200–207) вставляет
**полный** `rules/RULES.md` (47 КБ, 86 % блока) в общий проектный `AGENTS.md` (Codex/Pi/OpenCode); Cursor `.mdc`,
Windsurf, Cline, Kilo — тоже полная копия (~48 КБ). Глобальные блоки (`~/.codex|~/.pi/agent|~/.config/opencode|~/.cursor`
AGENTS.md, 13–15 КБ) повторяют CLAUDE-GLOBAL и пересказывают его третий раз в шапке Codex.
- Codex: `project_doc_max_bytes` = 32 768 на все проектные доки (openai/codex `codex-rs/config/defaults.toml:8`,
  `agents_md.rs` truncate) → в этом репо Codex теряет ~40 % правил и весь блок соглашений.
- Копия устаревает: AGENTS.md репо отстаёт от RULES.md на 102 строки (противоречит канону).
- Cursor грузит и `.mdc` (alwaysApply), и корневой AGENTS.md — правила дважды.
- Скил уже симлинкнут во все хосты (`install.sh:958–963`) — RULES.md и references читаются по требованию.
- Жёсткие правила обязаны оставаться в always-loaded файле: скил выбирает модель и может не загрузить
  (Pi docs). Решение владельца — AGR-063.

**Expected result.** (Бюджет уточнён 2026-10-07: Key rules ≤ 3 072 байт — тест каталога; MB-блок ≤ 1 536 байт; проектный блок целиком ≤ 4 608 байт; `.mdc`/windsurf/cline/kilo ≤ 4 608; лимит не должен зависеть от длины пути установки.) Проектный блок `AGENTS.md` ≤ 4,5 КБ, глобальные ≤ 8 КБ; первой секцией — `## Key rules`
(рендер из key-rules-onboarding Stage 3), затем короткий MB-блок со ссылками «читай `<skill>/rules/RULES.md` § X,
когда Y». Копии RULES.md нет нигде из always-loaded. Итог проектного AGENTS.md с соглашениями и языком ≤ 12 КБ.

**Related files:** `adapters/_lib_agents_md.sh`, `install.sh` (codex/opencode global sections), `adapters/_lib_pi_global.sh`,
`adapters/cursor.sh`, `adapters/windsurf.sh`, `adapters/cline.sh`, `adapters/kilo.sh`, `adapters/codex.sh` (65536 override),
тесты `tests/bats/test_agents_md_lib.bats`, `test_codex_adapter.bats`, `test_opencode_adapter.bats`, `test_pi_adapter.bats`,
`test_cursor*.bats`, `test_extensions_offer.bats`, `tests/pytest/test_global_prompt_guard.py`, `test_runtime_contract.py`.
Заменяет Sprint 2 Stage 4 плана anthropic-skill-guide-compliance (там — пометка «перенесено»).

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Тест-гейт размеров always-loaded файлов

**What to do / Testing (TDD):**
- bats `test_always_loaded_budget.bats`: рендер проектного блока (pure-функция `_agents_md_section`) ≤ 4 096 байт и не
  содержит заголовков RULES.md (`## Source of Truth`, `### Contract-First Development`…); блок Key rules — первая секция;
  каждый глобальный блок (codex/pi/opencode/cursor) ≤ 8 192 байт; `.mdc`/windsurf/cline/kilo ≤ 4 096 байт; ссылки на
  `rules/RULES.md` указывают на существующий путь установленного скила; проектные блоки ссылаются на локальный
  `RULES.md` проекта, глобальные — на глобальный (AGR-066).
- Красный на текущем коде (52 КБ / 15 КБ / 48 КБ).

**DoD:**
- [x] гейт красный до, с цифрами в отчёте `reports/2026-10-06_agents-md-baseline.md`

---

<!-- mb-stage:2 -->
### Stage 2: Общий проектный блок `_lib_agents_md.sh`

**What to do:**
- Убрать вставку RULES.md; оставить: Key rules (из key-rules-onboarding), статус-строку, где банк + «сначала `/mb context`»,
  firewall/drive-loop/граф по строке (AGR-024 — контракт drive-loop остаётся), nudge расширений (AGR-013/014), список
  «читай RULES.md § X когда Y» (TDD, Architecture, Tests, Session Pipeline, `/mb work`) + явная ссылка на локальный
  RULES.md проекта (`<repo>/RULES.md` или `<bank>/RULES.md`), который пользователь пишет вручную (AGR-066).
- Порядок: language-блок → Key rules → MB-блок → соглашения (в конце).

**Testing:** гейт Stage 1 для проектного блока зелёный; существующие `test_agents_md_lib.bats` (маркеры, refcount,
uninstall, пути) зелёные; утверждения про firewall/drive-loop/nudge сохранены.

**DoD:**
- [x] проектный блок ≤ 4608 Б (бюджет поднят владельцем 2026-10-07, было 4 КБ); все bats адаптеров codex/pi/opencode зелёные

---

<!-- mb-stage:3 -->
### Stage 3: Глобальные блоки Codex / Pi / OpenCode / Cursor

**What to do:**
- `codex_agents_section`, `pi_global_agents_section`, `opencode_agents_section`, cursor global: Key rules (user scope) +
  короткая шапка хоста (что специфично: Codex — нет нативных slash; Pi — `/mb work` gate) + указатели, включая ссылку на
  глобальный RULES.md (AGR-066). Убрать
  пересказ «Engineering baseline» и повторы CLAUDE-GLOBAL.
- Маркер OpenCode global переименовать в `memory-bank-opencode` с миграцией старого маркера (upsert находит оба).

**Testing:** гейт Stage 1 для глобальных блоков; `test_global_prompt_guard.py`, `test_runtime_contract.py` — сохранить
смысловые утверждения (статус-строка, RULES.md путь, ABSENT, язык), обновить только те, что требовали пересказ.

**DoD:**
- [x] каждый глобальный ≤ 8 КБ; тесты зелёные; апгрейд со старым маркером не дублирует блок (bats)
  (2026-10-07: Codex 9831→7544 Б, Pi 9496→~7950 Б, OpenCode 7443→7388 Б, Cursor 7909 Б без изменений —
  шапка Cursor живёт в `adapters/cursor.sh`, её чистка отдельно; `test_install_global_blocks.bats`.)

---

<!-- mb-stage:4 -->
### Stage 4: Cursor / Windsurf / Cline / Kilo проектные файлы

**What to do:**
- `.cursor/rules/memory-bank.mdc` (alwaysApply), windsurf/cline/kilo rule-файлы: тот же компактный блок ≤ 4608 Б с
  абсолютным путём к `rules/RULES.md` (у Windsurf/Cline/Kilo нет нативных скилов — файл читается по пути).
- Cursor: при наличии корневого AGENTS.md с нашим блоком `.mdc` не дублирует Key rules (только MB-указатели).

**Testing:** bats адаптеров + гейт Stage 1.

**DoD:**
- [x] размеры в лимите; адаптерные bats зелёные

---

<!-- mb-stage:5 -->
### Stage 5: Переустановка и замер

**What to do:**
- `install.sh` в temp HOME для всех клиентов дважды (идемпотентность); проектный адаптер codex/pi/opencode/cursor в temp-проекте.
- Таблица до/после по каждому файлу в отчёте; проверка, что Codex-лимит соблюдён без override 65536 (override оставить —
  не мешает, удаление — отдельное решение).
- Переустановить проектный блок в этом репо (`adapters/opencode.sh install`) — AGENTS.md ≤ 12 КБ.

**DoD:**
- [x] отчёт с цифрами; повторная установка байт-в-байт (2026-10-07: отчёт § Stage 5; install.sh ×2 в temp HOME —
  394 файла совпали, различие только `installed_at`/`backups` в манифестах; адаптеры ×2 — 87 файлов; Codex-проектный
  4 297 Б и AGENTS.md репо 7 987 Б ≤ 32 768 без override)
- [x] полный pytest/bats без новых красных против baseline (2026-10-07: pytest 3864 passed, 2 failed — оба до этой работы: test_pi_agents_dispatch.bats:239-240, hooks/lib/venv-requirements.sh не в git; bats 3662, 0 not ok)

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Агент на Codex/Pi без загруженного скила не прочтёт детальные правила | M | Key rules (жёсткие) остаются в always-loaded; «читай X когда Y» с абсолютным путём |
| Тесты, требующие текст RULES в блоке | L | аудит: ни один не требует; смысловые утверждения о шапке сохраняются |
| Пользовательский текст в AGENTS.md | L | managed-маркеры + refcount уже есть; чужое не трогается (bats) |

## Gate (plan success criterion)

Ни в одном always-loaded файле нет копии RULES.md; проектный блок ≤ 4608 Б, глобальные ≤ 8 КБ, Key rules — первая
секция; AGENTS.md этого репо ≤ 12 КБ и целиком помещается в лимит Codex 32 КиБ; все тесты зелёные.
