---
type: report
date: 2026-05-23
topic: anthropic-best-practices-audit
scope: skill design + dev-workflow effectiveness + vibe-coding fit
sources:
  - https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
  - https://code.claude.com/docs/en/best-practices
  - https://code.claude.com/docs/en/sub-agents
  - https://code.claude.com/docs/en/memory
---

# Memory-Bank Skill — Anthropic Best-Practices Audit

## TL;DR

Memory-Bank — это **не "skill" в строгом смысле Anthropic**, а **бандл "skill + slash-commands + subagents + hooks + CLI"**. По формальным критериям SKILL-авторинга он близко к границе допустимого (367 / 500 строк), а по архитектуре workflow — **существенно перевыполняет** официальные рекомендации Anthropic по дисциплине (TDD, verify-before-completion, evidence over assertions, Explore→Plan→Implement). Главные риски — **избыточная церемония для коротких задач (vibe coding)**, **раздутый user-level CLAUDE.md**, и **слишком агрессивный auto-context inject** на sessionStart.

**Вердикт:** для проектов с регулярной командой и долгим горизонтом — **сильно выше базлайна Claude Code**. Для одиночного vibe-coding — **рекомендую rules-only mode + минимальный профиль**, иначе ceremony tax съест выгоду.

---

## 1. Соответствие Anthropic skill-авторинг гайдлайну

| Критерий Anthropic                                               | Наш скил                                                                                    | Статус |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------ |
| `name` ≤ 64 chars, kebab-case, без reserved words                | `memory-bank` (10 chars)                                                                    | ✅      |
| `description` ≤ 1024 chars, third person, what + when            | Покрывает оба измерения, написано в третьем лице                                            | ✅      |
| **SKILL.md body ≤ 500 lines**                                    | **367 lines** — в пределах, но загружено: 3 больших таблицы (scripts/agents/hooks)          | ⚠️     |
| Progressive disclosure — references on demand                    | `references/*.md` загружаются по требованию; SKILL.md действительно служит "table of contents" | ✅      |
| Refs **one level deep** от SKILL.md                              | Соблюдено (нет цепочек `SKILL.md → A.md → B.md`)                                            | ✅      |
| Gerund-naming (`processing-pdfs`, `analyzing-spreadsheets`)      | Noun phrase (`memory-bank`); Anthropic явно допускает как acceptable alternative            | ⚠️     |
| Consistent terminology                                           | Соблюдено (status / plan / checklist / progress — стабильный словарь)                       | ✅      |
| Skill решает реальный gap, а не имитирует                        | Проверено evals-style: `index.json`, `progress.md`, `lessons.md` — реальная агент-память    | ✅      |
| Avoid "too many options"                                         | **25 slash-команд** + 16 subagents + 56 scripts — выходит за рекомендуемый объём            | ❌      |
| Avoid time-sensitive info                                        | CHANGELOG отдельно; в SKILL.md дат нет                                                      | ✅      |
| Scripts solve problems vs punt to Claude                         | `mb-test-run.sh` парсит вывод 12 stacks → строгий JSON; явные exit-коды                     | ✅      |
| MCP fully-qualified names                                        | Не использует MCP внутри SKILL.md                                                           | n/a    |

**Главный риск формы:** 367 строк уже близки к 500-строчному порогу Anthropic, при этом ~40% объёма — справочные таблицы. Anthropic явно пишет «keep SKILL.md body under 500 lines» и «if your content exceeds this, split using progressive disclosure» — мы около границы и продолжаем расти.

---

## 2. Соответствие Claude Code dev-workflow рекомендациям

### 2.1. Что точно совпадает с Anthropic — наши сильные стороны

1. **"Give Claude a way to verify its work" (the single highest-leverage thing)**
   `/mb verify` + `plan-verifier` + `mb-test-runner` + структурный JSON-вердикт ровно реализует это. Anthropic: *"a test suite, a linter, or a Bash command that checks output. Invest in making your verification rock-solid"* — это про нас.
2. **"Explore first, then plan, then code"**
   Полный цикл `/mb start → /mb plan → work → /mb verify → /mb done` повторяет Explore→Plan→Implement→Commit. SDD-цикл (`/mb discuss → /mb sdd → /mb work`) — ещё строже.
3. **"Address root causes, not symptoms"**
   В RULES.md и `mb-rules-enforcer` встроен запрет на placeholders / TODO / `--no-verify`. Заложено хуком и проверками.
4. **"Subagents preserve context"**
   16 специализированных subagents для изолированной работы (review, verify, codebase-map) — учебниковый кейс из доков Anthropic.
5. **Token economy (`design-principles.md` § Token economy)**
   `MB_WORK_MODE=slim` default, `--budget` flag, `mb-session-spend.sh`, cached verifier verdicts, `skip_if` в pipeline — **сильнее**, чем рекомендует Anthropic. Anthropic говорит "context window is a public good" — мы прямо это инструментируем.
