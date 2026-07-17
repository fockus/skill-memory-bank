---
topic: svp-docs-wiki
group: sdd-vision-pipeline
ice: {impact: 6, confidence: 8, ease: 7}
ice_confirmed: false
blocked_by: [svp-sdd-core, svp-roadmap-backlog-db]
covers_umbrella: [REQ-036, REQ-037]
status: ready
---

# Requirements: svp-docs-wiki

> Spec triple — see also: design.md, tasks.md.
> Слайс S6 группы `sdd-vision-pipeline` (ICE 336, self-interview). Контекст: `context/svp-docs-wiki.md`;
> транскрипты: `context/svp-docs-wiki-interview.md` + родительский.
>
> Ревизия 3 (2026-07-17): закрыт круг 2 spec-ревью (F-004…F-010 PARTIAL + R2-001…004). Добавлен
> REQ-012 (удалённые сущности — решение из контекста, потерянное в ревизии 2, R2-004); Scenario 5
> переведён с ручной проверки на детерминированные артефакты после генерации (R2-003); добавлен
> Scenario 11 (перенос стейта детектируется без участия git-index, F-006).
>
> EARS: Ubiquitous `THE SYSTEM SHALL` · Event `WHEN …` · State `WHILE …` · Optional `WHERE …` · Unwanted `IF … THEN …`

## Requirements (EARS)

### Requirement 1: Инкрементальный ingest по diff

**User Story:** As a maintainer, I want `/mb docs` to document only what changed since the last pass, so that documentation compounds cheaply instead of being regenerated.

#### Acceptance Criteria

- **REQ-001** (event-driven): When `/mb docs` runs, the system shall compute the git diff since the last documented SHA and ingest only the changed code into the wiki. <!-- D-27 -->
- **REQ-005** (event-driven): When `/mb docs` runs for the first time with no recorded SHA, the system shall bootstrap the wiki from a full repository overview. <!-- S6-A-02 -->
- **REQ-006** (event-driven): When ingest finishes, the system shall persist the documented SHA in the wiki state file. <!-- S6-A-01 -->

### Requirement 2: Структура вики по Карпатому

**User Story:** As a reader (human or agent), I want the wiki to follow the Karpathy rules — index catalog, append-only log, wikilinks, explicit contradictions — so that knowledge stays navigable and trustworthy.

#### Acceptance Criteria

- **REQ-002** (event-driven): When ingest completes, the system shall update `index.md` (one line per page) and append a `## [DATE] operation | description` entry to `log.md`. <!-- Karpathy -->
- **REQ-003** (ubiquitous): The wiki pages shall cross-reference each other with wikilinks and shall never modify source code — sources stay immutable. <!-- Karpathy -->
- **REQ-004** (event-driven): When the synthesizer emits a structured contradiction record between an existing wiki claim and new evidence, the system shall validate the record and render the contradiction explicitly on the affected page instead of silently overwriting the claim. <!-- Karpathy, R3-004 -->
- **REQ-008** (ubiquitous): The system shall validate the wiki structure — index/log presence, log entry format, orphan pages — by script. <!-- NFR-002 -->
- **REQ-012** (unwanted): If the target diff deletes every source file of an existing wiki page, then the system shall retain that page, mark it deprecated with the deleted paths and the target SHA, and shall neither delete the page silently nor leave it unmarked. <!-- context.md Edge cases, R2-004 -->

### Requirement 3: Конфигурация и границы

**User Story:** As a project with an occupied `docs/` folder, I want the wiki path configurable and the internal `/mb wiki` untouched, so that the feature composes with existing setups.

#### Acceptance Criteria

- **REQ-007** (optional): Where pipeline.yaml sets `docs.path`, the system shall generate the wiki there instead of the default `docs/`. <!-- S6-A-05 -->
- **REQ-009** (ubiquitous): The docs command shall reuse the code graph and `/mb wiki` outputs as fact sources without modifying them. <!-- D-28 -->

### Requirement 4: Честная деградация без graph/wiki/сабагентного транспорта

**User Story:** As an operator on any of the 8 supported hosts, I want `/mb docs` to degrade honestly when the code graph, the internal wiki, or subagent dispatch is unavailable, so that documentation is never silently wrong or silently produced from nothing.

#### Acceptance Criteria

- **REQ-010** (unwanted): If the code graph or the internal wiki is missing or unreadable, then the system shall continue ingestion from the git diff and source excerpts alone, report `degraded_sources` in the run result, and shall not create or modify the missing source. <!-- NFR-003, AGR-013 pattern -->
- **REQ-011** (unwanted): If the resolved host provides no subagent dispatch transport for the required model tier, then the system shall stop before writing any wiki file, report `platform_limited`, and leave the state file unchanged. <!-- NFR-003, AGR-013 pattern -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Increment after three sessions
**Covers:** REQ-001, REQ-002, REQ-006

