---
topic: svp-roadmap-backlog-db
created: 2026-07-17
status: ready
group: sdd-vision-pipeline
interview: self
interview_transcript: context/svp-roadmap-backlog-db-interview.md
parent_context: context/sdd-vision-pipeline.md
covers_umbrella: [REQ-024, REQ-025, REQ-026, REQ-027, REQ-028, REQ-029, REQ-041]
---

# Context: svp-roadmap-backlog-db (слайс S4, ICE 432)

Roadmap и backlog как «MD-база данных»: ICE-приоритизация, проценты/счётчики из чекбоксов, Group-секции, беклог-стейт-машина с иерархией и agent-briefs, out-of-scope-реестр. Родительские решения: D-14, D-15, D-20, D-31.

## Research Digest

- `scripts/mb-roadmap-sync.sh` — существующий autosync (Now/Next/Parallel-safe из frontmatter планов) — точка расширения.
- `scripts/mb-work-checkbox.sh` — чекбоксы уже машинно ведутся — источник для %/счётчиков.
- `commands/mb.md:62,1354-1420` — текущий беклог: I-NNN, NEW/TRIAGED/PLANNED/DONE/DECLINED/DEFERRED, `mb-idea.sh`/`mb-idea-promote.sh` — расширяются, не переписываются.
- `scripts/mb-migrate-structure.sh` — образец идемпотентного мигратора с backup (`.pre-migrate/<ts>/`).
- Референс стейт-машины: triage-скил mattpocock/skills (needs-info петля, ready-for-agent, wontfix KB, AGENT-BRIEF durability).
- Bootstrap-группа в роадмепе уже размечена вручную (`roadmap.md § Group: sdd-vision-pipeline`) — цель автоматизации.
- Реальный инвентарь легаси-статусов беклога (grep по `.memory-bank/backlog.md`): `NEW`(70), `DECLINED`(11), `RESOLVED[ <date>][ — <hash>]`(5), `DONE[ <date>]`(9), `DEFERRED`(2), `OPEN`(3), `PLANNED`(1), `PROPOSED`(1); `TRIAGED` пока не встречается, но валиден как целевое состояние.
- Все 8 child-спек группы уже несут `group`/`ice`/`blocked_by` во frontmatter `requirements.md` (родитель, Interfaces п.4). Сегодня `ice` там — plain integer (`ice: 432`), но это **черновая форма bootstrap'а**, а не контракт: родитель (ревизия 3, Interfaces п.4) фиксирует хранение **компонентов** `{impact: 1..10, confidence: 1..10, ease: 1..10}` со score = I×C×E, вычисляемым скриптом. Ревизия 2 этой спеки ошибочно канонизировала черновик по эмпирике; ревизия 3 выровнена по родителю (design.md C1), миграция 8 frontmatter — централизованно оркестратором (design.md § Cross-slice requests).
- Lock-паттерн `mb-agree.sh::_lock_acquire/_lock_release` (атомарный `mkdir`, PID-liveness reclaim) — переиспользуется по liveness-решению, не изобретается заново (F-012), **но с другим механизмом критической секции** (родительский Interface 2, ревизия 4, R3-001): маркер `<lock>/owner.<token>` + targeted `rmdir` мёртвого токена (`rmdir owner.<D>` затем `rmdir <lock>` только на пустом) вместо `owner`-файла и bulk-`rm -rf`. `mv`-reclaim ревизии 3 отменён — он тоже допускал двух писателей (отставший reclaim'ер двигал уже ДРУГОЙ, свежий лок). Owner-marker закрывает гонку целиком: reclaim целится в именованный мёртвый токен, а `rmdir <lock>` не проходит при живом `owner.<Z>`. TTL — только owner-less окно.
- **Варианты stale-break в `mb-agree.sh` пробовались и были отвергнуты** (`mb-agree.sh:60-78`) — за (а) ключевание решения на mtime/TTL и (б) вторичный `.reclaiming`-мьютекс с собственным blind-rm-rf. Контракт C6 сохраняет liveness-ключевание и не вводит мьютекса; owner-marker + targeted `rmdir` не использует ни `mv`, ни `rm -rf` → это не повтор disproved-дизайна. Файл `mb-agree.sh:56-116` обязателен к чтению перед реализацией (D-29).
- **Реальная коллизия I-NNN в этом репо** (`backlog.md`, запись I-079): `mb-idea.sh:65` берёт максимум только из `backlog.md`, из-за чего выдал `I-075` при существующем `I-075` в `progress.md` (пришлось править руками на I-078). Прямое нарушение инварианта «I-NNN никогда не переиспользуются» (`CLAUDE.md`) → глобальный аллокатор обязателен (design.md C6).
- `/mb consolidate` физически ПЕРЕНОСИТ progress-записи в `progress-archive.md` (`scripts/mb-consolidate.sh:24`) → это самостоятельный источник аллокации: после консолидации ID покидают `progress.md`.
- `mb-idea-promote.sh:69-75,102-107` принимает NEW|TRIAGED и пишет токен `PLANNED`, которого в машине D-15 НЕТ → скрипт требует явной миграции, иначе после S4 каждый его вызов сажает состояние вне алфавита (design.md C7).

## Assumptions (self-answered, подтверждены пользователем 2026-07-17)

- **S4-A-01**: `ice: {impact, confidence, ease}` и `group:` — YAML frontmatter спек (requirements.md) и планов. — Ревизия 2 ошибочно «скорректировала» это на plain-int по эмпирике bootstrap-frontmatter; **ревизия 3 (2026-07-17) возвращает исходное решение**: хранятся компоненты (каждый 1..10), score = I×C×E считает скрипт, `ice_confirmed` фиксирует подтверждение пользователя (D-14: цифры — предложение LLM). Схема — `design.md` C1, выровнена по родительскому Interfaces п.4 (ревизия 3).
- **S4-A-02**: Group-секции рендерит `mb-roadmap-sync.sh` внутри autosync-fences (новый блок); ручные Group-секции вне fences не трогаются.
- **S4-A-03**: Миграция беклога — отдельный идемпотентный скрипт с backup (паттерн migrate-structure); `parent:` — поле в заголовочной строке I-NNN.
- **S4-A-04**: Out-of-scope-реестр — секция `## Out of scope` в backlog.md (не отдельная папка).
- **S4-A-05**: Новый валидатор `mb-bank-lint.sh` — формат roadmap.md + backlog.md.

## Functional Requirements (EARS)

- **REQ-001** (ubiquitous): The roadmap-sync script shall order the Next queue by an ICE score the script itself computes as `impact × confidence × ease` from the frontmatter components (each `1..10`, per design.md C1), honoring an explicit `pin: N` override, and shall preserve today's ordering byte-for-byte in any section where no item carries `ice` or `pin`. <!-- D-14, S4-A-01 -->
- **REQ-002** (ubiquitous): The roadmap-sync script shall render per-spec and per-plan progress — percentage plus counters of stages/tasks planned, in progress and done — computed from checkbox state. <!-- D-14 -->
- **REQ-003** (event-driven): When specs share a `group:` frontmatter value, the roadmap-sync script shall render a group section with intra-group ICE order, member statuses, blockers and aggregated progress. <!-- D-31, S4-A-02 -->
- **REQ-004** (ubiquitous): The system shall validate `roadmap.md`, `backlog.md` and the frontmatter that feeds them — ICE components and their `1..10` range, the user-confirmation marker, `pin` and `group` — via `mb-bank-lint.sh`, reporting violations as key=value lines. <!-- D-14, S4-A-05 -->
- **REQ-005** (ubiquitous): The backlog shall implement the state machine NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX with transitions validated by script, and every writer that changes an item's state — including the idea-promotion script — shall go through that single validated primitive. <!-- D-15 -->
- **REQ-006** (optional): Where a backlog item declares `**Parent:** <I-NNN|none>`, the system shall treat an `I-NNN` parent as a subtask relationship and render the hierarchy in listings; an absent field or `none` denotes a root. <!-- D-15, S4-A-03; ревизия 4 R3-006: parent=spec убран, только I-NNN|none -->
- **REQ-013** (event-driven): When the rendered roadmap order uses at least one valid but unconfirmed ICE, the roadmap-sync script shall emit an observable `unconfirmed_ice=<slugs>` signal and shall not change the order because of the unconfirmed state, so that the orchestrator can escalate to the user; confirmation flips `ice_confirmed` to `true` in the spec frontmatter (orchestrator-only writer). <!-- D-14, AGR-021 (ревизия 4) -->
- **REQ-007** (event-driven): When a backlog item moves to READY, the system shall require an agent brief that is behavioral and free of file paths and line numbers. <!-- D-20 -->
- **REQ-008** (event-driven): When a backlog item is closed as WONTFIX with a rejection, the system shall record the precedent in the `## Out of scope` section and surface it when a similar idea arrives. <!-- D-15, S4-A-04 -->
- **REQ-009** (event-driven): When a deferred spec is registered with the `[SPEC:<group>]` prefix, the system shall parse it into the decomposed-spec registry with its group attribution — both when the record is written and when a pre-existing record is migrated. <!-- D-31, C7 из S1 -->
- **REQ-010** (event-driven): When the backlog migration script runs on a legacy backlog, the system shall create a backup and upgrade the format idempotently. <!-- S4-A-03 -->
- **REQ-011** (ubiquitous): The system shall parse legacy backlog entries without the new fields unchanged, and shall report a legacy state token as a migration hint rather than an error. <!-- D-26 -->
- **REQ-012** (ubiquitous): The system shall compute counters, percentages and ICE scores exclusively by script — hand-edits to generated numbers shall be flagged by the lint. <!-- D-14 -->

## Non-Functional Requirements

- **NFR-001**: Roadmap/backlog остаются человеко-читаемым Markdown (git-diff дружелюбие) — никаких JSON/SQLite.
- **NFR-002**: mb-roadmap-sync остаётся идемпотентным; контент вне fences — byte-identical.
- **NFR-003**: All backlog-mutating scripts (`mb-idea.sh`, `mb-idea-promote.sh`, `mb-backlog-state.sh`, `mb-backlog-migrate.sh`) shall serialize ID allocation and file mutation through one shared exclusive lock and shall obtain every new `I-NNN` from one shared allocator that takes the maximum across ALL bank-wide allocation sources (`backlog.md`, `progress.md`, `progress-archive.md`, `index.json` when present) — no writer implements its own allocator — guaranteeing globally unique identifiers and atomic (temp-file + rename) writes under concurrent invocation. <!-- design.md C6 -->
- **NFR-004**: All new/extended shell scripts in this slice shall run correctly under Bash 3.2 (macOS default) and current Bash (Linux), avoid associative arrays/`mapfile`/GNU-only flags without a portable fallback, and handle a `.memory-bank` path containing spaces. <!-- design.md C3/C4/C5 -->

## Constraints

- `mb-idea.sh`/`mb-idea-promote.sh` расширяются, не переписываются; существующие данные не портятся (легаси-статусы маппятся мигратором: PLANNED→IN-PROGRESS). **Одно осознанное исключение** (design.md C7, ревизия 3): `mb-idea-promote.sh` больше не пишет токен `PLANNED` и требует состояние `READY` — прямое следствие D-15 (READY — единственное предсостояние IN-PROGRESS) и D-20 (READY требует бриф). Это документируемая смена поведения (T5 + stderr-ремедиация), а не тихая поломка; альтернатива «легаси-ветка пишет PLANNED дальше» отклонена — она возвращает токен вне алфавита и делает READY-дисциплину мёртвой буквой.
- Монотонные I-NNN никогда не переиспользуются (инвариант `CLAUDE.md`; сегодня нарушен — коллизия I-075/I-079, см. Research Digest); progress.md append-only.
- Финальная таблица легаси→новых статусов зафиксирована в `design.md` C4 (не открытый вопрос, спецификация исполнима без догадок реализатора).
- Легаси WONTFIX-записи (мигрированные из `DECLINED`) без `**Reason:**` — grandfathered навсегда: `mb-bank-lint.sh` не требует Reason задним числом для записей без единой v2-метастроки (`**Type:**`/`**Parent:**`/`**Brief:**`/`**Reason:**`).
- `mb-agree.sh` не рефакторится этим слайсом; общий lock-алгоритм выносится в `scripts/_lib.sh` параллельно ему — то же liveness-решение, но другой механизм критической секции (owner-marker `<lock>/owner.<token>` + targeted `rmdir` вместо `owner`-файла и bulk-`rm -rf`, родительский Interface 2 ревизии 4, R3-001); контрактный тест держит общие поведения в синхроне (parity-часть) и фиксирует расхождение (divergence-часть).
- ICE-компоненты (1..10) и score = I×C×E — вычисление только скриптом; frontmatter 8 child-спек мигрирует оркестратор централизованно (design.md § Cross-slice requests), скрипта-мигратора frontmatter слайс не содержит (plain-int нигде не выпущен).

## Edge Cases & Failure Modes

- Спека без `ice:` — попадает в конец Next/Group с пометкой `no-ice` (lint warning), не ломает сортировку остальных (алгоритм — design.md C2).
- Битый `ice` (не flow-mapping / не 3 ключа / компонент вне 1..10 / plain-int) — lint error `invalid_ice`, элемент уходит в no-ice tail, sync НЕ падает; секция, где `ice` есть только битый, остаётся в legacy mode (byte-identical).
- Валидный `ice` без `ice_confirmed: true` — метка `(unconfirmed)` в рендере + warning `ice_unconfirmed`; на порядок подтверждение не влияет никогда (D-14).
- Одинаковый score/оба без `ice` — tie-break: `created` (context frontmatter для спек / дата в имени файла для планов) ↑, затем `topic` ↑, затем `rel` ↑ (тотальный порядок даже при совпадении topic); при полном отсутствии `ice`/`pin` у ВСЕХ элементов секции работает legacy mode — вызывается сегодняшний DFS `dependency_order()`, порядок byte-identical (эмпирика F-003: DFS и раундовый Kahn на графе A→C при файловом порядке A/B/C дают `C,A,B` против `B,C,A` — поэтому это разные режимы, а не один алгоритм).
- Дублирующийся `pin: N` у двух узлов — оба участвуют остальными ключами сортировки + lint warning `duplicate_pin`; `pin` никогда не «перепрыгивает» незакрытую зависимость (применяется только внутри готового topological frontier).
- Ручная правка счётчика % — `mb-bank-lint.sh --check`-путь флагует `progress_mismatch`; следующий `mb-roadmap-sync.sh` молча перезаписывает вычисленным значением (никогда не парсится обратно из roadmap.md).
- Недопустимый переход статуса (DONE → NEW) — `mb-backlog-state.sh` отказывает exit 1 с подсказкой допустимых переходов из текущего состояния.
- Осиротевшая группа (`## Group: <slug>` внутри fence, спеки с таким `group:` больше нет) — warning `orphan_group` + заголовок исчезает из нового блока; источник осиротевших слагов — только текущий fence, т.к. из скана `specs/*/requirements.md` такая группа прийти не может (R2-006); ручные `## Group:` вне fences реестром не считаются.
- Parent-цикл или ссылка на несуществующий I-NNN в `list --tree` — exit 1 с полным путём/причиной, пустой stdout, без частичного дерева.
- Два параллельных `mb-idea.sh`/`mb-backlog-state.sh`/`mb-backlog-migrate.sh` — общий mkdir-lock (`<bank>/.locks/backlog.lock`, design.md C6) + единственный глобальный аллокатор гарантируют разные I-NNN и отсутствие потерянной записи.
- Не-мигрированный банк под `mb-bank-lint.sh` — легаси-токены (`OPEN`/`PLANNED`/`DECLINED`/…) дают warning `legacy_state` с подсказкой мигратора, НЕ error `invalid_state` (иначе REQ-011 нарушен и любой существующий банк краснеет в день релиза).
- `mb-idea-promote.sh` на записи в `NEW`/`TRIAGED` — exit 2 с ремедиацией (цепочка до READY), план не создаётся, файл не мутируется (design.md C7).

## Out of Scope

- Runtime-исполнение групп (`/mb work <group>`) — S3; ADaPT-записи в беклог — S5; экспорт во внешние трекеры.

## Open Questions

Нет открытых. Ревизия 2 (spec-review, 2026-07-17) закрыла F-001…F-013:

| Finding | Резолюция |
|---|---|
| F-001 (сценарии) | 4 новых `mb-scenario` блока (REQ-003/004/006/009) в `requirements.md` |
| F-002 (входной frontmatter) | документирован как входной контракт C1 (design.md), plain-int `ice` |
| F-003 (ICE/pin/depends ordering) | раундовый Kahn + приоритет-тай-брейк, design.md C2 |
| F-004 (формула прогресса) | источник — `mb_work_items.py`, формула + грамматика рендера, design.md C2 |
| F-005 (backlog CLI) | полный CLI + брифо-гейт блокирующий, design.md C3 |
| F-006 (`[SPEC:<group>]` формат) | типизированная грамматика Type/Group/Parent/Spec, design.md C4 |
| F-007 (миграция легаси) | финальная таблица по реальному инвентарю, design.md C4 |
| F-008 (lint формат) | key=value протокол + severity/exit, design.md C5 |
| F-009 (Task 5 eval) | заменён на поведенческий `tests/bats/test_mb_roadmap_backlog_docs.bats` |
| F-010 (similarity WONTFIX) | детерминированный токен-скор без LLM, design.md C3 |
| F-011 (T1/T2 sizing) | разбито на 8 задач (T1/T2/T3/T4 + новые T6/T7/T8), см. tasks.md |
| F-012 (I-ID атомарность) | общий lock-хелпер, design.md C6 |
| F-013 (Bash 3.2/portability) | NFR-004 + Testing-требования в каждой задаче |

Ревизия 3 (spec-review круг 2, 2026-07-17) — закрыты все находки круга 2 + смысловая D-14-ICE-SCHEMA:

| Finding | Резолюция |
|---|---|
| D-14-ICE-SCHEMA (смысловая) | `ice` = компоненты `{impact, confidence, ease}` (1..10), score = I×C×E считает скрипт, `ice_confirmed` — отметка подтверждения пользователем; C1/REQ-001/REQ-004/сценарии 1/7/12 обновлены; lint отклоняет вне-диапазонный компонент (`invalid_ice`); миграция 8 frontmatter — cross_slice_request оркестратору |
| F-003 (Kahn vs byte-identical) | **два режима**: legacy mode ВЫЗЫВАЕТ немодифицированную `dependency_order()`, priority mode включается только при валидном `ice`/`pin`; несовместимость доказана эмпирически (`C,A,B` vs `B,C,A`) и зафиксирована фикстурой T1 + сценарием 11 |
| F-005 (формат `list`) | машинная грамматика `item=… state=… parent=… depth=… title=<JSON>` для обоих режимов, ошибки в stderr с кодами; сценарий 9 приведён к `depth=` |
| F-008 (lint escaping/счёт кодов) | `file=`/`detail=` — JSON-строки (`json.dumps`, `ensure_ascii=False`); детерминированный порядок вывода; **10 кодов** (добавлены `ice_unconfirmed`, `invalid_ice`, `legacy_state`), каждый со своим тест-кейсом |
| F-010 (`--force` в позиционном CLI) | грамматика `mb-idea.sh [--force] [--] <title> [priority] [mb_path]`, `--force` только первым аргументом, неизвестный флаг → exit 2 до мутации, старые вызовы byte-identical (единственная потеря — заголовок, начинающийся с `--`, без `--`; escape-hatch задокументирован) |
| F-012 (глобальность I-NNN) | глобальный аллокатор `mb_next_backlog_id` (C6) с исчерпывающим списком источников по фактам репо; регресс-тест на реальную коллизию I-079; Eval T2 гоняет и lock-тест; мигратор (T3) пишет под lock'ом |
| F-013 (portability в T7) | portability-гейт NFR-004 добавлен в Testing Task 7 |
| R2-001 (lock-контракт) | **частично отклонён**: mv-reclaim обязателен по родительскому Interface 2 (ревизия 3) — не убран; устранено внутреннее противоречие: helper = «та же семантика, КРОМЕ механизма reclaim», контрактный тест разделён на parity- и divergence-части |
| R2-002 (promote вне алфавита) | C7: promote требует READY, пишет только READY→IN-PROGRESS общим примитивом, `PLANNED` не пишет никогда; матрица состояний + exit-коды; Task 9 + docs T5 + сценарий 14 |
| R2-003 (S3/S4 разные порядки) | C2 объявлен единственным авторитетом порядка группы; cross_slice_request к S3-C5 (компаратор + pin/created в member-JSON + общая fixture-таблица) |
| R2-004 (реестр без writer'а) | C4: `mb-idea.sh` — production writer typed-формата (`Type: IDEA|SPEC`), call-site S2 не меняется; Task 8 + сценарий 15; cross_slice_request к S2-C7 (правка одного утверждения) |
| R2-005 (сценарий 8 не те источники) | GIVEN исправлен на generated Group-секцию roadmap.md + `specs/foo/requirements.md` без `ice:` |
| R2-006 (orphan_group недетектируем) | источник осиротевших слагов — `## Group:`-заголовки ВНУТРИ текущего fence; вне fences реестром не считаются |

Ревизия 4 (spec-review круг 3, 2026-07-18) — закрыты находки круга 3 + приземление AGR-021:

| Finding | Резолюция |
|---|---|
| R2-003-R3 (critical, S3/S4 разные порядки) | S4-C2 сделан исполнимым авторитетом: `created` из `context/<topic>.md`, missing/invalid `ice` → `ice=null` legacy_tail (не exit 2/3), общий файл фикстур `tests/fixtures/svp_group_ordering.json` (4 кейса, byte-identical порядок обоих потребителей); выравнивание S3 — cross_slice_request #2/#4 |
| R3-001 (critical, lock) | C6 перепроектирован на owner-marker `<lock>/owner.<token>` + targeted `rmdir` (mv-reclaim отменён); полный stdout/exit-контракт acquire/release; `mb_next_backlog_id` печатает `I-NNN`; весь read→decide→write под локом (TOCTOU) |
| R3-002 (transition-примитив) | `mb_backlog_transition_locked <backlog_path> <I-NNN> <NEW_STATE> [--reason][--plan]`, precondition «caller владеет локом», exit 0/1/2, `--plan` для promote |
| R3-003 (lint-матрица) | C5: 10→15 кодов (+ `invalid_ice_confirmed`/`invalid_pin`/`invalid_group`/`invalid_blocked_by`/`wontfix_without_reason`), отдельная фикстура на каждый |
| R3-004 (Task 3 DAG) | Task 3 `Blocked-by: 2, 9`; порядок Stage 2 `{6,7,9}→3`; precondition test-seam |
| R3-005 (list --tree заглушка) | Task 2 `list` flat полностью; `--tree` → exit 2 без placeholder; полный tree — Task 7 |
| R3-006 (parent=spec) | REQ-006 приведён к `<I-NNN|none>` в requirements + ledger (design/tasks уже так) |
| R3-007 (порядок Group-блоков) | C2: Group-блоки после `## Linked Specs (active)`, slug'и bytewise C-locale ↑, полная грамматика позиции |
| R3-008 (promote partial-failure) | C7: `code=promote_partial`, идемпотентный retry (один план, одна `**Plan:**`), fault-injection тест |
| R3-009 (annotate cycle Eval) | Task 2 anti-cycle кейс: `annotate` создающий цикл → exit 1 `parent_cycle`, записи байт-в-байт |
| R3-010 (SPEC-грамматика) | C4: `^\[SPEC:([a-z0-9][a-z0-9-]*)\] ([a-z0-9][a-z0-9-]*)$`, malformed `[SPEC:` → exit 2 без аллокации |
| AGR-021 / UNFIXED:D-14-ICE-SCHEMA | `ice_confirmed` больше не декоративен: C2 печатает наблюдаемый `unconfirmed_ice=<slugs>` в stderr, порядок не блокируется, оркестратор эскалирует, флип `false→true` пишет только оркестратор; REQ-013 + сценарий 16; umbrella Interface 4 согласован |
