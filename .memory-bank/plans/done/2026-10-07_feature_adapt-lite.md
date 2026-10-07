---
type: feature
topic: adapt-lite
status: done
depends_on: ["2026-10-07_feature_pipeline-presets-cost-tiers.md"]
parallel_safe: false
linked_specs: ["specs/svp-adapt-escalation"]
created: 2026-10-07
---
# Plan: feature — adapt-lite · дробление по необходимости (первый срез svp-adapt-escalation)

**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6

## Context

**Problem.** AGR-078/079 убрали обязательное мелкое дробление планов. Нужен механизм для случая, когда крупный пункт
всё-таки не поддаётся: ADaPT (As-Needed Decomposition and Planning, Prasad et al., 2023) — исполнитель пробует
пункт целиком, а декомпозиция запускается только при неудаче и только для застрявшего пункта. Полная спека
`specs/svp-adapt-escalation` заблокирована `svp-parallel-engine` (0/10) и `svp-roadmap-backlog-db` (3/9); решение
владельца AGR-080 — сделать облегчённый первый срез сейчас.

**Покрывает из спеки:**
- REQ-001 — сигнал `complexity_escalation`;
- REQ-002 частично: гарды «verify не прошёл за N циклов» и «перерасход токенов пункта», без scope-гарда, которому нужен S3;
- REQ-003 — пороги в `pipeline.yaml`;
- REQ-005 — HITL-выбор: продолжить, упростить, разложить или пропустить;
- REQ-006-lite — раскладка на подпункты внутри запуска, без нового spec-реестра.

REQ-004 (заглушки за флагом), REQ-007/008 (журнал) и REQ-010 (каскад-стоп) остаются в полной спеке.

**Expected result.**
1. **Правила.** Планирование и исполнитель: «бери пункт целиком; если видишь, что пункт требует новой подсистемы или не
   укладывается — верни `complexity_escalation` (причина, оценка, предложенные подпункты), а не дроби молча и не
   продолжай вслепую».
2. **`/mb work`.** Триггер ADaPT — сигнал исполнителя или гард (`adapt.verify_fail_cycles` по умолчанию 3,
   `adapt.item_token_budget` по умолчанию null = выкл). Дальше по режиму:
   - auto — planner раскладывает только этот пункт на 2–5 подпунктов (AND-семантика);
   - HITL — пользователь выбирает: продолжить, упростить, разложить или пропустить.

   Подпункты выполняются тем же workflow, родительский пункт закрывается после последнего подпункта.
   Глубина рекурсии ≤ 2. Подпункты живут в состоянии запуска (`mb-work-state`) и в progress-записи; в файл плана
   не пишутся, маркеры `mb-stage:N` остаются целочисленными.
3. **Конфиг.** `pipeline.yaml` → `adapt: {enabled: true, verify_fail_cycles: 3, item_token_budget: null,
   max_depth: 2}`. Флаг `--no-adapt`.

**Related files:**
- правила: `references/effort-tiers.md`, `commands/plan.md`, `references/templates.md`, `agents/mb-engineering-core.md` (отчёт исполнителя), `agents/mb-architect.md` (раскладка пункта);
- `/mb work`: `commands/work.md` / `references/work-reference.md` (оба на лимите 400 строк — детали в новый `references/adapt.md`), `scripts/mb-work-state.sh` / `mb-work-state-lib.sh`, `scripts/mb-work-plan.sh`, `references/pipeline.default.yaml`, валидатор, тесты.

**Parallel execution (AGR-073).**
- Stage 1 (правила) идёт сразу: его файлы свободны.
- Stage 2 (`/mb work`) идёт после pipeline-presets Stage 3: тот агент сейчас владеет `work.md`, `work-reference.md`, `mb-work-plan.sh`, `mb-work-state-lib.sh` и `pipeline.default.yaml`.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Правила ADaPT в планировании и отчёте исполнителя

**Files:** `references/effort-tiers.md`, `commands/plan.md`, `references/templates.md`, `agents/mb-engineering-core.md`,
`agents/mb-architect.md`, `references/adapt.md` (new), тесты

**What to do:**
- `references/adapt.md`: принцип ADaPT, триггеры, развилка auto/HITL, формат блока `complexity_escalation`
  (`reason`, `estimate`, `proposed_subitems[]`), глубина, связь со спекой.
- `effort-tiers.md`, `plan.md`, `templates.md`: одна-две строки «план крупный; дробление по необходимости — ADaPT»
  со ссылкой на `references/adapt.md`.
- `mb-engineering-core.md` § Scope / отчёт: исполнитель возвращает `complexity_escalation` вместо молчаливого дробления
  или работы вслепую.
- `mb-architect.md`: режим «разложить один пункт на 2–5 подпунктов с `Files:`».

**Testing (TDD):** pytest-гард — `references/adapt.md` существует и содержит формат блока; core и architect ссылаются на
него; `plan.md` упоминает ADaPT.

**DoD:**
- [x] гард зелёный; `test_agent_report_delivery.bats`, тесты рендера агентов зелёные (`test_repo_files_mentioned_in_skill` ждёт строки про `references/adapt.md` в SKILL.md — владелец SKILL.md)

<!-- mb-stage:2 -->
### Stage 2: ADaPT в `/mb work`

**Files:** `commands/work.md`, `references/work-reference.md`, `scripts/mb-work-state.sh`, `scripts/mb-work-state-lib.sh`,
`scripts/mb-work-plan.sh` или новый модуль, `references/pipeline.default.yaml`, валидатор, тесты

**What to do:**
- Парсинг `complexity_escalation` из отчёта исполнителя; гарды `verify_fail_cycles` и `item_token_budget`.
  Используется уже существующий счётчик циклов из `mb-work-state` и `mb-work-budget`.
- В auto: dispatch planner (`roles.planner`) на один пункт → подпункты в state (`mb-work-state.sh split <item>`). В HITL:
  четыре варианта. Подпункты проходят шаги workflow, родитель закрывается после последнего. Глубина ≤ `max_depth`.
- `adapt` в `pipeline.default.yaml` + валидация; флаг `--no-adapt`; строка в run summary о каждой эскалации.

**Testing (TDD):**
- bats: сигнал → split в state, родитель открыт, пока подпункты не закрыты; verify провален 3 раза → триггер;
  `--no-adapt` → прежнее поведение (halt); глубина 3 → отказ с сообщением; `adapt.enabled: false` → без изменений.

**DoD:**
- [x] тесты зелёные; без триггера поведение `/mb work` прежнее; `work.md` ≤ 400 строк (`scripts/mb_work_adapt.py`, `mb-work-state.sh split/sub-done/adapt-check`, `mb-workflow.sh --no-adapt` → JSON `adapt`; bats `test_mb_work_adapt_lite.bats` 13/13, pytest `test_mb_work_adapt.py`)

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Модель эскалирует слишком часто вместо работы | M | эскалация требует оценки и предложенных подпунктов; в HITL пользователь может выбрать «продолжить»; телеметрия — в полной спеке |
| Подпункты в state теряются при прерывании запуска | M | state уже переживает возобновление (`mb-work-state`); progress-запись при split |
| Расхождение с полной спекой | L | термины и формат блока — из `specs/svp-adapt-escalation`; срез помечен в спеке |

## Gate (plan success criterion)

Крупный пункт выполняется целиком, если получается; при сигнале исполнителя или провале verify 3 раза `/mb work`
раскладывает только этот пункт (auto) или предлагает 4 варианта (HITL); без триггера поведение прежнее; все тесты зелёные.
