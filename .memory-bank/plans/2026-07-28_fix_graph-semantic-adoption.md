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

**Baseline commit:** (пере-базирован 2026-09-17, стадии не начинались) — см. коммит, закрывающий подготовку; исходная редакция плана ссылалась на b5f074c453e43cf6f8f20c3c1a394ac54b63a69b

## Context

**Замер 2026-09-06 (владелец: «графы не используются — сделать, чтобы использовались», AGR-044).** Прогон `/mb work` Stage 4 cost-diet на этом репо: implementer (opus) — 7 запросов к графу (`status`, `catchup`, `impact`×2, `neighbors`×2, `tests`) против 6 grep, потому что его промпт (`mb-developer.md`) велит начать со `status`; verifier (sonnet) — **0** запросов к графу против 16 grep: в диспатч verify (`commands/work.md` §5c) `mb-tooling-core.md` не подмешивается, в отличие от §5a; nudge-хук в сабагентах не сработал ни разу — лимит «раз за сессию» израсходовала основная сессия. Покрытие: `graph.json` содержит 267 модулей `.py` и **ни одного из 155 `.sh` и 249 `.bats`** — для основного кода этого скила граф пуст, `graph_tests scripts/x.sh` не может ничего вернуть; семантический индекс `.index/codesearch/` не построен. Вывод: три причины неиспользования — (1) нечего спрашивать (покрытие), (2) никто не подсказывает в нужный момент (nudge/диспатч), (3) ответ нужно «тянуть», а не получать готовым (push-модель). Стадии 6–7 закрывают (1) и (3) и контракты ролей; стадии 1–5 — (2) и свежесть индексов. Сторожевой LLM-сабагент не нужен: детерминированные хуки + метрика `graph_share` + INFO-строка verifier'а дают ту же информацию без затрат.

**Порядок исполнения:** 6 (покрытие) → 2 (bootstrap индексов) → 8 (тёплый индекс достижим) → 3 (catchup) → 1 (nudge v2) → **4 (враппер) → 9 (Communities без networkx) → 10 (networkx в bootstrap) → 11 (детерминизм кластеров) → 5 (статус в диспатче)** → 7 (граф в каждом диспатче + замер). План — пререквизит cost-diet Sprint 2 (`depends_on` там).

Хвост пере-упорядочен 2026-09-25 по AGR-049: исходный `1 → 5 → 4 → 7` противоречив — Stage 5 обязана инжектить готовую команду `mb-graph.sh`, который создаётся только Stage 4, а текст nudge из Stage 1 иначе правится дважды. Stage 8 вставлена между 2 и 3 по AGR-047/AGR-048. Stage 9 вставлена между 4 и 5 по AGR-050; стадии 10 и 11 — после 9 по AGR-051 и AGR-052.

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
- [x] Новые bats-кейсы были красными до реализации (прогон зафиксирован), зелёные после; старые кейсы не сломаны
- [x] Nudge содержит подставленный символ из реального паттерна (проверено в bats на фикстурном вводе)
- [x] Повторный nudge наблюдаем: 2 nudge за один прогон с 2N+1 структурными вызовами (bats)
- [x] shellcheck чистый по изменённому хуку

**Code rules:** KISS (счётчик в файле, без нового состояния), fail-safe `{}` на всех ошибочных путях.

---

<!-- mb-stage:2 -->
### Stage 2: Bootstrap векторного индекса при `/mb graph --apply`

