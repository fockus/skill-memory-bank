---
type: fix
topic: proportional-effortsprint2-execution-economy
status: in_progress
depends_on: ["2026-10-07_fix_proportional-effortsprint1-routing-rules.md"]
parallel_safe: false
linked_specs: []
created: 2026-10-07
---
# Plan: fix — proportional-effort · Sprint 2 «экономия исполнения: целевые тесты, тон по модели, замер»

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem (найдено 2026-10-07).** Полный набор тестов гоняется на каждое изменение:
- `agents/mb-engineering-core.md` § 7: «After every significant change, run … tests (all green)» — каждый
  implementer после каждой правки гоняет весь набор;
- `agents/plan-verifier.md` Step 3.5: `mb-test-run.sh --dir .` — весь набор на **каждый** пункт `/mb work`
  (verify-шаг), а не один раз на план;
- `commands/work.md` § Cost ladder сам фиксирует «~28 test runs per item» для дефолтного `execution`.
Тон: core написан под слабые модели (Iron Law, NEVER, таблица отговорок «Quick fix, no test needed → next
week's regression»); сильные модели воспринимают это буквально и перестраховываются (Anthropic prompting
best practices для Claude 4.x: агрессивные формулировки ведут к overtriggering).

Решения владельца: AGR-068 (строгий тон для слабых, спокойный для сильных), AGR-071 (целевые тесты в работе,
полный набор в `/mb verify` и перед коммитом, без повторных прогонов), AGR-072 (замер на боевых задачах).

**Expected result.**
1. `mb-test-run.sh --changed-since <ref>` гоняет только тесты, относящиеся к изменённым файлам; полный набор —
   fallback при пустом/неоднозначном маппинге и при изменении общей инфраструктуры тестов.
2. В `/mb work` verify-шаг пункта — целевые тесты; полный набор — один раз на финальном пункте плана/спеки,
   в `/mb verify` и в `/commit`.
3. Core в спокойном тоне с причинами; строгая дисциплина — отдельный partial, подключается для моделей из
   списка `pipeline.yaml` и по выбору профиля для основной сессии.
4. Отчёт замера на боевых задачах: токены, время, число тестов и документов до/после.

**Related files:** `scripts/mb-test-run.sh`, `agents/plan-verifier.md`, `commands/work.md`,
`commands/verify.md`, `commands/commit.md`, `agents/mb-engineering-core.md`, `agents/mb-discipline-strict.md`
(new), `references/pipeline.default.yaml`, `scripts/mb-work-plan.sh`, `scripts/mb-agent-render.py`,
`scripts/mb-graph-query.py` (подкоманда `tests` — reuse), тесты.

**Parallel execution (AGR-073, 2026-10-07).** Waves, with one owner per file:
- Wave 1, running in parallel:
  - A = Stage 1 (`mb-test-run.sh`);
  - B = Stage 2 + Stage 3a (`agents/*`, `commands/work.md`, `commands/commit.md`, `pipeline.default.yaml` § discipline, `mb-work-plan.sh`). B codes against the interface contract of Stage 1 (`--changed-since <ref>`, `--files`, JSON `selection`/`selected[]`/`reason`);
  - C = Stage 4 (`mb-effort-report.sh`, report).
- Wave 2, after A+B: the integration scenario "full suite runs once per 3-item plan".
- Wave 2, after key-rules Stage 4: Stage 3b (profile `discipline` → `mb-rules.sh`).

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Целевой прогон тестов

**What to do:**
- `mb-test-run.sh --changed-since <ref>` (и `--files <list>`): набор тестов = изменённые тест-файлы +
  тесты по графу (`mb-graph-query.py tests` для символов изменённых файлов, если граф свежий) + тесты по
  конвенции имени (`foo.py` → `test_foo*.py`, `x.sh` → `test_x*.bats`). JSON получает
  `selection: targeted|full` и `selected[]`. Fallback на полный набор: маппинг пуст, изменены `conftest.py`,
  `tests/**/lib/**`, файлы сборки/зависимостей.
- Без нового индекса и зависимостей — только существующий граф и имена файлов.

**Testing (TDD):**
- bats на фикстурном репо: правка `a.py` → гоняется только `test_a.py`; правка `conftest.py` → full; правка
  без тестов → full с `reason`; `--files` эквивалентен `--changed-since`.

**DoD:**
- [x] bats красные до, зелёные после; shellcheck чистый; поведение без флагов байт-в-байт прежнее для одного стека (`assert_same_as_head`); в репо с несколькими стеками без флага теперь идут все (`bats+python`, раньше только первый) — осознанное изменение, в CHANGELOG

**Code rules:** reuse графа и runner'а; fallback всегда на полный набор, никогда на «ничего не запущено».

---

<!-- mb-stage:2 -->
### Stage 2: Пропорциональная проверка в агентах и `/mb work`

**What to do:**
- `agents/mb-engineering-core.md` § 7: во время работы — целевые тесты и линт изменённых файлов
  (`mb-test-run.sh --changed-since`); вывод показан один раз — не перезапускать без новых правок; полный
  набор — не на implementer'е.
