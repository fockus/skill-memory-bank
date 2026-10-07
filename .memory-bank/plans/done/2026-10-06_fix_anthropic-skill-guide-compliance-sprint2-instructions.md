---
type: fix
topic: anthropic-skill-guide-compliance-sprint2-instructions
status: done
depends_on: ["2026-10-06_fix_anthropic-skill-guide-compliance-sprint1-skill.md"]
parallel_safe: false
linked_specs: []
created: 2026-10-06
---
# Plan: fix — anthropic-skill-guide-compliance · Sprint 2 «CLAUDE.md: глобальный, проектный, шаблон»

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem.** Проверка 2026-10-06 трёх инструкций, которые грузятся в каждую сессию, по нашим правилам
(`rules/RULES.md`, канон из `opus55-prompt-fit` Stage 3–4) и по [Claude Code memory](https://code.claude.com/docs/en/memory):
«target under 200 lines», «only facts Claude should hold in every session; multi-step procedure → skill»,
«if two instructions contradict each other, Claude may pick one arbitrarily».

**Глобальный `~/.claude/CLAUDE.md`** (рендер `rules/CLAUDE-GLOBAL.md`, 88 строк, 12 КБ; с исходником синхронен):
- G1. ~45 строк — процедуры Memory Bank (session pipeline, codebase map, opt-in слои графа, профили,
  privacy, native memory). Грузятся в **каждый** проект, включая проекты без банка, и дублируют SKILL.md.
  По доке это материал скила, а не CLAUDE.md.
- G2. Дубли внутри файла: Testing Trophy, TDD, планы — по два раза (`# Engineering rules` и `# Global Rules`).

**Шаблон `references/claude-md-template.md`** (генерирует `/mb init --full`, 148 строк):
- T1. Блок «Critical rules» повторяет глобальные правила → две копии в контексте, и копия уже разошлась с
  каноном: SRP без «warns / blocks only when the change crosses the threshold», DRY «duplicate >2 times».
- T2. `Language — respond in English` зашит → противоречит `--language` установки (у владельца — ru) и блоку
  `mb-language`.
- T3. `If ./.memory-bank/ exists → [MEMORY BANK: ACTIVE]` — уже резолвера (`mb_resolve_path`: local/global/legacy)
  и без «только первый ответ» → противоречит глобальному правилу статус-строки.
- T4. `**MANDATORY**` — регистр давления, который opus55 Stage 3 убрал из остальных файлов.
- T5. Нет главного по доке — команд build/test/lint проекта; зато есть разделы Stack/Conventions, которые
  дублируют `codebase/STACK.md`/`CONVENTIONS.md` (их грузит `/mb context`); иерархия заголовков сломана
  (`## Technology Stack` и `## Languages` одного уровня).
- T6. Таблица маршрутизации графа + jq-пример — третья копия (SKILL.md, CLAUDE-GLOBAL) вопреки
  opus55 Stage 4 «таблица маршрутизации ровно в одном файле».

**Проектный `CLAUDE.md` этого репо** (118 строк, но 34,9 КБ):
- P1. 30,9 КБ (89 %) — `## Active Agreements`: 59 соглашений полным текстом, блок пишет `mb-agree.sh sync`.
  ≈9K токенов в каждой сессии. Тот же блок — в `AGENTS.md`. Это поведение продукта: так же раздувается
  CLAUDE.md у всех пользователей с длинным реестром.
- P2. «Prefer `AGENTS.md` when both exist» — неверно для Claude Code: при наличии `CLAUDE.md` он по умолчанию
  `AGENTS.md` не читает вовсе (memory § AGENTS.md).
- P3. `AGENTS.md` — 80 КБ / 927 строк (копия RULES.md + реестр). Для Codex выше лимита project doc 32 KiB
  (лимит указан в opus55 Stage 5) — хвост с реестром соглашений Codex не видит.

**Expected result.** Глобальный CLAUDE.md ≤ 60 строк без процедур MB и без внутренних дублей; шаблон не
повторяет глобальные правила, не противоречит им и содержит команды проекта; блок соглашений ≤ 4 КБ в любом
проекте; проектные CLAUDE.md/AGENTS.md этого репо в пределах лимитов.

**Related files:** `rules/CLAUDE-GLOBAL.md`, `references/claude-md-template.md`, `commands/mb.md` (§ init Step 4 —
только список секций), `scripts/mb-agree.sh` (рендер блока), `CLAUDE.md`, `AGENTS.md`, тесты
`test_global_prompt_guard.py`, новые `tests/pytest/test_claude_md_template.py`, `tests/bats/test_mb_agree_block_budget.bats`.

**Зависимость.** Sprint 1 Stage 2 должен сначала принять в SKILL.md/справочники то, что G1 выносит из
глобального файла, иначе текст потеряется.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Бюджет блока соглашений (P1)

**What to do:**
- `mb-agree.sh sync`: в управляемый блок CLAUDE.md/AGENTS.md писать индекс, а не полный текст:
  `- AGR-NNN: <первое предложение, ≤ 140 симв.>…`; общий бюджет блока 4 096 байт; при переполнении —
  последние N по номеру + строка `… ещё K → /mb agree list`. Полный текст остаётся в `agreements.md` (SSOT).
- Флаг/конфиг для старого поведения не добавлять (YAGNI); изменение — в CHANGELOG.

**Testing (TDD — tests BEFORE implementation):**
- bats: реестр из 60 соглашений по 600 симв. → блок ≤ 4 096 байт, все ID последних N присутствуют, хвостовая строка есть.
- bats: соглашение короче 140 симв. рендерится без `…`; повторный `sync` идемпотентен (байт-в-байт).
- существующие тесты `mb-agree` зелёные (маркеры, preflight).

**DoD (Definition of Done):**
- [x] новые bats красные до правки, зелёные после
- [x] `CLAUDE.md` этого репо после `mb-agree.sh sync` ≤ 10 КБ (`wc -c`)
- [x] `shellcheck scripts/mb-agree.sh` чистый

**Code rules:** SRP — рендер отдельной функцией; файл не перевалить за 300 строк сверх текущего.

---

<!-- mb-stage:2 -->
### Stage 2: Шаблон проектного CLAUDE.md (T1–T6)

**What to do:**
- `references/claude-md-template.md`:
  - удалить блок «Critical rules» → одна строка: «Engineering rules — global `~/.claude/CLAUDE.md`
    + `~/.claude/RULES.md`; project overrides below»; раздел `## Project rules` для отличий проекта;
  - удалить `Language — respond in English` (язык задаёт установка / `mb-language`);
  - статус-строку не дублировать — она в глобальном файле;
  - `MANDATORY` → обычный тон с причиной;
  - добавить `## Commands` (`{BUILD_CMD}`, `{TEST_CMD}`, `{LINT_CMD}`, `{RUN_CMD}`) первым после Project;
  - Stack/Conventions → 3–5 строк фактов, которые не выводятся из кода, + ссылка на `codebase/*.md`;
  - маршрутизацию графа и jq-пример заменить ссылкой на SKILL.md;
  - починить иерархию заголовков; цель ≤ 80 строк в отрендеренном виде.
- `commands/mb.md` § init Step 4 — синхронизировать список обязательных секций (только этот подраздел;
  файл в зоне opus55 Stage 6 — согласовать через `COORDINATION.md`, AGR-032/033).

**Testing (TDD):**
- pytest `test_claude_md_template.py`: в шаблоне нет `respond in English`, `MANDATORY`, `MEMORY BANK: ACTIVE`,
  `jq -r`; есть `## Commands`; формулировки SRP/DRY/TDD отсутствуют (не дублируются); заголовки — корректная
  иерархия; отрендеренный пример ≤ 80 строк.

**DoD:**
- [x] тест красный на e351a17, зелёный после
- [x] `/mb init --full` в `tmp`-проекте (python + pytest) даёт CLAUDE.md ≤ 80 строк с заполненными командами (проверено детерминированным рендером шаблона — 37 строк, 0 плейсхолдеров; живой интерактивный прогон `/mb init --full` не делался)

**Code rules:** DRY — одно правило в одном месте; KISS.

---

<!-- mb-stage:3 -->
### Stage 3: Глобальный CLAUDE-GLOBAL.md (G1, G2)

**What to do:**
- Вынести процедуры MB (§ Session Pipeline, Codebase Map & Code Graph, Personalization/privacy/native memory,
  детали `/mb work`) в SKILL.md/справочники Sprint 1 — **дословно**, с `--compare`.
- Оставить: статус-строку, rules-only mode, engineering rules (один раз), «где детали» (3–5 строк: `/mb`,
  `~/.claude/RULES.md`, проектный `RULES.md`), инварианты, без которых сломается работа до вызова скила
  (append-only `progress.md`, COORDINATION, `mb-agree` протокол — по одной строке).
- Убрать внутренние дубли (G2).
- Пользовательские правила владельца («всегда…», «никогда…») переносятся слово в слово.

**Testing (TDD):**
- `test_global_prompt_guard.py` + новые проверки: ≤ 60 строк; «Testing Trophy», «TDD —» встречаются по одному разу;
  рендер для 8 клиентов без потери маркеров (существующий тест).
- `--compare` старой и новой версии: каждая потерянная строка найдена в SKILL.md/references.

**DoD:**
- [x] `rules/CLAUDE-GLOBAL.md` ≤ 60 строк, тесты зелёные
- [x] 0 строк потеряно (вне перечисленных в отчёте)
- [x] переустановка во временном `HOME` (`install.sh`) идемпотентна, блок пересобран между маркерами

**Code rules:** Clean Architecture инструкций — всегда-загруженное только то, что нужно в каждой сессии.

---

<!-- mb-stage:4 -->
### Stage 4: Проектные CLAUDE.md / AGENTS.md этого репо (P2, P3)

> **P3 перенесён в план `2026-10-06_fix_agents-md-diet.md` (AGR-063).** Здесь остаётся только P2 — правка Compatibility Notes в `CLAUDE.md`.

**What to do:**
- `CLAUDE.md` § Compatibility Notes: заменить «Prefer AGENTS.md when both exist» на факт — Claude Code при
  наличии CLAUDE.md читает только его; общие правила для других агентов — в AGENTS.md.
- `AGENTS.md`: проверить фактический лимит Codex (`project_doc_max_bytes`) по актуальной доке Codex; если
  32 KiB — привести файл в лимит: копию RULES.md заменить ссылкой на `rules/RULES.md`, реестр — индекс Stage 1.

**Testing (TDD):**
- pytest: `AGENTS.md` ≤ лимита Codex (константа с источником в комментарии), `CLAUDE.md` ≤ 200 строк и ≤ 10 КБ.

**DoD:**
- [x] тест зелёный; источник лимита Codex указан ссылкой в отчёте (2026-10-07: `test_repo_instruction_budget.py`
  2 passed; `codex-rs/config/defaults.toml` → `reports/2026-10-06_sprint2-instructions.md` § Stage 4)
- [x] `scripts/mb-drift.sh .` без новых находок (2026-10-07: только `plan_vs_git` на 12 планов — тот же список
  на снимке HEAD, находка была до этого этапа)

**Code rules:** не трогать чужую незакоммиченную работу в этих файлах (AGR-033) — сверить `git diff` перед правкой.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Без полного текста соглашений в CLAUDE.md агент нарушит решение, которое раньше видел | M | Индекс несёт суть в первом предложении; `/mb recall` и `/mb agree list` уже ищут по реестру; A/B на сценарии «реши задачу, где действует AGR-NNN» |
| Сокращение глобального CLAUDE.md ослабит правила в проектах без банка (rules-only mode) | M | Engineering rules остаются в глобальном файле целиком; выносится только MB-процедура |
| Изменение шаблона не затронет уже сгенерированные CLAUDE.md пользователей | H | Записать в CHANGELOG; `/mb init --full` на существующем CLAUDE.md предлагает diff (уже показывает черновик) |
| Конфликт с opus55 Stage 6 по `commands/mb.md` | M | Правим только § init Step 4; координация через `COORDINATION.md` |

## Gate (plan success criterion)

Во всегда-загружаемом контексте этого репо (глобальный + проектный CLAUDE.md) ≤ 20 КБ против 47 КБ на e351a17,
ни одной противоречащей пары правил между глобальным файлом и отрендеренным шаблоном (тест Stage 2), все
тесты Sprint 2 зелёные, полный pytest/bats без новых красных.
