# claude-skill-memory-bank — Lessons & Antipatterns

Накапливаются по ходу рефактора v2.

## Meta / Skill Design

### Dogfooding = validation (2026-04-19 / audit)
Skill без собственного `.memory-bank/` в репозитории — явный сигнал нежизнеспособности. Первым делом — init в own repo. Если skill неудобен для самого автора, он неудобен для пользователей.

### Orphan agents leak from templates (2026-04-19 / audit)
При копировании agent'ов из другого плагина (GSD) важно проверить frontmatter (`name:`), output paths и integration points. Orphan `codebase-mapper` с `name: gsd-codebase-mapper` и записью в `.planning/` — классический artifact copy-paste без адаптации.

### Language hardcode in "universal" tools (2026-04-19 / audit)
Инструмент, позиционируемый как language-agnostic, но захардкоженный на `pytest`/`ruff`/`src/taskloom/` — ложное позиционирование. Либо честно ограничиться Python, либо реально детектировать стек (pyproject/go.mod/Cargo.toml/package.json).
