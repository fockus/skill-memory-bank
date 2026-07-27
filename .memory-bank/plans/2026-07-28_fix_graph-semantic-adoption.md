---
type: fix
topic: graph-semantic-adoption
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-07-28
---
# Plan: fix — graph-semantic-adoption

**Baseline commit:** b5f074c453e43cf6f8f20c3c1a394ac54b63a69b

## Context

**Problem:** Замер по транскриптам за 14 дней (28.07.2026): ~7 400 bash-grep против 43 вызовов `mb-graph-query`, ~0 настоящих вызовов `mb-semantic-search` — при том, что весь инструментарий реализован. Причины, подтверждённые фактами:
1. Векторный индекс `.index/codesearch/` физически существует только в FaberlicApp; в skill-memory-bank / taskloom / code-agent-cli его нет — первый запрос должен минуты строить индекс, поэтому не бутстрапится никогда (паттерн AGR-025/memsearch). Venv с fastembed при этом готов (`~/.claude/hooks/.venv`).
2. Граф свежий только в этом репо; taskloom — 19.07 при HEAD 27.07 (и 113 МБ), code-agent-cli — 14.06, FaberlicApp — 07.06. Auto-catchup встроен в `mb-graph-query.py`, но срабатывает только при запросе → курица-яйцо: не спрашивают → не обновляется → stale → не спрашивают.
3. `mb-graph-nudge.sh` подключён и работает (PreToolUse Grep|Bash), но троттлится до ОДНОГО nudge за сессию, текст генерический (без готовой команды с символом) — 34 инъекции quick-ref в одну сессию taskloom поведение не сдвинули.
4. Субагенты (~520 grep за период) не получают ни SessionStart quick-ref, ни статуса свежести графа; секции в `agents/mb-*.md` условны («если граф свежий») и им нечем это проверить дёшево.
5. Каноническая команда — трёхстрочный python-вызов с полным путём и точным `--symbol`; grep — однострочный рефлекс.

**Expected result:** Индексы и графы существуют и остаются свежими во всех активных банках без ручных действий; nudge в точке выбора даёт готовую короткую команду и срабатывает многократно; субагенты получают статус графа при диспатче. Измеримый рост доли graph/semantic-запросов в следующем замере.

**Related files:**
- `hooks/mb-graph-nudge.sh` + `tests/bats/test_mb_graph_nudge.bats`
- `memory_bank_skill/semantic_search.py`, `hooks/mb-semantic-bootstrap.sh`, `scripts/mb-codegraph.py`
- `hooks/mb-session-start.sh`, `hooks/mb-session-catchup.sh`, `memory_bank_skill/codegraph_catchup.py`, `scripts/mb-graph-query.py`
- `hooks/mb-context-slim-pre-agent.sh`, `agents/mb-developer.md` (и роль-агенты)
- `scripts/mb-context.sh` / `hooks/mb-session-start-context.sh` (тексты quick-ref)

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Nudge v2 — повторяемый и действенный

**What to do:**
- `hooks/mb-graph-nudge.sh`: заменить троттл «раз за сессию» на счётчик в маркер-файле — повторный nudge каждые N структурных grep (default 25, `MB_GRAPH_NUDGE_EVERY`), плюс сброс маркера после compaction (SessionStart:compact).
- Извлекать кандидат-символ из паттерна grep/rg (последний идентификатор CamelCase/snake_case ≥3 символов) и печатать ГОТОВУЮ команду: `mb-graph.sh who-calls <Symbol>` (короткая форма появляется в Stage 4; до него — полная команда с подставленным символом).
- Сохранить cheap-first порядок гвардов (нестуктурные вызовы не должны платить за python).

**Testing (TDD — tests BEFORE implementation):**
- bats (`test_mb_graph_nudge.bats`, новые кейсы красными до правок): re-nudge на (N+1)-м структурном вызове; извлечение символа из `grep -rn "def resolve_target" src/`; отсутствие nudge при `MB_GRAPH_NUDGE=off`; нестуктурный Bash-вызов → `{}` без создания маркера.