**What to do:**
- **Порт бэкенда на fastembed (AGR-045, добавлено 2026-09-17).** `memory_bank_skill/semantic_embeddings.py` сегодня импортирует `sentence_transformers`, а `hooks/mb-semantic-bootstrap.sh` ставит `fastembed` — код разошёлся с хуком, `available` всегда False, `--backend embeddings` молча падает в bm25. Переписать ретривер на `fastembed.TextEmbedding` (~50 МБ ONNX, без torch); формат кэша `embeddings.npy`/`embeddings.key` и публичный контракт `EmbeddingRetriever` (`available`/`index`/`search`) сохранить байт-в-байт, чтобы `make_retriever`/`FusedRetriever` не менялись.
- В конец пайплайна `scripts/mb-codegraph.py --apply` добавить построение/обновление `.index/codesearch/` через `memory_bank_skill/semantic_search.py` — fail-safe: нет venv/fastembed → одна честная строка «semantic index skipped (no fastembed)» и exit 0 (прецедент honest degradation AGR-013).
- Инкрементальность: пересобирать только при изменившемся наборе исходников (сверка по существующему `embeddings.key`-механизму).
- Разовый backfill: прогнать `--apply` (или только индекс-шаг) в 4 активных банках — `skill-memory-bank`, `~/Apps/code-agent`, `~/Apps/harness`, `~/Apps/techflow` (AGR-046; репозиториев taskloom / code-agent-cli / FaberlicApp из исходной редакции плана больше не существует).

**Testing (TDD):**
- pytest (порт бэкенда): `available` False без fastembed и True с ним (стаб-модуль в `sys.modules`); `index()` пишет `embeddings.npy`+`embeddings.key`; ключ кэша меняется при смене корпуса и совпадает при неизменном; `search()` возвращает те же поля, что раньше.
- pytest (индекс-шаг): `--apply` со stub-эмбеддером создаёт `.index/codesearch/{embeddings.npy,embeddings.key}`; без fastembed — скип с сообщением и rc=0; повторный прогон без изменений исходников не пересобирает (mtime не меняется).

**DoD:**
- [x] pytest-кейсы красные до реализации, зелёные после
- [x] `.index/codesearch/` существует в skill-memory-bank после реального `--apply` (прогон в verify)
- [x] `mb-semantic-search.py "<query>" --backend embeddings` отвечает без построения индекса (тёплый старт) — реальный прогон
- [x] Backfill выполнен в `~/Apps/code-agent`, `~/Apps/harness`, `~/Apps/techflow` (графы свежие, индексы существуют) — AGR-046

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
- [x] bats-кейсы красные до реализации, зелёные после
- [x] Реальная проверка на одном протухшем банке: после старта сессии mtime graph.json обновился, `mb-graph-query.py status` даёт `stale=false` (либо честный отчёт budget-exceeded)
- [x] SessionStart не замедлен: замер времени хука до/после в пределах +100мс

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
- [x] bats красные → зелёные; shellcheck чистый
- [x] Подсказка в nudge и quick-ref ≤2 строк и использует `mb-graph.sh` (grep по текстам хуков в bats)
- [x] Реальный прогон: `scripts/mb-graph.sh who-calls mb_resolve_path` в этом репо отвечает <2с и возвращает вызывающих (rc 0)
  _Уточнено 2026-09-30 по verify Stage 4: исходный `WriteFile` — Go-пример из CLAUDE.md, в графе этого репо его нет; прогон укладывался в 0.19 с, но отвечал `no_match`, то есть проверял только время, не корректность._

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

<!-- mb-stage:6 -->
### Stage 6: Покрытие — bash и bats в графе

**Role:** developer

