---
type: note
tags: [planning, security, refactor, installers, adapters, memory-bank]
related_features: []
sprint: null
importance: high
created: 2026-04-21
---

# plan-review-hardening-installer-boundaries
Date: 2026-04-21

## What was done
- Создан отдельный refactor-план на устранение проблем из full-repo review и security audit
- План отделён от `core-files-v3-1` и `agents-quality`, чтобы P0 hardening не смешивался с release-continuity и агентскими улучшениями
- В приоритет поставлены 3 High finding'а, contract cleanup для CLI/uninstall и вынос client-specific global logic из `install.sh`

## New knowledge
- **Security-first sequencing** для shell-heavy repo критично: сначала path validation и manifest safety, затем уже архитектурный разрез installer/adapters
- **Thin orchestrator pattern** здесь нужен буквально: `install.sh` должен координировать, а не знать Cursor-global внутренности
- **Shared helper extraction оправдан только там, где он сразу убирает heredoc duplication и упрощает тестирование** — поэтому фокус на text/IO helpers, а не на полном переносе всего bash в Python
- **Review finding != automatic code change**: low-confidence YAGNI пункты (`mb-import.py`, tree-sitter split, tags redesign, locale pruning) зафиксированы как out-of-scope, чтобы не утопить P0 hardening в scope creep