- `agents/plan-verifier.md` Step 3.5: verify пункта `/mb work` — `--changed-since <item baseline>`;
  полный набор — на финальном пункте и при `/mb verify` всего плана.
- `commands/work.md` § Cost ladder — пересчитать «test runs per item» по факту; `commands/commit.md` — полный
  набор перед коммитом (если не прогнан на этом же дереве).

**Testing (TDD):**
- pytest-гард: core не содержит «After every significant change … tests (all green)»; verifier использует
  `--changed-since` для пункта и полный набор для плана; work.md упоминает только целевой прогон на пункт.
- Сценарий: `/mb work` на фикстурном плане из 3 пунктов → полный набор запущен ровно 1 раз (лог runner'а).

**DoD:**
- [x] гард зелёный (`tests/pytest/test_proportional_verification_texts.py`); `test_mb_debugger_agent.py`, тесты рендера агентов зелёные (Stage 2, wave 1, 2026-10-07)
- [x] сценарий «полный набор ровно 1 раз на плане из 3 пунктов» зелёный (`tests/bats/test_proportional_full_suite_once.bats`: plan → 1 full / 0 targeted, stage → 2 targeted + 1 full, conftest.py → full с reason) (Stage 2, wave 2, 2026-10-07)

**Code rules:** один источник порядка проверок — workflow; агенты ссылаются, не дублируют.

---

<!-- mb-stage:3 -->
### Stage 3: Тон по силе модели

**What to do:**
- `agents/mb-engineering-core.md` — спокойный тон с причинами, без таблицы отговорок и капслока; смысл
  правил сохранён (каждое удалённое требование найдено в strict partial или справочнике — `--compare`).
- `agents/mb-discipline-strict.md` (new partial): Iron Law, NEVER-формулировки, таблица отговорок.
- Выбор: `pipeline.yaml` → `discipline: {strict_models: [<шаблоны имён моделей>]}` (дефолт: haiku и
  локальные/малые модели); `mb-work-plan.sh` отдаёт `discipline: strict|calm` в JSON пункта; `/mb work`
  добавляет strict partial в промпт диспатча при `strict`. Основная сессия: профиль
  `discipline: auto|strict|calm` → `mb-rules.sh` добавляет 3–5 строгих строк в блок Key rules при `strict`.

**Testing (TDD):**
- pytest: core без «NEVER»/таблицы; strict partial содержит Iron Law; `mb-work-plan.sh` для `model: haiku` →
  `strict`, для `opus` → `calm`; project override списка работает; рендер Key rules со `strict` ≤ 3 КБ.

**DoD:**
- [x] 3a: тесты зелёные (`tests/pytest/test_discipline_by_model.py`); сравнение старого и нового core: 0 потерянных требований (каждое удалённое — в `agents/mb-discipline-strict.md` или переформулировано в core) (2026-10-07)
- [x] 3b: профиль `discipline: auto|strict|calm` → `mb-rules.sh`; рендер Key rules со `strict` ≤ 3 КБ (2026-10-07: `strict_lines` в `rules/key-rules.json` заменяют строку `targeted-verification`, блок 3068 B на дефолтах; `auto` = calm — основная модель хоста при рендере неизвестна; `mb-rules.sh discipline <v> [--scope]`)

**Code rules:** один core + один addendum, без двух копий core.

---

<!-- mb-stage:4 -->
### Stage 4: Замер на боевых задачах

**What to do:**
- `scripts/mb-effort-report.sh <session-jsonl>…`: из транскриптов Claude Code (usage tokens, длительность) и
  `git diff --stat` диапазона задачи — токены, время, добавленные тесты, новые/изменённые документы.
- Baseline: 3 недавние боевые задачи до изменений (транскрипты из `~/.claude/projects/…`); после внедрения —
  3 сопоставимые боевые задачи. Отчёт `reports/<date>_proportional-effort.md` с таблицей до/после и уровнем
  каждой задачи.

**Testing (TDD):**
- bats на фикстурном jsonl + фикстурном git-репо: суммы токенов и счётчики тестов/доков верны.

**DoD:**
- [x] `scripts/mb-effort-report.sh` + bats (фикстурный jsonl + фикстурное git-репо); baseline «до» на 3 боевых
  задачах — `reports/2026-10-07_proportional-effort-baseline.md` (2026-10-07)
- [ ] отчёт с цифрами до/после на боевых задачах; качество — без новых багов в этих задачах за неделю
  (проверка по backlog/issues) — секция «After» в том же отчёте, заполняется после внедрения

**Code rules:** отчёт читает существующие артефакты, без телеметрии и сети.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Целевой прогон пропустит регрессию в соседнем модуле | M | полный набор на финальном пункте, `/mb verify` и `/commit`; fallback на full при общих файлах |
| Мягкий тон расслабит сильную модель на рискованных задачах | L | уровень extra включает строгий workflow; strict partial включается вручную через профиль |
| Шаблоны имён моделей устареют | M | список в `pipeline.yaml`, переопределяется в проекте |

## Gate (plan success criterion)

На плане из 3 пунктов полный набор тестов запускается 1 раз; core в спокойном тоне, strict подключается для
моделей из списка; отчёт на боевых задачах показывает снижение токенов/времени без новых багов; все тесты зелёные.