**What to do:**
- Новый чистый модуль `memory_bank_skill/codegraph_shell.py` (stdlib, regex; всегда включён, как `codegraph_python`): для `.sh` — `module`-узел на файл, `function`-узлы (`name() {` / `function name`), `call`-рёбра на вызовы известных функций того же файла и функций из `source`-нутых файлов, `import`-рёбра для `source|.  <path>` и для запусков `bash "<…>/scripts/x.sh"` / `"$SCRIPT_DIR/x.sh"` (резолв по basename внутри src root); для `.bats` — `module`-узел, `function`-узел на каждый `@test "…"`, `import`-рёбра на скрипты/хуки, упомянутые путём (`scripts/<x>.sh`, `hooks/<x>.sh`, `$REPO_ROOT/…`), `load 'lib/assert'` → import. Регистрация в `scripts/mb-codegraph.py` рядом с python-экстрактором; incremental-кэш по sha работает для новых расширений; битый файл → warning, батч продолжается.
- tree-sitter-bash **не** подключаем сейчас (YAGNI: regex покрывает функции/source/вызовы; upgrade path — строка в `LANG_CONFIG`, когда понадобятся вложенные конструкции).
- `mb-graph-query.py`: `tests --file scripts/x.sh` возвращает `.bats`-модули, импортирующие его; `impact --symbol <bash_func>` — вызовы из `.sh`; `god-nodes.md` — bash-функции в Top symbols.
- `docs/`/`commands/mb.md` (`graph`): строка «Always on: Python + Bash + Bats».

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_codegraph_shell.py` на фикстурах `tests/fixtures/codegraph-shell/`: `test_bash_functions_become_function_nodes`, `test_source_and_bash_invocation_become_import_edges`, `test_call_edge_to_function_of_sourced_file`, `test_bats_test_becomes_function_node_with_import_edge_to_script`, `test_load_helper_is_import`, `test_malformed_file_skipped_with_warning`, `test_sha_cache_hit_for_shell_files`.
- `tests/pytest/test_graph_query_shell.py`: `test_tests_for_shell_script_returns_bats_modules`, `test_impact_for_bash_function_lists_callers`.
- Регрессия: `test_codegraph*.py` существующие зелёные; `.py`-часть `graph.json` байт-идентична до/после (сравнение узлов/рёбер python-модулей на фикстуре).

**DoD:**
- [x] На этом репо после `/mb graph --apply`: модулей `.sh` ≥ 150 и `.bats` ≥ 240; `python3 scripts/mb-graph-query.py tests --file scripts/mb-status-rotate.sh` → `tests/bats/test_status_rotate.bats`; `impact --symbol mb_resolve_path` ≥ 20 вызывающих; сборка ≤ 30 с.
- [x] 9 новых pytest зелёные, старые `test_codegraph*` зелёные; `ruff` чист; строки в `SKILL.md` § Tools (`mb-codegraph.py` — «Python + Bash + Bats») и `commands/mb.md` (`graph`); CHANGELOG `### Added`.
- [x] `god-nodes.md` этого банка показывает bash-функции `_lib.sh` в Top symbols (проверка глазами в verify + assert «≥ 1 символ из `_lib.sh`»).

**Code rules:** чистый модуль без IO (по образцу `codegraph_python`), детерминизм, 0 новых зависимостей.

---

<!-- mb-stage:7 -->
### Stage 7: Граф в каждом диспатче `/mb work` + замер adoption

**Role:** developer

**What to do:**
- `commands/work.md`: §5c (verify), §5d (review), §5e (judge) подмешивают `agents/mb-tooling-core.md` перед промптом роли так же, как §5a (сегодня — только §5a, отсюда 0 запросов у verifier). Push-модель: оркестратор кладёт в промпт всех трёх ролей готовый блок `## Graph` — вывод `mb-graph-query.py tests|impact` по `Files:` item (≤ 40 строк, fail-open: нет графа → одна строка «graph unavailable: <reason>»); когда появится context pack (cost-diet Sprint 2 Stage 3), блок переезжает туда.
- Контракты ролей: `agents/mb-engineering-core.md` §1 «graph-first» + в отчёт implementer строка `Graph: <n> queries (impact/neighbors/tests) | unavailable: <reason>`; `agents/plan-verifier.md` Step 3.5 — тесты для diff берутся через `graph_tests`, INFO если в отчёте implementer нет строки `Graph:`; `agents/mb-reviewer.md`, `mb-reviewer-logic.md`, `mb-judge.md` — blast-radius через `impact` для каждого touched-файла перед вердиктом (детерминированно, дёшево).
- `hooks/mb-graph-nudge.sh`: маркер троттла ключуется по сессии **и** агенту (`CLAUDE_AGENT_ID` / путь транскрипта), чтобы каждый сабагент имел свой бюджет nudge (сегодня основная сессия съедает единственный); совместимо со Stage 1 (повтор каждые N).
- `scripts/mb-cost-report.py`: per role `graph_calls` (Bash-команды с `mb-graph.sh|mb-graph-query.py|mb-semantic-search.py|mb-code-context.py` — `mb-graph.sh` добавлен 2026-09-30: с Stage 4 это ведущая команда во всех подсказках и инструкциях, без неё адопшен враппера в замере невидим), `grep_calls` (Grep-tool + Bash `grep -r`/`rg `), `graph_share = graph/(graph+grep)` (0 без lookups) в таблице и `--json`; `--since 7` — недельный замер adoption (AGR-038).
- Сторожевой сабагент не добавляется — обоснование в Context.

