---
topic: sdd-vision-pipeline
created: 2026-07-17
status: ready
interview_transcript: context/sdd-vision-pipeline-interview.md
---

# Context: sdd-vision-pipeline

Umbrella-спека эволюции пайплайна brief → spec → plan → work до вижена: качественный брифинг с интервью, контракт-ферст спека с детерминированными эвалами, умная декомпозиция (~1M/спека, ≤400k/этап, ≤120k/задача), параллельное исполнение по DAG, ICE-роадмеп с процентами, беклог-стейт-машина, ADaPT adaptive replan, spec-review в pipeline, `/mb docs` (LLM-вики Карпатого). Референсы усвоены из mattpocock/skills (MIT) — гэп-анализ G1–G14.

## Purpose & Users

- **Кто**: пользователи Memory Bank скила — от инженеров, ведущих спеки строго, до вайбкодеров, желающих MVP за 1–2 промта; плюс сами код-агенты (Claude Code / Pi / OpenCode / Cursor / Codex) как исполнители.
- **Проблема**: сейчас sdd — скаффолд, план — отдельный ручной шаг, эвалы опциональны и прозой, задачи линейны (нет параллели), роадмеп/беклог не детерминированы, нет adaptive replan; последовательная работа медленная.
- **Успех (качественно)**: одна команда `/mb sdd` доводит от брифа до исполняемой спеки с планом внутри; каждое gated-требование проверяется кодом (red→green), а не только LLM; большие задачи сами декомпозируются в реестр спек; roadmap/backlog читаются как «база данных» и ведутся скриптами; `/mb work --parallel` безопасно ускоряет исполнение; фокус — качество по умолчанию, скорость — по явному выбору.

## Research Digest

- `.memory-bank/reports/2026-07-17_research_mattpocock-skills-vs-mb-pipeline.md` — гэп-анализ G1–G14 против mattpocock/skills; подтверждён пользователем.
- `commands/sdd.md:137` — «does not auto-generate design.md / tasks.md content» (текущий sdd — скаффолд).
- `commands/plan.md:43-50`, `references/templates.md:119-141` — текущие лимиты: Sprint ≤200k, 3–7 stages.
- `commands/work.md:566-599`, `scripts/mb-work-pivot.sh` — pivot реагирует только на стагнацию ревью-циклов.
- `commands/sdd.md:110-120` — GWT-гейт `sdd.require_scenarios` opt-in, default off.
- `scripts/mb-work-checkbox.sh`, `scripts/mb-roadmap-sync.sh` — чекбоксы и roadmap-autosync уже детерминированы; % не считается.
- `commands/mb.md:62,1354-1420` — беклог I-NNN: NEW/TRIAGED/DONE, плоский.
- `specs/sdd-openspec-parity/requirements.md` — уже владеет: vague-lint, `scenarios: required` маркер, SHOULD/MAY модалы, coverage-гейты, secret-scan, living specs/deltas.
- `specs/quality-track/requirements.md` — уже владеет: оракулы QA-кейсов, evidence, gate-verdicts, отчёты.
- mattpocock/skills (MIT): `diagnosing-bugs` (red-capable команда как гейт), `to-tickets` (DAG/фронтир/vertical slices), `triage` (стейт-машина, agent brief), `batch-grill-me` (frontier-раунды), `to-spec` (seams, durability), `domain-modeling` (глоссарий), `wayfinder` (карта decision-тикетов) — <https://github.com/mattpocock/skills>.
- <https://arxiv.org/abs/2311.05772> — ADaPT (Prasad 2023): adaptive as-needed decomposition.
- <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f> — правила LLM-вики: слои sources/wiki/schema, ingest/query/lint, index.md + append-only log.md, wikilinks, явные противоречия.
- AGR-006/009/016 — текущая очередь: openspec-adapter → update-notify → donor v5.4.0; AGR-003 — на пересечении побеждает новый трек.

## Decision Log

