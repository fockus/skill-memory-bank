# Review: session-memory + memsearch comparison + code-graph adoption
Date: 2026-07-15
Method: 3 parallel mb-research agents (session-memory / memsearch / graph) + own spot-checks. All claims file:line-grounded; key ones re-verified in the main session.

## Verdict (TL;DR)

1. **Session-память работает и архитектурно лучше, чем задокументирована** (в коде — гибридный semantic+RRF recall, в SKILL.md описан только ripgrep). Но найдено 2 реальных бага качества (чанкинг, висячие эмбеддинги) и 8 расхождений доков с кодом.
2. **memsearch не «лучше», а другой по трейд-оффам**: LLM-саммари каждого хода + Milvus hybrid + drill-down в сырой транскрипт против нашего zero-LLM per-turn лога + локального fastembed+RRF. Наши слабые места — качество чанков и отсутствие anchor-а в транскрипт; их слабое место — стоимость (Haiku на каждый Stop) и тяжёлая зависимость (Milvus/uv bootstrap).
3. **Агенты не используют граф, потому что честно выполняют инструкцию**: граф в этом репо перманентно stale (последняя сборка 2026-05-27, 263 коммита назад, без meta-стампа → `status: stale (unknown)` навсегда), а routing-блок у имплементеров велит при stale падать на Grep. Автоперестройки нет нигде.

---

## 1. Session-память: как работает на самом деле

- **Capture**: `Stop` hook (`hooks/mb-session-turn.sh:141-143`) пишет одну строку на ход в `session/<date>_<hhmm>_<sid8>.md`: текст запроса юзера + имена тулов + файлы + ok/err + numstat. Без LLM. Кап: 600 символов/строка (`MB_SESSION_BULLET_MAX`), 12 файлов. Мысли ассистента и результаты тулов не сохраняются.
- **Summary**: Haiku на SessionEnd/catch-up, строго 4 секции (`mb-session-summarize.sh:74-83`); gated Sonnet-judge пишет 0-2 notes/ (`mb-session-end.sh:56-66`).
- **Recall** (`hooks/mb-recall.sh`): семантика (fastembed, cosine ≥0.3, веса note>session>transcript) + лексика (rg) → **RRF-фьюжн** (`memory_bank_skill/rrf.py`). Компактный индекс ~15 ток/строка, `--expand` для тел.
- **Injection**: UserPromptSubmit → semantic-only top-5 (≥0.35, 3s timeout); SessionStart → `_recent.md` (кап 4KB).

### Дефекты (ранжировано)
1. **HIGH — чанкинг не выровнен по строкам** (`hooks/lib/semantic_chunk.py:26-65`): `_split_long` схлопывает `\n` в пробелы, overlap `_pack` режет по сырому char-offset. Итог: summary-строка чанка начинается с середины пути (`rs/fockus/Apps/...`) — ровно то, что видно в живых инъекциях. Фикс: чанковать по границам bullet'ов Live log.
2. **MEDIUM — `age: "?"` = висячие эмбеддинги**: `mb-session-prune.sh --apply` удаляет файлы, не трогая семантический индекс; инкрементальный reindex не прунит (`indexer.py:73-75`). Фикс: prune → full reindex, либо recall дропает хиты с несуществующим source.
3. **MEDIUM — молчаливая потеря при 600-char cap**: длинные делегированные сообщения режутся без структурного маркера `truncated: true`.
4. **MEDIUM — доки врут** (`references/session-memory.md`): схема frontmatter (agent/ended/mtime/summary_backend — никогда не пишутся), формат Live log (multi-line vs реальный single-line), 6 секций Summary vs реальные 4, `## Diagnostics` — не существует, `MB_RECALL` — мёртвая переменная, `MB_AUTO_CAPTURE` default в доке `off`, в коде `auto` (легаси-писатель progress.md включён по умолчанию параллельно session-памяти!), `MB_CATCHUP_MAX` 5 vs 2. И `SKILL.md:439` до сих пор описывает recall как «ripgrep», хотя он hybrid+RRF.

## 2. Сравнение с memsearch (zilliztech/memsearch v0.4.6)

