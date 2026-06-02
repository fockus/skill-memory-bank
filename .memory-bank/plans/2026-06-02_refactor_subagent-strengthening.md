---
type: refactor
topic: subagent-strengthening
status: queued
depends_on: []
parallel_safe: false
linked_specs: []
sprint: 1
phase_of: agent-quality
created: 2026-06-02
baseline_commit: 7d58c64da659999442a4cc993bdf02fb18490b29
---

# Plan: refactor — Subagent strengthening (engineering-core composition)

**Baseline commit:** 7d58c64da659999442a4cc993bdf02fb18490b29

## Context

Аудит 16 MB-субагентов (методология `customaize-agent-agent-evaluation`, эталоны
`~/.claude/agents/{developer,billing-ledger-reviewer,clean-arch-boundary-auditor,critic}.md`)
выявил два класса:

- 🟢 **Контролёры** (`mb-reviewer`, `plan-verifier`, `mb-rules-enforcer`, `mb-test-runner`) — сильные (≈4.3/5): structured output, severity tree, guardrails, baseline-aware.
- 🔴 **Разработчики** (`mb-developer` + 8 специализированных) — слабее эталона (≈3.0/5).

**Корневой дефект:** дисциплинарный каркас (anti-rationalization table, evidence-before-claims
Iron Law, escalation rules, status-system, production-wiring awareness), который делает эталонный
`developer.md` (176 стр) сильным, у `mb-developer` (53 стр) отсутствует, а у 8 специализированных
агентов присутствует только как **нерабочая текстовая отсылка** «Inherit all `mb-developer`
principles» — субагент физически не видит текст базового файла, потому что `commands/work.md:160`
инлайнит в промпт **только** `<contents of agents/<agent>.md>`.

**Согласованные решения (с пользователем):**
- Scope: 9 dev-агентов (полный каркас) + точечно `mb-reviewer` и `plan-verifier`.
- Механизм: **композиция** — общий каркас в отдельном partial-файле, оркестратор инлайнит
  `core + дельта специалиста`. DRY, один источник правды.
- Глубина: полный каркас как у эталона.

**Целевой результат:** dev-агенты получают полный дисциплинарный каркас через композицию;
специализированные агенты остаются тонкими доменными дельтами; контролёры получают
adversarial-default и «invariants proven». Поведенческая проверка before/after подтверждает рост.

## Gate (overall success criteria)

1. `agents/mb-engineering-core.md` существует и содержит 5 каркасных паттернов.
2. `commands/work.md` implement-step инлайнит `core + role-delta`; reviewer-step не регрессировал.
3. Все 8 специализированных агентов: убрана нерабочая фраза «Inherit … principles», добавлена
   корректная ссылка на core, доменная дельта сохранена, output-контракт усилен.
4. `mb-reviewer` и `plan-verifier` получили adversarial-default + «invariants proven» секцию.
5. Партиал доставляется в установленную среду и НЕ засоряет реестр subagent types.
6. Поведенческий before/after тест (≥2 представительных агента) показывает улучшение по rubric
   (instruction-following / discipline / verification-rigor) при pairwise-сравнении со swap позиций.
7. `bash scripts/*test*` / существующие тесты репозитория зелёные; SKILL.md и CHANGELOG обновлены.

---

## Stage 0 — RED: зафиксировать baseline-поведение слабых агентов

**Что:** до правок прогнать 2 представительных слабых агента (`mb-developer`, `mb-backend`)
на контрольном тест-кейсе через субагента и зафиксировать провалы каркаса.

**TDD (prompt-testing, методология evaluation):**
- Тест-кейс: «реализуй stage X, после чего отчитайся» с намеренной ловушкой
  (нет запуска тестов / есть соблазн заявить "tests pass" без вывода / код не подключён в entry point).
- Прогнать текущий `mb-backend.md` как промпт subagent'а; зафиксировать: заявил ли успех без
  доказательств, эскалировал ли при 3 неудачах, проверил ли production wiring.

**DoD (SMART):**
- [ ] Создан `.memory-bank/reports/2026-06-02_subagent-baseline.md` с outputs baseline-прогонов.
- [ ] Для каждого из 2 агентов зафиксированы ≥3 конкретных провала каркаса (с цитатами).
- [ ] Зафиксированы rubric-баллы baseline (1–5 по: instruction-following, discipline, verification).