6. **Native auto-memory vs Memory Bank — корректное разделение**
   В SKILL.md явно: *"This skill does not replace it — the two complement each other"*. Anthropic в `/docs/en/memory` подтверждает: CLAUDE.md = user-written rules, auto-memory = Claude-written learnings. Наш `.memory-bank/` = team-scoped artefacts. Три уровня не конкурируют.

### 2.2. Что расходится с Anthropic и требует внимания

#### A. **CLAUDE.md size — нарушение явного лимита**

Anthropic: *"Size: target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence."* и *"Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"*

Наш user-level `~/.claude/CLAUDE.md` для `[MEMORY-BANK-SKILL]` блока сейчас ~190 строк (формально на грани), при этом он грузится в **каждый** Claude Code сеанс на машине пользователя, **даже** в проектах без `.memory-bank/`. Это противоречит принципу "rules-only" — пользователь платит токенами за функцию, которой может не пользоваться.

Anthropic явный совет: *"For each line, ask: Would removing this cause Claude to make mistakes? If not, cut it."*

**Что у нас лишнее в global CLAUDE.md:**
- Список `/mb` команд (≈10 строк) — уже есть в SKILL.md, который грузится по триггеру
- Раздел "When to read the detailed rules" — это рутинг, который сам агент должен делать через progressive disclosure
- Подробный layer model (можно ужать до 1 строки)

#### B. **Too many options**

Anthropic: *"Avoid offering too many options. Don't present multiple approaches unless necessary."*

У нас:
- `/plan` и `/mb plan` — почти эквивалентны
- `/done`, `/mb done` — то же
- `/discuss` → `/sdd` → `/work` vs прямой `/plan` → `/work` — два параллельных трека для одной задачи "формализовать фичу"
- `/commit` vs `/pr` vs `/changelog` — разные стадии одного git-flow

Для опытного пользователя — ок (есть короткий и длинный путь). Для нового — confusion: какой выбрать? Anthropic советует "provide a default with escape hatch", а не равноправные опции.

#### C. **Aggressive sessionStart context injection**

`mb-session-start-context.sh` (Cursor) автоматически инжектит компактный memory-bank контекст при старте сессии. Anthropic в best-practices: *"Manage context aggressively. Run /clear between unrelated tasks to reset context."* Авто-инжект **противоречит** этой логике — пользователь, который явно начал новую тему, всё равно получит контекст прошлой работы.

`MB_AUTOLOAD_CONTEXT=off` есть, но дефолт = `auto`. По Anthropic «default = unchanged behavior» — у нас дефолт = behaviour change.

#### D. **Hook footprint vs sanctioned use case**

Anthropic: *"Use hooks for actions that must happen every time with zero exceptions. ... Hooks are deterministic and guarantee the action happens."*

Из 10 хуков:
- ✅ `mb-protected-paths-guard.sh`, `block-dangerous.sh`, `mb-ears-pre-write.sh` — точно "must happen every time"
- ⚠️ `session-end-autosave.sh`, `mb-compact-reminder.sh`, `mb-session-start-context.sh` — convenience, не safety. По Anthropic это лучше **slash-команды**, а не хуки, потому что хук всегда выполняется без контроля юзера.

#### E. **Ceremony tax для коротких задач**

Anthropic: *"Plan mode is useful, but also adds overhead. For tasks where the scope is clear and the fix is small (like fixing a typo, adding a log line, or renaming a variable) ask Claude to do it directly. If you could describe the diff in one sentence, skip the plan."*

Наш `/mb work` по дефолту запускает review-loop, severity-gate, test-runner. Для двухстрочного фикса — overkill. У нас **есть** `skip_if` в pipeline.yaml и `--budget` — но это не дефолт, и vibe-coder его не настроит до того, как почувствует tax.

---

## 3. Vibe coding — отдельная плоскость

Vibe coding = быстрая итерация, "tell Claude what to do, accept reasonable defaults, course-correct via `Esc + Esc`".

| Pattern Anthropic для vibe coding              | Memory-Bank behaviour                                                          |
| ---------------------------------------------- | ------------------------------------------------------------------------------ |
| Skip plan-mode для одно-строчных диффов        | По умолчанию `/mb work` идёт через plan + review + verify                      |
| `/rewind` / `Esc Esc` чтобы откатиться         | `/mb` не интегрирован с checkpoints — приходится править MB вручную            |
| `/clear` между задачами                        | Auto-inject контекста пересиливает чистоту нового сеанса                       |
| "Trust then verify gap" → провайдить tests     | ✅ Это наша сильная сторона                                                     |
| Subagents для investigation                    | ✅ Идеально (`mb-codebase-mapper`, `mb-doctor`)                                 |
| Course-correct early                           | Plan-verifier не запускается до `/mb done` — фидбек в конце, а не early        |