**Testing (TDD):**
- doc-pytest `tests/pytest/test_graph_dispatch_docs.py`: `commands/work.md` §5c/§5d/§5e содержат `mb-tooling-core.md` и `## Graph`; `mb-engineering-core.md`, `plan-verifier.md`, `mb-reviewer.md`, `mb-judge.md` содержат `Graph:`/`impact`.
- `hooks/tests/test_mb_graph_nudge.bats`: `marker is per session+agent`, `subagent gets its own first nudge`, `off-switch`.
- `tests/pytest/test_mb_cost_report.py`: `test_graph_and_grep_calls_counted_per_role`, `test_graph_share_zero_when_no_lookups` (фикстура: implementer 2 grep + 1 graph → 0.33).

**DoD:**
- [ ] Демо-item `/mb work` (execution) на этом репо после Stage 6: implementer ≥ 3 запросов к графу и `graph_share ≥ 0.5`; verifier ≥ 1 запрос; nudge наблюдаем в транскрипте сабагента (grep по output-файлу); `mb-cost-report.py` печатает `graph_share` по ролям; отчёт → `reports/`.
- [ ] doc-pytest + 3 bats + 2 pytest зелёные; shellcheck; `ruff`; CHANGELOG.
- [ ] Через 7 дней после раскатки `mb-cost-report.py --since 7`: `graph_share` implementer ≥ 0.5 (замер adoption по AGR-038); результат в `reports/`.

**Code rules:** детерминированный замер (regex), без LLM; fail-open на отсутствие графа; никаких новых зависимостей.

---

<!-- mb-stage:8 -->
### Stage 8: Тёплый индекс доступен документированной командой

**Role:** developer

**Добавлена 2026-09-18** по решениям владельца AGR-047 и AGR-048 — после того как Stage 2 построил индекс, но обнаружилось, что дойти до него документированной командой нельзя. Исполняется СРАЗУ после Stage 2, до Stage 3.

**What to do:**
- **Маршрутизация (AGR-047).** `scripts/mb-semantic-search.py` при запуске проверяет, доступен ли embeddings-бэкенд в текущем интерпретаторе. Если нет, а `memory_bank_skill/semantic_index._semantic_python()` находит подходящий — перезапустить себя под ним (`os.execv`), защитившись env-флагом от рекурсии. Действует и для `--backend embeddings`, и для `--backend auto` (дефолт). Если подходящего интерпретатора нет — поведение как сегодня: честное предупреждение и BM25.
- **Один слот кэша (AGR-048).** В `memory_bank_skill/semantic_search.py::run_search` убрать фильтрацию `source_only` ДО индексации; корпус всегда полный. Фильтр `is_test` применяется после выдачи, `fetch_k` расширяется на `source_only` так же, как уже сделано для `churn`.
- **Честный skip вместо вечного «refreshing» (CRITICAL-1 из verify Stage 2).** `semantic_index._semantic_python()` проверяет только `os.access(..., X_OK)` и не убеждается, что fastembed в этом интерпретаторе импортируется. Потомок запускается с `stdout=DEVNULL, stderr=DEVNULL`, его возврат `"skipped"` никто не читает, поэтому комментарий `semantic_index.py:128-132` («сообщает потомок, не мы») — ЛОЖЕН, и каждый следующий `--apply` печатает `refreshing in background`, а индекс не появляется никогда. Потомок обязан записать терминальный статус (`built`/`skipped`/`current`) в `.index/codesearch/.index.status`, а `refresh_index()` — прочитать его перед решением порождать нового потомка: «застряло навсегда» превращается в одну честную строку `skipped (no fastembed)`. Это прямое требование Code rule этой стадии и прецедента AGR-013.
- **Никакого переднего кодирования (AGR-048).** Если тёплого кэша под текущий `corpus_key` нет, `run_search` не кодирует в своём процессе: отвечает BM25 с честным предупреждением и запускает фоновую `semantic_index.refresh_index()`. Следующий запрос попадает в тёплый индекс.

