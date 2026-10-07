---
type: feature
topic: project-quality-settings
status: done
depends_on: ["2026-10-06_feature_key-rules-onboarding.md", "2026-10-07_fix_proportional-effortsprint1-routing-rules.md"]
parallel_safe: false
linked_specs: []
created: 2026-10-07
---
# Plan: feature — project-quality-settings · coverage, TDD, Testing Trophy, архитектура и принципы как настройки проекта

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem (2026-10-07).** Владелец хочет задавать правила качества на уровне проекта: процент покрытия, нужен ли
TDD, Testing Trophy, выбранную архитектуру (clean, модульная, другие) и отдельные пункты SOLID / DRY / KISS / YAGNI.
Эти правила должны быть видны в `RULES.md` проекта и работать в пайплайне (AGR-076).

Сейчас то же самое разбросано по двум несвязанным механизмам:
- **rules profile** (`references/rules-profile.schema.md`, `scripts/mb-profile.sh`):
  - поля `architecture` (`clean | hexagonal | modular-monolith | microservices | ddd | fsd | mobile-udf | event-driven | custom`), `delivery` (`tdd | contract-first | api-first | sdd | legacy-safe | exploratory`) и `strictness`;
  - у каждого значения есть пресет `references/rules-presets/*/<name>.json` с правилами и severity `block | warn | advisory`;
- **каталог key rules** (`rules/key-rules.json`, plan key-rules-onboarding): группы `architecture` и `tests` сделаны независимыми переключателями (`clean-architecture`, `fsd`, `tdd`, `testing-trophy`, `coverage`…) и никак не связаны с полями профиля.

Из-за этого выбор архитектуры или TDD хранится в двух местах. Гейты пайплайна (верификатор — coverage, TDD
red-gate в `/mb work`, `review_rubric`, `mb-rules-check.sh`) читают захардкоженные значения или `pipeline.yaml`,
а не настройки проекта.

**Expected result.**
1. **Один источник** — профиль проекта поверх профиля пользователя: `architecture` (одна или несколько + `custom` с текстом),
   `delivery`, `quality: {tdd: on|off|small+, testing_trophy: on|off, coverage: {enabled, overall, core, infra},
   principles: {solid, dry, kiss, yagni: on}}`, плюс `key_rules` из key-rules-onboarding.
2. **Строки Key rules для архитектуры и тестов выводятся из профиля:**
   - выбранная архитектура даёт свою однострочную формулировку из пресета;
   - TDD, Trophy и coverage берут числа из `quality`.

   Отдельные переключатели этих правил в каталоге убираются, второго хранилища нет.
3. **Блок `<!-- mb-project-rules:start/end -->` в проектном `RULES.md`** (корень репо, иначе `<bank>/RULES.md`; если файла
   нет — создаётся только по `/mb rules init --scope=project`):
   - человекочитаемые настройки: архитектура с правилами пресета, принципы, TDD, Trophy, coverage-пороги;
   - ниже блока свободный текст пользователя, его не трогаем.
4. **Гейты пайплайна читают настройки:**
   - верификатор сравнивает coverage только при `coverage.enabled` и с порогами профиля;
   - TDD red-gate в `/mb work` и требование RED в промпте implementer'а — только при `tdd: on` (или `small+` для уровня small и выше);
   - `review_rubric` (tests и code_rules) собирается из включённых принципов и Trophy;
   - `mb-rules-check.sh` применяет пресет выбранной архитектуры.

   `/mb config show` показывает эти настройки рядом с моделями и шагами.
5. **Команда** `/mb rules set <key> <value> [--scope=user|project]`, например `set architecture modular-monolith`, `set tdd off`,
   `set coverage 80/95/70`, `set principle kiss off`. Плюс онбординг: шаг «Quality» в `install.sh` и `/mb rules init`.

**Принципы (AGR-077):** SOLID, DRY, KISS и YAGNI по умолчанию включены, но выключаются по одному (`/mb rules set principle
kiss off --scope=project`). В каталоге key rules с этих четырёх снимается `locked`; остальные locked-пункты (Fail Fast,
No placeholders, Root cause) не меняются.

**Related files:** `references/rules-profile.schema.md`, `memory_bank_skill/rules_profile.py`, `memory_bank_skill/key_rules.py`,
`rules/key-rules.json`, `references/rules-presets/**`, `scripts/mb-profile.sh`, `scripts/mb-rules.sh`, `scripts/mb-rules-check.sh`,
`agents/plan-verifier.md`, `commands/work.md` (TDD red-gate), `references/pipeline.default.yaml` (`review_rubric`),
`commands/rules.md`, `commands/config.md`, `install.sh`, тесты.

