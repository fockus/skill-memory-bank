# Global Rules

> Универсальные правила кодирования и процесса.
> Применяются ко ВСЕМ проектам. Проект-специфичные правила — в `RULES.MD` корня проекта.

---

## CRITICAL — нарушение = провал

1. **Язык**: русский — ответы и комментарии в коде. Техтермины на английском.
2. **Код без заглушек**: никаких `...`, `TODO`, `pass` (исключение: staged stubs за feature flag с docstring)
3. **Деструктивные действия — только после "go"**
4. **Защищённые файлы** (`.env`, `ci/**`, Docker/K8s/Terraform) — не трогать без запроса
5. **Новая логика = тесты FIRST** (TDD)
6. **Принципы**: TDD / SOLID / DRY / KISS / YAGNI / Clean Architecture — без исключений
7. **Contract-First**: интерфейс → contract-тесты → реализация
8. **Fail Fast**: не уверен в направлении → план на 3-5 строк, спроси
9. **RULES.md — обязательный стандарт**: ВСЯ работа ОБЯЗАНА следовать правилам из этого файла + проектного `RULES.MD`. Не рекомендация, а hard requirement.

---

## Source of Truth — цепочка планирования

Если в проекте есть Memory Bank (`.memory-bank/`), планирование и реализация работают через единую цепочку:

```
plan.md (поле "Active plan" → ссылка на файл)
    ↓
plans/<файл>.md  ← Source of truth: задачи, DoD, этапы
    ↓
checklist.md     ← Трекинг: ✅ закрыто, ⬜ осталось
    ↓
STATUS.md        ← Фаза, blockers, audit findings
```

### Правила консистентности

1. **Новый план** (`/mb plan`) ОБЯЗАН быть отражён во ВСЕХ трёх местах:
   - `plans/<файл>.md` — детальный план с DoD
   - `plan.md` — ссылка в поле "Active plan" + обновлённый фокус
   - `STATUS.md` — обновлённый roadmap (секция "В процессе")
   - `checklist.md` — задачи из плана как ⬜ пункты
2. **Задачи берутся ТОЛЬКО из детального плана**. Не придумывать задачи вне плана.
3. **checklist.md отражает план**: каждый этап из `plans/<файл>.md` = ⬜ пункт в checklist.
4. **STATUS.md отражает факты**: roadmap обновляется при реальном завершении, не при планировании.
5. **При смене активного плана**: обновить plan.md + STATUS.md + checklist.md.
6. **При завершении плана**: перенести в `plans/done/`, обновить plan.md, STATUS.md, checklist.md.

---

## Архитектура

### Clean Architecture

**Направление зависимостей**: `Infrastructure → Application → Domain` (никогда обратно).
Запрещено: импорт из infrastructure в application/domain.

**Слои:**

- **Domain**: types, protocols, business logic. Нет зависимостей от внешних библиотек (кроме stdlib)
- **Application**: use cases, orchestrators. Зависит от Domain
- **Infrastructure**: frameworks, DB, HTTP, файловая система. Зависит от Application и Domain

### SOLID

- **SRP** (Single Responsibility): один модуль = одна причина для изменения. >3 публичных методов разной природы = нарушение. Класс с >300 строк — кандидат на разделение
- **OCP** (Open/Closed): расширять через композицию и Strategy pattern, не правкой существующего кода. Новое поведение = новый класс, не `if-else` в старом
- **LSP** (Liskov Substitution): подкласс должен работать везде, где работает родитель. Нарушение: переопределение метода с другой семантикой
- **ISP** (Interface Segregation): Protocol/Interface ≤5 методов. Клиент не должен зависеть от методов, которые не использует. Толстый интерфейс → разбить на несколько тонких
- **DIP** (Dependency Inversion): зависимость от Protocol/ABC, не от конкретных классов. Конструктор принимает абстракцию, фабрика создаёт конкретику

### DRY / KISS / YAGNI

