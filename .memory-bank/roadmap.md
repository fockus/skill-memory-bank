# Roadmap

_Last updated: auto-synced by mb-roadmap-sync.sh_

## Now (in progress)

_No active plan. Run /mb plan <type> <topic> to start._

## Next (strict order — depends)

Работа v4 idет последовательно, Phase 1 завершена, следующие два sprint'а в строгом порядке:

1. **⏭ Sprint 3 — I-028 fix (multi-active correctness)** [HIGH priority, ~50 строк + tests]
   - Baseline для Phase 2 — без этого fix'а `/mb discuss` планы словят коллизию в checklist.md
   - Маркеры `<!-- mb-plan:<basename> -->` над каждой `## Stage N:` секцией
   - Remove-logic по маркеру (plan-scoped), не по heading content
   - Backward-compat: секции без маркеров — legacy ownership
   - Repro: `sync p1 && sync p2 (одинаковый Task name) && done p1` → checklist empty, p2 orphaned

2. **⏳ Phase 2 Sprint 1 — `/mb discuss` + EARS validator + `context/<topic>.md`** [depends_on: Sprint 3]
   - Заполняет input-сторону traceability pipeline (Sprint 2 построил output, матрица пока всегда "No specs yet")
   - `/mb discuss <topic>` — структурированное интервью → EARS REQ-001..N
   - EARS validator — 5 шаблонов (Ubiquitous/Event-driven/State-driven/Optional/Unwanted)
   - `/mb plan` читает `context/<topic>.md` → REQ-линковка в stages
   - Решает spec §1 ("нет SDD-дисциплины")

**Обоснование порядка:** Phase 2 планы сами используют `## Task N:` headings, поэтому multi-active коллизии гарантированы при одновременной работе. Починить I-028 **до** Phase 2.

## Parallel-safe (can run now)

_Independent plans. See plans/*.md frontmatter: parallel_safe: true._

## Paused / Archived

_Plans in paused/cancelled state._

## Linked Specs (active)

- `specs/mb-skill-v2/` — skill v2 design doc (Phase 1 completed)

## Open high/medium backlog (см. backlog.md)

- **I-028 (HIGH)** — multi-active plan collision → Sprint 3 baseline ☝️
- I-023 (MED) — grep→find в start.md/mb-doctor
- I-026 ✅ resolved в Sprint 2 (Phase/Sprint/Task parser)

## Roadmap high-level (из specs/mb-skill-v2/design.md §20)

- **Phase 1 — Foundation** ✅ COMPLETE (rename + autosync + traceability-gen infrastructure)
- **Phase 2 — Discussion & SDD artifacts** (Sprint 1: discuss+EARS+context; Sprint 2: /mb sdd + specs/<topic>/ + SDD-lite)
- **Phase 3 — Work engine** (Sprint 1: pipeline.yaml + /mb config; Sprint 2: /mb work + 9 role-agents; Sprint 3: review-loop + severity gates)
- **Phase 4 — Hardening** (Sprint 1: plan-verifier + 4 critical hooks; Sprint 2: --auto/--range/--budget + sprint_context_guard; Sprint 3: superpowers overrides + installer update)

## See also
- traceability.md — REQ coverage matrix (пока "No specs yet", Phase 2 заполнит)
- backlog.md — future ideas & ADR
- checklist.md — current in-flight tasks
- notes/2026-04-22_20-30_sprint3-vs-phase2-priority.md — обоснование порядка Sprint 3 → Phase 2

---

### Legacy content (preserved from the previous plan-file format — review and integrate above)

# claude-skill-memory-bank — План

## Текущий фокус

**v3.0.0 stable + public website live.** Core release уже shipped, а 2026-04-21 для репозитория поднят GitHub Pages лендинг `https://fockus.github.io/skill-memory-bank/`. P0 hardening из full-repo review закрыт: 3 High finding'а покрыты тестами, `mb-compact.sh` снова отвечает только за decay, structural migration возвращён в `mb-migrate-structure.sh`, а installer/adapter surface сокращён перед `v3.1.0`.

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

## Active plans

<!-- mb-active-plans -->
<!-- /mb-active-plans -->

## Ближайшие шаги

1. v3.1.2 shipped — no active plans. Next work: v3.2.0 (agents-quality tag, CHANGELOG [3.2.0] already staged), or Stage 8.5 repo-migration cleanup.
2. Optional: Stage 7 `mb-session-recoverer` when user signal arrives.

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