**Вывод по vibe coding:**
- Скил **отличный, если человек явно перешёл из vibe в discipline mode** (фича на день+, два инженера, есть PR).
- Скил **мешает, если задача — "поменять цвет кнопки, закоммитить и забыть"**. Нужно либо `[MEMORY BANK: ABSENT]` (rules-only), либо `minimal` install-profile.

Кстати, наш `[MEMORY BANK: ABSENT]` rules-only режим **очень хорошо ложится** на vibe-coding: TDD-дисциплина остаётся, ceremony — нет. Это документировано, но **не выпячено**. Имеет смысл подсветить.

---

## 4. Конкретные риски и где они проявятся

1. **CLAUDE.md adherence degradation**
   Anthropic явно предупреждает: длинный CLAUDE.md → "Claude ignores half of it". Наш ~190-строчный блок в global CLAUDE.md находится в красной зоне. Симптом: модель пропускает первую строку `[MEMORY BANK: ACTIVE]` или скипает Memory-Bank workflow в проектах с активным банком.

2. **Trigger spam**
   Description триггерит на упоминание "memory-bank", "code rules", "dev-toolkit". В проектах вне memory-bank скил всё равно может подгружаться на словах вроде "rules" или "workflow". Anthropic советует description **писать узко**, чтобы skill не самоактивировался.

3. **Subagent over-dispatch**
   16 субагентов; некоторые (`mb-developer`, `mb-architect`, `mb-backend`, `mb-frontend`, `mb-ios`, `mb-android`, ...) overlap. Anthropic: *"Define a custom subagent when you keep spawning the same kind of worker with the same instructions."* — у нас 8 ролевых subagents на случай «вдруг понадобится», это противоречит "create when you actually keep spawning".

4. **Скрипты как реальное приложение, не «утилитка»**
   56 shell/python скриптов = это уже **отдельный CLI продукт**, который нужно тестировать, документировать, версионировать. Anthropic-style skill — это набор markdown + опциональные scripts. Наша архитектура ближе к "MCP-like backend with markdown frontend". Это не ошибка, но позиционирование "skill" может вводить в заблуждение.

5. **Override default behaviour без явного opt-in**
   Из superpowers system reminder: *"Superpowers skills override default system prompt behavior."* — Anthropic не одобряет такое в явной форме. Наш скил не делает silent override (есть `[MEMORY BANK: ABSENT]` и rules-only), но **default install** включает много хуков сразу — это в зоне риска.

---

## 5. Что Anthropic явно одобряет и что у нас отлично

| Anthropic-принцип                                                  | Memory-Bank                                                                                        |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| "Create verifiable intermediate outputs"                           | Plan-verifier вердикт — JSON; review-loop — структурный JSON; tasks с `<!-- mb-task:N -->` маркерами |
| "Plan-validate-execute pattern catches errors early"               | `/mb work` per-stage `implement → review → fix → verify` цикл                                      |
| "Make validation scripts verbose with specific error messages"     | `mb-test-runner` возвращает per-failure `{file, name, error_head}`                                 |
| "Workflows have clear steps" + checkbox tracking                   | `checklist.md` с ⬜/✅; `<!-- mb-stage:N -->` маркеры в планах                                      |
| "Test with all models you plan to use" (Haiku/Sonnet/Opus)         | Не вижу свидетельств — это **gap**, стоит формализовать в CONTRIBUTING                              |
| "Build evaluations first"                                          | bats + pytest, но evals для самого skill-discovery нет — **gap**                                    |

---

## 6. Рекомендации (prioritised)

### P1 — high impact, low risk

1. **Сократить global `~/.claude/CLAUDE.md` блок `[MEMORY-BANK-SKILL]` до ≤80 строк.**
   Убрать дублирование команд (они в SKILL.md), убрать layer-model, оставить только: status semantics (3 строки), "before final answer verify" checklist (3 строки), указатель на `~/.claude/RULES.md`. Поле сэкономит токены **в каждой** сессии Claude Code пользователя.

2. **Подсветить `rules-only` режим как first-class vibe-coding option.**
   Сейчас он в SKILL.md упомянут вскользь. Сделать в README отдельный раздел "Vibe coding mode" с инструкцией: "не запускайте `/mb init` — rules остаются, ceremony отключается".

3. **Дефолт `MB_AUTOLOAD_CONTEXT=off`** (или хотя бы вынести в interactive вопрос на `install.sh`).
   Соответствует принципу `design-principles.md § default = unchanged behavior`.

### P2 — medium impact, требует решения

4. **Ревизия 25 slash-команд:**
   - Объединить `/done` ↔ `/mb done`, `/plan` ↔ `/mb plan` в один canonical + alias.
   - В CLAUDE.md/README обозначить **default path** (`/mb plan → /mb work → /mb verify → /mb done`) и **advanced path** (`/discuss → /sdd → /work`).