**Testing (TDD — tests BEFORE implementation):**
- `test_semantic_search_routing.py`: без fastembed и с доступным venv — происходит re-exec (стаб `os.execv` фиксирует argv) для `auto` и для `embeddings`; при выставленном env-флаге re-exec НЕ повторяется; при отсутствии venv re-exec не происходит и ответ приходит на BM25; `--backend bm25` не вызывает re-exec никогда.
- `test_semantic_search.py`: `--source-only` и полный запрос дают ОДИН `corpus_key` (кэш не вытесняется); `--source-only` не возвращает ни одного `is_test`-документа; при `k` меньшем числа отфильтрованных всё равно возвращается `k` результатов.
- `test_semantic_index.py`: промах кэша не кодирует синхронно (стаб-эмбеддер не вызывается), отдаёт BM25 и порождает фоновую сборку; интерпретатор СУЩЕСТВУЕТ, но fastembed в нём не импортируется (`MB_SEMANTIC_PY` на системный python3) → второй вызов `refresh_index()` печатает честный skip и НЕ порождает потомка повторно; ветка `"locked"` в `build_index()` покрыта (сегодня 0 тестов — WARNING-2 из verify Stage 2).

**DoD:**
- [x] Новые тесты красные до реализации, зелёные после; старые `test_semantic_*` зелёные
- [x] Реальный прогон: `python3 scripts/mb-semantic-search.py "<query>" .memory-bank --backend embeddings` СИСТЕМНЫМ python3 отвечает `backend: embeddings` без пересборки индекса
- [x] Реальный прогон: та же команда без `--backend` (auto) тоже использует векторы
- [x] Реальный прогон: `--source-only` не пересобирает индекс — `embeddings.key` и mtime `embeddings.npy` не меняются
- [x] Промах кэша отвечает за <2 с (BM25) и оставляет фоновую сборку; `ruff` чист; CHANGELOG
- [x] Воспроизведённый сценарий CRITICAL-1 закрыт: при `MB_SEMANTIC_PY`, указывающем на интерпретатор без fastembed, второй `refresh_index()` печатает skip вместо `refreshing in background`
- [x] Воспроизведённый сценарий CRITICAL-2 закрыт: чередование `--source-only` и обычного запроса на тёплом индексе не даёт переднего кодирования (замер verify Stage 2: 1:00.89 и затем 3:49.81 — должно стать <2 с)

**Code rules:** fail-open на всех путях (нет venv / нет индекса / фоновый запуск не удался → BM25, никогда не блокировать), 0 новых зависимостей.

---

<!-- mb-stage:9 -->
### Stage 9: `--apply` без networkx не стирает Communities и Bridge files

**Role:** developer

**Добавлена 2026-09-30** по AGR-050 (фикс I-225). Исполняется между Stage 4 и Stage 5.

**Проблема (факты).** `god-nodes.md` отслеживается git'ом, а его содержимое зависит от интерпретатора, которым пересобран граф: с networkx в отчёте есть `## Communities` и `## Bridge files`, без него — только degree-ранжирование и строка-подсказка про установку. В git-истории секция Communities есть ровно в трёх коммитах, где сборка шла под dev-`.venv` (`9fb7b32`, `3bf7ff1`, `cfee2e0`), и отсутствует во всех остальных, включая текущий HEAD. Stage 3 превратила эпизодический баг в постоянный: фоновый catchup на SessionStart поднимает `mb-codegraph.py --apply` через `sys.executable` системного `python3`, а networkx там нет — ни в системном python, ни в `~/.claude/hooks/.venv` (он ставит только fastembed+numpy). Networkx есть только в dev-`.venv` этого репо, то есть у пользователей скила его нет почти никогда.

