---
topic: svp-spec-review-loop
status: ready
created: 2026-07-18
source: беседа 2026-07-18 (после круга 3 ревью группы); codex-ревью спеки НЕ проводилось — AGR-022
---

# Context: svp-spec-review-loop (S9)

Spec-уровневые кубики пайплайна **review + judge**: автоматический судья вердиктов spec-ревью, fix-петля, durable реестр принятых отклонений, preflight-гейт `/mb work`. Расширение S2-C5 (`sdd.spec_review` — одиночный ревьюер, судья-человек, D-30), а не его замена. Мотивация — прожитый вручную опыт трёх кругов ревью группы `sdd-vision-pipeline` (96 → 91 → 75 находок, волновые фиксеры, реестр принятых отклонений в промптах круга 3): всё это должно быть штатными, конфигурируемыми ступенями пайплайна.

## Research digest

- S2-C5 уже даёт: `sdd.spec_review {enabled, agent, model, thinking}` (инлайн-мапа), вердикт append-only JSONL `<bank>/tmp/spec-review/<topic>.jsonl`, писатель `scripts/mb-sdd-review-result.sh` (S2-T7), same_model exit 2, SKIPPED loudly — `specs/svp-sdd-core/design.md` § C5, `tasks.md` Task 7.
- Умбрелла REQ-035 (D-30): spec-review опционален, судья — человек/оркестратор. S9 добавляет автоматического судью НЕ отменяя ручной путь (spec_judge выключен → поведение D-30 как было).
- Существующие кубики кода: `mb-judge` агент (GO/GO_WITH_BACKLOG/NO_GO), `codex-reviewer` (health-check + SKIPPED loudly), `mb-work-review-parse.sh`, `mb-work-severity-gate.sh` — переиспользуются паттерны, но severity-гейт кода 1:1 не подходит (у спеки нет диффа кода).
- Рубрика спец-ревью (11 пунктов: coverage/contract/eval/consistency/parent-decision/cross-slice/feasibility/edge-case/sizing/over-engineering/clarity) выверена тремя кругами — scratchpad `review/rubric.md`, копия в `reports/2026-07-17_review_spec-group-round3-raw/rubric.md`.
- Уроки (нативная память + notes): «judge terminates the review loop» (иначе ревьюер бесконечно улучшает); «governed review needs independent re-fix pass» (после фиксов — независимый re-review, не self-check); реестр принятых отклонений в промпте круга 3 предотвратил повторное поднятие отклонённого.

## Decision Log

- **D-01** — Spec-уровневые review+judge как composable кубики пайплайна (запрос пользователя: «ревью и судью не только на уровне кода, но и на уровне спеки»). Alternatives rejected: оставить только ручные codex-круги (не масштабируется: 3 ручных круга × 10 агентов на группу).
- **D-02** — Судья автоматический: `GO | GO_WITH_BACKLOG | NO_GO`; судья, а не ревьюер, терминирует цикл. Alternatives rejected: судья-человек всегда (остаётся дефолтом при выключенном spec_judge — D-30 не ломаем).
- **D-03** — Fix-петля: NO_GO → фикс-проход по findings → НОВЫЙ независимый re-review; `max_cycles` с honest stop (спека не принята, наблюдаемая сигнатура, решение у пользователя).
- **D-04** — Durable реестр принятых отклонений `specs/<topic>/review-deviations.md`; инъектируется в каждый последующий review-промпт; отклонение = запись с якорным доказательством. Alternatives rejected: хранить в tmp (теряется), в леджере context (смешивает решения спеки с ревью-процессом).
- **D-05** — Preflight-гейт `/mb work`: действующий вердикт CHANGES_REQUESTED без judge GO/GO_WITH_BACKLOG → отказ до диспатча с наблюдаемой причиной; явный override фиксируется в JSONL. Alternatives rejected: молчаливый запуск (нарушает честную деградацию).
- **D-06** — Промпт ревью собирает детерминированный скрипт (rubric + реестр отклонений + файлы спеки + схема вердикта), LLM только исполняет — тестируемый шов вместо непроверяемой инструкции.
- **D-07** — Рубрика трёх кругов становится bundled default `references/spec-review-rubric.md`; переопределение путём в pipeline.
- **D-08** — Спека создана БЕЗ codex-ревью — явное решение пользователя (AGR-022, «только не будем его проверять»); ревью-долг зафиксирован во frontmatter `review: waived`. Интеграция в umbrella (REQ/строка слайса/мета-задача) — после завершения ремедиации круга 3 (umbrella сейчас у фиксера F1).

## Open Questions

- Групповое ревью (N спек × M ревьюеров волной, как наши круги) — вне scope S9 (одиночная спека); оркестрация группы остаётся ручной/будущий слайс.
- Автофиксер findings как отдельная роль пайплайна (сейчас фикс-проход делает оркестратор/фиксер-агент вручную) — решить после первых прогонов S9.