| Измерение | Наш MB session-memory | memsearch |
|---|---|---|
| Capture | Stop hook, 1 строка/ход, **без LLM**, $0 | Stop hook, 2-10 буллетов через `claude -p haiku` **каждый ход** |
| Источник правды | `session/*.md` (факт-лог) | `.memsearch/memory/YYYY-MM-DD.md` (LLM-журнал) |
| Индекс | fastembed + numpy (`.index/`), локально | Milvus Lite (vector DB), dense+BM25 sparse |
| Поиск | semantic + rg → **RRF** (наш код) | dense + BM25 → **RRF(k=60)** в Milvus + опц. cross-encoder reranker |
| Drill-down | compact index → `--expand` (2 уровня) | chunk → expand → **±3 хода из сырого JSONL-транскрипта** (3 уровня, anchor `<!-- session/turn/transcript -->`) |
| Инъекция | авто: top-5 на каждый промпт + _recent.md | авто: только hint `[memsearch] Memory available`; поиск pull-based |
| Кураторский слой | status.md/notes/ (наши, богаче) | PROJECT.md/USER.md (off by default, Sonnet, 24h gate) |
| Зависимости | python3 + fastembed venv | uv/uvx bootstrap, pymilvus, milvus_lite, ONNX Runtime |

**Что стоит позаимствовать**: (a) anchor в сырой транскрипт (у нас `transcript:` уже есть во frontmatter — нет только инструмента «покажи ±3 хода вокруг turn_uuid»); (b) выравнивание чанков по заголовкам/буллетам (их chunker heading-aware — наш баг №1); (c) их подход «hint вместо авто-инъекции» — спорно, наша авто-инъекция агрессивнее, но при текущем качестве строк она шумит.
**Что у нас лучше**: $0 capture (без LLM на каждый ход), редакция секретов + `<private>`, судья→notes/, RRF уже есть, нет тяжёлого Milvus.

## 3. Граф: почему имплементеры его не используют

Корневые причины (ранжировано, по силе доказательств):
1. **Граф перманентно stale** — сборка 2026-05-27 (28a40f2), 263 коммита назад; первый ряд graph.json — не meta (стамп-фича I-087 появилась 2026-07-04, ПОЗЖЕ последней сборки) → `mb-graph-query.py status` = `stale (unknown)` навсегда. Routing-блок имплементеров (`agents/mb-developer.md:36-41` и клоны) велит: stale → Grep/Glob/Read. **Агенты выполняют инструкцию.**
2. **Нет ни одного автопути перестройки**: git-hook `post-commit-codegraph.sh` opt-in и не установлен (`.git/hooks/post-commit` нет); `/mb work` не перестраивает; `/mb start` предлагает только `/mb map` при пустом codebase/. Даже nudge-hook (`mb-graph-nudge.sh:71-72`) молчит при stale — safety-net отключается ровно тогда, когда нужен.
3. **Primacy-файл слеп к графу**: `mb-engineering-core.md` (первый в композиции промпта `work.md:338-340`) — ноль упоминаний графа.
4. **Недостижимая проверка**: роли велят «проверь строку Code graph в `/mb context`», но dispatched-промпт `/mb context` не содержит; в том же промпте tooling-core даёт другой протокол (fail-open). Два конфликтующих протокола свежести.
5. **Асимметрия прав**: только mb-research'у разрешено перестроить stale-граф; имплементерам — только фолбэк. Граф-сирота никем не чинится.

### Рекомендации
1. Пересобрать граф сейчас + поставить post-commit hook в этом репо.
2. Автообновление в `/mb work` шаг 5g (после коммита item'а) — инкрементальный `mb-codegraph.py --apply`.
3. Дать имплементерам право одноразовой перестройки при stale (1 строка в `mb-tooling-core.md`).
4. Убрать `/mb context`-зависимую формулировку из role-файлов (self-contained `mb-graph-query.py status`).
5. Одна строка-указатель на routing в `mb-engineering-core.md`.
6. (session-memory) Починить чанкинг по bullet-границам; prune → reindex; маркер truncated; актуализировать `references/session-memory.md` (8 пунктов) и решить судьбу `MB_AUTO_CAPTURE=auto` (двойная запись по умолчанию — похоже, не задумано).
