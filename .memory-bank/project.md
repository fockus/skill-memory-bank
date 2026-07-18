---
type: project
name: skill-memory-bank
created: 2026-07-18
updated: 2026-07-18
---

## Mission

Memory Bank — скил долговременной проектной памяти + engineering-правила + dev-toolkit (`/mb`, 25 команд) для Claude Code и семи других агентских клиентов.

## Domain

Инструментарий LLM-агентной разработки: project memory, SDD-спеки, governed execution pipeline.

## Stack

See codebase/STACK.md.
- Bash 3.2-совместимые скрипты (стоковый macOS), Python 3.9+ stdlib-only, тесты bats + pytest.

## Non-negotiable constraints

- Никаких новых runtime-зависимостей без явного запроса; переносимость macOS/Linux (никакого голого GNU `timeout` — `mb_adapt_bounded_run`).
- `progress.md` append-only; IDs монотонные (I-/EXP-/ADR-/AGR-NNN, не переиспользуются); scoped `git add` (никогда `-A`) — в дереве живёт чужой WIP.
- `COORDINATION.md` читается перед стадиями/коммитами; FREEZE-записи обязательны к исполнению.
- TDD + contract-first: red-якорь до реализации; Eval-гейты только через `mb-work-state.sh eval-red/eval-green` (норма X-05).
- Protected paths: `.env*`, `ci/**`, `.github/workflows/**`, `Dockerfile*`, `k8s/**`, `terraform/**`.

## Team coding conventions

See codebase/CONVENTIONS.md.
- Файлы ≤400 строк (SRP-гейт mb-rules-check); имена тестов `test_<what>_<condition>_<result>`.

## Architecture notes

- Источник истины исполнения — `specs/<topic>/tasks.md` блоки `<!-- mb-task:N -->`; design.md держит контракты и Eval-декларации fenced-списком byte-identical tasks.md.

## Out of scope

- Редактирование транскриптов `context/*-interview.md`; авто-инициализация банка без явного `/mb init`.
