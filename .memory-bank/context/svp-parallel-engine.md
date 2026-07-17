---
topic: svp-parallel-engine
created: 2026-07-17
status: ready
group: sdd-vision-pipeline
interview: self
interview_transcript: context/svp-parallel-engine-interview.md
parent_context: context/sdd-vision-pipeline.md
covers_umbrella: [REQ-017, REQ-018, REQ-019, REQ-020, REQ-021, REQ-022, REQ-023, REQ-042, REQ-043, REQ-044]
blocked_by: [svp-sdd-core]
---

# Context: svp-parallel-engine (слайс S3, ICE 252, blocked by S2)

Параллельное исполнение в `/mb work`: выбор режима на старте (sequential/parallel + HITL/автономно), фронтир по DAG + непересекающиеся Scope, claims с TTL, оркестратор-only записи банка, group-target, честная деградация. Родительские решения: D-07, D-08, D-23, D-24, D-32, D-33.

## Research Digest

- `scripts/mb_work_items.py` + v2-поля Blocked-by/Scope (контракт C1/C2 из S2 — зависимость).
- `scripts/mb-work-slots.sh`, `mb-work-state.sh` — существующее состояние прогона — точки расширения для claims.
- `scripts/mb-work-protected-check.sh` — образец детерминированной сверки diff с path-правилами → Scope-чек.
- `references/coordination.md`, `.memory-bank/COORDINATION.md` — кросс-сессионный борд: остаётся; интра-сессия компонуется (D-07); git-stash инцидент T3 adapter-parity — главный урок.
- Диспатч сабагентов: Claude Code — Agent tool; Pi/OpenCode — dispatch-расширения adapter-parity; Codex — нет диспатча → platform_limited (AGR-013).
- Frontier/claim-паттерн: wayfinder (assignee = claim) + to-tickets (работа по фронтиру).

## Assumptions (self-answered, подтверждены пользователем 2026-07-17)

- **S3-A-01**: Claims — `<bank>/tmp/work-claims.jsonl`, append-only события `{task_id, session_id, ts, op}` под mkdir-локом (схема — умбрелла `sdd-vision-pipeline/design.md` §Interfaces п.2; сам лок потребляется из S4-C6, пятая копия алгоритма не пишется), TTL 2ч по умолчанию (константа скрипта, конфиг-override приходит с оркестрацией), `release-stale` для снятия. Ревизия 3: TTL относится к claim'у (умбрелла REQ-023), liveness — к локу (умбрелла Interface 2); это разные объекты и разные сигналы.
- **S3-A-02**: Параллель: Claude Code — нативный Task-инструмент; Pi/OpenCode/Cursor — role-scoped маршрут `mb-subinvoke-resolve.sh` (примитив уже существует для Pi; adapter-parity T7 назвал недостающим звеном именно routing wiring в `/mb work` — `adapters/pi.sh:328-340`, backlog I-121/I-122). Дефолт N=3. Ревизия 3 (закрывает SVP-PE-008): full mode на всех хостах по D-07 — сужение ревизии 2 до Claude Code отменено; `platform_limited` ключуется на фактическом резолве маршрута (C8 `--probe`), а не на имени хоста; I-121/I-122 закрываются этим слайсом (Task 10).
  - **Ревизия круга 3 (AGR-020, 2026-07-18)**: Cursor включается в полный режим intra-session параллели наравне с Claude Code/Pi/OpenCode (у Cursor есть саб-агенты); сужение D-07 до трёх хостов **отменено** — scope полного режима теперь **четырёххостовый**, формулировки «ровно трёххостовый scope» сняты. C8 передаёт role **и** имя агента раздельно (WorkItem-роль `backend` → файл `agents/mb-backend.md`); OpenCode-ветка резолвера расширяется, чтобы реально выбирать агента (`opencode run --agent <mb-agent>`), — сегодня она unscoped, поэтому заявленный role-routing OpenCode фактически отсутствовал (SVP-PE-008). Для Cursor, если транспортного факта в репо ещё нет, — честная деградация `platform_limited` как исполняемый fallback, но замысел «полный режим» зафиксирован требованием REQ-015; wiring Cursor-арма — в Scope Task 10 наравне с OpenCode.
