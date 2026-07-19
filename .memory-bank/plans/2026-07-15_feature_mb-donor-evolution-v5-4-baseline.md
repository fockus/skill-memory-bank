---
title: "mb-donor-evolution — v5.4.0 Trustworthy Baseline (release wrapper)"
type: feature
topic: mb-donor-evolution-v5-4-baseline
release: 5.4.0
linked_spec: specs/mb-donor-evolution
tasks: 1-6
depends_on: []
parallel_safe: false
status: queued
created: 2026-07-15
owner: main-agent (Fable) — plan; /mb work — execution
roles: "implement=sonnet · review=codex gpt-5.5 · judge=opus"
---

# Plan: mb-donor-evolution — v5.4.0 Trustworthy Baseline

Release wrapper для первого релиза donor-программы. Исполняемый источник истины —
`specs/mb-donor-evolution/tasks.md`, блоки `<!-- mb-task:1 -->`…`<!-- mb-task:6 -->`
(BL-01…BL-06). Диапазон `tasks: 1-6` нормативен: CLI-range не должен его расширять.

## Контекст

- Документ-источник: `specs/mb-donor-evolution/source-plan.md` (Этап 0, §10).
- Нумерация сдвинута +1 минор: доковский v5.3.0 Baseline выходит как **v5.4.0**,
  потому что v5.3.0 уже выпущена 2026-07-13 (стабилизация main + PyPI). Сдвиг
  санкционирован source-plan §23 (R-15, монотонный сдвиг).
- Часть скоупа Этапа 0 уже фактически закрыта релизом 5.3.0 (стабилизация main,
  зелёные тесты, публикация). BL-задачи выполняются относительно текущего HEAD.

## Entry gate (§10.1, адаптировано)

- [ ] Зафиксированы HEAD SHA, `VERSION=5.3.0`, dirty state и объём `[Unreleased]` после 5.3.0.
- [ ] Свежие CI/check результаты получены (или недоступность явно зафиксирована).
- [ ] Umbrella-спека `mb-donor-evolution` прошла `mb-spec-validate.sh --require-scenarios`.

## Задачи (см. spec tasks.md — исполнять через /mb work)

| mb-task | ID | Суть |
|---:|---|---|
| 1 | BL-01 | Reconcile status/roadmap/spec metadata |
| 2 | BL-02 | Validate current test/build/package baseline |
| 3 | BL-03 | Umbrella SDD finalization + 2 ADR (single entrypoint, single writer) |
| 4 | BL-04 | Supersede parallel-pipeline design (закрепить миграционную заметку) |
| 5 | BL-05 | Close unreleased gates accumulated after 5.3.0 |
| 6 | BL-06 | Version/changelog/docs/package verification → v5.4.0 evidence |

BL-01 и BL-02 — параллельно-безопасные read-only; BL-03…BL-06 последовательно.

## Exit / release gate (§10.5)

- `VERSION`, changelog, package metadata, status и release notes называют 5.4.0.
- Все shipped-спеки имеют корректный terminal status; drift suite: 0 противоречий.
- Umbrella SDD валидна (`--require-scenarios --json`), traceability сгенерирована.
- Полные tests/lint/shellcheck/packaging + clean-install smoke — свежие evidence.
- `parallel-pipeline` нигде не числится текущей архитектурой.
- Публикация (tag/PyPI/Homebrew/push) — только по отдельному явному разрешению.

## Rollback

Только metadata/docs изменения — обычный revert. Миграций состояния банка нет.
