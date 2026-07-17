---
topic: svp-docs-wiki
created: 2026-07-17
status: ready
group: sdd-vision-pipeline
interview: self
interview_transcript: context/svp-docs-wiki-interview.md
parent_context: context/sdd-vision-pipeline.md
covers_umbrella: [REQ-036, REQ-037]
---

# Context: svp-docs-wiki (слайс S6, ICE 336)

Команда `/mb docs` — LLM-вики по правилам Карпатого в `docs/` (конфигурируемо): инкрементальный ingest по git-diff от SHA последней фиксации документации, index.md-каталог, append-only log.md, wikilinks, явные противоречия. Родительские решения: D-27, D-28.

## Research Digest

- Правила Карпатого — <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f>: слои sources(immutable)/wiki(LLM-owned)/schema; операции ingest/query/lint; index.md — каталог с одной строкой на страницу; log.md — append-only `## [DATE] operation | description`, parseable unix-тулами; противоречия флагуются явно; знание накапливается.
- `/mb wiki` существующий (`commands/mb.md § wiki`): Haiku-авторы + Sonnet-синтезатор через host-сабагенты, packs → articles → merge-edges — паттерн диспатча переиспользуется; сам wiki НЕ трогается (D-28).
- `docs/` в этом репо уже сайт MkDocs (AGR-010) — конфликт имён: дефолт для этого репо должен быть переопределён (pipeline.yaml docs.path), у обычных проектов дефолт `docs/`.
- SHA-стейт паттерн: `.import-state.json` (mb-import) — образец resume-состояния.

## Assumptions (self-answered, подтверждены пользователем 2026-07-17)

- **S6-A-01**: SHA-стейт — `<docs-path>/.mb-docs-state.json` (переносим вместе с вики — автоматической миграции нет: если файл вручную не переехал вместе с папкой, команда останавливается с `path_mismatch` вместо тихого второго bootstrap; design.md §C3, review 2026-07-17).
- **S6-A-02**: Первый запуск без истории — полный обзор репо → базовые страницы (bootstrap-ingest).
- **S6-A-03**: Структура: `<docs-path>/{index.md, log.md, pages/<slug>.md}`; pages = сущности/концепты кода.
- **S6-A-04**: Генерация — Haiku (страницы) / Sonnet (синтез и противоречия) сабагентами по образцу `/mb wiki`; без API-ключа.
- **S6-A-05**: Путь — `docs.path` в pipeline.yaml (default `docs/`).

## Functional Requirements (EARS)

- **REQ-001** (event-driven): When `/mb docs` runs, the system shall compute the git diff since the last documented SHA and ingest only the changed code into the wiki. <!-- D-27 -->
- **REQ-002** (event-driven): When ingest completes, the system shall update `index.md` (one line per page) and append a `## [DATE] operation | description` entry to `log.md`. <!-- Karpathy -->
- **REQ-003** (ubiquitous): The wiki pages shall cross-reference each other with wikilinks and shall never modify source code — sources stay immutable. <!-- Karpathy layers -->
- **REQ-004** (event-driven): When new code contradicts an existing wiki claim, the system shall flag the contradiction explicitly on the affected page instead of silently overwriting. <!-- Karpathy -->
- **REQ-005** (event-driven): When `/mb docs` runs for the first time with no recorded SHA, the system shall bootstrap the wiki from a full repository overview. <!-- S6-A-02 -->
- **REQ-006** (event-driven): When ingest finishes, the system shall persist the documented SHA in the wiki state file. <!-- S6-A-01 -->
- **REQ-007** (optional): Where pipeline.yaml sets `docs.path`, the system shall generate the wiki there instead of the default `docs/`. <!-- S6-A-05, D-27 -->
- **REQ-008** (ubiquitous): The system shall validate the wiki structure — index/log presence, log entry format, orphan pages — by script. <!-- D-14 determinism -->
- **REQ-009** (ubiquitous): The docs command shall reuse the code graph and `/mb wiki` outputs as fact sources without modifying them. <!-- D-28 -->
- **REQ-010** (unwanted): If the code graph or the internal wiki is missing or unreadable, then the system shall continue ingestion from the git diff and source excerpts alone, report `degraded_sources`, and shall not create or modify the missing source. <!-- NFR-003, AGR-013 pattern, review 2026-07-17 -->
- **REQ-011** (unwanted): If the resolved host provides no subagent dispatch transport for the required model tier, then the system shall stop before writing any wiki file, report `platform_limited`, and leave the state file unchanged. <!-- NFR-003, AGR-013 pattern, review 2026-07-17 -->
- **REQ-012** (unwanted): If the target diff deletes every source file of an existing wiki page, then the system shall retain that page, mark it deprecated with the deleted paths and the target SHA, and shall neither delete the page silently nor leave it unmarked. <!-- Edge cases ниже, review round 2 R2-004 -->