- **S3-A-03**: Review-ансамбль исполняется в ветке своей задачи; judge сериализуется оркестратором (один вердикт за раз).
- **S3-A-04**: Worktree в v1 не автоматизируется — для очень больших задач work рекомендует несколько сессий через COORDINATION.md (D-32-вариант «несколько сессий»).
- **S3-A-05**: Group-target деградирует до упорядоченного списка спек, если Group-frontmatter (S4) ещё не отгружен. Ревизия 3 (закрывает R2-004): деградация — ровно ICE-упорядоченный список с `degraded:true`, как и сказано здесь; «деградация до roadmap-таблицы» была изобретением ревизии 2 — roadmap является рендером frontmatter'а (S4-C2) и обратно не парсится.

## Functional Requirements (EARS)

- **REQ-001** (optional): Where `--parallel[=N]` is passed to `/mb work` or set as the pipeline.yaml default, the system shall dispatch frontier tasks to parallel subagents from a single orchestrator session. <!-- D-07 -->
- **REQ-002** (event-driven): When `/mb work` starts on a group or large target, the system shall ask the execution mode — sequential, or parallel via teammates, subagents, or additional sessions (worktree or coordination board) — and the intervention mode — HITL or autonomous. <!-- D-32 -->
- **REQ-003** (ubiquitous): The frontier shall contain only tasks whose blockers are done, whose claims are free and whose declared Scopes are pairwise disjoint with running tasks; conflicting tasks shall be serialized. <!-- D-07, D-08 -->
- **REQ-004** (event-driven): When a task is dispatched, the system shall record a claim with session id and timestamp, visible to concurrent sessions. <!-- D-24 -->
- **REQ-005** (event-driven): When a claim exceeds its TTL, the system shall allow releasing it via an explicit stale-release operation. <!-- D-24, S3-A-01 -->
- **REQ-006** (event-driven): When a parallel task completes, the system shall deterministically verify the actual diff against the declared Scope and escalate out-of-scope changes. <!-- D-08 -->
- **REQ-007** (state-driven): While parallel execution is active, the system shall allow only the orchestrator to write to `.memory-bank/` files; task agents shall return structured reports. <!-- D-23 -->
- **REQ-008** (unwanted): If the host platform lacks subagent dispatch, then the system shall fall back to sequential execution and report `platform_limited`. <!-- D-07, AGR-013 -->
- **REQ-009** (optional): Where a spec group is the target, the system shall execute member specs respecting the group DAG and intra-group ICE order, degrading to an ordered spec list when group metadata is unavailable. <!-- D-32, S3-A-05 -->
- **REQ-010** (state-driven): While in autonomous intervention mode, the system shall interrupt only on escalations and shall report every problem in the run summary. <!-- D-33 -->
- **REQ-011** (ubiquitous): The judge step shall be serialized by the orchestrator across parallel task pipelines. <!-- S3-A-03 -->
- **REQ-012** (event-driven): When the recommended strategy is multiple sessions, the system shall generate the coordination-board entries (scopes, freezes) for the user instead of dispatching itself. <!-- D-32, S3-A-04 -->
- **REQ-013** (unwanted): If the resolved Blocked-by graph contains a cycle, then the system shall abort frontier resolution before any claim or dispatch, exit non-zero, and print the complete ordered cycle path. <!-- umbrella REQ-022, runtime-рубеж; spec-рубеж — S2 REQ-052 -->
- **REQ-014** (ubiquitous): Every dispatch, wait, judge, escalate and done decision shall be produced by the deterministic scheduler command, and the `/mb work` prompt shall only execute the actions that command emits. <!-- ревью SVP-PE-009 -->
- **REQ-015** (optional): Where the active host resolves a per-role dispatch route, the system shall run full parallel mode on that host — the native subagent tool on Claude Code, and the role-scoped sub-invoke route on Pi, OpenCode and Cursor — and shall report `platform_limited` only when the route is genuinely absent or fails its dispatch contract test. <!-- D-07, AGR-013/014/020 -->
- **REQ-016** (unwanted): If the actual change surface cannot be collected — no git binary, no work tree, or an unreadable index — then the system shall report `scope_status: unavailable` and escalate, and shall never report an empty change surface as a successful in-scope verdict. <!-- ревью R2-003, enum S5-C1 -->
- **REQ-017** (event-driven): When the system generates coordination-board entries, it shall append STATUS, FREEZE and QUESTION entries marked as awaiting acknowledgement, shall never append an ACK on behalf of another session, and shall keep the frozen work blocked until that session appends its own ACK. <!-- ревью R2-005, references/coordination.md -->

## Non-Functional Requirements

