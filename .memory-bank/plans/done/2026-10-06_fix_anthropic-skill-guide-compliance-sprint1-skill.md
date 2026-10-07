---
type: fix
topic: anthropic-skill-guide-compliance-sprint1-skill
status: queued
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-10-06
---
# Plan: fix — anthropic-skill-guide-compliance · Sprint 1 «скил memory-bank»

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem.** Скил `memory-bank` проверен 2026-10-06 по `~/Downloads/anthropic-skills-guide.md`
(сверен с оригиналами Anthropic: [best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices),
[Claude Code skills](https://code.claude.com/docs/en/skills)). Скрипт замера из гайда дал 881 «нарушение»,
но почти все — шум: папка скила = весь репозиторий, и скрипт считает файлы `.memory-bank/`, `tests/`,
`.opencode/`, `docs/` справочниками скила. Реальные нарушения, относящиеся к скилу:

| # | Правило гайда / Anthropic | Факт на e351a17 |
|---|---|---|
| R3 | SKILL.md < 500 строк | 623 строки, 64 КБ ≈ 27K токенов. 155 строк (≈20 КБ) — таблица всех скриптов, включая внутренние библиотеки (`mb_*_core.py`, «Sourced… Not a standalone entry point»). После автокомпакта Claude Code сохраняет только первые 5 000 токенов вызванного скила — всё ниже ~110-й строки теряется |
| R4 | `description` = что + когда, у каждого авто-вызываемого скила/команды | `SKILL.md` — ок (296 симв., «Use when…»). 33 команды в `commands/` попадают в листинг скилов Claude Code (команды = скилы), у всех `disable-model-invocation` нет, и ни у одной описания нет «когда». `commands/pipeline.md` без frontmatter |
| R1 | Справочник >100 строк — оглавление в начале | 23 файла `references/*.md` и `rules/RULES.md` (805 строк) без оглавления |
| R2 | Каждый файл скила упомянут в SKILL.md, ссылки на один уровень | Не упомянуты: `rules/RULES.md`, `rules/CLAUDE-GLOBAL.md`, `references/pi-native-integration.md`; `flow-templates/patterns/*.md` и `references/rubric-examples/*.md` доступны только через второй уровень |
| R2/ловушка | файлы скила в командах — через `${CLAUDE_SKILL_DIR}` | Используется `$SKILL_DIR` с цепочкой `MB_SKILLS_ROOT → SKILL_DIR → ~/.claude/skills/memory-bank`. Это **осознанное отклонение**: SKILL.md читают Codex/Cursor/Pi/OpenCode, где `${CLAUDE_SKILL_DIR}` не подставляется. Оставляем, но записываем в design-decisions |
| R7 | Три сценария до/после, проверка на Haiku/Sonnet/Opus | Eval-набора нет (идея есть в queued-плане `2026-05-23_feature_skill-improvements-anthropic-audit` Stage 3) |

Что уже соответствует: `name` (`memory-bank`, без reserved words), описание в третьем лице, пути через `/`,
нет XML-тегов во frontmatter, справочники подключены по одному уровню из `## References`.

**Пересечения.** Пункт `SKILL.md: таблицы скриптов, хуков и раздел Cursor/Codex → references/` из
`2026-09-24_fix_opus55-prompt-fit` Stage 6 выполняется здесь (Stage 2 этого плана); его DoD «`SKILL.md` ≤ 9K»
закрывается этим планом. Разбиение `commands/mb.md` (1774 строки) остаётся в opus55 Stage 6 — здесь не трогаем.
Stage 3 queued-плана `skill-improvements-anthropic-audit` (eval-набор) заменяется Stage 6 этого плана.

**Expected result.** SKILL.md ≤ 300 строк и ≤ 9K токенов (оценка `len/4`), ключевой сценарий и маршрутизация
в первых 100 строках; все справочники > 100 строк с оглавлением; каждый файл скила достижим из SKILL.md за
один переход; у каждой команды описание «что + когда» ≤ 1 024 симв.; детерминированный тест-гейт держит это
от регресса; A/B-прогон старой и новой версии на трёх сценариях не хуже.

**Related files:** `SKILL.md`, `references/*.md`, `rules/RULES.md`, `commands/*.md` (только frontmatter),
`references/design-principles.md`, новый `references/scripts.md`, новый `tests/pytest/test_skill_guide_compliance.py`.

**Порядок работы из гайда (обязателен на каждом этапе с правкой текста):** бэкап вне папки скилов
(`cp -R` в `~/skills-backup-2026-10-06/`), замер до, правка, замер после + `--compare` «ни одна строка не
потерялась», кроме переписанных по плану. Удалять текст по правилу 5 — **только предлагать**, не применять
без «да» владельца.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Тест-гейт соответствия (контракт до правок)

**What to do:**
- `tests/pytest/test_skill_guide_compliance.py` — детерминированные проверки, без сети и LLM:
  1. frontmatter `SKILL.md`: `name` ∈ `[a-z0-9-]{1,64}` без `anthropic|claude`; `description` 1…1 024 симв.,
     без XML-тегов, содержит «when/use»; не начинается с «I/You».
  2. тело `SKILL.md` ≤ 300 строк и ≤ 36 000 байт (≈9K токенов).
  3. каждый `references/**/*.md` и `rules/RULES.md` длиннее 100 строк имеет оглавление в первых 40 строках
     (заголовок `Contents`/`Table of contents`/`Содержание`).
  4. каждый `references/**/*.md`, `rules/*.md`, `flow-templates/**/*.md` упомянут в `SKILL.md` по пути.
  5. каждая ссылка/путь `references/…`, `rules/…`, `scripts/…` в `SKILL.md` существует на диске.
  6. каждый `commands/*.md` имеет frontmatter с `description` 1…1 024 симв., содержащим маркер «когда»
     (`Use when|when the user|Triggers`), и без `disable-model-invocation` (AGR-061).
- Область проверки задаётся явным списком каталогов (не весь репозиторий) — это и есть поправка к
  скрипту гайда, давшему 881 ложное срабатывание.

**Testing (TDD — tests BEFORE implementation):**
- Прогнать на e351a17: ожидаемо красные проверки 2, 3, 4, 6 (зафиксировать вывод в отчёте Stage 1);
  1 и 5 — зелёные.
- Позитивный и негативный фикстур на каждую проверку (`tmp_path`-скил с нарушением и без), `@parametrize`.

**DoD (Definition of Done):**
- [x] тест-файл существует, 6 проверок × (фикстура-нарушение красная, фикстура-норма зелёная) — все зелёные на фикстурах
- [x] прогон против репо на e351a17 красный ровно по проверкам 2, 3, 4, 6; вывод сохранён в `reports/2026-10-06_skill-guide-baseline.md`
- [x] проверки 2/3/4/6 помечены `xfail(strict=True)` с ссылкой на Stage, снимающий xfail
- [x] `ruff check` чистый

**Code rules:** SOLID, DRY, KISS, YAGNI; Testing Trophy — тест читает настоящие файлы скила, не моки.

---

<!-- mb-stage:2 -->
### Stage 2: SKILL.md — оглавление, а не справочник (R3)

**What to do:**
- Бэкап: `cp -R ~/Apps/skill-memory-bank/{SKILL.md,references} ~/skills-backup-2026-10-06/` (вне `~/.claude/skills/`).
- Перенести **дословно** в новые/существующие справочники, оставив в SKILL.md 1–2 строки + ссылку:
  - таблица скриптов (строки 152–315) → `references/scripts.md`, разбить на группы (bank core / plans & specs /
    `/mb work` / graph & search / session memory / internal libs). В SKILL.md — только 8–10 точек входа,
    которые агент реально вызывает (`mb-context.sh`, `mb-graph.sh`, `mb-plan.sh`, `mb-work-*.sh` resolve/plan,
    `mb-agree.sh`, `mb-coord.sh`, `mb-search.sh`, `mb-recall`);
  - `## Agents`, `## Hooks`, `## Host-specific notes`, `## Private content`, `## Auto-capture`,
    `## Session memory`, `## PreCompact handoff capsule` → в существующие `references/hooks.md`,
    `references/session-memory.md`, новый `references/hosts.md`, `references/agents.md`;
  - Quick start c bash-комментариями-заголовками (строки 54–100) — оставить, но превратить `# …`-комментарии
    в обычные строки внутри блока (сейчас они ломают иерархию заголовков).
- Первые 100 строк SKILL.md: что это, когда применять, статус-строка, разрешение банка, development flow,
  индекс команд, ссылка на маршрутизацию графа. Это то, что переживает компакт (5 000 токенов).
- Удалить внутренние библиотеки из SKILL.md можно (они переезжают в `references/scripts.md`, не теряются).

**Testing (TDD):**
- Снять `xfail` с проверки 2 Stage 1 → она красная до правки, зелёная после.
- `python3 /tmp/skill_check.py --compare ~/skills-backup-2026-10-06 .` — потерянных строк 0, кроме
  перечисленных в отчёте (заголовки, переписанные ссылки).
- Существующие тесты на SKILL.md (`grep -l SKILL.md tests/`) зелёные или обновлены с обоснованием.

**DoD:**
- [x] `SKILL.md` ≤ 300 строк и ≤ 36 000 байт (`wc -l`, `wc -c`)
- [x] `--compare` показывает 0 потерянных строк вне списка в отчёте
- [x] проверка 2 зелёная без xfail; полный `pytest tests/pytest -q` и `bats tests/bats` без новых красных против baseline
- [x] `scripts/mb-drift.sh .` без новых находок (path-checker видит новые файлы)

**Code rules:** DRY (один источник на таблицу скриптов), KISS.

---

<!-- mb-stage:3 -->
### Stage 3: Оглавления и одноуровневые ссылки (R1, R2)

**What to do:**
- Добавить `## Contents` (список якорей разделов) в начало каждого справочника > 100 строк:
  23 файла `references/**/*.md`, `rules/RULES.md`, `flow-templates/{arch,research}.md`. Текст файлов не менять.
- В `## References` SKILL.md добавить: `rules/RULES.md`, `rules/CLAUDE-GLOBAL.md`,
  `references/pi-native-integration.md`, `references/rubric-examples/` (по файлу на стек),
  `flow-templates/` + `flow-templates/patterns/` (по файлу), новые файлы Stage 2.
- Агенты (`agents/*.md`) и команды (`commands/*.md`) **не** получают оглавление: они грузятся целиком как
  системный промпт/тело команды, а не читаются через Read — правило `head -100` к ним не относится.
  Зафиксировать это в design-decisions (Stage 5).

**Testing (TDD):**
- Снять xfail с проверок 3 и 4 → красные до, зелёные после.

**DoD:**
- [x] проверки 3 и 4 зелёные без xfail
- [x] `git diff --stat` по справочникам показывает только добавленные строки (`git diff --numstat` — 0 удалённых в каждом)
- [x] якоря оглавлений рабочие: тест проверяет, что каждый пункт Contents совпадает с заголовком файла

**Code rules:** KISS — оглавление генерируется один раз, не скриптом на каждом коммите.

---

<!-- mb-stage:4 -->
### Stage 4: Описания команд — «что + когда» (R4)

**What to do:**
- Для каждой из 33 `commands/*.md` переписать `description`: первым — ключевой сценарий, затем
  `Use when …` с фразами, которыми пользователь просит (RU + EN, если команда реально вызывается по-русски),
  третье лицо, ≤ 1 024 симв.; все прежние слова-триггеры сохранить.
- `commands/pipeline.md`: добавить frontmatter (`description`, `allowed-tools` — по образцу `config.md`).
- Тело команд и `allowed-tools`/`argument-hint` **не трогать**.
- `disable-model-invocation` **не добавлять** ни одной команде (AGR-061): Claude сохраняет право вызывать
  любые команды сам, поэтому описание «что + когда» нужно всем 33.

**Testing (TDD):**
- Снять xfail с проверки 6 → красная до, зелёная после.
- Тест: множество слов-триггеров старого описания ⊆ новому (по каждому файлу, `@parametrize`).

**DoD:**
- [x] проверка 6 зелёная; тест сохранения триггеров зелёный для 33 файлов
- [x] суммарная длина описаний 33 команд ≤ 6 000 символов (бюджет листинга — 1 % контекста)
- [x] ни в одном `commands/*.md` нет `disable-model-invocation` (тест, AGR-061)

**Code rules:** не менять `name`/имя файла — сломается `/команда`.

---

<!-- mb-stage:5 -->
### Stage 5: Осознанные отклонения и ловушки Claude Code

**What to do:**
- `references/design-principles.md` (или `docs/DESIGN-DECISIONS.md`, если Stage 1 queued-плана
  `skill-improvements-anthropic-audit` уже выполнен) — раздел «Anthropic skill guide: отклонения»:
  1. `$SKILL_DIR` вместо `${CLAUDE_SKILL_DIR}` — кросс-агентность; Claude-only команды могут
     использовать `${CLAUDE_SKILL_DIR}` (решение по каждой при правке, без массовой замены);
  2. папка скила = весь репозиторий (тесты, `.memory-bank/`) — файлы вне `references/rules/flow-templates`
     не являются справочниками скила;
  3. агенты и команды без оглавления (см. Stage 3);
  4. команды с побочными эффектами (`/commit`, `/pr`, `/db-migration`, `/drive`) без
     `disable-model-invocation` — Claude вызывает их сам по решению владельца (AGR-061);
  5. дубль установки `~/.claude/skills/memory-bank` и `~/.claude/skills/skill-memory-bank` (оба симлинка на
     репо) — проверить в `/skills`, не листится ли скил дважды; если да — `install.sh` не создаёт второй алиас.

**Testing (TDD):**
- Тест: раздел существует и перечисляет 5 пунктов (по якорям).
- Ручная проверка п.5: `claude` → `/skills` — один `memory-bank`; результат в отчёт.

**DoD:**
- [x] раздел записан, тест зелёный
- [x] п.5 проверен на живом Claude Code, вывод в отчёте; при дубле — заведена задача в backlog (`mb-idea.sh`)

**Code rules:** ADR-формат (контекст → решение → альтернативы → последствия).

---

<!-- mb-stage:6 -->
### Stage 6: Eval — старая против новой версии (R7, шаг 6б гайда)

**What to do:**
- `evaluations/skill-guide/` — три сценария JSON (`query`, `expected_behavior[]`, `must_not[]`):
  1. должен вызвать скил: «восстанови контекст проекта и скажи, что в работе» в репо с `.memory-bank/`;
  2. похожий, но не должен: «что такое memory bank в нейросетях?» в репо без банка;
  3. настоящая задача целиком (без необратимых шагов): «найди, кто вызывает `mb_resolve_path`, и где это
     описано в скиле» — проверяет маршрутизацию графа и одноуровневые ссылки.
- Прогон: два свежих сабагента на каждый сценарий (Haiku 4.5 и Sonnet 5.5; Opus 5.5 — сценарий 3),
  один со скилом из бэкапа, другой с новой версией. Каждый отдаёт: какие файлы скила открыл и сколько строк
  прочитал, какие пути проверил и нашлись ли, итог.
- Новая версия хуже хоть в одном пункте → откатить конкретную правку и сообщить владельцу.

**Testing (TDD):**
- Валидатор JSON-сценариев (структура, 3 файла) — pytest.

**DoD:**
- [x] 3 сценария × 2 версии × модели прогнаны, таблица до/после в `reports/2026-10-06_skill-guide-eval.md`
- [x] новая версия не хуже ни по одному пункту ни на одной модели (или откат + запись)
- [x] сценарий 2 не вызывает скил ни в одной версии

**Code rules:** только чтение; никаких записей в банк, сетевых запросов, `git` с побочными эффектами.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Вынос текста из SKILL.md ухудшит поведение агентов, которые читали только SKILL.md (Codex/Cursor/Pi) | M | Первые 100 строк — маршрутизация + явные ссылки; A/B Stage 6; откат по правке |
| Тесты, проверяющие наличие строк в SKILL.md (`test_doc_counts.py` и др.), упадут | H | Перед Stage 2 — `grep -rl SKILL.md tests/`; переносить ожидания на новый файл, а не ослаблять |
| Конфликт с параллельной сессией pi-native-integration по `SKILL.md`/`references/` | M | `mb-coord.sh active` перед каждым этапом; scoped `git add`; AGR-032 — один владелец файла |
| Переписанные описания команд перестанут ловить старые формулировки | M | Тест сохранения триггеров (Stage 4) |
| `opus55-prompt-fit` Stage 6 параллельно правит SKILL.md | M | Пункт про SKILL.md забран сюда; в opus55 отметить «выполнено в anthropic-skill-guide-compliance» |

## Gate (plan success criterion)

`pytest tests/pytest/test_skill_guide_compliance.py` зелёный без xfail, полный pytest/bats без новых красных
против baseline e351a17, и A/B-отчёт Stage 6 показывает, что новая версия не хуже старой ни на одном сценарии.