## Non-Functional Requirements

- **NFR-001**: Токен-экономия — инкремент по diff, не полный переобход; Haiku для страниц, Sonnet только для синтеза.
- **NFR-002**: Детерминированная подготовка (diff, packs, состояние) — скриптом; LLM только пишет текст страниц.
- **NFR-003**: Без API-ключа — host-сабагенты (паттерн /mb wiki); при отсутствии транспорта — честная деградация (`platform_limited`), не тихий отказ.

## Constraints

- `/mb wiki` (внутренняя вики банка) не изменяется — D-28; log.md append-only; исходники не модифицируются.
- В этом репо `docs/` занят MkDocs-сайтом (AGR-010) — для догфуда путь переопределяется на `project-wiki/` (вне `mkdocs docs_dir`, см. Decisions ниже).

## Edge Cases & Failure Modes

- Пустой diff (нет незадокументированных изменений) — no-op с сообщением, SHA не двигается.
- Гигантский diff (месяцы без запуска) — батчирование по модулям, лог фиксирует партии.
- Переименование/смена `docs.path` при существующем стейте — автопереноса нет; если стейт найден по
  старому пути, команда останавливается с `error=path_mismatch` (или `ambiguous_state` при
  нескольких кандидатах) вместо тихого второго bootstrap — решение зафиксировано в design.md §C3
  (review 2026-07-17, закрывает прежнюю формулировку «переезжает вместе с папкой» как нереализуемую).
- Rebase/force-push сделал SHA недостижимым — fallback: merge-base или bootstrap-предложение, никогда тихий полный переобход.
- Страница удалённой сущности — помечается deprecated, не удаляется молча (история знаний);
  формализовано ревизией 3 как REQ-012 + `deleted_files` (design.md §C10) + `deprecate` (§C5.1) +
  детерминированный штамп (§C5.3). Триггер — удаление ВСЕХ источников страницы; частичное удаление
  источников — обычное обновление.
- Частичный сбой прогона (краш после записи части страниц) — SHA не продвигается, пока не пройдёт
  lint; следующий прогон переигрывает тот же диапазон диффа (design.md §C5). Повтор идемпотентен по
  `run_id`: журнальная строка несёт `run=<base>..<target>`, повторный append — no-op (§C5.4).
- Отсутствие `graph.json`/`<bank>/codebase/wiki/` — деградация до git diff + excerpt'ов, `degraded_sources` (REQ-010).
- Отсутствие сабагентного транспорта на хосте — остановка до записи, `platform_limited` (REQ-011).

## Decisions (review 2026-07-17, ревизии 2–3)

- **Lint публичность закрыта**: `mb-docs.py lint` — внутренняя обязательная проверка каждого
  обычного прогона; публичный `/mb docs --lint` не входит в v1 (снимает прежний Open Question).
- **docs.path precedence**: `--docs-path` CLI > `pipeline.yaml: docs.path` > дефолт `docs/`;
  containment-проверка (repo-relative, без `..`, без symlink-выхода) — design.md §C3.
- **Шов прогона (ревизия 3)**: детерминированная run-логика вынесена из промпта в
  `memory_bank_skill/docs_run.py` (`plan` read-only → диспатч LLM → `apply` — единственный writer).
  Промпт `commands/mb.md § docs` отвечает только за диспатч сабагентов; всё остальное тестируется на
  production-CLI (design.md §C5 + § «Что здесь НЕ проверяется кодом»).
