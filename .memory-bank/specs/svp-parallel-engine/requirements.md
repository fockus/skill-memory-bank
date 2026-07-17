---
topic: svp-parallel-engine
group: sdd-vision-pipeline
ice: {impact: 9, confidence: 7, ease: 4}
ice_confirmed: false
blocked_by: [svp-sdd-core]
covers_umbrella: [REQ-017, REQ-018, REQ-019, REQ-020, REQ-021, REQ-022, REQ-023, REQ-042, REQ-043, REQ-044]
status: ready
---

# Requirements: svp-parallel-engine

> Spec triple — see also: design.md, tasks.md.
> Слайс S3 группы `sdd-vision-pipeline` (ICE 252, blocked by svp-sdd-core, self-interview).
> Контекст: `context/svp-parallel-engine.md`; транскрипты: слайсовый + родительский.
> Ревизия 3 (2026-07-17): закрыты находки круга 2 (SVP-PE-001/004/006/008/009 + R2-001…006).
> Ключевое: full mode восстановлен на Claude Code + Pi + OpenCode + **Cursor** (D-07 + AGR-020;
> ревизия 2 ошибочно сузила до Claude Code, сужение D-07 до трёх хостов отменено AGR-020) — REQ-015;
> role + agent-name передаются раздельно, OpenCode/Pi role-routing реально провязан (SVP-PE-008);
> решения диспатча вынесены в детерминированный scheduler-CLI (REQ-014);
> producer поверхности изменений назначен с `unavailable`-семантикой (REQ-016); ACK на борде
> никогда не генерируется за другую сессию (REQ-017).
>
> EARS: Ubiquitous `THE SYSTEM SHALL` · Event `WHEN …` · State `WHILE …` · Optional `WHERE …` · Unwanted `IF … THEN …`

## Requirements (EARS)

### Requirement 1: Выбор режима на старте

**User Story:** As an operator, I want `/mb work` to ask how to execute (sequential/parallel/multi-session) and how to intervene (HITL/autonomous), so that big work runs the way I intend.

#### Acceptance Criteria

- **REQ-001** (optional): Where `--parallel[=N]` is passed to `/mb work` or set as the pipeline.yaml default, the system shall dispatch frontier tasks to parallel subagents from a single orchestrator session. <!-- D-07 -->
- **REQ-002** (event-driven): When `/mb work` starts on a group or large target, the system shall ask the execution mode — sequential, or parallel via teammates, subagents, or additional sessions (worktree or coordination board) — and the intervention mode — HITL or autonomous. <!-- D-32 -->
- **REQ-010** (state-driven): While in autonomous intervention mode, the system shall interrupt only on escalations and shall report every problem in the run summary. <!-- D-33 -->
- **REQ-012** (event-driven): When the recommended strategy is multiple sessions, the system shall generate the coordination-board entries (scopes, freezes) for the user instead of dispatching itself. <!-- S3-A-04 -->

### Requirement 2: Фронтир, claims, скоупы

**User Story:** As a parallel engine, I want to dispatch only unblocked, unclaimed, scope-disjoint tasks with claims visible across sessions, so that parallel work never collides on files or duplicates effort.

#### Acceptance Criteria

- **REQ-003** (ubiquitous): The frontier shall contain only tasks whose blockers are done, whose claims are free and whose declared Scopes are pairwise disjoint with running tasks; conflicting tasks shall be serialized. <!-- D-07/08 -->
- **REQ-004** (event-driven): When a task is dispatched, the system shall record a claim with session id and timestamp, visible to concurrent sessions. <!-- D-24 -->
- **REQ-005** (event-driven): When a claim exceeds its TTL, the system shall allow releasing it via an explicit stale-release operation. <!-- S3-A-01 -->
- **REQ-006** (event-driven): When a parallel task completes, the system shall deterministically verify the actual diff against the declared Scope and escalate out-of-scope changes. <!-- D-08 -->
- **REQ-013** (unwanted): If the resolved Blocked-by graph contains a cycle, then the system shall abort frontier resolution before any claim or dispatch, exit non-zero, and print the complete ordered cycle path. <!-- umbrella REQ-022, runtime-рубеж -->
- **REQ-016** (unwanted): If the actual change surface cannot be collected — no git binary, no work tree, or an unreadable index — then the system shall report `scope_status: unavailable` and escalate, and shall never report an empty change surface as a successful in-scope verdict. <!-- ревью R2-003, enum S5-C1 -->

### Requirement 3: Целостность банка и вердиктов

**User Story:** As a bank owner, I want only the orchestrator writing to `.memory-bank/` and judge verdicts serialized, so that parallelism never corrupts project state.

#### Acceptance Criteria