- **DRY**: дублирование >2 раз → извлечь в функцию/класс. НО: не извлекать если совпадение случайное (разные домены, разные причины изменения)
- **KISS**: простое решение предпочтительнее сложного. Три одинаковых строки лучше преждевременной абстракции. Если решение требует объяснения — оно слишком сложное
- **YAGNI**: не писать код "на будущее". Не добавлять feature flags, конфигурацию, абстракции для гипотетических требований. Добавлять только когда нужно СЕЙЧАС

### Training / Inference separation (ML проекты)

- `nn.Module` = только `forward()`, `act()`, `evaluate()`. Без training logic
- `Trainer` = `update()`, `train_epoch()`. Использует модули через Protocol
- Модуль не импортирует свой Trainer. Trainer импортирует модуль

### Frontend — Feature-Sliced Design (FSD)

Для фронтенд-проектов (React/Vue/Angular/Svelte) используй FSD вместо классической Clean Architecture. FSD специализирован под UI-композицию.

**Слои (top → bottom, импорт строго вниз):**

| Слой | Что внутри | Пример |
|------|------------|--------|
| `app/` | Инициализация, провайдеры, роутер, глобальные стили | `<AppProviders>`, `App.tsx`, `index.css` |
| `pages/` | Отдельные страницы приложения | `pages/product/`, `pages/checkout/` |
| `widgets/` | Самостоятельные блоки UI, composable | `Header`, `Sidebar`, `ProductCard` |
| `features/` | Пользовательские действия с бизнес-ценностью | `auth-by-email`, `add-to-cart` |
| `entities/` | Бизнес-сущности (модель данных + UI representation) | `user`, `product`, `order` |
| `shared/` | Переиспользуемые примитивы без бизнес-контекста | `shared/ui/Button`, `shared/lib/dayjs`, `shared/api` |

**Структура slice (bussiness-слой кроме shared/app):**

```
features/auth-by-email/
  ├── ui/          # React-компоненты фичи
  ├── model/       # state (Redux/Zustand/MobX), хуки, селекторы
  ├── api/         # HTTP-запросы, tRPC/RTK Query endpoints
  ├── lib/         # helpers, чистые функции
  └── index.ts     # public API — ТОЛЬКО то что нужно снаружи
```

**Правила:**

- **Импорт строго вниз по слоям**: `page` → `widget` → `feature` → `entity` → `shared`. Обратно — запрещено.
- **Cross-slice import внутри одного слоя запрещён**: `features/auth` НЕ импортит из `features/cart`. Композиция — в `widget` или `page`.
- **Public API slice через `index.ts`**: внешние импорты только через `@/features/auth-by-email`, никогда `@/features/auth-by-email/model/store.ts`.
- **UI kit в `shared/ui/`**: dumb-компоненты без бизнес-логики (Button, Input, Modal).
- **Pages = композиция**: страница не содержит бизнес-логики, только сборка widgets/features.

**Линтер**: `@feature-sliced/eslint-config` + `steiger` для валидации.

**Что НЕ FSD** (типичные ошибки):

- `src/components/` / `src/pages/` / `src/utils/` — это structure-by-type, анти-FSD
- Фичи импортят друг друга напрямую → надо через widget или shared/model
- Компоненты импортят конкретные файлы slice минуя `index.ts`

### Mobile — iOS / Android

Для нативных мобильных приложений используй паттерны платформы, построенные на Unidirectional Data Flow (UDF) и Clean-слоях.

**iOS (Swift/SwiftUI):**

- **UI**: SwiftUI + Observation (`@Observable`, `@State`, `@Binding`) для iOS 17+. UIKit + MVVM+Coordinator для legacy.
- **Concurrency**: `async/await` + `Actor`, не GCD/Combine в новом коде.
- **Persistence**: SwiftData (iOS 17+) или Core Data.
- **Слои**: `View → ViewModel → UseCase → Repository → DataSource(network/local)`. Domain — протоколы + Entity, без зависимостей от UIKit/SwiftUI.
- **Модульность**: SPM feature-модули (`FeatureAuth`, `CoreUI`, `CoreNetwork`).
- **Крупные приложения**: The Composable Architecture (TCA) — Redux-like для SwiftUI, оправдан при shared state между экранами.
- **Tests**: XCTest + `swift-snapshot-testing` для UI.

