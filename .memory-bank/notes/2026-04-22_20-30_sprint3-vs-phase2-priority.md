---
date: 2026-04-22
topic: sprint-3 vs phase-2 priority decision
tags: [planning, priority, blocker, sprint-3, phase-2, i-028]
---

# Sprint 3 (I-028 fix) перед Phase 2 Sprint 1

## Контекст

После Phase 1 Sprint 2 (roadmap autosync + traceability-gen + Phase/Sprint/Task parser) финальный reviewer нашёл **Critical bug I-028**: multi-active plan checklist collision. Два плана с `## Task 1: Setup` сливаются в одну секцию checklist.md, и close одного удаляет у другого (silent data loss).

## Почему I-028 должен быть раньше Phase 2

Phase 2 Sprint 1 (`/mb discuss` + EARS + `context/<topic>.md`) сам по себе разбивается на `## Task 1..N` планы. При одновременной работе с другим планом — коллизия гарантирована. Поэтому:

**Порядок:**
1. **Sprint 3 baseline — I-028 fix** (~50 строк + tests): маркеры `<!-- mb-plan:<basename> -->` над каждой `## Stage N:` секцией, remove-logic ключуется по маркеру не по heading content. Backward-compat: секции без маркеров — legacy ownership.
2. **Phase 2 Sprint 1** — `/mb discuss` + EARS validator + `context/<topic>.md` template.

## Зачем нужен Phase 2 Sprint 1

Sprint 2 построил **output-сторону** traceability pipeline (`mb-traceability-gen.sh`), но **input-сторона пуста** → `traceability.md` всегда "No specs yet".

Phase 2 закрывает этот gap:
- `/mb discuss <topic>` — структурированное интервью → EARS-форматированные требования → `context/<topic>.md` с REQ-001..N
- EARS validator — проверяет 5 шаблонов (Ubiquitous / Event-driven / State-driven / Optional / Unwanted). Каждый REQ = атомарный test case
- `/mb plan <type> <topic>` читает `context/<topic>.md` → план с `## Requirements` секцией + per-stage `covers_requirements: [REQ-NNN]`
- Тесты с `REQ_NNN` в имени/docstring → автосвязь с матрицей

**Бизнес-ценность:** решает spec §1 ("нет SDD-дисциплины — требования в планах свободной формы"). Ловит unclear specs до кода. Kiro/Kilo-совместимо.

## Open backlog (LOW, не блокеры)

- I-023 (grep→find в start.md/mb-doctor), I-024 (`--` end-of-options), I-025 (`PLAN_MD` → `ROADMAP_MD`), I-027 (bash 4+ guard), I-029…I-032 (polish в traceability/roadmap-sync)
- Эти — cleanup'ы между фазами, не критичны