- **NFR-001**: Кросс-платформенность (ревизия 3, закрывает SVP-PE-008 + AGR-020): полный параллельный режим — на каждом хосте, где per-role маршрут диспатча фактически резолвится: Claude Code (нативный `Task`), Pi, OpenCode и **Cursor** (role-scoped `mb-subinvoke-resolve.sh`, role + имя агента раздельно) — **четырёххостовый** scope D-07+AGR-020 (прежнее «ровно трёххостовый scope» снято AGR-020). Разрешение выдаётся по dispatch contract test (C8 `--probe`), а не по списку имён. Честная деградация sequential + `platform_limited` — там, где маршрут отсутствует или проваливает probe: Codex всегда (нет subagents), Pi/OpenCode — при отказе от opt-in расширения (AGR-013: отказ = byte-identical install), Cursor — пока нет транспортного факта (замысел полного режима фиксируется требованием REQ-015). Ревизия 2 сузила full mode до Claude Code вопреки D-07 — сужение отменено; backlog I-121/I-122 закрывается Task 10, а не переносится дальше.
- **NFR-002**: Детерминизм: фронтир, claims, Scope-чек — скрипты; LLM только исполняет задачи.
- **NFR-003**: Git-безопасность: урок T3 — никакой общий stash; конфликт скоупов = сериализация, не гонка.

## Constraints

- COORDINATION.md-протокол не ослабляется; scoped `git add` only; claims дополняют борд, не заменяют. ACK принадлежит принимающей стороне (`references/coordination.md:49`) — оркестратор пишет STATUS/FREEZE/QUESTION с `awaiting_ack=true` и никогда не эмитит ACK за другую сессию (ревизия 3, REQ-017/R2-005).
- Оркестратор — единственный писатель банка (D-23); judge — один вердикт за раз (REQ-011), сериализация живёт в scheduler-CLI (C7), а не в дисциплине промпта.
- Грамматика Scope/Blocked-by — **зафиксирована в `svp-sdd-core/design.md` C1 и потребляется как есть**; этот слайс её не ревизует, не переопределяет, не сужает и **не расширяет** (ревизия круга 3: термин «POSIX glob» заменён на **restricted glob** синхронно с владельцем S2-C1 revision 4 / S2-X-01 — литералы + `*` в сегменте + сегмент `**`; запрещённые метасимволы `?`/`[`/`]`/`{`/`}`/escape/запятая-в-элементе → malformed exit 2, те же пять негативных кейсов, что у T1 owner-парсера). Алгоритм пересечения двух Scope-списков и его контрактная таблица — тоже S2-C1.
- Порядок членов группы — компаратор S4-C2 целиком (`pin` ↑ → `score` ↓ → `created` ↑ → `topic` ↑ → `rel` ↑ + `legacy_tail`); собственный вариант не изобретается, roadmap не является источником зависимостей (ревизия 3, R2-004).
- Порог «большого target» — родительский: умбрелла REQ-043 → рубрика REQ-016 → `spec=over` по S2-C3 (>1M токенов). Item-count порогом не является (ревизия 3, R2-002).

## Edge Cases & Failure Modes

- Сабагент умер, claim повис — TTL + `--release-stale`; задача возвращается во фронтир.
- Два параллельных Claude-сессии берут одну задачу — read-validate-append выполняется целиком под owner-token `mkdir`-локом (`<bank>/tmp/.work-claims.lock`), поэтому оба никогда не увидят «владельца нет»; проигравший получает exit 1 и берёт следующую задачу.
- Цикл в графе `Blocked-by` (задач или членов группы) — fail-fast до любого claim/диспатча с печатью полного пути цикла (REQ-013). Рубеж spec-времени принадлежит S2 (REQ-052), runtime-рубеж — этот слайс; умбрелла REQ-022 требует обоих (ревизия 3, SVP-PE-001).
- Scope пересёкся по факту (агент вышел за декларацию) — Scope-чек ловит, эскалация (S5-гард), diff изолируется.
- Поверхность изменений не собралась (нет git / не work tree / нечитаемый индекс) — `scope_status=unavailable` + эскалация; пустой список НИКОГДА не выдаётся за успешный in-scope вердикт (ревизия 3, REQ-016/R2-003).
- Фронтир пуст, но задачи остались (все заблокированы) — честный отчёт о блокерах вместо тихого завершения.
- pipeline.yaml default=parallel на хосте без диспатча — platform_limited + sequential, предупреждение один раз.

## Out of Scope

- Автоматизация worktree (v2+); межмашинная оркестрация; изменение review-контрактов (только сериализация judge).

## Open Questions

- TTL 2ч — калибровка по факту длительности задач ≤120k (после первых governed-прогонов).