**DoD (Definition of Done):**
- [ ] Новые bats-кейсы были красными до реализации (прогон зафиксирован), зелёные после; старые кейсы не сломаны
- [ ] Nudge содержит подставленный символ из реального паттерна (проверено в bats на фикстурном вводе)
- [ ] Повторный nudge наблюдаем: 2 nudge за один прогон с 2N+1 структурными вызовами (bats)
- [ ] shellcheck чистый по изменённому хуку

**Code rules:** KISS (счётчик в файле, без нового состояния), fail-safe `{}` на всех ошибочных путях.

---

<!-- mb-stage:2 -->
### Stage 2: Bootstrap векторного индекса при `/mb graph --apply`

**What to do:**
- В конец пайплайна `scripts/mb-codegraph.py --apply` добавить построение/обновление `.index/codesearch/` через `memory_bank_skill/semantic_search.py` — fail-safe: нет venv/fastembed → одна честная строка «semantic index skipped (no fastembed)» и exit 0 (прецедент honest degradation AGR-013).
- Инкрементальность: пересобирать только при изменившемся наборе исходников (сверка по существующему `embeddings.key`-механизму).
- Разовый backfill: прогнать `--apply` (или только индекс-шаг) в 4 активных банках.

**Testing (TDD):**
- pytest: `--apply` со stub-эмбеддером создаёт `.index/codesearch/{embeddings.npy,embeddings.key}`; без fastembed — скип с сообщением и rc=0; повторный прогон без изменений исходников не пересобирает (mtime не меняется).

**DoD:**
- [ ] pytest-кейсы красные до реализации, зелёные после
- [ ] `.index/codesearch/` существует в skill-memory-bank после реального `--apply` (прогон в verify)
- [ ] `mb-semantic-search.py "<query>" --backend embeddings` отвечает без построения индекса (тёплый старт) — реальный прогон
- [ ] Backfill выполнен в taskloom / code-agent-cli / FaberlicApp (индексы существуют)

**Code rules:** Contract-First (скип-путь — часть контракта), YAGNI (без новых конфигов).

---

<!-- mb-stage:3 -->
### Stage 3: Auto-catchup графа на SessionStart

**What to do:**
- В `hooks/mb-session-start.sh` (или `mb-session-catchup.sh` — по месту, где уже есть банк-резолв) добавить фоновый запуск `python3 scripts/mb-graph-query.py catchup --graph <bank>/codebase/graph.json --budget <N>` (nohup, fire-and-forget) при существующем graph.json.
- Off-switch `MB_GRAPH_CATCHUP=off`; бюджет по умолчанию из `codegraph_catchup.maybe_catchup` (гард для 113-МБ taskloom — catchup обязан уложиться в бюджет или честно выйти).

**Testing (TDD):**
- bats: при существующем graph.json старт сессии порождает catchup-процесс (проверка через лог/маркер, не sleep); при `MB_GRAPH_CATCHUP=off` или отсутствии графа — не порождает; SessionStart-хук завершается <1с независимо от размера графа (фон).

**DoD:**
- [ ] bats-кейсы красные до реализации, зелёные после
- [ ] Реальная проверка на одном протухшем банке: после старта сессии mtime graph.json обновился, `mb-graph-query.py status` даёт `stale=false` (либо честный отчёт budget-exceeded)
- [ ] SessionStart не замедлен: замер времени хука до/после в пределах +100мс

**Code rules:** прецедент I-131 — никакой синхронной тяжёлой работы в lifecycle-хуках.

---

<!-- mb-stage:4 -->
### Stage 4: Короткий враппер `mb-graph.sh` + короткие тексты подсказок