- **D-01**: Umbrella-спека + ссылки: владеет только новой работой; пересечения остаются в sdd-openspec-parity и quality-track (референсы, без дублирования REQ). — Rationale: паттерн AGR-008. Rejected: поглощение (ломает AGR-007/008/009), полная независимость (drift двух источников правды).
- **D-02**: `/mb sdd <topic>` без context сам запускает discuss-интервью (или self-answer в auto); `/mb discuss` остаётся отдельной командой. — Rejected: prerequisite-отказ (два шага), полное слияние (ломает session pipeline).
- **D-03**: План живёт в tasks.md (этапы, blocked_by, Scope, Eval, бюджеты); новых файлов нет; sprint-обёртки в plans/ опциональны. — Rejected: specs/<topic>/plan.md (drift), автогенерация plans/*.md (лишние файлы).
- **D-04**: Self-interview по брифу: агент сам отвечает на вопросы интервью; self-answered решения помечаются как assumptions и предъявляются пакетом на ревизию.
- **D-05**: SDD — только декларации (design.md §Contract: интерфейсы; поле **Eval:** = имя команды + red/green-сигнал); код эвала пишется первым шагом задачи в /mb work: red → реализация → green; verify гоняет команду детерминированно; LLM-ревью — слой поверх. — Rationale: контракт-ферст + токен-экономия (код не пишется на этапе спеки).
- **D-06**: GWT + Eval обязательны только для gated (SHALL/MUST) REQ; SHOULD/MAY опционально. — Rejected: все REQ (дорого), config-off (эвалы перестают быть гарантией).
- **D-07**: `/mb work --parallel[=N]` / `--sequential` (default) + дефолт в pipeline.yaml; оркестратор одной сессии диспатчит фронтир саб-агентам (Claude Code/Pi/OpenCode; без диспатча — sequential + platform_limited); COORDINATION.md остаётся кросс-сессионным бордом, интра-сессионная механика с ним компонуется.
- **D-08**: Скоуп задачи: декларация **Scope:** на этапе sdd + детерминированная runtime-сверка diff после задачи (как protected-path check); выход за скоуп = эскалация. — Rejected: только LLM-оценка (недетерминированно), worktree-везде (мерж-ад, кросс-платформа).
- **D-09**: Финальный гейт интервью «есть ли что добавить?» перед генерацией; непустой ответ → новая итерация обсуждения; только явное «нет» открывает генерацию.
- **D-10**: Размерный триаж в интервью: оценка объёма; >~1M токенов → рекомендация разбить на отдельные спеки (своё интервью на каждую), пользователь может отказаться; выбранная продолжает интервью, остальные — в реестр декомпозированных спек.
- **D-11**: Escape-hatch скорости: отказ от разбиения/интервью, «быстрее к коду» — доступен всегда; дефолт — качество.
- **D-12**: План интервью в md-файле ДО старта (белые пятна/темы); перед генерацией — сверка: все пункты закрыты, возврат из отступлений к плану; тема размером в спеку → варианты: отложить как отдельную спеку / упростить до MVP в текущей.
- **D-13**: Бюджеты: задача ≤120k · этап ≤400k (~4 задачи; этап исполним несколькими сабагентами) · спека ~1M (триггер D-10). — Rationale: эффективная зона агента ~50% окна 240k; оркестратор обычно в окне 1M. Rejected: этап ≤200k (всего 2 задачи), задача ≤80k (оверхед контекст-загрузки).
- **D-14**: ICE во frontmatter спек/планов (LLM предлагает, пользователь подтверждает); score=I×C×E — авторитетный порядок Next + pin-override; % и счётчики (этапы/задачи: запланировано/в работе/готово) считает код из чекбоксов; roadmap/backlog — «MD как база данных»: формат валидируется скриптом, заполняется скриптом где возможно, LLM — только несводимое к коду.
  - **AGR-021 (2026-07-18, ревизия 3 spec-review, приземление UNFIXED:D-14-ICE-SCHEMA)**: авто-приоритизация остаётся; неподтверждённые ICE (`ice_confirmed ≠ true`) используются с ворнингом и НЕ блокируют ordering; `mb-roadmap-sync.sh` печатает наблюдаемый `unconfirmed_ice=<slugs>` (stderr), по которому оркестратор ЭСКАЛИРУЕТ пользователю «подтверди/поправь приоритеты»; подтверждение флипает `ice_confirmed: false→true` во frontmatter спеки, писать флип вправе только оркестратор (D-23). Приземление: S4 `svp-roadmap-backlog-db` REQ-013 + design C1/C2 + сценарий 16; umbrella Interface 4 (`ice_confirmed` больше не декоративен). До этого ревью подтверждение было декоративным (все 8 child-спек `ice_confirmed:false`), хотя roadmap уже использовал оценки как авторитетный порядок.
- **D-15**: Беклог: NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX (переходы валидирует скрипт); parent-иерархия подзадач; READY требует agent-brief; WONTFIX пишет прецедент в out-of-scope-реестр, новые идеи сверяются с ним; реестр декомпозированных спек (D-10) — тип SPEC там же.
- **D-16**: ADaPT-триггеры: структурный сигнал complexity_escalation от агента + дет-гарды (превышен токен-бюджет задачи; выход за Scope; eval не зеленеет за max_cycles; превышен порог циклов на verify/review/judge — число подобрать в design). Реакция: auto → stub за feature-флагом + беклог + продолжить, доработка предлагается после; интерактив → выбор: идти дальше несмотря ни на что / упростить / перепланировать (декомпозиция или смена требований) / пропустить этап.
- **D-17**: Seam-шаг в design-фазе sdd: существующие seams > новые, максимально высокий, идеал — один; подтверждается пользователем (из to-spec).
- **D-18**: Опция frontier-раундов интервью (из batch-grill-me): все разблокированные вопросы одним раундом, параллельные fact-finding сабагенты; дефолт — по одному вопросу.
- **D-19**: MIT-атрибуция mattpocock/skills: credits-блок в README + ссылка на источник в commands/discuss.md (где цитируются grilling rules).
- **D-20**: Durability-правила agent-brief в беклоге: behavioral-not-procedural, без путей файлов и номеров строк (из AGENT-BRIEF.md).
- **D-21**: Очередь: дожать openspec-adapter + update-notify как есть → sdd-vision-pipeline становится главным треком; donor-релизы пере-ICE-иваются после его создания (паттерн AGR-003). — Rejected: впереди openspec-adapter (ломает AGR-016), размазать по donor-релизам (вижен растворится).
- **D-22**: Минимальный глоссарий `.memory-bank/glossary.md`: термин = одно значение; discuss/sdd обновляют inline и челленджат конфликты. — Rejected: полный domain-modeling с CONTEXT-MAP (YAGNI).
- **D-23**: В .memory-bank/ при параллели пишет ТОЛЬКО оркестратор; таск-агенты возвращают структурные отчёты; Scope задач касается только кода проекта. — Rejected: per-agent lock (известная гонка .reclaiming), шардирование банка (ломает «MD как БД»).
- **D-24**: Цикл в blocked_by → mb-spec-validate падает; claim несёт timestamp+session-id, видим кросс-сессионно, снятие протухших по TTL (`--release-stale`); детали механики — в design.
- **D-25**: Задача без runtime-поверхности (доки/конфиги) получает структурный Eval (файл существует/секция присутствует/линтер зелёный); `Eval: none` запрещён для задач, покрывающих gated REQ.
- **D-26**: Обратная совместимость: легаси tasks.md без новых полей парсится как раньше; новые поля обязательны только для спек нового sdd; REQ/mb-task не перенумеровываются (паттерн AGR-009).
- **D-27**: `/mb docs`: LLM-вики по правилам Карпатого в `docs/` (default; путь конфигурируется в pipeline.yaml); инкрементальный ingest — анализ git diff от SHA последней фиксации документации; index.md (каталог), append-only log.md (`## [DATE] operation | description`), wikilinks, явное флагование противоречий, знание накапливается.
- **D-28**: `/mb docs` ≠ `/mb wiki`: docs — человеко-читаемая документация проекта; wiki — внутренний инструмент банка (граф-коммьюнити, semantic-рёбра); docs читает graph.json/wiki как источник фактов, не наоборот.
- **D-29**: Транскрипт интервью сохраняется в `context/<topic>-interview.md` (полные Q&A, формулировки пользователя, отклонённые альтернативы); его обязаны читать планировщик спеки (sdd-генерация) и spec-ревьювер — леджера недостаточно как контекста.
- **D-30**: Этап spec-review в pipeline.yaml: ревью сгенерированной спеки другой моделью (конфигурация как у code-ревьюверов: model/agent/thinking); судья спеки = человек, в auto-режиме — оркестратор; отдельный judge-агент не нужен.
- **D-31**: Группы спек: спеки, рождённые декомпозицией одного запроса (D-10), объединяются в именованную группу (по умолчанию — имя umbrella-топика); каждая child-спека несёт `group:` во frontmatter; roadmap рендерит секцию группы с внутригрупповой ICE-приоритизацией и агрегированным прогрессом; реестр декомпозированных спек (D-15) хранит принадлежность к группе. — Rationale: сгенерированное одним запросом должно читаться и приоритизироваться как единое целое.
- **D-32**: `/mb work` принимает **группу спек** как target (не только спеку/план) — исполняет членов группы по DAG и внутригрупповому ICE. При старте на группе (или очень большом target) work спрашивает: (а) режим исполнения — последовательно / параллельно, и если параллельно — как: teammates, сабагенты, или рекомендация открыть несколько сессий (worktree или COORDINATION.md), когда один work явно не справится; (б) режим вмешательства — HITL или автономно. — Rationale: 2026-07-17, запрос пользователя при планировании группы.
- **D-33**: Автономный режим прерывается ТОЛЬКО на эскалациях (D-16) и никогда не замалчивает проблемы — каждая проблема репортится, а не проглатывается молчаливым продолжением.
- **D-35**: Размерная эскалация на этапе sdd-генерации (вторая линия после интервью-триажа D-10): когда оценка генерируемой спеки превышает бюджет (~1M), sdd останавливается ДО записи tasks.md и эскалирует на пользователя с вариантами: (а) **разбить сейчас** на группу child-спек, каждая со своим доп-интервью — рекомендация по умолчанию; (б) **урезать до MVP** — вынести часть требований в беклог-реестр (`[SPEC:<group>]`), одна спека влезает в бюджет; (в) **тонкая umbrella + JIT-слайсы** — umbrella сейчас, слайсы по мере старта (паттерн AGR-001); (г) **явный override** — продолжить одной большой спекой, решение фиксируется во frontmatter (`budget_override: user`) и видно verify/review. В auto-режиме дефолт — (а) через self-interview слайсов, выбор фиксируется как assumption. — Rationale: 2026-07-17, интервью-оценка может устареть к генерации (требования выросли по ходу discuss).
- **D-34**: Новая команда `/mb brief <topic>` — пре-discuss этап формализации запроса: пользователь даёт запрос в любом формате + документы (PRD, JTBD, vision, схемы, промт — что угодно); команда анализирует, задаёт лёгкие уточняющие вопросы (не глубина discuss — только где суть/цель непонятны) и генерирует **одностраничник** (референсы: 1P Авито / бриф 2ГИС / Amazon PR-FAQ): суть, цель/импакт, референсы, решение (JTBD), сценарии, ограничения, UX, критерии готовности, приложения. Складывается в специализированную папку вместе с исходниками (конвенция inputs-registry из sdd-openspec-parity, D-01) и предлагает перейти к `/mb discuss`, который читает бриф как вход Phase 0. Новый слайс S7 группы.

## Functional Requirements (EARS)

- **REQ-001** (event-driven): When `/mb sdd <topic>` runs without an existing `context/<topic>.md`, the system shall run the discuss interview (or self-interview in auto mode) before generating the spec triple. <!-- D-02 -->
- **REQ-002** (event-driven): When `/mb sdd` completes, the system shall generate `requirements.md`, `design.md` and `tasks.md` with full content — stages, tasks and per-task fields — rather than empty scaffolds. <!-- D-03 -->
- **REQ-003** (ubiquitous): The `tasks.md` format shall support stage grouping, `blocked_by` edges, `Scope`, `Eval` and size-budget fields per task, while remaining parseable by `mb_work_items.py`. <!-- D-03, D-26 -->
- **REQ-004** (optional): Where the user requests self-interview mode with a brief, the system shall answer the interview questions itself and mark every self-answered decision as an assumption presented to the user for review. <!-- D-04 -->
- **REQ-005** (ubiquitous): The generated `design.md` shall contain a Contract section declaring interfaces and per-task Eval declarations (command name + expected red/green signal) without implementation code. <!-- D-05 -->
- **REQ-006** (event-driven): When `/mb work` starts a task with an Eval declaration, the system shall materialize the eval into executable code first, observe it fail (red) before implementation and pass (green) after implementation. <!-- D-05 -->
- **REQ-007** (state-driven): While a requirement carries a SHALL or MUST modal, the system shall require at least one GWT scenario and one Eval declaration covering it. <!-- D-06 -->
- **REQ-008** (unwanted): If a task covering a gated requirement declares `Eval: none`, then the system shall fail spec validation. <!-- D-25 -->
- **REQ-009** (event-driven): When `design.md` is generated, the system shall record the agreed test seams, preferring existing seams and the highest possible seam. <!-- D-17 -->
- **REQ-010** (event-driven): When the interview plan has no remaining open topics, the system shall ask the user a final "anything to add?" question before generating artifacts. <!-- D-09 -->
- **REQ-011** (unwanted): If the user adds new material at the final gate, then the system shall reopen the discussion iteration and update the decision ledger before generation. <!-- D-09 -->
- **REQ-012** (event-driven): When an interview starts, the system shall write an interview plan file listing the topics and white spots to close. <!-- D-12 -->
- **REQ-013** (unwanted): If any interview plan item remains unclosed before artifact generation, then the system shall return to it and ask the missing questions before generating. <!-- D-12 -->
- **REQ-014** (unwanted): If the estimated scope of a topic exceeds the spec budget (~1M tokens), then the system shall recommend decomposition into separate specs — each with its own interview — and let the user decline. <!-- D-10 -->
- **REQ-015** (event-driven): When the user accepts decomposition, the system shall register deferred specs in the decomposed-spec registry and continue the interview on the selected spec. <!-- D-10, D-15 -->
- **REQ-016** (ubiquitous): The system shall enforce size budgets — task ≤120k, stage ≤400k, spec ~1M tokens — via deterministic validation heuristics at spec-generation time. <!-- D-13 -->
- **REQ-017** (optional): Where `--parallel[=N]` is passed to `/mb work` or set as the pipeline.yaml default, the system shall dispatch frontier tasks to parallel subagents from a single orchestrator session. <!-- D-07 -->
- **REQ-018** (ubiquitous): The system shall treat as parallelizable only tasks that are both unblocked in the DAG and have pairwise-disjoint declared Scopes; conflicting tasks shall be serialized. <!-- D-07, D-08 -->
- **REQ-019** (unwanted): If the host platform lacks subagent dispatch, then the system shall fall back to sequential execution and report `platform_limited` honestly. <!-- D-07 -->
- **REQ-020** (event-driven): When a task completes in parallel mode, the system shall deterministically verify the actual diff against the declared Scope and escalate on out-of-scope changes. <!-- D-08 -->
- **REQ-021** (state-driven): While parallel execution is active, the system shall allow only the orchestrator to write to `.memory-bank/` files; task agents shall return structured reports. <!-- D-23 -->
- **REQ-022** (unwanted): If `tasks.md` contains a `blocked_by` cycle, then spec validation shall fail with the cycle path reported. <!-- D-24 -->
- **REQ-023** (event-driven): When a task is dispatched, the system shall record a claim (timestamp + session id) visible to concurrent sessions, and shall release stale claims by TTL. <!-- D-24 -->
- **REQ-024** (ubiquitous): The roadmap shall order the Next queue by ICE score (impact×confidence×ease from frontmatter) with an explicit pin override, computed and sorted by script. <!-- D-14 -->
- **REQ-025** (ubiquitous): The roadmap shall display per-spec and per-plan progress — percentages and counters of stages/tasks planned, in progress and done — computed deterministically from checkboxes by script. <!-- D-14 -->
- **REQ-026** (ubiquitous): The system shall validate the structure and format of `roadmap.md` and `backlog.md` by script, treating both files as machine-maintained databases. <!-- D-14 -->
- **REQ-027** (ubiquitous): The backlog shall implement the state machine NEW → NEEDS-INFO ⇄ TRIAGED → READY → IN-PROGRESS → DONE | WONTFIX with script-validated transitions and a parent field for subtask hierarchy. <!-- D-15 -->
- **REQ-028** (event-driven): When a backlog item moves to READY, the system shall require an agent brief that is behavioral and free of file paths and line numbers. <!-- D-15, D-20 -->
- **REQ-029** (event-driven): When a backlog item is closed as WONTFIX (rejected), the system shall record the rejection in the out-of-scope registry and check future ideas against it. <!-- D-15 -->
- **REQ-030** (event-driven): When an implementer emits a `complexity_escalation` signal or a deterministic guard fires (task token budget exceeded, Scope violation, eval not green after max cycles, or verify/review/judge loop threshold exceeded), the system shall trigger the ADaPT fork. <!-- D-16 -->
- **REQ-031** (state-driven): While running in auto mode, on an ADaPT trigger the system shall implement a stub behind a feature flag, register a backlog item for the deferred work and continue execution. <!-- D-16 -->
- **REQ-032** (state-driven): While running interactively, on an ADaPT trigger the system shall offer the user the choices: continue anyway, simplify, replan via decomposition or requirement change, or skip the step. <!-- D-16 -->
- **REQ-033** (event-driven): When a term is resolved during the interview, the system shall update `glossary.md` inline and challenge later uses that conflict with it. <!-- D-22 -->
- **REQ-034** (event-driven): When the interview completes, the system shall save the full interview transcript to `context/<topic>-interview.md`, and the spec generator and spec reviewer shall read it as input context. <!-- D-29 -->
- **REQ-035** (optional): Where pipeline.yaml declares a `spec_review` model/agent, the system shall dispatch a review of the generated spec by that model before the spec is accepted, with the human (or the orchestrator in auto mode) as the judge. <!-- D-30 -->
- **REQ-036** (event-driven): When `/mb docs` runs, the system shall analyze the git diff since the last documented SHA and update the LLM wiki under the docs directory following the Karpathy rules — index.md catalog, append-only log.md, wikilinks and explicit contradiction flags. <!-- D-27 -->
- **REQ-037** (optional): Where pipeline.yaml sets a docs path, the system shall generate the wiki there instead of the default `docs/`. <!-- D-27 -->
- **REQ-038** (ubiquitous): The documentation shall credit mattpocock/skills (MIT) wherever its patterns are cited, including the grilling rules in `commands/discuss.md`. <!-- D-19 -->
- **REQ-039** (ubiquitous): The system shall parse legacy `tasks.md` files without the new fields unchanged, requiring the new fields only for specs created by the new sdd pipeline. <!-- D-26 -->
- **REQ-040** (optional): Where the user requests batch interview mode, the system shall ask the whole current frontier of unblocked questions in one numbered round with a recommendation per question. <!-- D-18 -->
- **REQ-041** (event-driven): When a topic is decomposed into multiple specs, the system shall assign every child spec to a named group, store the group in the spec frontmatter and the decomposed-spec registry, and render the group in the roadmap with intra-group ICE ordering and aggregated progress. <!-- D-31 -->
- **REQ-042** (optional): Where a spec group is passed as the target to `/mb work`, the system shall execute the member specs of the group respecting the group DAG and the intra-group ICE order. <!-- D-32 -->
- **REQ-043** (event-driven): When `/mb work` starts on a group target, the system shall ask the user to choose the execution mode — sequential, or parallel via teammates, subagents, or additional sessions (worktree or coordination board) — and the intervention mode — HITL or autonomous. <!-- D-32 -->
- **REQ-044** (state-driven): While running in autonomous intervention mode, the system shall interrupt only on escalations and shall report every encountered problem instead of silently continuing. <!-- D-33 -->
- **REQ-045** (event-driven): When `/mb brief <topic>` runs with a free-form request and attached documents, the system shall analyze them, ask light clarifying questions only where the intent is unclear, and generate a one-pager brief stored together with the source documents. <!-- D-34 -->
- **REQ-046** (event-driven): When a brief is completed, the system shall offer to proceed to `/mb discuss` seeded by that brief as Phase 0 input. <!-- D-34 -->
- **REQ-047** (unwanted): If the size estimate at sdd-generation time exceeds the spec budget, then the system shall stop before writing tasks and escalate to the user, recommending immediate decomposition into grouped specs with their own interviews and offering the alternatives: an MVP scope cut with the remainder registered in the backlog, a thin umbrella spec with JIT slices, or an explicit override recorded in the spec frontmatter. <!-- D-35 -->
- **REQ-048** (state-driven): While running in auto mode, on a budget excess at sdd-generation time the system shall decompose into self-interviewed slices by default and record that choice as an assumption. <!-- D-35 -->

## Non-Functional Requirements

- **NFR-001**: Токен-экономия — на этапе sdd только декларации (ни строчки кода эвалов); дорогие слои (parallel, batch, docs) включаются явно; дефолт — качество, но без скрытых расходов.
- **NFR-002**: Детерминизм — всё, что может вести код (валидация форматов, %, счётчики, DAG, Scope-сверка, стейт-переходы), ведёт код; LLM — только несводимое.
- **NFR-003**: Кросс-платформенность — паритет на 8 клиентах с честной деградацией (паттерн AGR-013/platform_limited).
- **NFR-004**: Обратная совместимость — существующие банки/спеки работают без миграции; поведение легаси-путей byte-identical.
- **NFR-005**: Наблюдаемость — эскалации ADaPT, claims, spec-review вердикты логируются структурно (JSONL в `<bank>/tmp/`, как pivot-log).

## Constraints

- REQ-ID и mb-task не перенумеровываются; ID монотонны (AGR-009, инварианты банка).
- Пересекающиеся требования принадлежат sdd-openspec-parity / quality-track — сюда не копируются (D-01).
- roadmap/backlog остаются Markdown (git-diff-читаемость); никаких SQLite/JSON-баз.
- Никакого BDD-компилятора GWT под стеки — сценарии материализуются агентом в обычные тесты на согласованных seams.
- Судья spec-review — человек (auto: оркестратор); нового judge-агента для спек не заводить.
- `progress.md` append-only; COORDINATION.md-протокол не ослабляется.

## Edge Cases & Failure Modes

- Одновременный финиш двух параллельных задач → только оркестратор пишет в банк (D-23), таск-агенты не трогают чекбоксы/progress/claims.
- Смерть сессии с claim → TTL + `--release-stale` (D-24).
- Цикл в blocked_by → валидация падает с путём цикла (REQ-022).
- Docs-задача без runtime-поверхности → структурный eval; `Eval: none` на gated REQ → отказ валидации (D-25).
- Self-interview дал неверное допущение → assumptions-блок в спеке, предъявляется пакетом; spec-review (REQ-035) — вторая линия обороны.
- Легаси tasks.md → парсится как раньше, новые поля не требуются (REQ-039).
- Хост без сабагентов (Codex) → sequential + platform_limited (REQ-019).
- Интервью ушло в сторону → план интервью возвращает к незакрытым пунктам (REQ-013); ветка размером в спеку → варианты отложить/упростить (D-12).

## Out of Scope

- Интеграция с внешними трекерами (GitHub Issues/Linear) — тикеты живут в банке; экспорт — возможная будущая спека.
- Полный domain-modeling (CONTEXT-MAP, мульти-контексты) — только минимальный глоссарий (D-22).
- Мульти-агентная оркестрация из НЕСКОЛЬКИХ сессий (это COORDINATION.md, уже есть) — здесь только интра-сессионная параллель.
- Runtime-интеграция OpenSpec (iceboxed v6.7.0) и дублирование quality-track/sdd-openspec-parity REQ.
- Playwright/healer-слои QA (отдельные JIT-слайсы по AGR-008).

## Open Questions

- Порог циклов эскалации на verify/review/judge (D-16) — подобрать число в design (blocked on: телеметрия pivot-log).
- Механика claim: маркер в tasks.md vs state-файл `<bank>/tmp/`; значение TTL (blocked on: design).
- Взаимодействие параллели с review-ансамблем: сериализация judge или параллельные review-петли на задачу (blocked on: design).
- Эвристика оценки объёма темы в токенах на этапе интервью (D-10/D-13): по каким сигналам считать ~1M (blocked on: design).
- Формат реестра декомпозированных спек внутри backlog.md (тип SPEC): поля, связь с interview-планами (blocked on: design G9-слайса).
