# claude-skill-memory-bank — План

## Текущий фокус

**v2.1 — Auto-capture + hardening (в работе).** Профиль: **гибрид C** — personal сейчас, public через v3.0.

После обратной связи внешнего ревью составлен план на 9 этапов через 3 минорных релиза (уточнён 2026-04-20):
- **v2.1 (этапы 1-4):** Auto-capture, drift checkers без AI, PII markers, compaction decay
- **v2.2 (этапы 5-7):** JSONL import, tree-sitter code graph, tags normalization
- **v3.0 (этапы 8-9):** Cross-agent (Cursor/Windsurf/Cline/Kilo/OpenCode/Pi Code) + pipx/PyPI distribution + Homebrew tap
- **v3.1+ backlog:** benchmarks (LongMemEval), sqlite-vec, native memory bridge

Полный план: `plans/2026-04-20_refactor_skill-v2.1.md`.

## Active plan

<!-- mb-active-plan -->
### План 2026-04-20 refactor skill-v2.1

**Статус:** 0/9 этапов выполнено

- ⬜ Этап 1: Auto-capture через SessionEnd hook (v2.1)
- ⬜ Этап 2: Drift checkers без AI (`mb-drift.sh`) (v2.1)
- ⬜ Этап 3: PII markers `<private>...</private>` (v2.1)
- ⬜ Этап 4: Compaction decay `/mb compact` (v2.1)
- ⬜ Этап 5: Import from Claude Code JSONL (v2.2)
- ⬜ Этап 6: Tree-sitter code graph в `codebase/` (v2.2)
- ⬜ Этап 7: Tags normalization (v2.2)
- ⬜ Этап 8: Cross-agent output — Cursor, Windsurf, Cline, Kilo, OpenCode, Pi Code (v3.0)
- ⬜ Этап 9: pipx/PyPI distribution + Homebrew tap (v3.0)

Полный план: `.memory-bank/plans/2026-04-20_refactor_skill-v2.1.md`
<!-- /mb-active-plan -->

## Ближайшие шаги

1. **Этап 1 (auto-capture) старт** — TDD red-first: `tests/bats/test_auto_capture.bats` (≥8 тестов) до кода. 1-2 дня.
2. После Gate v2.1 — Этапы 5-7 (v2.2 knowledge reach)
3. После Gate v2.2 — Этапы 8-9 (v3.0 public distribution через pipx)

## Уточнено 2026-04-20

- **Pi Code** = [pi-coding-agent от badlogic](https://github.com/badlogic/pi-mono) — 6-й adapter в Этапе 8
- **Distribution** — pipx/PyPI primary (наш стек уже 12% Python), Homebrew tap secondary, Anthropic plugin tertiary. npm отменён.
- **Имена**: `memory-bank-skill` на PyPI ✓ свободно, `@fockus/memory-bank` на npm ✓ свободно (reserved на будущее), `fockus/homebrew-tap/memory-bank` создать при release
- **Benchmarks (Этап 10)** отложены в v3.1+ backlog

## Отклонено (после ревью)

- **Hash-based IDs** — решает multi-device конфликты, которых у нас нет (YAGNI)
- **KB compilation (`concepts/`, `connections/`, `qa/`)** — преждевременная иерархия
- **GWT в DoD** — дублирует test requirements в текущем шаблоне плана
- **Schema drift detection** — domain-specific, не fits generic skill
- **`/mb debug`** — дублирует `superpowers:debugging` skill
- **Viewer UI** — chrome over substance
- **REST API / daemon mode** — ломает наше архитектурное преимущество (simplicity, 93% Shell)
- **OpenAI/Cohere embeddings через API** — не деремся, local MiniLM

## Отложено (v3.1+ backlog)

- **sqlite-vec semantic search** — после Gate v3.0, когда keyword+tags+codegraph окажутся insufficient
- **i18n error-сообщений**
- **Native memory bridge** (программная синхронизация с Claude Code auto memory)
- **Viewer dashboard** (если adoption потребует)