**Edge cases:** агент случайно повёл себя дисциплинированно → прогнать 2-й вариант ловушки.

---

## Stage 1 — Создать `agents/mb-engineering-core.md` (общий каркас)

**Что:** role-neutral дисциплинарный + инженерный каркас, переносимый из `mb-developer` + взятый
из эталонного `developer.md`. Содержит:
1. TDD (Red→Green→Refactor), Contract-First (с contract-drift примером), Clean Architecture
   (таблица направлений слоёв), SOLID-пороги, DRY/KISS/YAGNI, no-placeholders.
2. **Production Wiring Awareness** (код подключён в DI/entry point, не только проходит тесты).
3. **Evidence-before-claims Iron Law** («никогда не говори "тесты проходят" / "lint clean" без
   вывода команды в этом же сообщении»).
4. **Escalation rules** (fix attempt 1→2→3=STOP, анти-thrashing).
5. **Status system** (DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT, статус без доказательств = невалидный).
6. **Таблица рационализаций** (anti-rationalization).
7. Scenario test-plan hook (перенос из текущего mb-developer п.9).

**Стиль:** English, agent-agnostic (как остальные mb-агенты). Файл-партиал, помечен в заголовке
как «prepended by /mb work — not a standalone agent».

**DoD (SMART):**
- [ ] Файл создан, содержит все 7 секций; длина 90–160 строк.
- [ ] НЕ содержит role-специфичного текста (никаких "ты backend/generic").
- [ ] Frontmatter без `name:` ИЛИ с маркером партиала (Stage 5 решает доставку/реестр).

---

## Stage 2 — Рефактор `mb-developer.md` → тонкая generic-дельта

**Что:** убрать из `mb-developer` всё, что переехало в core; оставить только идентичность
«generic implementer / fallback when no specialist matches» + ссылку «engineering core applies»
+ его специфичный self-review/output (если отличается от core).

**DoD (SMART):**
- [ ] `mb-developer.md` ≤ 25 строк тела, без дублирования секций core.
- [ ] Содержит явную ссылку: при standalone-вызове читать `agents/mb-engineering-core.md`.
- [ ] Output-контракт сохранён (DoD status + files + tests + deviations).

**Edge cases:** `mb-developer` может вызываться и как fallback в work.md (через core+delta), и
standalone (subagent_type) — обе ветки должны давать дисциплину (см. Stage 5 guard-строку).

---

## Stage 3 — Рефактор 8 специализированных агентов

**Файлы:** `mb-backend`, `mb-frontend`, `mb-ios`, `mb-android`, `mb-devops`, `mb-qa`,
`mb-analyst`, `mb-architect`.

**Что:**
- Заменить нерабочую фразу «Inherit all `mb-developer` principles (…)» на корректную:
  «The engineering core (`agents/mb-engineering-core.md`) is prepended when dispatched via
  `/mb work`; if invoked standalone, read it first.»
- Доменные принципы — **сохранить** (они качественные).
- Усилить тонкий output-контракт «Same shape as mb-developer» → явный список полей
  (DoD status + files + tests + deviations + STATUS из core).

**DoD (SMART):**
- [ ] Во всех 8 файлах нет строки «Inherit all `mb-developer`» (grep = 0).
- [ ] Во всех 8 есть ссылка на `mb-engineering-core.md`.
- [ ] Доменные секции не урезаны (диф не удаляет доменные принципы).
- [ ] Output-секция явная (не «same shape»).

---

## Stage 4 — Композиция в `commands/work.md`

**Что:** implement-step (строки ~152–162) — инлайнить core ПЕРЕД дельтой роли:
```
prompt="<contents of agents/mb-engineering-core.md>\n\n---\n\n<contents of agents/<agent>.md>\n\nPlan: …\nStage: …\n\n<item body>\n\nLinked context: …"
```
- Reviewer-step (3c) и verify-step не меняются (контролёры самодостаточны).
- Зафиксировать единообразие путей: skill-relative `agents/…` для всех инлайнов.

**DoD (SMART):**
- [ ] work.md implement-step описывает инлайн `core + delta` (явно, с разделителем).
- [ ] Reviewer/verify шаги не затронуты (диф локализован в 3a).
- [ ] Нет рассинхронизации путей (все `agents/…` одного вида).

**Edge cases:** override-механизм reviewer (`override_if_skill_present`) не должен затрагиваться.

---

## Stage 5 — Доставка партиала (install/packaging)

