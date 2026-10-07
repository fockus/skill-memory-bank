---
type: feature
topic: key-rules-onboarding
status: done
depends_on: ["2026-10-06_fix_anthropic-skill-guide-compliance-sprint2-instructions.md"]
parallel_safe: false
linked_specs: []
created: 2026-10-06
---
# Plan: feature — key-rules-onboarding · каталог ключевых правил, онбординг и `/mb rules`

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem.** Сейчас правила о коде живут в трёх формах: полный `rules/RULES.md` (48 КБ), выжимка
`rules/CLAUDE-GLOBAL.md` (блок «Engineering rules», абзацы по 1–3 строки) и полная копия RULES.md в
проектных `AGENTS.md`/`.mdc`. Пользователь не выбирает, какие правила ему инжектят, и не может дописать
свои. Решения владельца — AGR-063, AGR-064.

**Expected result.**
1. Каталог ключевых правил `rules/key-rules.json` — правила только о коде и процессе работы над кодом,
   одна строка на правило, сгруппированы, у каждого `id`, `group`, `text`, `default` (on/off), `locked`
   (обязательные принципы — снять нельзя).
2. Выбор хранится в существующем rules-profile (`references/rules-profile.schema.md`, user/project scope,
   приоритет project > user) — новое поле `key_rules: {enabled[], disabled[], custom[]}`.
3. Рендер: управляемая секция `## Key rules` **в самом верху** `CLAUDE.md` и `AGENTS.md` (глобальных и
   проектных) — маркеры `<!-- mb-key-rules:start/end -->`, одна строка `- ` на правило, ≤ 3 КБ.
4. Онбординг в `install.sh`: интерактивный чеклист (на TTY) с готовым списком + поле «свои правила»
   (архитектура, процесс, что угодно); без TTY / `--non-interactive` — дефолты. Тот же онбординг доступен
   агенту через `/mb rules init` (вопросы с multiSelect).
5. Команда `/mb rules` (`commands/rules.md` + `scripts/mb-rules.sh`): `list | enable <id> | disable <id> |
   add "<text>" | remove <n> | init | sync`, флаг `--scope=user|project` — переопределение глобально и
   для конкретного проекта.
6. `rules/RULES.md` остаётся детальным шаблоном-справочником (читается по требованию); каждая строка
   каталога ссылается на свой раздел RULES.md, если он есть.

**Состав каталога (черновик, финализируется в Stage 1):**
- *Principles (locked):* SOLID (SRP/ISP/DIP пороги одной строкой) · DRY — правило трёх · KISS · YAGNI —
  без кода «на будущее» · Fail Fast — уточнять, только если разные прочтения ведут к разной работе ·
  No placeholders · Root cause, а не симптом.
- *Minimal code & comments (ponytail):* лестница перед кодом — нужно ли вообще → есть ли в кодовой базе →
  stdlib → нативная платформа → уже установленная зависимость → одна строка → минимум кода · без
  непрошенных абстракций (интерфейс с одной реализацией, фабрика одного продукта, конфиг для константы) ·
  удаление лучше добавления, скучное лучше хитрого · самый короткий дифф — но только после понимания задачи ·
  комментарии — только неочевидное «почему», не пересказ кода · осознанное упрощение помечается
  `ponytail:`-комментарием с потолком и путём апгрейда · никогда не упрощать валидацию на границе доверия,
  безопасность, обработку ошибок против потери данных.
- *Architecture:* Clean Architecture направление зависимостей · FSD для фронтенда · DDD-группировка папок ·
  Mobile UDF (default off) · backend macro-architecture выбрать одну (default off).
- *Tests:* TDD — тест до кода · Contract-First · Testing Trophy · один исполняемый чек на нетривиальную
  логику · именование и AAA · покрытие 85/95/70 (default on).
- *Process:* многоэтапная работа → план · проверка перед «готово» (доказательство, не утверждение) ·
  protected files (`.env`, CI, Docker/K8s/Terraform) · scoped `git add`, без деструктивных git без просьбы ·
  не расширять скоуп без запроса.