**Android (Kotlin/Compose):**

Следуй официальному [Android Recommended Architecture](https://developer.android.com/topic/architecture):

```
UI Layer         (Composable + ViewModel + UiState immutable)
     ↓ UDF
Domain Layer     (UseCase — опционально, если логика shared между VM)
     ↓
Data Layer       (Repository = Single Source of Truth;
                  DataSource: Remote (Retrofit/Ktor) + Local (Room))
```

- **UI**: Jetpack Compose + Material 3. XML View system — только legacy.
- **Reactive**: Kotlin Coroutines + Flow. `StateFlow` для UI state, `SharedFlow` для one-off events.
- **DI**: Hilt (поверх Dagger).
- **Persistence**: Room (SQL), DataStore (preferences), WorkManager (background).
- **Модульность**: Gradle multi-module — `:feature:auth`, `:feature:cart`, `:core:ui`, `:core:network`, `:core:database`.
- **Shared логика iOS+Android**: Kotlin Multiplatform (KMP) — domain/data слои на Kotlin, UI нативно на каждой платформе.
- **Tests**: JUnit + Turbine (Flow), Paparazzi/Roborazzi для UI snapshot.

**Общие правила (iOS + Android):**

- **UDF**: state течёт вниз (Repository → ViewModel → UiState → View), events вверх (View → VM.onEvent()).
- **Immutable UI state**: всегда новый объект через `copy()` / `struct`, никогда мутация.
- **Single Source of Truth**: Repository владеет данными; ViewModel — только derived state.
- **Testability**: зависимости через protocols/interfaces, DI контейнер подставляет fakes в тестах.
- **One ViewModel per screen**: не шарить VM между экранами (composable state — через shared Repository).

---

## TDD — Test-Driven Development

### Два режима TDD

**Детерминистичные модули** (parsers, validators, business logic, routers):

```
Red → Green → Refactor
```

1. Написать failing тест ПЕРЕД кодом
2. Минимальная реализация чтобы тест прошёл
3. Refactor (убрать дублирование, улучшить naming)
4. Повторить

**ML-модули** (models, trainers, losses):

- **Contract tests (ДО реализации):** output shape, gradient flow, range invariants, determinism (seed), no NaN/Inf, device-agnostic
- **Statistical tests (ПОСЛЕ):** convergence (final_loss < initial * threshold), sanity checks. Маркер `@pytest.mark.slow`

**Когда пропустить TDD:** опечатки, форматирование, exploratory prototypes.

### Contract-First Development

1. Определить интерфейс (Protocol / ABC / type signatures)
2. Написать contract-тесты (проверяют контракт, а не реализацию)
3. Реализовать
4. Contract-тесты должны проходить для ЛЮБОЙ корректной реализации

---

## Тесты — Testing Trophy

### Приоритет (Testing Trophy)

```
         /  E2E  \          ← точечно, критические flows
        / Integration \      ← ОСНОВНОЙ ФОКУС
       /    Unit Tests   \   ← чистая логика, edge cases
      / Static Analysis    \ ← type checking, linting — всегда
```

- **Интеграционные (основной фокус):** реальные компоненты вместе, mock только внешние сервисы (DB, HTTP, файловая система). Если >5 mock'ов — кандидат на интеграционный тест
- **Unit:** чистая логика, edge cases, граничные значения. Быстрые, изолированные
- **E2E:** только критические user flows. Дорогие, хрупкие — минимум
- **Static:** type checking, linting — всегда, на каждый коммит

### Правила написания тестов

- **Имя = бизнес-требование**: `test_<что>_<условие>_<результат>`. Пример: `test_evidence_pack_caps_rel_facts_at_ten`
- **Assert = бизнес-факт**: каждый assert проверяет конкретное требование или edge case

```python
# Плохо — бессмысленный assert
assert result is not None

# Хорошо — проверяет бизнес-требование
assert len(pack.rel_facts) <= 10
assert encoder.sigma > 0
assert loss < initial_loss * 0.8
```

- **Мокать только внешние границы**: DB, HTTP API, файловая система, третьесторонние сервисы. Бизнес-логику НЕ мокать — использовать in-memory реализации
- **Вариации через `@parametrize`**, не копипаста тестов
- **Каждый тест = один сценарий**: не проверять 5 вещей в одном тесте
- **Тест должен падать по одной причине**: если упал — сразу понятно что сломалось
- **Arrange-Act-Assert**: чёткое разделение setup / действие / проверка
- **Specification by Example**: требования как конкретные входы/выходы = готовые test cases

### Markers

- `@pytest.mark.slow` — тесты >10 секунд (ML convergence, statistical)
- `@pytest.mark.gpu` — требуют GPU
- Проект-специфичные markers — в `RULES.MD` проекта

### Coverage

- Target: **85%+** общий
- Core/business logic: **95%+**
- Infrastructure/adapters: **70%+**
- Проект-специфичные targets по слоям — в `RULES.MD` проекта

---

## Coding Standards

### Общие

- Полные импорты, valid syntax, complete functions — код copy-paste ready
- Без placeholder'ов: никаких `TODO`, `...`, псевдокода
- No new libraries/frameworks без явного запроса
- Multi-file changes → план сначала, потом реализация

### Рефакторинг

- **Strangler Fig**: новый код оборачивает старый, замена поэтапно с тестами
- Каждый шаг рефакторинга — тесты проходят. Никогда не ломать тесты "на время"
- Переименование: найти ВСЕ использования (grep/IDE), не угадывать

### Архитектурные решения

- Значимое решение → ADR (контекст → решение → альтернативы → последствия)
- Перед архитектурным изменением — проверить существующие ADR
- Если есть Memory Bank → ADR в `.memory-bank/BACKLOG.md`

### Формат ответа

- Структура: **Цель → Действие → Результат**
- Если Memory Bank активен: `[MEMORY BANK: ACTIVE]` в начале
- Код: полные функции, copy-paste ready, полные импорты

---

## ML: device, reproducibility, numerical hygiene

**Device-agnostic:** запрещено `.cuda()`. Только `.to(config.device)`. Тесты = CPU.

**Seed:** фиксировать seed (random, numpy, torch, cuda) в начале каждого run.

**Checkpoint:** weights + optimizer + config + metrics + git hash. Model version — mismatch при загрузке = error.

**Numerics:** gradient clipping обязателен. NaN/Inf detection в debug. Running mean/std для reward normalization.

**Fail-fast:** NaN в loss, entropy→0 (policy collapse), OOM → немедленная остановка.

**Experiment lifecycle:** hypothesis (SMART) → baseline → одно изменение → run → compare (p-value, Cohen's d) → keep/rollback. Запрещено менять 2+ вещи без ablation.

---

## Staged stubs (разрешены)

Stub = полная реализация Protocol/Interface + docstring (что, чем заменяется, когда).
Stub за feature flag. Без feature flag — не stub, а production code.

---

## Memory Bank Operations

---

## Skill и инструменты

**Skill**: `memory-bank` (`~/.claude/skills/memory-bank/`)
**Шаблоны**: `~/.claude/skills/memory-bank/references/templates.md`
**Workflow**: `~/.claude/skills/memory-bank/references/workflow.md`
**Структура**: `~/.claude/skills/memory-bank/references/structure.md`
**Subagent**: MB Manager (sonnet) — для механической актуализации. Prompt: `~/.claude/skills/memory-bank/agents/mb-manager.md`
**Plan Verifier**: `~/.claude/skills/memory-bank/agents/plan-verifier.md`

---

## Команды /mb

| Команда | Описание |
|---------|----------|
| `/mb` или `/mb context` | Собрать контекст проекта (статус, чеклист, план) |
| `/mb start` | Расширенный старт сессии (контекст + активный план целиком) |
| `/mb search <query>` | Поиск информации в банке по ключевым словам |
| `/mb note <topic>` | Создать заметку по теме |
| `/mb update` | Актуализировать core files (checklist, plan, status) |
| `/mb tasks` | Показать незавершённые задачи |
| `/mb index` | Реестр всех записей в банке (core files + notes/plans/experiments/reports с количеством) |
| `/mb done` | Завершение сессии (actualize + note + progress) |
| `/mb plan <type> <topic>` | Создать план (type: feature, fix, refactor, experiment) |
| `/mb verify` | Верификация выполнения плана (план vs код, все DoD). **ОБЯЗАТЕЛЬНО** перед `/mb done` если работа велась по плану |
| `/mb init` | Инициализировать Memory Bank в новом проекте |

---

## Структура `.memory-bank/`

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
| `experiments/` | `EXP-NNN_<n>.md` — детальные записи ML экспериментов | При завершении эксперимента |
| `plans/` | `YYYY-MM-DD_<type>_<n>.md` — детальные планы | Перед сложной работой |
| `reports/` | `YYYY-MM-DD_<type>_<n>.md` — отчёты | Когда полезно будущим сессиям |
| `notes/` | `YYYY-MM-DD_HH-MM_<тема>.md` — заметки по задачам | По завершении задачи |

---

## Workflow

### `/mb start` — начало сессии

1. Проверить `.memory-bank/` существует → `[MEMORY BANK: ACTIVE]`
2. Читать 4 core files:
   - `STATUS.md` → где мы в проекте, roadmap, gates
   - `checklist.md` → текущие задачи (⬜/✅)
   - `plan.md` → приоритеты и направление
   - `RESEARCH.md` → какие гипотезы активны, текущий эксперимент
3. Резюмировать фокус в 1-3 предложения
4. Если есть активный план в `plans/` → прочитать его целиком

### Во время работы — когда обновлять файлы

| Событие | Действие |
|---------|----------|
| Завершена задача из checklist | `checklist.md`: ⬜ → ✅ (сразу, не откладывать) |
| Новая задача обнаружена | `checklist.md`: + ⬜ новая задача |
| Завершён этап / milestone | `STATUS.md`: обновить roadmap и метрики |
| Сдвинулся roadmap | `STATUS.md`: перенести пункты между секциями |
| Изменились ключевые метрики | `STATUS.md`: обновить секцию метрик |
| Новая гипотеза | `RESEARCH.md`: строка в таблицу (📋 PLANNED) |
| Начало ML эксперимента | `experiments/EXP-NNN_<n>.md` + статус 🔬 в RESEARCH.md |
| Эксперимент завершён | RESEARCH.md: статус ✅/🔴/⚠️ + finding. experiments/: результаты |
| Архитектурное решение | `BACKLOG.md`: ADR-NNN (контекст → решение → альтернативы) |
| Детальная многоэтапная работа | `plans/`: файл через `/mb plan <type> <topic>` |
| Замеченный антипаттерн | `lessons.md`: запись с контекстом |
| Сменился фокус/приоритеты | `plan.md`: обновить |

### `/mb done` — завершение сессии

1. **Если работа велась по плану** → `/mb verify` **ОБЯЗАТЕЛЬНО** перед `/mb done`:
   - Plan Verifier перечитает план, проверит `git diff`, найдёт расхождения
   - CRITICAL → исправить обязательно
   - WARNING → на усмотрение (спросить пользователя)
2. `checklist.md`: отметить завершённое ✅, добавить новое ⬜
3. `progress.md`: дописать в конец (APPEND-ONLY, никогда не удалять старое)
4. `STATUS.md`: обновить если milestone или сдвинулся roadmap
5. `RESEARCH.md`: обновить если ML результаты (статус гипотезы, finding)
6. `lessons.md`: добавить если обнаружен антипаттерн
7. `BACKLOG.md`: добавить если идея или ADR
8. `plan.md`: обновить если сменился фокус
9. `notes/`: создать заметку по завершённой работе

### `/mb update` — промежуточная актуализация

Подмножество `/mb done`: обновляет только core files (checklist, plan, status).
Без создания note и без записи в progress.
Вызывать когда: закончен промежуточный этап, но сессия продолжается.

### Перед compaction

Вызвать `/mb update` чтобы сохранить текущий прогресс ДО сжатия контекста.

---

## Edge cases: notes/ vs reports/

**notes/ — создавать когда:**

- Завершена конкретная задача или этап
- Обнаружено переиспользуемое знание (паттерн, решение, workaround)
- Формат: 5-15 строк, фокус на **выводах и паттернах**, не на хронологии
- Имя: `YYYY-MM-DD_HH-MM_<тема>.md`

**notes/ — НЕ создавать когда:**

- Тривиальные изменения (опечатки, форматирование)
- Exploratory prototype, который не дал полезного знания
- Информация уже зафиксирована в lessons.md или RESEARCH.md

**reports/ — создавать когда:**

- Полный отчёт полезен будущим сессиям (больше чем note)
- Анализ результатов эксперимента (дополнение к experiments/)
- Сравнительный анализ подходов
- Post-mortem инцидента
- Свободный формат, подробнее чем notes/

---

## /mb index — реестр записей

Показывает: core files (с числом строк и датой модификации) + списки notes/, plans/, experiments/, reports/ с количеством файлов.
Скрипт: `~/.claude/skills/memory-bank/scripts/mb-index.sh`.

---

## Кто обновляет файлы

| Работа | Кто |
|--------|-----|
| Механическая актуализация (checklist ⬜→✅, progress append, STATUS метрики) | MB Manager (sonnet subagent) |
| Создание планов (plans/) | Главный агент (требует глубины, DoD, TDD) |
| Архитектурные решения (ADR) | Главный агент формулирует → MB Manager сохраняет в BACKLOG.md |
| ML результаты (интерпретация) | Главный агент интерпретирует → MB Manager обновляет RESEARCH.md |

---

## Ключевые правила

- `progress.md` = **APPEND-ONLY** (никогда не удалять/редактировать старое)
- Нумерация сквозная: H-NNN, EXP-NNN, ADR-NNN (не переиспользовать)
- notes/ = знания и паттерны (5-15 строк), **не хронология**
- checklist: ✅ = done, ⬜ = todo. Обновлять **сразу** при завершении задачи
- Каждая гипотеза: метрика + порог (target) + ссылка на EXP после проверки
- Запрещено: гипотеза без метрики, эксперимент без гипотезы
- Finding = подтверждённый факт после stat. significant результата. Не удаляется

---

## Форматы файлов (кратко)

Полные шаблоны → `~/.claude/skills/memory-bank/references/templates.md`

### STATUS.md

```markdown
# <Проект>: Статус

## Текущая фаза
## Ключевые метрики
## Roadmap (✅ Завершено / 🔄 В процессе / 📋 Следующее / 🔮 Горизонт)
## Gates (критерии перехода)
## Известные ограничения
```

### RESEARCH.md

```markdown
# Research Log

## Гипотезы
| ID | Гипотеза | Статус | Метрика | Target | Результат | EXP |
Статусы: 📋 PLANNED → 🔬 TESTING → ✅ CONFIRMED / 🔴 REFUTED / ⚠️ INCONCLUSIVE

## Подтверждённые факты
## Текущий эксперимент
```

### BACKLOG.md

```markdown
## Идеи (HIGH / MEDIUM / LOW)
## Архитектурные решения (ADR)
## Отклонённые идеи
```

### experiments/EXP-NNN

```markdown
## Meta (дата, гипотезы, git hash, config, hardware)
## Setup (arms, epochs, параметры)
## Results (таблица метрик)
## Statistical Tests (Welch t-test, Cohen's d, p-value)
## Выводы + Решение (Keep / Rollback / Повторить)
```
