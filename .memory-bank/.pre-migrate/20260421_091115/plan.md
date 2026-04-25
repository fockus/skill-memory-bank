# claude-skill-memory-bank — План

## Текущий фокус

**v3.0.0 stable + public website live.** Core release уже shipped, а 2026-04-21 для репозитория поднят GitHub Pages лендинг `https://fockus.github.io/skill-memory-bank/`. Ближайший фокус возвращается к release-continuity и backlog после закрытия публичной entrypoint-задачи.

После обратной связи внешнего ревью составлен план на 9 этапов через 3 минорных релиза (уточнён 2026-04-20):

- **v2.1 (этапы 1-4):** Auto-capture, drift checkers без AI, PII markers, compaction decay
- **v2.2 (этапы 5-7):** JSONL import, tree-sitter code graph, tags normalization
- **v3.0 (этапы 8-9):** Cross-agent (Cursor/Windsurf/Cline/Kilo/OpenCode/Pi Code/Codex) + repo migration + pipx/PyPI distribution + Homebrew tap
- **v3.1+ backlog:** benchmarks (LongMemEval), sqlite-vec, native memory bridge

Фактический статус по аудиту 2026-04-20:

- ✅ Этапы 1-8 закрыты в `checklist.md`
- 🔄 Этап 8.5 закрыт частично (migration сделана в коде/remote, release continuity ещё не доведена)
- 🔄 Этап 9 закрыт частично (package/docs/workflows готовы, release verification и smoke зелёные, не закрыты final release chores)
- ⬜ Gate v3.0 не выполнен: verification и smoke зелёные, но не завершены final release actions

Полный план: `plans/2026-04-20_refactor_skill-v2.1.md`.

## Active plan

<!-- mb-active-plan -->
**Active plan:** `plans/2026-04-21_refactor_core-files-v3-1.md` — refactor — core-files-v3-1
<!-- /mb-active-plan -->





## Ближайшие шаги

1. Закрыть остатки Stage 8.5: архив старого repo, continuity release/tags/docs
2. Решить, нужен ли отдельный follow-up на развитие/расширение сайта beyond landing
3. Принять решение по Anthropic plugin: финальный gate или post-release defer

## Уточнено 2026-04-20

- **Pi Code** = [pi-coding-agent от badlogic](https://github.com/badlogic/pi-mono) — 6-й adapter в Этапе 8; **Codex** добавлен как 7-й adapter (ADR-010)
- **Distribution** — pipx/PyPI primary (наш стек уже 12% Python), Homebrew tap secondary, Anthropic plugin tertiary. npm отменён.
- **Имена**: `memory-bank-skill` на PyPI ✓ свободно, `@fockus/memory-bank` на npm ✓ свободно (reserved на будущее), `fockus/homebrew-tap/memory-bank` создать при release
- **Benchmarks (Этап 10)** отложены в v3.1+ backlog

## Отклонено (после ревью)

- **Hash-based IDs** — решает multi-device конфликты, которых у нас нет (YAGNI)
- **KB compilation (`concepts/`, `connections/`, `qa/`)** — преждевременная иерархия
- **GWT в DoD** — дублирует test requirements в текущем шаблоне плана
- **Schema drift detection** — domain-specific, не fits generic skill
- `**/mb debug`** — дублирует `superpowers:debugging` skill
- **Viewer UI** — chrome over substance
- **REST API / daemon mode** — ломает наше архитектурное преимущество (simplicity, 93% Shell)
- **OpenAI/Cohere embeddings через API** — не деремся, local MiniLM

## Отложено (v3.1+ backlog)

- **sqlite-vec semantic search** — после Gate v3.0, когда keyword+tags+codegraph окажутся insufficient
- **i18n error-сообщений**
- **Native memory bridge** (программная синхронизация с Claude Code auto memory)
- **Viewer dashboard** (если adoption потребует)