**Выбор решения.** Резолв интерпретатора с networkx (по образцу `semantic_index._semantic_python()`) у пользователей ничего не найдёт — лечит только этот репо. Поэтому чинится запись отчёта: когда networkx недоступен, а в существующем `god-nodes.md` секции Communities / Bridge files есть, `--apply` переносит их дословно из прежнего файла с явной пометкой, что они от предыдущей сборки. Без networkx секции не пересчитываются, но и не пропадают; с networkx — считаются заново, как сегодня. Установка networkx в bootstrap-venv — отдельное решение владельца (новая зависимость на машине пользователя), в объём стадии не входит.

**What to do:**
- В `memory_bank_skill/codegraph_analytics.py` (функция, собирающая отчёт `god-nodes.md`) при `communities is None` и `betweenness is None` читать прежний `god-nodes.md`, если он есть, и переносить блоки `## Communities …` и `## Bridge files …` до следующего заголовка `## ` дословно, добавив под заголовком строку-пометку `_Carried over from the previous build: networkx is unavailable in this interpreter, so these sections were not recomputed._`. Строку-подсказку про установку networkx оставить.
- Пометку при следующей сборке с networkx не накапливать: секции пересчитываются с нуля.
- Прежнего файла нет или секций в нём нет → поведение как сегодня.

**Testing (TDD — тесты ПЕРЕД реализацией):**
- pytest: без networkx (стаб `HAS_NX=False` / monkeypatch) и с прежним `god-nodes.md`, где есть Communities и Bridge files → новый отчёт содержит обе секции дословно + пометку, Top symbols пересчитаны.
- pytest: без networkx и без прежнего файла → отчёта-регресса нет (секций нет, подсказка есть) — байт-в-байт как сегодня.
- pytest: с networkx и прежним файлом, где уже стоит пометка → пометки в новом отчёте нет (не накапливается).
- pytest: перенос не захватывает соседние секции (блок кончается на следующем `## `).

**DoD:**
- [x] pytest-кейсы красные до реализации, зелёные после; старые `test_codegraph*` зелёные
- [x] Реальный прогон: `god-nodes.md` этого репо с секциями Communities → `python3 scripts/mb-codegraph.py --apply .memory-bank .` СИСТЕМНЫМ python3 → секции на месте с пометкой, `git diff --stat` по файлу не показывает удаления ~80 строк
- [x] Реальный прогон: фоновый catchup на SessionStart (Stage 3) после правки исходника не удаляет Communities
- [x] `ruff` чист; CHANGELOG

**Code rules:** 0 новых зависимостей; fail-open (прежний файл нечитаем → поведение как сегодня); без изменения формата `graph.json`.

---

<!-- mb-stage:10 -->
### Stage 10: networkx в bootstrap-venv + `mb-codegraph.py` под ним

**Role:** developer

**Добавлена 2026-09-30** по AGR-051. Исполняется после Stage 9, до Stage 11.

**Проблема (факты, verify Stage 9).** Stage 9 сохранила секции Communities / Bridge files в `god-nodes.md`, но зависимость от интерпретатора осталась в двух других местах: под системным `python3` `graph.json` теряет поле `community` у всех 9491 узлов (под `.venv` — 9491 из 9491), а Top symbols / Top modules в `god-nodes.md` переключаются с PageRank на degree (~45 строк). Git-отслеживаемый граф прыгает на ~9.5 тыс. строк при каждой смене интерпретатора; `/mb wiki` читает кластеры из `graph.json` (`commands/mb.md:917`). networkx нет ни в системном `python3`, ни в `~/.claude/hooks/.venv` — только в dev-`.venv` этого репо.