**Parallel execution (AGR-073).**
- Stage 1 (схема + резолвер) — первым.
- Затем параллельно, с разведёнными владельцами файлов: Stage 2 (рендер Key rules и RULES.md: `key_rules.py`, `mb-rules.sh`), Stage 3 (гейты: `plan-verifier.md`, `work.md`, `pipeline.default.yaml`, `mb-rules-check.sh`) и Stage 4 (команда и онбординг: `commands/rules.md`, `install.sh`).

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Схема `quality` + резолвер настроек проекта

**What to do:**
- `rules-profile.schema.md`: блок `quality` (см. Expected result 1). У `architecture` допускается список и `custom: "<текст>"`.
  Коды ошибок: `unknown_architecture`, `coverage_out_of_range`. С `solid/dry/kiss/yagni` в `rules/key-rules.json` снять `locked` (AGR-077), тест каталога обновить.
- Резолвер в существующем python-ядре (`rules_profile.py`/`key_rules.py`), без второго механизма: user → project,
  дефолты (`tdd: small+`, `testing_trophy: on`, `coverage.enabled: false` + 85/95/70, принципы on).
  CLI: `mb-profile.sh quality [--json]`.
- Аудит: найти всех потребителей `references/rules-presets` и `architecture`/`delivery` (сейчас их явно не видно) — подключить
  или зафиксировать в отчёте, что пресеты ни к чему не подключены.

**Testing (TDD):**
- pytest: дефолты; project перекрывает user по каждому ключу; невалидные значения → коды ошибок; `custom`-архитектура проходит
  с текстом и падает без него.

**DoD:**
- [x] тесты красные до, зелёные после; `mb-profile.sh validate` ловит невалидный `quality` (2026-10-07: `memory_bank_skill/quality.py`, `mb-profile.sh quality [--json]`, `tests/pytest/test_project_quality.py`; принципы — единственный источник `quality.principles`, id в `key_rules.*` → `principle_in_quality`; аудит: `references/rules-presets` рантаймом не читаются нигде (только `test_rules_presets.py` и docs), `architecture` читает лишь `mb-rules-check.sh` (fsd-проверка), `delivery` — никто; подключение — Stage 3)

---

<!-- mb-stage:2 -->
### Stage 2: Рендер — Key rules из профиля + блок в проектном `RULES.md`

**What to do:**
- `key-rules.json`: строки `architecture` и `tests` заменить на ссылки на пресеты (`source: profile.architecture` / `quality.*`).
  Формулировка архитектуры берётся из однострочника пресета (поле `one_liner` добавить в пресеты). Бюджет всего блока ≤ 3 072 байт.
- `mb-rules.sh sync --scope=project` пишет `<!-- mb-project-rules:start/end -->` в проектный `RULES.md` (атомарно,
  идемпотентно, чужой текст не трогается; файл не создаётся без `init`).

**Testing (TDD):**
- bats: `architecture: modular-monolith` → Key rules и RULES.md содержат правила modular-monolith и не содержат clean;
  `tdd: off` → строки TDD нет; coverage 80/95/70 → числа в обоих местах; свободный текст под блоком сохраняется; повтор —
  байт-в-байт.

**DoD:**
- [x] bats зелёные; блок Key rules ≤ 3 КБ на дефолтах (2026-10-07: каталог — одна строка `architecture` (`source: architecture`, однострочник `one_liner` пресета, custom → `Architecture: <text>`), `tdd`/`testing-trophy`/`coverage` с `source: quality.*` — их enable/disable пишут `quality`; бывшие id `clean-architecture`/`fsd`/`ddd-folders`/`mobile-udf`/`backend-macro` и source-id в `key_rules` → `profile_setting`; `key_rules.resolve_effective`; блок `<!-- mb-project-rules -->` в RULES.md — `quality.render_project_rules`, `mb-rules.sh sync --scope=project`; дефолт `architecture: [clean, fsd, ddd]` — те же три строки, что были до стадии; Key rules на дефолтах 2941 Б, strict 2987 Б, дефолт+coverage+strict 3053 Б, худший случай (три самых длинных однострочника + coverage + strict) 3056 Б (лимит 3072); `tests/bats/test_mb_rules_quality.bats`)

---

<!-- mb-stage:3 -->
### Stage 3: Гейты пайплайна читают настройки

