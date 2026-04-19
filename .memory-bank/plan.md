# claude-skill-memory-bank — План

## Текущий фокус

Рефактор skill v1 → v2: language-agnostic, DRY, tested, integrated with Claude Code ecosystem. Устраняем 36 проблем, выявленных в аудите.

## Active plan

**`plans/2026-04-19_refactor_skill-v2.md`** — главный план рефактора (10 этапов).

## Ближайшие шаги

1. Завершить Этап 0 (этот init) — зафиксировать в progress.md
2. Начать Этап 1 — `_lib.sh` + `detect_stack` + bats-тесты (TDD first)
3. Этапы 2-4 выполняются параллельно после Этапа 1

## Отложено

- Создание отдельного plugin'а `memory-bank-dev-commands` (Этап 5) — вынос orphan-команд
- sqlite-vec для реального semantic search — вне scope v2 (опционально в v3)
- i18n error-сообщений — v3
- Интеграция с нативной Claude Code memory через bridge — Этап 5 (только документация, не код)