- **REQ-007** (state-driven): While parallel execution is active, the system shall allow only the orchestrator to write to `.memory-bank/` files; task agents shall return structured reports. <!-- D-23 -->
- **REQ-011** (ubiquitous): The judge step shall be serialized by the orchestrator across parallel task pipelines. <!-- S3-A-03 -->
- **REQ-014** (ubiquitous): Every dispatch, wait, judge, escalate and done decision shall be produced by the deterministic scheduler command, and the `/mb work` prompt shall only execute the actions that command emits. <!-- ревью SVP-PE-009, NFR-002 -->
- **REQ-017** (event-driven): When the system generates coordination-board entries, it shall append STATUS, FREEZE and QUESTION entries marked as awaiting acknowledgement, shall never append an ACK on behalf of another session, and shall keep the frozen work blocked until that session appends its own ACK. <!-- ревью R2-005, references/coordination.md -->

### Requirement 4: Group-target и деградация

**User Story:** As a user, I want to run a whole spec group in one command with honest fallback on limited hosts, so that scale never depends on silently broken features.

#### Acceptance Criteria

- **REQ-008** (unwanted): If the host platform lacks subagent dispatch, then the system shall fall back to sequential execution and report `platform_limited`. <!-- AGR-013, umbrella REQ-019 -->
- **REQ-009** (optional): Where a spec group is the target, the system shall execute member specs respecting the group DAG and intra-group ICE order, degrading to an ordered spec list when group metadata is unavailable. <!-- D-32, S3-A-05 -->
- **REQ-015** (optional): Where the active host resolves a per-role dispatch route, the system shall run full parallel mode on that host — the native subagent tool on Claude Code, and the role-scoped sub-invoke route on Pi, OpenCode and Cursor — and shall report `platform_limited` only when the route is genuinely absent or fails its dispatch contract test. <!-- D-07, AGR-013/014/020 -->

## Scenarios

<!-- mb-scenario:1 -->
### Scenario: Mode question on a group target
**Covers:** REQ-002

- GIVEN `/mb work <group>` — группа из N спек с валидными `group`, `ice` и `blocked_by` во frontmatter
- AND N = 8 для фикстуры `sdd-vision-pipeline`
- WHEN команда стартует
- THEN заданы два вопроса: исполнение (sequential / parallel: teammates|сабагенты / несколько сессий) и вмешательство (HITL / автономно); выбор зафиксирован в состоянии прогона с полем `source`
<!-- /mb-scenario:1 -->

<!-- mb-scenario:2 -->
### Scenario: Frontier with scope conflict
**Covers:** REQ-003

