
# Roadmap

<!-- mb-roadmap-auto -->
## Now (in progress)

- [2026-05-24_fix_cursor-compatibility-remediation](plans/2026-05-24_fix_cursor-compatibility-remediation.md) — Cursor Compatibility Remediation — progress=86% stages(done=5,in_progress=1,planned=0,total=6)
- [2026-06-23_SEQUENCE_codex-remediation](plans/2026-06-23_SEQUENCE_codex-remediation.md) — Execution Sequence — codex/GPT-5.5 remediation (I-082..I-086) — progress=0% stages(done=0,in_progress=0,planned=0,total=0)
- [2026-06-23_fix_config-validation-docs](plans/2026-06-23_fix_config-validation-docs.md) — Config Validation & Doc Consistency — progress=28% stages(done=1,in_progress=2,planned=3,total=6)
- [2026-07-05_SEQUENCE_long-running-sessions](plans/2026-07-05_SEQUENCE_long-running-sessions.md) — SEQUENCE — Long-running autonomous sessions — progress=0% stages(done=0,in_progress=0,planned=0,total=0)
- [graph-semantic-adoption](plans/2026-07-28_fix_graph-semantic-adoption.md) — fix — graph-semantic-adoption — progress=0% stages(done=0,in_progress=0,planned=7,total=7)

## Next (strict order — depends)

