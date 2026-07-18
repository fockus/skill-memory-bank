---
id: G-001
status: active
mode: static
progress_source: checklist
progress_target: 100
replan_with: ""
linked_plans: []
---

# Goal: Исполнение группы sdd-vision-pipeline (10 спек) через /mb work до судейского GO

## Description

Все 10 спек группы `sdd-vision-pipeline` (umbrella + S1–S9) реализованы в коде через
governed-пайплайн `/mb work`: исполнители — сабагенты на Opus, ревью — codex CLI
(gpt-5.6), судья — сабагент на Fable. Исполнение идёт до трёх параллельных треков,
но не более 4 одновременных сабагентов; оркестратор — основная сессия, порядок
треков задан DAG-ом umbrella (T1 → S1 → S7 → S4 → S2 → S8 → S9 → S6 → S3 → S5).
Цель завершена, когда каждая спека прошла цикл implement→verify→review→judge до
вердикта GO/GO_WITH_BACKLOG и вся тестовая батарея репозитория зелёная.

## Acceptance criteria

- [ ] Все task-блоки 9 child-спек (62 задачи) исполнены: каждый DoD-чекбокс `[x]`, red→green Eval-якоря пройдены через mb-work-state.sh eval-red/eval-green
- [ ] Все 10 umbrella-задач sdd-vision-pipeline закрыты; delegate-гейты T2–T10 проходят (0 открытых DoD в child-спеках)
- [ ] Каждая из 10 спек получила судейский вердикт GO или GO_WITH_BACKLOG (судья на Fable); backlog-находки зарегистрированы в backlog.md до done
- [ ] Полный тестовый прогон репозитория зелёный (bats + pytest), shellcheck error-gate чист
- [ ] roadmap/status/checklist/progress актуализированы; работа закоммичена scoped-коммитами
