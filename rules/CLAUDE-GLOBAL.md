# CRITICAL RULES — НЕ ЗАБЫВАТЬ ПРИ COMPACTION

> **Contract-First** — Protocol/ABC → contract-тесты → реализация. Тесты проходят для ЛЮБОЙ корректной реализации.
> **TDD** — сначала тесты, потом код. Пропуск: только опечатки, форматирование, exploratory prototypes.
> **Clean Architecture (backend)** — `Infrastructure → Application → Domain` (никогда обратно). Domain = 0 внешних зависимостей.
> **FSD (frontend)** — Feature-Sliced Design для React/Vue/Angular. Слои сверху вниз: `app → pages → widgets → features → entities → shared`. Импорт строго вниз; cross-slice внутри слоя — через widget/page; public API каждого slice — через `index.ts`.
> **Mobile (iOS/Android)** — UDF + Clean слои: `View → ViewModel → UseCase → Repository (SSOT) → DataSource`. iOS: SwiftUI + `@Observable`, `async/await`, SwiftData, SPM feature-модули. Android: Jetpack Compose + StateFlow + Hilt + Room, Gradle multi-module, Google Recommended Architecture. Immutable UI state, DI через protocols/interfaces.
> **SOLID пороги** — SRP: >300 строк или >3 публичных метода разной природы = разделить. ISP: Interface ≤5 методов. DIP: конструктор принимает абстракцию.
> **DRY / KISS / YAGNI** — дубль >2 раз → извлечь. Три одинаковых строки лучше преждевременной абстракции. Не писать код "на будущее".
> **Testing Trophy** — интеграционные > unit > e2e. Mock только внешние сервисы. >5 mock'ов → кандидат на интеграционный.
> **Качество тестов** — имя: `test_<что>_<условие>_<результат>`. Assert = бизнес-факт. Arrange-Act-Assert. `@parametrize` вместо копипасты.
> **Coverage** — общий 85%+, core/business 95%+, infrastructure 70%+.
> **Fail Fast** — не уверен → план 3-5 строк, спроси.
> **Язык** — ответы на русском, техтермины на английском.
> **Без placeholder'ов** — никаких TODO, `...`, псевдокода. Код copy-paste ready. Исключение: staged stub за feature flag с docstring.
> **Планы** — подробные DoD (SMART) на каждый этап, требования по TDD и нашим правилам кода, сценарии проверки, edge cases.
> **Защищённые файлы** — `.env`, `ci/**`, Docker/K8s/Terraform — не трогать без запроса.
> **Подробные правила:** `~/.claude/RULES.md` + `RULES.md` в корне проекта.


---

# Global Rules

## Coding
- No new libraries/frameworks without explicit request
- New business logic → tests FIRST, then implementation
- Full imports, valid syntax, complete functions — copy-paste ready
- Multi-file changes → план сначала
- Specification by Example: требования как конкретные входы/выходы = готовые test cases
- Рефакторинг через Strangler Fig: поэтапно, тесты проходят на каждом шаге
- Значимое решение → ADR (контекст → решение → альтернативы → последствия)
— У каждой задачи которую ты пишешь, должны быть критерии готовности (по SMART) которые ты проверяешь (DoD)

## Testing — Testing Trophy
- **Покрытие тестами:**: 85%+ (core 95%+, infrastructure 70%+)
- **Интеграционные (основной фокус):** реальные компоненты вместе, mock только внешнее
- **Unit (вторичный):** чистая логика, edge cases. 5+ mock'ов → кандидат на интеграционный
- **E2E (точечно):** только критические user flows
- **Static:** go vet, golangci-lint, type checking — всегда

## Reasoning
- Complex tasks: analysis → plan → implementation → verification
- Before editing: search the project, don't guess
- Response format: Цель → Действие → Результат
- Destructive actions — only after explicit confirmation
- Do not expand scope without request

## Planning

When creating plans (including built-in plan mode):
- Write plans to `./.memory-bank/plans/` if Memory Bank active
- Every stage has DoD criteria by SMART
- Every stage has test requirements BEFORE implementation (TDD)
- Tests: unit + integration + e2e where applicable
- Stages are atomic and ordered by dependencies


## Memory Bank