**What to do:**
- `agents/plan-verifier.md`: coverage — только при `coverage.enabled`, пороги из `mb-profile.sh quality --json`.
- `commands/work.md` / промпт implementer'а: RED-требование и TDD red-gate — по `quality.tdd` и уровню задачи (proportional-effort).
- `review_rubric` (`pipeline.default.yaml`): пункты tests/code_rules собираются из включённых принципов и Trophy (`mb-review.sh`
  или сборщик payload — найти, где rubric читается).
- `mb-rules-check.sh`: применяет правила пресета выбранной архитектуры (severity из пресета).
  Механическая проверка архитектуры есть только для fsd; `clean_arch/direction` выполняется всегда (направление clean держится внутри каждого модуля); остальные пресеты — guidance для ревьюера и агентов.
- `/mb config show`: секция «Quality» с итоговыми значениями и источником (user/project/default).

**Testing (TDD):**
- bats/pytest: `coverage.enabled:false` → verifier не требует coverage; `tdd: off` → нет RED-требования в промпте; принцип
  выключен → его нет в rubric и в Key rules; архитектура fsd → `mb-rules-check.sh` ловит импорт вверх по слоям.

**DoD:**
- [x] тесты зелёные; на этом репо (без quality в профиле) поведение гейтов прежнее (2026-10-07: verifier — coverage только при `coverage.enabled`, иначе `Coverage: not enabled`; `/mb work` 5a — TDD-строка по `quality.tdd` и уровню (`work-reference.md` § Project quality settings), Eval спеки не отключается; rubric — `mb_rubric_quality.py` через `mb-rules-resolve.sh`, стоковые пункты SOLID/DRY/KISS/YAGNI/Trophy выпадают при off, свои пункты проекта остаются; `mb-rules-check.sh` — `architecture.names` (user→project, default не включает доп. проверок), severity fsd из пресета (block→CRITICAL), `dry-kiss-yagni` убран из immutable-fallback; `/mb config show` — секция `quality:` из `mb-profile.sh quality`; тесты: `test_quality_gates_doc.bats`, +3 `test_rules_check_profile.bats`, +3 `test_mb_rules_resolve.bats`, +2 `test_mb_config_hosts.bats`)

---

<!-- mb-stage:4 -->
### Stage 4: `/mb rules set` + онбординг «Quality»

**What to do:**
- `mb-rules.sh set <key> <value> [--scope]`; `commands/rules.md` — описание; `/mb rules init` спрашивает архитектуру, TDD,
  Trophy, coverage (multiSelect + ввод порога).
- `install.sh`: после чеклиста Key rules — короткий шаг Quality для user-профиля (TTY only, `--non-interactive` → дефолты).

**Testing (TDD):**
- bats: `set architecture hexagonal --scope=project` → профиль, Key rules и RULES.md обновлены, глобальные файлы не тронуты;
  install в temp HOME с подставленным stdin → user-профиль содержит выбор.

**DoD:**
- [x] тесты зелёные; `test_command_descriptions.py` зелёный — без install.sh (2026-10-07: `mb-rules.sh set architecture|tdd|trophy|coverage|principle|discipline`, `discipline` — алиас; `commands/rules.md` — `set` + шаг Quality в `init`; `dry-kiss-yagni` снят с immutable baseline)
- [x] `install.sh`: шаг Quality (TTY / `--non-interactive`) (2026-10-07: `init --interactive` после чеклиста и своих правил спрашивает architecture (номера пресетов / `c <text>`), TDD, Trophy, coverage — `key_rules_prompt.quality_prompt`, запись тем же `Selection.set` + `save`; Enter/EOF — текущее значение, неверный ответ — переспрос один раз, затем текущее; тесты: `test_key_rules_quality_prompt.py` (11), +3 `test_install_key_rules.bats`)

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Два источника снова разойдутся (каталог и профиль) | M | Stage 2 убирает переключатели архитектуры/тестов из каталога; тест «одна настройка — одно место» |
| Пресеты архитектур окажутся неподключёнными нигде | M | аудит в Stage 1, подключение в Stage 3 |
| Блок в RULES.md конфликтует с ручным текстом пользователя | L | managed-маркеры, текст вне блока не трогается, файл не создаётся без `init` |

## Gate (plan success criterion)

`/mb rules set architecture modular-monolith --scope=project` и `set coverage 80/95/70` меняют один профиль; это видно в Key rules,
в проектном `RULES.md` и в `/mb config show`; верификатор, TDD-gate, rubric и `mb-rules-check.sh` ведут себя по этим настройкам;
все тесты зелёные.