- GIVEN стейт с SHA abc123 и 14 изменённых файлов после него
- WHEN `/mb docs` запускается
- THEN обновлены только страницы затронутых сущностей, index.md дополнен, log.md получил append-строку `## [2026-07-17] ingest | run=abc123..<target-40-hex> 14 files, 3 pages updated` (обязательный `run=<run_id>` сразу после `|` — грамматика C4), стейт указывает на тот же `<target-40-hex>`
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: First run bootstraps state
**Covers:** REQ-005

- GIVEN стейт-файла нет
- WHEN `/mb docs` запускается
- THEN полный обзор → базовые страницы + index + log с bootstrap-записью `## [<date>] bootstrap | run=bootstrap..<target-40-hex> <description>`; стейт указывает на `<target-40-hex>` (первый bootstrap-apply не отклоняется как `stale_run`)
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Contradiction is surfaced
**Covers:** REQ-004

- GIVEN страница утверждает «конфиг читается из env»
- WHEN diff показывает переход на pipeline.yaml
- THEN страница обновлена с явным блоком противоречия/supersede, а не молчаливой заменой
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Unreachable SHA falls back
**Covers:** REQ-001

- GIVEN история переписана force-push'ем, SHA недостижим
- WHEN `/mb docs` запускается
- THEN предложен merge-base или bootstrap; тихого полного переобхода нет
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Occupied docs directory
**Covers:** REQ-007

- GIVEN pipeline.yaml: `docs.path: project-wiki/`, каталог `docs/` занят MkDocs-контентом с известными content-хешами
- WHEN прогон исполняется до конца (`mb-docs.py plan` → фикстурный результат агентов → `mb-docs-apply.sh`)
- THEN после прогона существуют `project-wiki/index.md`, `project-wiki/log.md`, `project-wiki/pages/<slug>.md` и `project-wiki/.mb-docs-state.json` со стейтом на target SHA; манифест прогона не содержит ни одного пути вне `project-wiki/`; все хеши под `docs/` не изменились
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Sources stay immutable across a run
**Covers:** REQ-003, REQ-009

- GIVEN graph.json, вывод `/mb wiki` и страницы вики с известными content-хешами
- WHEN `/mb docs` запускается
- THEN сгенерированные страницы связаны друг с другом wikilinks, graph.json и внутренняя вики остаются read-only входами, их хеши после прогона не изменились
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Lint returns a machine-readable verdict
**Covers:** REQ-008

- GIVEN валидная фикстура вики и отдельная сломанная фикстура (битый wikilink, отсутствующая запись в index)
- WHEN `mb-docs.py lint` запускается на каждой
- THEN валидная фикстура даёт exit 0 без вывода, сломанная — exit 1 со стабильными строками `error=<code>` на каждое нарушение
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Missing graph/wiki degrades honestly
**Covers:** REQ-010

- GIVEN в репозитории нет `.memory-bank/codebase/graph.json` и нет `.memory-bank/codebase/wiki/`
- WHEN `/mb docs` запускается
- THEN паки всё равно строятся из git diff и исходных excerpt'ов, отчёт о прогоне перечисляет `degraded_sources`, ни graph.json, ни wiki/ не создаются
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Missing host dispatch stops before writing
**Covers:** REQ-011

- GIVEN хост без требуемого транспорта сабагентного диспатча (`mb-agent-caps.sh resolve --role docs_author` завершается ненулевым кодом под `MB_CAPS_FIXTURE`)
- WHEN `mb-docs.py plan` запускается
- THEN команда завершается кодом 6 до записи любой page/index/log/state, на stderr — `result=platform_limited platform_limited=subagent-dispatch role=docs_author`
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Deleted entity page is deprecated
**Covers:** REQ-012

- GIVEN стейт содержит страницу `parser-core` с `source_files: ["src/parser.py"]`, и diff до target SHA удаляет `src/parser.py`
- WHEN прогон исполняется до конца
- THEN `pages/parser-core.md` существует, несёт управляемый блок со `Status: deprecated`, перечисленным `src/parser.py` и target SHA; файл не удалён, прежнее тело страницы сохранено
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Untracked state left behind is detected
**Covers:** REQ-006, REQ-007

- GIVEN `docs.path` переключён на `project-wiki/`, а старый `docs/.mb-docs-state.json` остался на месте и НЕ добавлен в git-index (untracked или ignored)
- WHEN `mb-docs.py plan` запускается
- THEN команда завершается кодом 2 с `error=path_mismatch old_path=docs/.mb-docs-state.json new_path=project-wiki/`; второго bootstrap не происходит
<!-- /mb-scenario:11 -->