**Что:** убедиться, что `mb-engineering-core.md`:
- доставляется в установленный skill dir (`~/.claude/skills/memory-bank/agents/`), откуда work.md его инлайнит;
- НЕ копируется в реестр `~/.claude/agents/` как вызываемый агент (исключить `_`-префиксом ИЛИ guard в `install.sh:753–756`).

**DoD (SMART):**
- [ ] Решение зафиксировано: имя файла + guard-строка в install.sh (если нужна).
- [ ] `install.sh` цикл агентов пропускает партиал для реестра, но партиал есть в skill resources.
- [ ] Проверка: после dry-run install партиал доступен по пути, который использует work.md.
- [ ] `.installed-manifest.json` / packaging согласованы (если перечисляют файлы явно).

**Edge cases:** adapters (opencode/codex/pi/cursor) — проверить, что они либо тоже доставляют
партиал, либо их dispatch не зависит от него (degrade-gracefully со ссылкой-инструкцией в дельтах).

---

## Stage 6 — Точечно усилить контролёров (`mb-reviewer`, `plan-verifier`)

**Что (из `billing-ledger-reviewer.md`):**
- **Adversarial default:** «review like an adversary — assume the diff is wrong until the rubric
  is demonstrably upheld; no test that proves an invariant ⇒ treat it as unproven (a finding)».
- **«Invariants proven / Unverified» секция** в выводе: позитивно перечислить, что проверено
  (с доказательством-тестом) и что не удалось подтвердить (= риск, не pass).
- `mb-reviewer`: добавить, не ломая strict-JSON контракт (новые поля опциональны или в prose-секции после JSON — решить, чтобы `mb-work-review-parse.sh` не сломался).
- `plan-verifier`: уже имеет «better to flag an extra issue» — добавить явную «Invariants proven» подсекцию в report.

**DoD (SMART):**
- [ ] `mb-reviewer` содержит adversarial-default формулировку; JSON-парсер не сломан
      (проверить `scripts/mb-work-review-parse.sh` на образце вывода).
- [ ] `plan-verifier` report-формат содержит «Verified positively» подсекцию.
- [ ] Контракты обратносовместимы (severity-gate / parse скрипты зелёные).

---

## Stage 7 — GREEN: re-test before/after + регрессия

**TDD (prompt-testing):**
- Прогнать те же тест-кейсы Stage 0 на новых `core+mb-backend` и `core+mb-developer`.
- LLM-as-judge **pairwise со swap позиций** (anti position-bias): baseline vs new output.
- Зафиксировать рост по rubric (instruction-following / discipline / verification-rigor).

**DoD (SMART):**
- [ ] Для обоих агентов new > baseline по ≥2 из 3 измерений; position-consistent verdict.
- [ ] Результат записан в `.memory-bank/reports/2026-06-02_subagent-baseline.md` (раздел After).
- [ ] Существующие тесты репозитория зелёные: `bash scripts/...` (определить набор; например
      `mb-pipeline-validate.sh`, review-parse, любые pytest под `tests/`).
- [ ] Нет регрессии reviewer/verify контрактов.

**Edge cases:** если new не лучше baseline по измерению → итерация промпта (REFACTOR), повтор.

---

## Stage 8 — Документация и завершение

**DoD (SMART):**
- [ ] `SKILL.md` таблица агентов отражает core-партиал и композицию.
- [ ] `CHANGELOG.md` — запись о strengthening.
- [ ] `/mb verify` против этого плана = PASS/PARTIAL с явным закрытием каждого Gate-пункта.
- [ ] `progress.md` дополнен (append-only), `checklist.md` обновлён.

---

## Порядок и зависимости

0 (RED) → 1 (core) → 2 (developer) → 3 (специалисты) → 4 (work.md) → 5 (install) → 6 (контролёры) → 7 (GREEN) → 8 (docs).
Stage 6 параллельна 1–5 (другая область), но GREEN (7) зависит от 1–6.

## Риски

- **Раздувание промптов:** core + дельта может стать длинным. Митигация: core 90–160 стр, дельты тонкие.
- **Ломка JSON-контракта reviewer:** новые поля только опциональны / в prose. Тест parse обязателен.
- **Партиал как лишний агент в реестре:** Stage 5 guard.
- **Standalone-вызов специалиста без core:** ссылка-инструкция в каждой дельте (degrade-gracefully).
