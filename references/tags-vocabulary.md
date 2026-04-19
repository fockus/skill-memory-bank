# Default tags vocabulary

Controlled vocabulary для frontmatter `tags` в `notes/*.md`. Используется `mb-tags-normalize.sh` для detection unknown-тегов и synonym-merge.

Пользователь может скопировать этот файл в `.memory-bank/tags-vocabulary.md` и кастомизировать под проект (добавить domain-specific теги, убрать неиспользуемые).

## Conventions

- Только kebab-case: `refactor`, `db-migration`, `perf-critical`
- Lowercase, без пробелов
- Существительные (где применимо): `bug` не `bugs`
- Краткие: `api` не `api-endpoint`

## Core tags

- arch          # архитектурное решение / паттерн
- auth          # authentication / authorization
- bug           # баг или его фикс
- ci            # continuous integration
- doc           # документация
- db            # база данных
- deploy        # deployment / release
- experiment    # эксперимент / research
- feature       # новая фича
- infra         # infrastructure
- lesson        # извлечённый урок (дублирует lessons.md как tag)
- migration     # миграция (schema / framework / version)
- monitoring    # observability / alerts
- perf          # performance optimization
- pii           # privacy / personal data handling
- pattern       # повторно используемый pattern
- refactor      # рефакторинг
- security      # security issue / hardening
- test          # тесты (unit / integration / e2e)

## Process tags

- debug         # отладочная сессия
- review        # code review findings
- post-mortem   # разбор инцидента
- adr           # architectural decision record
- spike         # исследовательский спайк

## Workflow tags

- blocked       # заблокировано внешней зависимостью
- todo          # требует действия
- wip           # work in progress
- imported      # импортировано из JSONL (авто-tag)
- discussion    # архитектурная дискуссия (авто-tag)