**What to do:**
- `hooks/mb-semantic-bootstrap.sh`: ставить `networkx` рядом с `fastembed numpy`. Проверка готовности должна включать networkx — иначе у существующих пользователей (venv с fastembed уже есть) bootstrap напишет «ready» и networkx не доставит никогда. Если fastembed ставится, а networkx нет (или наоборот) — честная строка про то, чего не хватает, exit 0.
- `scripts/mb-codegraph.py`: когда networkx в текущем интерпретаторе не импортируется, а `semantic_index._semantic_python()` находит интерпретатор — re-exec под ним по образцу `scripts/mb-semantic-search.py` (Stage 8, AGR-047): сравнение путей литеральное (НЕ `realpath` — venv-python симлинк на базовый бинарник, Stage 8 на этом уже спотыкалась), env-флаг против рекурсии, `OSError` от `execv` → работа как сегодня (fail-open), коды выхода и stdout не меняются. Кандидат без networkx (старый venv) — не re-exec'ать впустую: проверка импорта в кандидате или отказ после первой неудачи.
- Путь catchup (`codegraph_catchup.py:194`, `sys.executable` + `mb-codegraph.py --apply`) и документированная команда `python3 …/mb-codegraph.py --apply` должны оба приходить к сборке с networkx — через re-exec самого `mb-codegraph.py`, а не отдельной логикой в каждом вызывающем.
- `scripts/mb-deps-check.sh`: подсказка для networkx указывает на тот же bootstrap.
- Документация: `commands/mb.md`, `references/code-graph.md`, `SKILL.md` — где сказано, что networkx опционален и как его получить; CHANGELOG.

**Testing (TDD — tests BEFORE implementation):**
- bats (bootstrap): venv с fastembed+numpy, но без networkx → bootstrap НЕ пишет «ready» и доставляет networkx (стаб pip фиксирует argv); всё есть → «ready», pip не зовётся.
- pytest (re-exec): без networkx и с кандидатом → `os.execv` вызван с кандидатом (стаб); env-флаг выставлен → повтора нет; кандидат — симлинк на текущий бинарник → re-exec всё равно происходит; нет кандидата / `execv` бросает `OSError` → сборка идёт в текущем python; networkx есть в текущем → re-exec нет.

**DoD:**
- [x] Новые тесты красные до реализации, зелёные после; старые `test_codegraph*` и bootstrap-тесты зелёные
- [x] Реальный прогон: после bootstrap `~/.claude/hooks/.venv/bin/python -c "import networkx"` → rc 0
- [x] Реальный прогон: `python3 scripts/mb-codegraph.py --apply .memory-bank .` СИСТЕМНЫМ python3 даёт `graph.json` с `community` у всех модульных узлов и `god-nodes.md` с PageRank-ранжированием — `git diff --stat` против сборки под `.venv` на том же коде = 0 (при условии детерминизма кластеров — если I-219 мешает, сравнивать всё, кроме разбивки, и явно это отметить)
- [x] Фоновый catchup Stage 3 приходит к тому же результату
- [x] shellcheck, ruff, CHANGELOG

**Code rules:** fail-open на всех путях; одна новая зависимость (networkx, AGR-051) и только в bootstrap-venv; переиспользовать `_semantic_python()`, не дублировать резолв.

---

<!-- mb-stage:11 -->
### Stage 11: детерминированная кластеризация (I-219)

**Role:** developer

**Добавлена 2026-09-30** по AGR-052. Исполняется после Stage 10, до Stage 5.

**Проблема (факты).** `detect_communities` (`memory_bank_skill/codegraph_analytics.py:162`) зовёт `nx.community.louvain_communities(G, seed=_SEED)` — seed задан, докстринг обещает детерминизм, но на фиксированном графе разные `PYTHONHASHSEED` дают разное число сообществ (замер I-219: 220/219/218; на графе коммита `871e407`: 13/14/14). Вероятная причина — порядок вставки узлов/рёбер в `_nx_file_graph` зависит от итерации по set/dict. После Stage 3 (фоновый catchup на SessionStart) это значит: `god-nodes.md` и поля `community` в `graph.json` меняются в git без изменений в коде. Вдобавок 188 из 217 сообществ — одиночки (132 `tests/bats/*.bats`, 16 `scripts/*.sh`, 11 `hooks/tests/*.bats`…): связь «тест → скрипт по пути» не считается файловым ребром, а одиночки дают louvain лишнюю свободу и раздувают сводку `communities=N`.