- *Custom:* свободный текст пользователя, по строке на правило.

**Related files:** `rules/key-rules.json` (new), `rules/RULES.md`, `rules/CLAUDE-GLOBAL.md`,
`references/rules-profile.schema.md`, `scripts/mb-profile.sh`, `scripts/mb-rules.sh` (new),
`commands/rules.md` (new), `install.sh`, `adapters/_lib_agents_md.sh`, `scripts/mb-language.py`
(образец top-of-file блока), тесты.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Каталог `rules/key-rules.json` (контракт)

**What to do:**
- JSON: `{schema_version:1, groups:[…], rules:[{id, group, text, default, locked, ref}]}`; `text` — одна строка ≤ 160 симв.,
  без переносов; `ref` — якорь в `rules/RULES.md` или `null`.
- Наполнить по черновику из Context; формулировки SOLID/DRY совпадают с каноном RULES.md (opus55 Stage 4).

**Testing (TDD — tests BEFORE implementation):**
- pytest `test_key_rules_catalog.py`: схема валидна; `id` уникальны, kebab-case; `text` ≤ 160 симв. и однострочный;
  каждый `ref` резолвится в заголовок RULES.md; есть группы principles/minimal-code/architecture/tests/process;
  все principles — `locked:true`; каталог содержит правила о комментариях и о лестнице ponytail.

**DoD (Definition of Done):**
- [x] тест красный до создания каталога, зелёный после
- [x] суммарный рендер всех default-on правил ≤ 3 072 байт (тест)

**Code rules:** один источник формулировок; без дублей с CLAUDE-GLOBAL (Stage 4 убирает дубль).

---

<!-- mb-stage:2 -->
### Stage 2: Профиль + резолвер выбора

**What to do:**
- `references/rules-profile.schema.md`: поле `key_rules {enabled[], disabled[], custom[]}`; locked нельзя отключить
  (ошибка валидации с кодом причины); custom — строки ≤ 200 симв.
- Резолвер (в существующем `mb-profile.sh`/python-ядре): итог = default-on ∪ user.enabled − user.disabled,
  затем project поверх user; custom = user.custom + project.custom; locked всегда включены.

**Testing (TDD):**
- pytest: пустые профили → дефолт; user отключил правило → нет; project включил обратно → есть; попытка отключить
  locked → ошибка; custom из обоих scope в порядке user→project; невалидный id → ошибка с именем id.

**DoD:**
- [x] тесты красные до, зелёные после; существующие тесты `mb-profile` зелёные
- [x] `mb-profile.sh validate` ловит отключение locked

**Code rules:** расширение существующего профиля, не второй механизм хранения (KISS).

---

<!-- mb-stage:3 -->
### Stage 3: Рендер секции `## Key rules` вверху файлов

**What to do:**
- `scripts/mb-rules.sh render|sync` пишет блок `<!-- mb-key-rules:start -->…<!-- mb-key-rules:end -->` в начало файла
  (после `mb-language` блока, если он есть; до всего остального), по одной строке `- <text>` на правило, custom — в конце
  с пометкой «(your rule)».
- Цели: user scope → `~/.claude/CLAUDE.md` и глобальные AGENTS.md установленных хостов (Codex/Pi/OpenCode/Cursor);
  project scope → проектные `CLAUDE.md` и `AGENTS.md` (только существующие, как у `mb-agree.sh`).
- Идемпотентность, атомарная запись, чужой текст не трогается.
- Последняя строка блока — ссылка на детальные правила (AGR-066): в проектных файлах — на локальный RULES.md проекта
  (`<repo>/RULES.md`, иначе `<bank>/RULES.md`; если файла нет — строка «create `RULES.md` in the project root for your own
  rules»), в глобальных — на глобальный `~/.claude/RULES.md` / RULES.md установленного скила для хоста.