- **Обнаружение переноса стейта — без git-index (ревизия 3)**: filesystem-scan видит tracked,
  untracked и ignored одинаково — прежний git-tracked-поиск молча пропускал валидный untracked-стейт
  и давал второй bootstrap (design.md §C3).
- **Lock (ревизия 3)**: потребляется `mb_lock_acquire`/`mb_lock_release` из `scripts/_lib.sh`
  (S4-C6, umbrella Interface 2) — liveness-reclaim по `kill -0`, атомарный mv-reclaim. Прежнее
  утверждение «крах процесса освобождает лок» неверно (`mkdir`-каталог переживает SIGKILL) и
  удалено; авто-слом по возрасту >1ч удалён (допускал второго writer'а поверх живого прогона).
  Владелец лока — живая bash-обёртка `scripts/mb-docs-apply.sh`, т.к. токен лока несёт PID
  **вызывающей оболочки** (design.md §C5.2).
- **Транспорт (ревизия 3)**: резолвится существующим `scripts/mb-agent-caps.sh resolve --role
  docs_author|docs_synthesizer`; ненулевой exit → `platform_limited`, exit 6, ноль записей.
  `substituted=true` (exit 0) — легитимный сконфигурированный фолбэк, а не отказ; строгость
  включается существующим `dispatch.on_none_available: error` (design.md §C7).
- **Dogfood override этого репозитория**: `project-wiki/` (не `docs/wiki` — тот всё ещё внутри
  `mkdocs docs_dir: docs`); публикация сгенерированной вики остаётся вне объёма слайса.
- **Межслайсовая зависимость**: задача, трогающая `references/pipeline.default.yaml` и
  `scripts/mb-pipeline-validate.sh`, блокируется `svp-sdd-core#7` (тот же файл-пара); frontmatter
  спеки несёт `blocked_by: [svp-sdd-core]`.

### Ревизия 3 (round-3 codex spec-review, 2026-07-18)

- **R3-001**: первый bootstrap-apply не отклоняется как `stale_run` — `apply` нормализует
  `expected_base = state.sha | bootstrap` так же, как `plan` (C5.2).
- **R3-002**: `mb-docs-apply.sh --plan --results`; `run_id`/`base_sha`/`target_sha`/`docs_path`/
  `deprecate`/`degraded_sources` авторитетны из плана, схема результатов синтезатора их не несёт →
  LLM не подменяет SHA; `degraded_sources` доезжает до `applied`-вывода (REQ-010).
- **F-008**: page schema = writer API (`summary` добавлен); index one-line из summary-блока;
  `write_page(page)`.
- **F-010**: manifest разведён — `durable_writes_completed`/`control_writes`/`pending_state_path`/
  `sources`; финальный стейт — `os.replace` из temp только после зелёного lint.
- **R3-004**: REQ-004 — код: структурный `contradictions[]` + детерминированный рендер (C5.5);
  семантика обнаружения — non-gated промпт.
- **R3-005**: положительный lint-код `missing_cross_reference` (REQ-003).
- **R3-007**: `log_entry.description` валидируется до записи (single-line, без CR/LF/`## [`/`run=`).
- **R3-008**: непустой `source_files` у нового page; легаси-пустой → `page_provenance:<slug>` в
  `degraded_sources`, страница не депрекейтится.
- **R3-003/CPR-B**: жёсткая зависимость от lock-helper S4 — `blocked_by: [svp-sdd-core,
  svp-roadmap-backlog-db]`, T4 `Blocked-by … svp-roadmap-backlog-db#2`, fallback-фраза удалена; lock
  выровнен на S4-C6 ревизии 4 (owner-marker + targeted `rmdir`, не `mv`). Umbrella §DAG/tasks уже
  несут ребро S4→S6 — cross-package request не требуется.

## Out of Scope

- Query-операция Карпатого как отдельная команда (будущий слайс); публичный `/mb docs --lint`
  (lint остаётся внутренним, см. Decisions); публикация вики на сайт; документация НЕ-кода (процессы, ADR).

## Open Questions

Нет открытых вопросов — закрыты ревизиями 2–3 (см. Decisions).