- [cost-multi-model](plans/2026-05-23_feature_cost-multi-model.md) — feature — Cost (multi-model role assignment, S4 of harness-upgrade) — progress=0% stages(done=0,in_progress=0,planned=4,total=4)
- [skill-improvements-anthropic-audit](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — skill-improvements-anthropic-audit — progress=0% stages(done=0,in_progress=0,planned=6,total=6)
- [2026-05-24_fix_pi-compatibility-remediation](plans/2026-05-24_fix_pi-compatibility-remediation.md) — Pi Compatibility Remediation — progress=0% stages(done=0,in_progress=0,planned=0,total=0)
- [2026-06-23_feature_dispatcher-wiring-transports](plans/2026-06-23_feature_dispatcher-wiring-transports.md) — Capability Dispatcher Wiring + Transports — progress=0% stages(done=0,in_progress=0,planned=0,total=0)
- [mb-donor-evolution-v5-4-baseline](plans/2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md) — mb-donor-evolution — v5.4.0 Trustworthy Baseline — progress=0% stages(done=0,in_progress=0,planned=2,total=2)
- [mb-work-cost-diet-sprint2](plans/2026-09-05_fix_mb-work-cost-diet-sprint2.md) — fix — mb-work-cost-diet · Sprint 2 «work-loop-diet» — progress=0% stages(done=0,in_progress=0,planned=4,total=4)
- [mb-work-cost-diet-sprint3](plans/2026-09-05_fix_mb-work-cost-diet-sprint3.md) — fix — mb-work-cost-diet · Sprint 3 «instruction-diet + гигиена» — progress=0% stages(done=0,in_progress=0,planned=4,total=4)

## Parallel-safe (can run now)

_None._

## Paused / Archived

_None._

## Linked Specs (active)

- cost-multi-model — progress=0% tasks(done=0,in_progress=0,planned=4,total=4)
- cursor-extension — progress=90% tasks(done=8,in_progress=0,planned=1,total=9)
- pi-extension — progress=0% tasks(done=0,in_progress=0,planned=12,total=12)
- dynamic-flow — progress=88% tasks(done=12,in_progress=0,planned=2,total=14)
- reviewer-2.0 — progress=100% tasks(done=6,in_progress=0,planned=0,total=6)
- work-loop-v2 — progress=100% tasks(done=5,in_progress=0,planned=0,total=5)
- drive-loop — progress=62% tasks(done=3,in_progress=0,planned=2,total=5)
- parallel-pipeline — progress=0% tasks(done=0,in_progress=0,planned=6,total=6)
- parallel-team-execution — progress=0% tasks(done=0,in_progress=0,planned=10,total=10)
- mb-donor-evolution — progress=0% tasks(done=0,in_progress=0,planned=132,total=132)

## Group: sdd-vision-pipeline
progress=39%
svp-interview-upgrade — ice=504 — ready — progress=100% tasks(done=6,in_progress=0,planned=0,total=6) — blocked_by=none
svp-roadmap-backlog-db — ice=432 (unconfirmed) — ready — progress=39% tasks(done=3,in_progress=0,planned=6,total=9) — blocked_by=none
svp-sdd-core — ice=400 (unconfirmed) — draft — progress=100% tasks(done=9,in_progress=0,planned=0,total=9) — blocked_by=none
svp-brief — ice=448 (unconfirmed) — ready — progress=41% tasks(done=2,in_progress=0,planned=2,total=4) — blocked_by=svp-interview-upgrade
svp-contract-test-loop — ice=360 (unconfirmed) — ready — progress=34% tasks(done=3,in_progress=0,planned=5,total=8) — blocked_by=svp-sdd-core
svp-docs-wiki — ice=336 (unconfirmed) — ready — progress=0% tasks(done=0,in_progress=0,planned=7,total=7) — blocked_by=svp-sdd-core,svp-roadmap-backlog-db
svp-spec-review-loop — ice=336 (unconfirmed) — ready — progress=40% tasks(done=2,in_progress=0,planned=3,total=5) — blocked_by=svp-sdd-core
svp-parallel-engine — ice=252 (unconfirmed) — ready — progress=0% tasks(done=0,in_progress=0,planned=10,total=10) — blocked_by=svp-sdd-core
svp-adapt-escalation — ice=294 (unconfirmed) — ready — progress=0% tasks(done=0,in_progress=0,planned=5,total=5) — blocked_by=svp-sdd-core,svp-parallel-engine,svp-roadmap-backlog-db
<!-- /mb-roadmap-auto -->

_Last updated: auto-synced by mb-roadmap-sync.sh_

## Phase: mb-work-cost-diet (2026-09-05) — `/mb work` быстрее и дешевле

**Goal:** стоимость `/mb work` ≈ ходы × контекст; обе половины раздуты самим скилом (аудит [reports/2026-09-05_mb-work-cost-audit.md](reports/2026-09-05_mb-work-cost-audit.md): implementer 243 хода и 15.6 прогонов тестов, item 2–2.5 ч и 10–12 сабагентов, `/mb start` до 84k токенов). Сделать дешёвый путь путём по умолчанию, не отменяя governed там, где он нужен; всё измеримо `mb-cost-report.py`.

| Sprint | План | Статус | Граница |
|---|---|---|---|
| 1 — context-diet + измерение | [sprint1](plans/done/2026-09-05_fix_mb-work-cost-diet-sprint1.md) | ✅ done (2026-09-13, 7/7) | core-файлы, контекст сессии, конфиг; без правок цикла |
| 2 — work-loop-diet | [sprint2](plans/2026-09-05_fix_mb-work-cost-diet-sprint2.md) | ⬜ planned | цикл `/mb work`: улика, триаж, context pack, внешнее ревью |
| 3 — instruction-diet + гигиена | [sprint3](plans/2026-09-05_fix_mb-work-cost-diet-sprint3.md) | ⬜ planned | инструкции (`mb.md`, `work.md`, Agreements), машина состояний, инсталлер |

**Dependencies:** 2 ← 1 (baseline `reports/2026-09-05_cost-baseline.json` из Sprint 1 Stage 1, дефолт `execution`); 3 ← 2 (`mb-work-next.sh` кодирует цикл с evidence/triage/pack). Спринты 2–3 синкаются в `checklist.md` только при старте (cap 120 строк до починки прунера в Sprint 1 Stage 5).

**Phase Gate:** `mb-cost-report.py` на недельном окне после раскатки: implementer ≤ 120 ходов avg, ≤ 3 полных прогона тестов на item, старт сессии ≤ 12k токенов, `/mb work` инструкции ≤ 32 KB — против baseline. Пересечения: `cost-multi-model` (Next) получает `model_hint` из триажа, не дублирует его; `graph-semantic-adoption` (Now) даёт свежий граф для context pack (fail-open без него).

## Track 2 — Donor Evolution Program (2026-07-15, `specs/mb-donor-evolution`)

Источник: `specs/mb-donor-evolution/source-plan.md` (donor-driven план GSD/OpenSpec/Archon/Superpowers/CCPM/Ruflo). Решения discovery-интервью: `context/mb-donor-evolution.md`. Roadmap ведётся **двумя параллельными дорожками**: legacy-очередь ниже живёт своей жизнью; при пересечении с donor-релизом **побеждает donor** — legacy-план замораживается на старте соответствующего релиза, живые требования переносятся в release-slice через SDD delta-review. `parallel-pipeline` → **superseded** немедленно (source-plan §2.1).

Нумерация сдвинута +1 минор внутри 5.x (v5.3.0 уже выпущена 2026-07-13): доковский Этап 0 → v5.4.0 и далее; серия 6.x без сдвига. REQ-ID и mb-task 1–132 не перенумеровываются.

### ICE-приоритизация релизов программы

ICE = Impact × Confidence × Ease (1–10). Порядок = ICE с поправкой на граф зависимостей (source-plan §9.3: 5.4→5.5→5.6→5.7→6.0→6.1; 5.5→6.2; 6.1+6.2→6.3→6.4; 6.3+6.4→6.5→6.6). Нумерация 6.x-хвоста сдвинута +1 под QA-релиз (AGR-009, 2026-07-15): QA→6.2.0, Portable Skills→6.3.0, Delta Specs→6.4.0, Adaptive Ops→6.5.0, icebox GSD/OpenSpec→6.6.0/6.7.0.

| Релиз | Название | P | I | C | E | ICE | Вердикт |
|---|---|---|---|---|---|---:|---|
| v5.4.0 | Trustworthy Baseline | P0 | 8 | 9 | 9 | **648** | Next — после `adapter-parity` (AGR-012); wrapper `2026-07-15_feature_mb-donor-evolution-v5-4-baseline` |
| v5.5.0 | Spec Control Plane | P0 | 8 | 8 | 6 | **384** | Next |
| v6.1.0 | Evidence, UAT & Gap Closure | P1 | 9 | 7 | 5 | **315** | Next (после 6.0 — жёсткая зависимость) |
| v5.6.0 | Long-Session Kernel & Event Journal **+ drive-loop** | P0 | 10 | 7 | 4 | **280** | Next — поглощает остаток `specs/drive-loop` (AGR-011); **T2+T4 вытащены вперёд очереди (AGR-024)**, в слайсе дожимаются T3+T5 |
| v6.2.0 | **Quality Track — QA & Evidence Graph** (`specs/quality-track`, 29 REQ) | P1 | 9 | 7 | 4 | **252** | Next (сразу после 6.1.0 — строится поверх его evidence-ядра EV-01…05, не дублируя его; AGR-008). Высокий impact, высокая сложность — потому середина очереди, а не старт |
| v5.7.0 | Plan IR & Typed Workflow Planner | P0 | 8 | 7 | 4 | **224** | Next |
| v6.0.0 | Isolated Mixed-Node Execution | P1 | 8 | 6 | 3 | **144** | Next (разблокирует 6.1) |
| v6.3.0 | Portable Skills & Provider Platform | P1 | 6 | 6 | 4 | **144** | Next (зависит только от 5.5; можно параллельно 5.6–6.2) |
| v6.5.0 | Adaptive Operations & Observability | P3 | 5 | 5 | 4 | **100** | Later (после 6.4 — зависимость) |
| v6.4.0 | Delta Specs, Projection & Executor Adapters | P2 | 5 | 5 | 3 | **75** | Later |
| v6.6.0 | Optional GSD Execution Engine | P2 | 3 | 4 | 2 | **24** | **Icebox** — пересмотреть после метрик 6.1 и реального спроса на внешний executor |
| v6.7.0 | Optional OpenSpec Authoring Engine | P2 | 3 | 4 | 2 | **24** | **Icebox** — пересмотреть вместе с 6.6 (зависит от него) |

**Итоговый порядок исполнения** (зависимости доминируют над сырым ICE):
`5.4.0 → 5.5.0 → 5.6.0 (+drive-loop) → 5.7.0 → 6.0.0 → 6.1.0 → 6.2.0 (QA) → 6.3.0 (∥ возможно раньше, после 5.5) → 6.4.0 → 6.5.0 → [icebox: 6.6.0, 6.7.0]`.

ICE-примечания: 6.1 имеет третий score программы, но заперт за 6.0 — это главный аргумент не откладывать 6.0. **Quality Track (6.2.0): сырой ICE 252 поставил бы его пятым, но жёсткая зависимость от evidence-ядра 6.1.0 (манифест §7.5, freshness, коллекторы EV-01…05) фиксирует его сразу за 6.1 — раньше физически нельзя без двойной постройки evidence-слоя (D-01/D-02 в `context/quality-track.md`); позже — нельзя оправдать, его ICE выше всего хвоста.** 6.3 — единственный кандидат на параллельный лейн (зависит только от 5.5). Icebox честный: оба optional-движка — самые дорогие (E=2) и наименее подтверждённые потребностью (I=3) части программы; их REQ/задачи (mb-task 102–132) остаются в umbrella-спеке и активируются JIT-слайсами при разморозке.

**Пересечения с legacy-дорожкой** (правило «donor побеждает», замораживать на старте релиза):
- `drive-loop` + `SEQUENCE_long-running-sessions` ↔ **5.6.0** — исключение из заморозки (AGR-011): оставшиеся фазы drive-loop входят в слайс v5.6.0 и ДОДЕЛЫВАЮТСЯ в нём (много вложенной работы, фича важная); **AGR-024 (2026-07-19): T2 (`/mb drive` + loop-контракт) и T4 (resume-gate) вытащены вперёд очереди ближайшим слотом, в 5.6.0 остаются T3+T5**;
- `work-loop-v2` ↔ 5.6.0/5.7.0 (execution state machine `/mb work`);
- `reviewer-2.0` ↔ 6.1.0 (evidence/review);
- `quality-track` ↔ 6.2.0 — это и ЕСТЬ релиз 6.2.0 (AGR-008), спека уже написана (29 REQ), задачи авторятся JIT при старте слайса;
- `cost-multi-model` ↔ 6.3.0 (provider capabilities/routing);
- `parallel-team-execution` ↔ 6.0.0 (уже де-факто перекрыт mixed-node execution).

## 📋 Реестр незакрытого (2026-09-13, после `/mb doctor`) — каждый открытый план/спека привязан к очереди

Инвариант: ничто незаконченное не живёт вне этого роудмепа. Появился новый план или спека — сюда добавляется строка с местом в очереди. Состояние сверено 2026-09-13 с галочками `tasks.md`, DoD планов и git; закрытое в этот день — `status.md` § Recently done.

| Работа | Артефакт | Состояние | Где в очереди |
|---|---|---|---|
| Fix-слайс по ревью Sprint 1 | backlog I-194 · I-195 · I-196 · I-208; [отчёт](reports/2026-09-13_sprint1-review.md) | судья NO_GO, плана нет | HIGH, параллельно фокусу |
| graph-semantic-adoption | [план](plans/2026-07-28_fix_graph-semantic-adoption.md) | 0/7 стадий | Now — пререквизит Sprint 2 (AGR-044), порядок стадий 6→2→3→1→5→4→7 |
| mb-work-cost-diet Sprint 2 → Sprint 3 | [sprint2](plans/2026-09-05_fix_mb-work-cost-diet-sprint2.md) · [sprint3](plans/2026-09-05_fix_mb-work-cost-diet-sprint3.md) | 0/12 · 0/13 DoD | Next — раздел Phase выше |
| drive-loop остаток | `specs/drive-loop` + SEQUENCE `long-running-sessions` Phase 3 | T1, T2, T4 ✅ · T3, T5 ⬜ | внутри donor v5.6.0 (AGR-011, AGR-024) |
| long-running-sessions Phase 4–6 | SEQUENCE + `specs/parallel-team-execution` (0/10) + `specs/cost-multi-model` (0/4) | не начаты | parallel-team-execution заморожен на старте v6.0.0; cost-multi-model ↔ v6.3.0 |
| dynamic-flow хвост | `specs/dynamic-flow` | T1–T12 ✅ · T13–T14 ⬜ (pi/opencode sub-invoke) | Phase 5 SEQUENCE |
| sdd-vision-pipeline (G-001) | umbrella + 9 child-спек, § Group в авто-блоке | S1 ✅ · S2 ✅ · S7 2/4 · S4 3/9 · S8 3/8 · S9 2/5 · S6, S3, S5 не начаты | главный трек (AGR-017), пауза с 2026-07-27; порядок AGR-029 |
| codex-remediation Wave 2 | I-086 [config-validation-docs](plans/2026-06-23_fix_config-validation-docs.md) → I-084 [dispatcher-wiring-transports](plans/2026-06-23_feature_dispatcher-wiring-transports.md) | Stages 1–2 ✅, 3–6 ⬜ · не начат | I-084 после I-086 |
| cursor-extension хвост | [cursor-compatibility-remediation](plans/2026-05-24_fix_cursor-compatibility-remediation.md) | 20/23; Task 9 — hook-rename sync после handoff-v2 | мелкий ∥ слот |
| openspec-adapter хвост | строка `/mb openspec` в `commands/mb.md` | T1–T6 ✅ | мелкий ∥ слот (заморозка файла снята AGR-033) |
| adapter-parity | `specs/adapter-parity` + `context/adapter-parity.md` | T1–T7 ✅ (T1/T2 отмечены 2026-09-13 по доказательствам); T8 lifecycle ⬜ — upgrade не обновляет расширения, uninstall их оставляет, docs (I-213, I-118, I-124) | был первым в очереди (AGR-012); остался T8 |
| agreements (`/mb agree`) | `specs/agreements` (8 задач), коммит `9cdb41e` | работает; 19/24 пунктов подтверждены 2026-09-13; открыто I-212: 3 пробела в тестах, CI, dogfood 8 решений фичи | входит в donor v5.4.0 Trustworthy Baseline |
| donor v5.4.0 Trustworthy Baseline | [план](plans/2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md) | 0/2 стадий | голова donor-поезда |
| donor v5.5.0…v6.5.0 | umbrella `specs/mb-donor-evolution` (0/132) | не начаты | ICE-таблица Track 2 |
| quality-track | `specs/quality-track` | не начата | = donor v6.2.0 (AGR-008, AGR-009) |
| sdd-openspec-parity | `specs/sdd-openspec-parity` | не начата | HIGH ∥ лейн (AGR-007); Phase 2 — отдельный `/mb discuss` |
| pi-extension | `specs/pi-extension` (0/12) + [pi-compatibility-remediation](plans/2026-05-24_fix_pi-compatibility-remediation.md) | не начаты; pi-часть частично поглощена adapter-parity | Next |
| skill-improvements-anthropic-audit | [план](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) | не начат | docs-лейн, ∥ любому code-wave |
| I-109 остаток: агент mb-debugger | backlog | — | мелкий ∥ слот |
| Deferred: I-001 benchmarks · I-002 sqlite-vec · I-003 native-memory-bridge · I-005 graph-viz | backlog | заморожены осознанно | при user-сигнале |

## 📚 sdd-vision-pipeline — история группы (архив, не автогенерируется)

> Живые ICE и progress группы теперь рендерит autosync-фенс (слайс S4). Этот раздел —
> курируемая история: аннотации по слайсам, три круга spec-ревью и ссылки на отчёты,
> которые генератор не воспроизводит. Заголовок намеренно НЕ в форме `## Group: <slug>`,
> иначе bootstrap снесёт его при следующем прогоне.

Umbrella-группа (D-31, bootstrap вручную — автоматика рендера придёт из слайса S4). Контекст: [context/sdd-vision-pipeline.md](context/sdd-vision-pipeline.md) (D-01…D-35 → REQ-001…048; REQ-049…053 добавлены слайсом S8 по AGR-018; REQ-054 — D-11/находка ревью SVP-012) · транскрипт: [context/sdd-vision-pipeline-interview.md](context/sdd-vision-pipeline-interview.md) · umbrella-спека: `specs/sdd-vision-pipeline` (T1 + 8 слайсов) · гэп-анализ: `reports/2026-07-17_research_mattpocock-skills-vs-mb-pipeline.md`.

**Позиция (AGR-017):** главный трек после дожатия openspec-adapter + update-notify (оба ✅ завершены 2026-07-15); donor-релизы пере-ICE-иваются после создания этой группы. Пересечения принадлежат `sdd-openspec-parity` (quality-слой) и `quality-track` (оракулы/evidence) — ссылками, без дублирования (D-01).

Члены группы (внутригрупповой ICE-порядок, D-14 — цифры предложены LLM, подтверждает пользователь; % считается вручную до S4):

| # | Слайс / задача | ICE | Статус | Blocked by |
|---|---|---|---|---|
| T1 | MIT-атрибуция mattpocock/skills (REQ-038) | — | ⬜ ready | — |
| S1 | `svp-interview-upgrade` | 504 | 🟢 spec ready, 3 круга ревью (24 REQ, 6 задач, 20 сценариев) | — |
| S7 | `svp-brief` | 448 | 🟢 spec ready, 3 круга ревью (10 REQ, 4 задачи, 7 сценариев) | S1 |
| S4 | `svp-roadmap-backlog-db` | 432 | 🟢 spec ready, 3 круга ревью (13 REQ, 9 задач, 16 сценариев) | — |
| S2 | `svp-sdd-core` | 400 | 🟢 spec ready, 3 круга ревью (22 REQ, 9 задач, 21 сценарий) | — |
| S8 | `svp-contract-test-loop` | 360 | 🟢 spec ready, 2 круга ревью — первым был круг 2 (21 REQ, 8 задач, 12 сценариев) | S2 |
| S6 | `svp-docs-wiki` | 336 | 🟢 spec ready, 3 круга ревью (12 REQ, 7 задач, 11 сценариев) | S2 |
| S5 | `svp-adapt-escalation` | 294 | 🟢 spec ready, 3 круга ревью (10 REQ, 5 задач, 10 сценариев) | S2, S3, S4 |
| S3 | `svp-parallel-engine` | 252 | 🟢 spec ready, 3 круга ревью (17 REQ, 10 задач, 16 сценариев) | S2, S4 |
| S9 | `svp-spec-review-loop` | 336 (не подтверждён) | 🟢 spec ready, **ревью waived** (AGR-022, 2026-07-18; 13 REQ, 5 задач, 11 сценариев; батарея зелёная, эвалы red) — spec-уровневые review+judge кубики: spec_judge GO/GO_WITH_BACKLOG/NO_GO, fix-петля, реестр отклонений, work-гейт; umbrella-интеграция после ремедиации круга 3 | S2 |

Прогресс группы: задач umbrella 0/10 · child-спек создано 9/9 (S9 добавлен 2026-07-18, AGR-022) · **три круга spec-ревью пройдены, 96+91+75 находок закрыто (2026-07-17/18)**. Полная батарея: EARS 10/10, `--require-scenarios` 9/9 child, 124/124 сценария child-спек извлекаются (test_id уникальны, ASCII), 62 задачи child с полным v2 (Stage/Blocked-by/Scope/Budget/Eval); 10 задач umbrella — bootstrap legacy/meta (CPR-F, круг 3), все eval-гейты подтверждённо красные с `output~:`-якорями настоящего провала. Исполнение: T1 (MIT) → S1 (504) → S7 (448) → S4 (432) → S2 (400) → S8 (360) → S9 (336, после S2) → S6 (336) → S3 (252) → S5 (294, после S3/S4).

**Ревью группы 2026-07-17** ([reports/2026-07-17_review_spec-group-sdd-vision-pipeline.md](reports/2026-07-17_review_spec-group-sdd-vision-pipeline.md), 8 независимых ревьюеров Codex `gpt-5.6-sol`, effort=high): 8/8 CHANGES_REQUESTED, 96 находок (8 critical). **Все закрыты в тот же день**: механика скриптом (роли bare, 39+12 сценариев канонизированы с английскими именами, frontmatter group/ice/blocked_by), umbrella+S2 — оркестратором (грамматики Scope/Blocked-by зафиксированы в S2-C1, claims-lock, двухфазная эскалация, red=FAIL, REQ-054 fast-to-code, REQ-015 батарея самопроверки), S1/S7/S4/S6 — Sonnet-фиксерами, S3/S5 — Opus-фиксерами; каждый слайс верифицирован оркестратором независимо. Процесс-фикс: `commands/sdd.md` § Generation self-check (обязательная батарея потребителей) + урок в `notes/2026-07-17_1300_spec-generation-needs-consumer-battery.md`.

**Ревью группы, круг 2, 2026-07-17** ([reports/2026-07-17_review_spec-group-round2.md](reports/2026-07-17_review_spec-group-round2.md), 9 технических ревьюеров Codex `gpt-5.6-sol` — по одному на спеку, S8 впервые — + 10-й смысловой аудитор с полным транскриптом интервью): 83 технические находки + 8 смысловых. **Все закрыты в тот же день волновыми Opus-фиксерами** (волна 1 — владельцы контрактов umbrella/S1/S2/S4, волна 2 — потребители S7→S3→S8→S6→S5; правило «контракт чинит владелец, потребитель выравнивается под его текущий текст»), каждый слайс верифицирован оркестратором независимо (батарея + перепрогон red-эвалов + grep контрактов). Смысловая находка INT-PLAN-CONTRACT-EVAL решением пользователя не исправляется → AGR-019 (`/mb plan` остаётся ручным). Групповые нормы, введённые кругом 2: red-якоря `output~:` на всех Eval (S2 REQ-054/055, umbrella Interface 1), liveness-lock `mb_lock_acquire` S4-C6 (umbrella Interface 2), JSONL-вердикты (umbrella Interface 5), ICE-объект во frontmatter (umbrella Interface 4), реестр `Contract-checkers` (S8-C3a), субкоманда `annotate` для достижимости READY (X5-01).

**Ревью группы, круг 3 + ремедиация, 2026-07-17/18** ([reports/2026-07-17_review_spec-group-round3.md](reports/2026-07-17_review_spec-group-round3.md) → [reports/2026-07-18_review_spec-group-round3-remediation.md](reports/2026-07-18_review_spec-group-round3-remediation.md); та же схема 9+1 ревьюеров, каждому передан raw-вердикт круга 2 + реестр принятых отклонений): 73 технические находки (7 critical) + 2 смысловые; 15 — UNFIXED/PARTIAL круга 2. **Ремедиация по плану `plans/done/2026-07-18_fix_spec-group-round3-remediation.md` (через `/mb work`): ровно 4 Opus-фиксера двумя волнами по 2** (F1 umbrella+S4, F2 S2+S1 → F3 S7+S3+S5, F4 S6+S8), непересекающиеся файловые пакеты, независимая верификация оркестратором после каждого, кросс-пакетные запросы маршрутизировались владельцам (CPR-A…G, X-03/X-04). Смысловые решения пользователя: **AGR-020** (Cursor — четвёртый хост полного режима S3, D-07 восстановлен) и **AGR-021** (`ice_confirmed` не декоративен: `unconfirmed_ice=`-ворнинг + эскалация подтверждения, S4-C2/REQ-013). Ключевые нормы круга 3: lock-reclaim через owner-marker + targeted `rmdir` (НЕ `mv`/`rm -rf`); Eval-декларации design.md — fenced-списком byte-identical tasks.md (markdown-таблица заставляет `\|`, ломающий ERE); work-state `eval-red`/`eval-green` сами исполняют cmd-file (фальсификация вердикта флагами невозможна); restricted-glob грамматика Scope; секрет под `<private>` не попадает в git ни в одной политике. Попутно группа получила **S9 `svp-spec-review-loop`** (AGR-022, ревью waived): автоматизация этих же кругов — spec_judge, fix-петля, durable реестр отклонений, preflight-гейт `/mb work`.

## Active plans

<!-- mb-active-plans -->
- [2026-05-23] `queued` [2026-05-23_feature_cost-multi-model.md](plans/2026-05-23_feature_cost-multi-model.md) — feature — Cost (multi-model role assignment, S4 of harness-upgrade)
- [2026-05-23] `queued` [2026-05-23_feature_skill-improvements-anthropic-audit.md](plans/2026-05-23_feature_skill-improvements-anthropic-audit.md) — feature — skill-improvements-anthropic-audit
- [2026-05-24] `in_progress` [2026-05-24_fix_cursor-compatibility-remediation.md](plans/2026-05-24_fix_cursor-compatibility-remediation.md) — fix — Cursor Compatibility Remediation
- [2026-05-24] `queued` [2026-05-24_fix_pi-compatibility-remediation.md](plans/2026-05-24_fix_pi-compatibility-remediation.md) — fix — Pi Compatibility Remediation
- [2026-06-23] `in_progress` [2026-06-23_SEQUENCE_codex-remediation.md](plans/2026-06-23_SEQUENCE_codex-remediation.md) — sequence — Execution Sequence — codex/GPT-5.5 remediation (I-082..I-086)
- [2026-06-23] `queued` [2026-06-23_feature_dispatcher-wiring-transports.md](plans/2026-06-23_feature_dispatcher-wiring-transports.md) — feature — Capability Dispatcher Wiring + Transports
- [2026-06-23] `in_progress` [2026-06-23_fix_config-validation-docs.md](plans/2026-06-23_fix_config-validation-docs.md) — fix — Config Validation & Doc Consistency
- [2026-07-05] `in_progress` [2026-07-05_SEQUENCE_long-running-sessions.md](plans/2026-07-05_SEQUENCE_long-running-sessions.md) — sequence-plan — SEQUENCE — Long-running autonomous sessions
- [2026-07-15] `queued` [2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md](plans/2026-07-15_feature_mb-donor-evolution-v5-4-baseline.md) — feature — mb-donor-evolution — v5.4.0 Trustworthy Baseline
- [2026-07-28] `in_progress` [2026-07-28_fix_graph-semantic-adoption.md](plans/2026-07-28_fix_graph-semantic-adoption.md) — fix — graph-semantic-adoption
- [2026-09-05] `queued` [2026-09-05_fix_mb-work-cost-diet-sprint2.md](plans/2026-09-05_fix_mb-work-cost-diet-sprint2.md) — fix — mb-work-cost-diet · Sprint 2 «work-loop-diet»
- [2026-09-05] `queued` [2026-09-05_fix_mb-work-cost-diet-sprint3.md](plans/2026-09-05_fix_mb-work-cost-diet-sprint3.md) — fix — mb-work-cost-diet · Sprint 3 «instruction-diet + гигиена»
<!-- /mb-active-plans -->

## Архив

Старые разделы (priority inserts 2026-07-15, реестр 2026-07-15, current focus 2026-06, ICE-таблица 2026-06-14, recently completed 2026-04…06, legacy-план v3) перенесены дословно в [reports/2026-09-13_roadmap-archive.md](reports/2026-09-13_roadmap-archive.md).