- GIVEN задачи T3 (Scope: scripts/*) и T5 (Scope: scripts/*, commands/*) разблокированы
- WHEN параллельный диспатч N=2
- THEN T3 диспатчится, T5 сериализуется (пересечение scripts/*); следующая непересекающаяся задача занимает слот
<!-- /mb-scenario:2 -->

<!-- mb-scenario:3 -->
### Scenario: Stale claim released
**Covers:** REQ-004, REQ-005

- GIVEN сессия умерла, claim задачи T4 старше TTL
- WHEN другой оркестратор запускает `--release-stale`
- THEN claim снят, T4 вернулась во фронтир; в логе запись о снятии
<!-- /mb-scenario:3 -->

<!-- mb-scenario:4 -->
### Scenario: Out-of-scope diff escalates
**Covers:** REQ-006

- GIVEN T2 задекларировала Scope: hooks/*, а diff тронул scripts/install.sh
- WHEN задача завершилась
- THEN Scope-чек красный → эскалация (ADaPT-гард S5), задача не закрывается
<!-- /mb-scenario:4 -->

<!-- mb-scenario:5 -->
### Scenario: Host without dispatch degrades honestly
**Covers:** REQ-008

- GIVEN pipeline default=parallel, хост без резолвящегося per-role маршрута (Codex)
- WHEN `/mb work --parallel`
- THEN sequential + однократное `platform_limited`-предупреждение; никакой тихой параллели
<!-- /mb-scenario:5 -->

<!-- mb-scenario:6 -->
### Scenario: Autonomous run reports every problem
**Covers:** REQ-010

- GIVEN автономный режим, 6 задач, одна эскалация и один platform-limited обход
- WHEN печатается итог
- THEN обе проблемы в отчёте с деталями; ноль умолчаний
<!-- /mb-scenario:6 -->

<!-- mb-scenario:7 -->
### Scenario: Single-session parallel dispatch
**Covers:** REQ-001

- GIVEN `pipeline.yaml: parallel.default: parallel` (или `--parallel=2`) и фронтир из 3 независимых задач
- WHEN `/mb work` стартует диспатч
- THEN ровно один оркестраторный процесс диспатчит задачи параллельным сабагентам/teammates (Agent tool); никакая дополнительная сессия не создаётся
<!-- /mb-scenario:7 -->

<!-- mb-scenario:8 -->
### Scenario: Only the orchestrator writes the bank
**Covers:** REQ-007

- GIVEN параллельная задача T2 завершилась и вернула структурный отчёт с предложенными правками `.memory-bank/`
- WHEN оркестратор обрабатывает отчёт
- THEN только оркестраторный процесс пишет `.memory-bank/checklist.md`/`progress.md`; процесс task-агента T2 не делает ни одной записи в банк
<!-- /mb-scenario:8 -->

<!-- mb-scenario:9 -->
### Scenario: Group members ordered by DAG then ICE
**Covers:** REQ-009

- GIVEN группа из 3 спек: A (заблокирована B), B (свободна, ICE 300), C (свободна, ICE 500)
- WHEN `/mb work <group>` резолвит членов
- THEN порядок диспатча — C, B (обе свободны, ICE по убыванию), затем A после того как B завершена
<!-- /mb-scenario:9 -->

<!-- mb-scenario:10 -->
### Scenario: Judge calls are serialized across pipelines
**Covers:** REQ-011

- GIVEN две параллельные task-пайплайна одновременно доходят до judge-шага
- WHEN оба запрашивают вердикт
- THEN оркестратор допускает только один активный judge-вызов за раз; второй ждёт своей очереди
<!-- /mb-scenario:10 -->

<!-- mb-scenario:11 -->
### Scenario: Multi-session recommendation generates board entries
**Covers:** REQ-012

- GIVEN рекомендованная стратегия — несколько сессий (задача слишком велика для одной сессии)
- WHEN `/mb work` подтверждает стратегию с пользователем
- THEN в `COORDINATION.md` генерируются записи STATUS/FREEZE/QUESTION со `awaiting_ack=true` для каждой рекомендованной сессии; сам оркестратор диспатч не запускает
<!-- /mb-scenario:11 -->

<!-- mb-scenario:12 -->
### Scenario: DAG cycle aborts frontier resolution
**Covers:** REQ-013

- GIVEN `Blocked-by`-граф с циклом `A → B → C → A`
- WHEN вычисляется фронтир (`mb_work_items.py --frontier`)
- THEN команда завершается с ненулевым кодом, ничего не диспатчится и не клеймится, а stderr содержит полный путь цикла `A -> B -> C -> A`
<!-- /mb-scenario:12 -->

<!-- mb-scenario:13 -->
### Scenario: Scheduler emits the dispatch decision, prompt only executes it
**Covers:** REQ-014

- GIVEN фронтир из 4 дизъюнктных задач и `--max-agents 2`
- WHEN оркестратор вызывает `mb_parallel_scheduler.py next --run-id <id>`
- THEN печатается ровно один JSON-объект с не более чем двумя `dispatch`-действиями, у каждого — `task_id`, `role`, `prompt_file` и уже взятый `claim_token`; `commands/work.md` исполняет ровно эти действия и сам решений не принимает
<!-- /mb-scenario:13 -->

<!-- mb-scenario:14 -->
### Scenario: Pi resolves a role route and runs full mode
**Covers:** REQ-015

- GIVEN хост Pi с установленным opt-in расширением (`mb-subinvoke-resolve.sh --agent pi --role backend` резолвится) и `--parallel=2`
- WHEN scheduler выдаёт два `dispatch`-действия
- THEN оба уходят по role-scoped маршруту Pi, одновременных процессов не больше `max_agents`, `platform_limited` не печатается; при снятом расширении тот же прогон честно деградирует в sequential + `platform_limited`
<!-- /mb-scenario:14 -->

<!-- mb-scenario:15 -->
### Scenario: Unavailable change surface never passes as in-scope
**Covers:** REQ-016

- GIVEN задача завершилась, а `git` недоступен (нет бинаря / не work tree)
- WHEN собирается поверхность изменений для Scope-сверки
- THEN producer завершается ненулевым кодом с `{"status":"unavailable","reason":"<code>"}`, Scope-чек отдаёт `scope_status=unavailable` (exit 3) и эскалирует; пустой список путей не выдаётся за успешный in-scope вердикт
<!-- /mb-scenario:15 -->

<!-- mb-scenario:16 -->
### Scenario: Board entries never self-ACK
**Covers:** REQ-017

- GIVEN multi-session стратегия подтверждена, оркестратор пишет FREEZE на `scripts/**`
- WHEN генерируются записи борда
- THEN появляются STATUS/FREEZE/QUESTION с `awaiting_ack=true` и ноль ACK-записей от имени оркестратора; замороженная работа остаётся заблокированной, пока принимающая сессия сама не допишет ACK; попытка сгенерировать собственный ACK отвергается
<!-- /mb-scenario:16 -->