**What to do:**
- `_nx_file_graph` / `detect_communities`: строить граф с отсортированными узлами и рёбрами, чтобы результат не зависел от `PYTHONHASHSEED`. Если одной сортировки недостаточно — найти реальный источник недетерминизма и закрыть его (замером, не догадкой).
- Одиночек (файлы без файловых рёбер) в louvain не подавать; у них нет поля `community` либо единый явный id — выбрать и задокументировать; сводка `communities=N` считает только настоящие кластеры.
- Сохранить правило id: 0 — самое большое, тай-брейк по алфавитно первому члену.
- Докстринг — правдивый.
- **Дополнено 2026-09-30 по итогам verify Stage 10.** (а) `Bridge files` (выборочный betweenness поверх set `files`) тоже зависит от `PYTHONHASHSEED`: два прогона одного python подряд дают разные строки. Закрыть тем же приёмом: отсортированный вход, фиксированный seed выборки. (б) Кластеры зависят от версии networkx: при `PYTHONHASHSEED=0` dev-`.venv` (3.6.1) и bootstrap-venv (3.7) дают разные Communities (6 строк `god-nodes.md`). Сборка разработчика и фоновый catchup тогда по очереди переписывают git-отслеживаемый файл. Выровнять: одна minor-версия networkx в `pyproject.toml [codegraph]` и `hooks/lib/venv-requirements.sh` (их синхронность держит тест), dev-`.venv` обновить до неё.

**Testing (TDD):**
- pytest: один и тот же граф-фикстура под `PYTHONHASHSEED=0,1,2` (подпроцессы) → идентичный mapping файл → id. Фикстура должна воспроизводить недетерминизм на текущем коде (красный прогон обязателен — если на маленькой фикстуре не краснеет, взять граф крупнее или реальный `graph.json` этого репо).
- pytest: одиночки не получают id кластера и не входят в сводку.
- pytest/bats: две последовательные сборки без изменений кода → `god-nodes.md` и `graph.json` байт-в-байт.

**DoD:**
- [x] Тесты красные до реализации, зелёные после; старые `test_codegraph*` зелёные
- [x] Реальный прогон: `.venv/bin/python scripts/mb-codegraph.py --apply .memory-bank .` три раза с `PYTHONHASHSEED=0,1,2` → `cmp` всех трёх `god-nodes.md` и `graph.json` идентичен
- [x] Реальный прогон: фоновый catchup Stage 3 без изменений в коде не оставляет `god-nodes.md` и тело `graph.json` (всё, кроме строки meta) в `git diff`; `src_root` в meta относительный (AGR-054, 2026-10-01: meta с `generated_at`/`commit` меняется после каждого коммита по построению)
- [x] Bootstrap readiness сверяет установленные версии с `hooks/lib/venv-requirements.sh` и переставляет несовпавший пакет; реальный `~/.claude/hooks/.venv` после bootstrap на networkx 3.6.x (AGR-054)
- [x] Реальный прогон: сборка `.venv/bin/python` и сборка системным `python3` (re-exec в bootstrap-venv) дают побайтно одинаковые `god-nodes.md` и `graph.json`, включая Communities и Bridge files
- [x] Сводка `communities=N` без одиночек; ruff; CHANGELOG; I-219 закрыт в бэклоге

**Code rules:** 0 новых зависимостей; формат `graph.json` меняется только в части `community` у одиночек (задокументировать).

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

Демо-прогон на этом репо после всех стадий: (0) `graph.json` покрывает `.sh`/`.bats` (Stage 6) и в демо-item `/mb work` implementer/verifier/reviewer используют граф с `graph_share` implementer ≥ 0.5 (Stage 7); (1) структурный grep даёт nudge с готовой командой и повторяется после N вызовов; (2) `mb-graph.sh who-calls <Symbol>` отвечает <2с; (3) `mb-semantic-search.py --backend embeddings` отвечает на тёплом индексе без пересборки; (4) во всех 4 активных банках `graph.json` не старше 1 коммита от HEAD (или честный budget-exceeded статус) и `.index/codesearch/` существует. Контрольный замер adoption скриптом по транскриптам — через неделю после раскатки, цель ≥10× по graph/semantic вызовам (43 → ≥400 при сопоставимом объёме, фиксируется в progress.md заметкой).