**What to do:**
- Новый `scripts/mb-graph.sh`: `mb-graph.sh who-calls|impact|tests|status|search <Symbol|query>` — резолвит банк через `mb_resolve_path`, делегирует в `mb-graph-query.py` / `mb-semantic-search.py`; `search` роутит: точное имя → bm25, иначе embeddings.
- Обновить тексты: nudge (Stage 1), quick-ref в `mb-context.sh` / session-start контексте — печатать короткую форму (≤2 строк) вместо трёхстрочного python-вызова.

**Testing (TDD):**
- bats: `who-calls` делегирует с правильными аргументами (стаб mb-graph-query.py фиксирует argv); резолв банка из подкаталога проекта; неизвестная подкоманда → usage + rc≠0; `search <CamelCase>` уходит в bm25, фразовый запрос — в embeddings.

**DoD:**
- [ ] bats красные → зелёные; shellcheck чистый
- [ ] Подсказка в nudge и quick-ref ≤2 строк и использует `mb-graph.sh` (grep по текстам хуков в bats)
- [ ] Реальный прогон: `scripts/mb-graph.sh who-calls WriteFile` в этом репо отвечает <2с

**Code rules:** DRY — все подсказки ссылаются на одну команду; тонкий враппер без логики.

---

<!-- mb-stage:5 -->
### Stage 5: Статус графа в диспатче субагентов

**What to do:**
- Расширить `hooks/mb-context-slim-pre-agent.sh` (PreToolUse:Task, уже подключён): к инжектируемому контексту добавлять ≤3 строк — статус графа (`fresh|stale + возраст`) и готовую команду `mb-graph.sh who-calls <Symbol>`; при отсутствии графа — не добавлять ничего.
- Статус брать дёшево: из кэша `mb-graph-query.py status` (без полного парса 113-МБ графа — только заголовок/метаданные), либо пропускать при превышении 200мс.

**Testing (TDD):**
- bats: при свежем графе инжект содержит строку `code graph: fresh`; при отсутствии графа инжект не меняется; добавка ≤3 строк (wc -l); хук укладывается в лимит времени на фикстурном банке.

**DoD:**
- [ ] bats красные → зелёные; существующее поведение слиммера не изменилось (старые кейсы зелёные)
- [ ] Реальный прогон: перехваченный prompt субагента содержит статус-строку (ручная проверка в verify)

**Code rules:** жёсткий лимит на размер инжекта — контекст субагента не раздуваем (прецедент token-economical defaults).

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| fastembed недоступен/сломан на машине пользователя | M | Честный скип одной строкой, lexical/bm25 фолбэк остаётся (AGR-013 honest degradation) |
| Catchup на 113-МБ графе taskloom съедает бюджет/CPU на каждом старте | M | Бюджет в `maybe_catchup` + фон + off-switch; при повторном budget-exceeded — честный статус, не молчание |
| Nudge каждые 25 grep начинает раздражать | M | `MB_GRAPH_NUDGE_EVERY` конфигурируем, `MB_GRAPH_NUDGE=off` работает как раньше |
| Инжект в субагентов раздувает контекст / ломает slim-режим | L | Лимит ≤3 строк, bats-гард на размер, при таймауте статуса — молча пропустить |
| Индекс-шаг в `--apply` удлиняет и без того долгую пересборку | L | Инкрементальный key-чек; полный ребилд индекса только при изменившихся исходниках |

## Gate (plan success criterion)

Демо-прогон на этом репо после всех стадий: (1) структурный grep даёт nudge с готовой командой и повторяется после N вызовов; (2) `mb-graph.sh who-calls <Symbol>` отвечает <2с; (3) `mb-semantic-search.py --backend embeddings` отвечает на тёплом индексе без пересборки; (4) во всех 4 активных банках `graph.json` не старше 1 коммита от HEAD (или честный budget-exceeded статус) и `.index/codesearch/` существует. Контрольный замер adoption скриптом по транскриптам — через неделю после раскатки, цель ≥10× по graph/semantic вызовам (43 → ≥400 при сопоставимом объёме, фиксируется в progress.md заметкой).