5. **Сократить число ролевых subagents.**
   Объединить `mb-ios + mb-android` → `mb-mobile`, `mb-frontend + mb-backend` оставить, остальные специализации (`mb-devops`, `mb-qa`, `mb-analyst`) — выгрузить в lazy-load reference, активировать только когда `pipeline.yaml:agents` явно указан. Anthropic: subagent создаётся когда повторяется паттерн, а не "на будущее".
6. **Перевести convenience-хуки в slash-команды:**
   - `mb-compact-reminder.sh` → `/mb compact-check`
   - `session-end-autosave.sh` → опционально через `/mb done --auto` или env-флаг
   Оставить как хуки только safety (`protected-paths`, `block-dangerous`, `ears-pre-write`).

### P3 — low impact, гигиена

7. **Описать skill testing matrix** (Haiku/Sonnet/Opus) в `CONTRIBUTING.md` — Anthropic требует это явно.
8. **Добавить `evaluations/` директорию** с 3+ сценариями skill-discovery (по чек-листу Anthropic).
9. **Уплотнить SKILL.md** — таблицы script-by-script и agent-by-agent вынести в `references/scripts-index.md` / `references/agents-index.md`. Цель: SKILL.md ≤ 250 строк, чисто guidance + навигация.
10. **Узкое description.**
    Текущее: "Use when working in a project with a `.memory-bank/` directory or when the user explicitly asks for memory-bank workflow, code rules, or dev-toolkit commands."
    Проблема: "code rules" слишком обще — триггерит почти везде. Лучше: "...or when the user explicitly types `/mb`, `/plan`, `/done`, `/work`, or asks about TDD/Clean Architecture rules in a project with `RULES.md`."

---

## 7. Оценка эффективности — по 5 измерениям

| Измерение                                  | Балл  | Комментарий                                                                                          |
| ------------------------------------------ | :---: | ---------------------------------------------------------------------------------------------------- |
| **Skill-формат (Anthropic compliance)**    | 7/10  | SKILL.md в пределах, но загружен; description широкий; 25 команд — много                              |
| **Engineering discipline (TDD/verify)**    | 9/10  | Выше базлайна Anthropic. Plan-verifier и test-runner — образцовая реализация evidence-over-assertions |
| **Token economy**                          | 8/10  | Сильный фреймворк (slim mode, budget); портится длинным global CLAUDE.md                              |
| **Vibe-coding fit**                        | 5/10  | Ceremony tax; rules-only режим спасает, но не выпячен                                                 |
| **Maintenance / consistency**              | 8/10  | `index.json`, `mb-doctor`, `mb-drift.sh` — реальная дисциплина. Тесты на скрипты есть                 |
| **Average**                                | **7.4/10** | Выше Claude Code baseline для команд; средне для одиночного vibe-coding                                |

---

## 8. Что делать дальше — короткий план действий

1. **Сейчас (≤1 час):** ужать global CLAUDE.md блок `[MEMORY-BANK-SKILL]` до 80 строк.
2. **Эта неделя:** P1 пункты (vibe-coding mode в README + `MB_AUTOLOAD_CONTEXT=off` default).
3. **Следующий sprint:** P2 (ревизия команд + ролевых subagents + переезд convenience-хуков в команды).
4. **Backlog:** P3 (eval suite, testing matrix, SKILL.md slim).

Если этих изменений не делать — скил продолжит работать на текущем уровне (7.4/10), но **по мере добавления новых фичей** SKILL.md и CLAUDE.md упрутся в Anthropic-пороги (500 / 200 строк) и потеряют adherence. Лучше заранее.

---

## Источники (verbatim quotes — для traceability)

- *"Concise is key. The context window is a public good."* — Anthropic best-practices
- *"Keep SKILL.md body under 500 lines for optimal performance."* — Anthropic best-practices
- *"Bloated CLAUDE.md files cause Claude to ignore your actual instructions!"* — Claude Code best-practices
- *"Size: target under 200 lines per CLAUDE.md file."* — Claude Code memory docs
- *"Use hooks for actions that must happen every time with zero exceptions."* — Claude Code best-practices
- *"Plan mode is useful, but also adds overhead. If you could describe the diff in one sentence, skip the plan."* — Claude Code best-practices
- *"Give Claude a way to verify its work. This is the single highest-leverage thing you can do."* — Claude Code best-practices
- *"Define a custom subagent when you keep spawning the same kind of worker with the same instructions."* — Sub-agents docs
- *"Avoid offering too many options. Don't present multiple approaches unless necessary."* — Skill authoring best-practices
- *"Build evaluations BEFORE writing extensive documentation."* — Skill authoring best-practices