**Если `./.memory-bank/` существует → `[MEMORY BANK: ACTIVE]`.**
Если, папки нет, создай ее с внутренней структурой. и напиши `[MEMORY BANK: INITIALIZED]`

**Skill:** `memory-bank`. **Команда:** `/mb`. **Subagent:** MB Manager (sonnet).
**Глобальные правила**: `~/.claude/RULES.md` (TDD, SOLID, DRY, KISS, YAGNI, Clean Architecture, Testing Trophy, MB workflow — для ВСЕХ проектов)
**Проект-специфичные правила**: `RULES.MD` в корне проекта
**Шаблоны**: `~/.claude/skills/memory-bank/references/templates.md`
**Workflow**: `~/.claude/skills/memory-bank/references/workflow.md`

### Команды /mb

| Команда | Описание |
|---------|----------|
| `/mb` или `/mb context` | Собрать контекст проекта (статус, чеклист, план) |
| `/mb start` | Расширенный старт сессии (контекст + активный план целиком) |
| `/mb search <query>` | Поиск информации в банке по ключевым словам |
| `/mb note <topic>` | Создать заметку по теме |
| `/mb update` | Актуализировать core files (checklist, plan, status) |
| `/mb tasks` | Показать незавершённые задачи |
| `/mb index` | Реестр всех записей (core files + notes/plans/experiments/reports) |
| `/mb done` | Завершение сессии (actualize + note + progress) |
| `/mb plan <type> <topic>` | Создать план (type: feature, fix, refactor, experiment) |
| `/mb verify` | Верификация плана vs код. **ОБЯЗАТЕЛЬНО** перед `/mb done` если работа по плану |
| `/mb init` | Инициализировать Memory Bank в новом проекте |

### Ключевые правила

- progress.md = **append-only** (никогда не удалять/редактировать старое)
- Нумерация сквозная: H-NNN, EXP-NNN, ADR-NNN (не переиспользовать)
- notes/ = знания и паттерны (5-15 строк), **не хронология**. Не создавать для тривиальных изменений
- reports/ = подробные отчёты, полезные будущим сессиям (анализ, post-mortem, сравнения)
- checklist: ✅ = done, ⬜ = todo. Обновлять **сразу** при завершении задачи

**Путь**: `./.memory-bank/`

### Структура

**Ядро (читать каждую сессию):**

| Файл | Назначение | Когда обновлять |
|------|-----------|-----------------|
| `STATUS.md` | Где мы, roadmap, ключевые метрики, gates | Завершён этап, сдвинулся roadmap, изменились метрики |
| `checklist.md` | Текущие задачи ✅/⬜ | Каждую сессию, сразу при завершении задачи |
| `plan.md` | Приоритеты, направление | Когда меняется вектор/фокус |
| `RESEARCH.md` | Реестр гипотез + findings + текущий эксперимент | При изменении статуса гипотезы или нового finding |

**Детальные записи (читать по запросу):**

| Файл / Папка | Назначение | Когда обновлять |
|--------------|-----------|-----------------|
| `BACKLOG.md` | Идеи, ADR, отклонённое | Когда появляется идея или архитектурное решение |
| `progress.md` | Выполненная работа по датам | Конец сессии (append-only) |
| `lessons.md` | Повторяющиеся ошибки, антипаттерны | Когда замечен паттерн |
| `experiments/` | `EXP-NNN_<n>.md` — ML эксперименты | При завершении эксперимента |
| `plans/` | `YYYY-MM-DD_<type>_<n>.md` — детальные планы | Перед сложной работой |
| `reports/` | `YYYY-MM-DD_<type>_<n>.md` — отчёты | Когда полезно будущим сессиям |
| `notes/` | `YYYY-MM-DD_HH-MM_<тема>.md` — заметки | По завершении задачи (знания, не хронология) |


### Workflow (кратко)

**Старт**: `/mb start` → читать 4 core files (STATUS, checklist, plan, RESEARCH) → резюме фокуса.
**Работа**: checklist.md обновлять сразу (⬜→✅). STATUS.md — при milestone/метриках. RESEARCH.md — при изменении гипотез.
**Конец**: `/mb verify` (если план) → `/mb done` (checklist + progress + note + STATUS/RESEARCH если нужно).
**Перед compaction**: `/mb update` чтобы не потерять прогресс.