**Testing (TDD):**
- bats: блок встаёт первой секцией (после language-блока); повтор — байт-в-байт; отключённое правило исчезает;
  custom-строка появляется; файл без блока получает его, остальной текст неизменен; ≤ 3 КБ на дефолтах;
  проектный блок ссылается на `<repo>/RULES.md` (или `<bank>/RULES.md`), глобальный — на глобальный RULES.md.

**DoD:**
- [x] bats зелёные; shellcheck чистый

**Code rules:** переиспользовать `mb_upsert_marked_block`/логику top-of-file из `mb-language.py`, не писать третий writer.

---

<!-- mb-stage:4 -->
### Stage 4: Онбординг в `install.sh` + `/mb rules`

**What to do:**
- `install.sh`: при TTY и без `--non-interactive` — шаг «Key rules»: пронумерованный чеклист по группам
  (`[x] 3. KISS …`, locked показаны как `[*]`), ввод номеров для переключения, Enter — принять; затем поле
  «Your own rules (architecture, process, anything) — one per line, empty line to finish». Пишет user-профиль, вызывает
  `mb-rules.sh sync --scope=user`. Повторная установка показывает текущий выбор. Флаги: `--key-rules=default|keep`,
  `--non-interactive` → default (первая установка) / keep (повторная).
- `commands/rules.md` (`/mb rules` + алиас в `commands/mb.md` роутере): `list`, `enable/disable <id>`, `add "<text>"`,
  `remove <n>`, `init` (агентский онбординг через вопрос с multiSelect + свободный ввод), `sync`; `--scope=user|project`
  (project по умолчанию внутри банка). Описание «что + когда» (проходит `test_command_descriptions.py`).
- `rules/CLAUDE-GLOBAL.md`: блок «Engineering rules» заменяется ссылкой на секцию Key rules (рендерится выше) +
  `~/.claude/RULES.md` для деталей — без дубля формулировок.

**Testing (TDD):**
- bats: install с подставленным stdin (`printf '3\n\nprefer composition over inheritance\n\n'`) в temp HOME → user-профиль
  содержит disabled/custom, `~/.claude/CLAUDE.md` начинается с блока Key rules без отключённого правила и с custom;
  `--non-interactive` → дефолт; повторный install с `keep` не меняет выбор.
- bats: `mb-rules.sh disable <id> --scope=project` в проекте → проектный CLAUDE.md/AGENTS.md без правила, глобальные
  файлы не тронуты; `--scope=user` → наоборот.
- pytest: `commands/rules.md` frontmatter + описание; `commands/mb.md` маршрутизирует `rules`.

**DoD:**
- [x] все тесты зелёные; `test_skill_guide_compliance.py` и `test_command_descriptions.py` зелёные (34 команды)
- [x] ручной прогон `install.sh` в temp HOME на TTY — скриншот/вывод в отчёте
- [x] `SKILL.md` индекс команд и счётчик «— N commands» обновлены (test_doc_counts)

**Code rules:** bash 3.2-совместимо (macOS); без новых зависимостей (no `dialog`/`whiptail`).

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Интерактивный шаг ломает CI/headless установки | M | только при `[ -t 0 ]` и без `--non-interactive`; тест на non-TTY |
| Пользователь отключит правило, на которое опираются гейты (`mb-rules-check.sh`, TDD-гейт) | M | принципы `locked`; гейты читают RULES.md/профиль strictness, не Key rules |
| Две копии правил (Key rules и CLAUDE-GLOBAL) разойдутся | H | Stage 4 убирает блок Engineering rules из CLAUDE-GLOBAL; тест «одна формулировка в одном месте» |
| Конфликт с agents-md-diet по файлам `_lib_agents_md.sh`/`install.sh` | M | этот план идёт первым; agents-md-diet использует рендер Stage 3 |

## Gate (plan success criterion)

Свежая установка в temp HOME на TTY показывает чеклист и поле своих правил; выбранный набор оказывается первой
секцией `~/.claude/CLAUDE.md` и глобальных AGENTS.md по строке на правило; `/mb rules disable|add --scope=project`
меняет только проектные файлы; все тесты зелёные.
