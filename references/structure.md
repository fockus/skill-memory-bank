# Memory Bank — File Structure (v3.1)

> **v3.1 note:** четыре core-файла (`STATUS.md`, `plan.md`, `checklist.md`, `BACKLOG.md`) теперь имеют чётко разделённые обязанности и strict-формат со скрипт-управляемыми markers. Если у вас старый bank, запустите `scripts/mb-migrate-structure.sh --apply`.

## Core files — roles matrix

| File           | Покрытие                                     | Лимит (рекомендация) | Кто редактирует                                         |
|----------------|----------------------------------------------|----------------------|---------------------------------------------------------|
| `STATUS.md`    | «где я прямо сейчас» snapshot                | ≤ 60 строк           | человек + `mb-plan-sync.sh` / `mb-plan-done.sh`         |
| `plan.md`      | направление + активные планы                 | ≤ 80 строк           | человек + `mb-plan-sync.sh` / `mb-plan-done.sh`         |
| `checklist.md` | операционный to-do **только по активным**    | ≤ 100 строк          | агент в сессии + `mb-plan-sync.sh` / `mb-plan-done.sh`  |
| `BACKLOG.md`   | реестр идей + ADR                            | без лимита           | человек + `mb-idea.sh` / `mb-idea-promote.sh` / `mb-adr.sh` / `mb-compact.sh` |

Лимиты — *рекомендации*, не enforce. Если превышены — подсказка запустить `/mb compact`.

---

## `STATUS.md` — current snapshot

**Назначение:** прочитав за 30 секунд, увидеть, где проект сейчас и что происходит в работе.

```markdown
# <Project> — Status

**Current phase:** <phase name>
**Focus:** <what we're doing>
**Blockers:** none | <list>

## Metrics

- Tests: NNN green / MMM
- Coverage: NN%
- Last compact: YYYY-MM-DD

## Active plans

<!-- mb-active-plans -->
- [2026-04-21] [plans/2026-04-21_refactor_core-files-v3-1.md](plans/2026-04-21_refactor_core-files-v3-1.md) — refactor — core-files-v3-1
<!-- /mb-active-plans -->

## Recently done (last 10)

<!-- mb-recent-done -->
- 2026-04-18 — [plans/done/2026-04-15_feature_oidc.md](plans/done/2026-04-15_feature_oidc.md) — feature — OIDC publishing
<!-- /mb-recent-done -->

## Roadmap (high level)

See [BACKLOG.md](BACKLOG.md) for the idea registry and ADRs.
```

**Markers:**
- `<!-- mb-active-plans -->` / `<!-- /mb-active-plans -->` — upsert: одна запись на `basename` плана. Скрипты: `mb-plan-sync.sh` (добавить/обновить), `mb-plan-done.sh` (удалить).
- `<!-- mb-recent-done -->` / `<!-- /mb-recent-done -->` — FIFO newest-first. Trim до `MB_RECENT_DONE_LIMIT` (default `10`). Управляет `mb-plan-done.sh`.

---

## `plan.md` — direction + active plans

**Назначение:** один источник правды о том, что «в работе прямо сейчас» и куда двигаемся.

```markdown
# <Project> — Plan

## Current focus

<1-3 sentences describing the current direction>

## Active plans

<!-- mb-active-plans -->
- [2026-04-21] [plans/2026-04-21_refactor_core-files-v3-1.md](plans/2026-04-21_refactor_core-files-v3-1.md) — refactor — core-files-v3-1
<!-- /mb-active-plans -->

## Next up

See [BACKLOG.md](BACKLOG.md) — ideas with priority, ADRs.

## Отложено

<!-- bullets мигрируют в BACKLOG как DEFERRED через /mb compact --apply -->

## Отклонено

<!-- bullets мигрируют в BACKLOG как DECLINED через /mb compact --apply -->
```

**Что НЕ пишем:**
- Исторические «что сделано» (`progress.md`).
- Операционные to-do для активных планов (`checklist.md`).
- Сырые идеи (`BACKLOG.md`).

---

## `checklist.md` — operational to-do

**Назначение:** оперативный список шагов **только по активным планам**. Не архив.

```markdown
# <Project> — Checklist

## Stage N: <stage title>
- ⬜ <operational step 1>
- ⬜ <operational step 2>
- ✅ <completed step>
```

**Lifecycle:**
1. `mb-plan-sync.sh <plan>` добавляет секцию `## Stage N: <title>` с `⬜` items.
2. Агент по ходу работы меняет `⬜ → ✅`.
3. `mb-plan-done.sh <plan>` **удаляет всю секцию** (материал уже в `plans/done/<basename>`).
4. Завершённые секции без связанного plan-файла живут до `/mb compact --apply` (по threshold'у `MB_COMPACT_CHECKLIST_DAYS`, default `30`).

---

## `BACKLOG.md` — ideas + ADR registry

**Назначение:** живой parking lot идей + журнал архитектурных решений.

```markdown
# Backlog

## Ideas

### I-001 — restructure logging layer [HIGH, NEW, 2026-04-20]

**Problem:** logs unstructured, hard to parse in production.

**Sketch:** use structlog + JSON formatter.

**Plan:** —

### I-002 — OIDC publishing [MED, DONE, 2026-04-18]

**Problem:** PyPI token rotation is manual.

**Plan:** [plans/done/2026-04-18_feature_oidc.md](plans/done/2026-04-18_feature_oidc.md)

**Outcome:** migrated to OIDC Trusted Publishing.

## ADR

### ADR-001 — Use OIDC for PyPI publishing [2026-04-18]

**Context:** stored long-lived token in GitHub secrets.

**Options:**
- A: rotate token manually — high toil
- B: OIDC Trusted Publishing — PyPI-native, keyless

**Decision:** adopt B (OIDC).

**Rationale:** zero-token rotation, audit trail, PyPI-recommended.

**Consequences:** requires configuring PyPI Trusted Publisher per project.
```

**ID schemes:**
- **Idea ID:** `I-NNN` — monotonic через весь файл, zero-padded до 3 цифр. Генератор: `mb-idea.sh`. При ручной вставке `I-NNN` автоматика учитывает `max + 1`.
- **ADR ID:** `ADR-NNN` — monotonic через весь файл. Генератор: `mb-adr.sh`.

**Idea status lifecycle:** `NEW → TRIAGED → PLANNED → DONE` (или `DEFERRED` / `DECLINED`).

**Idea priorities:** `HIGH | MED | LOW` (case-insensitive на вход, uppercase в файле).

**Auto-transitions:**
- `mb-idea-promote.sh I-NNN <type>` → `NEW|TRIAGED` → `PLANNED` + создать plan-файл + добавить `**Plan:** [plans/...](...)`.
- `mb-plan-done.sh <plan>` → если идея привязана к плану (`**Plan:** plans/...`), `PLANNED` → `DONE` + `**Outcome:** <placeholder>`.
- `mb-compact.sh --apply` → `plan.md` «Отложено» / «Отклонено» → новые `I-NNN` идеи со статусом `DEFERRED` / `DECLINED`.

---

## `RESEARCH.md` — hypothesis log

```markdown
# <Project> — Research

## Current experiment

EXP-NNN: <title>

## Hypotheses

| ID    | Hypothesis           | Status        | Experiment | Result   | Conclusion   |
|-------|----------------------|---------------|------------|----------|--------------|
| H-001 | <text>               | ✅ Confirmed  | EXP-001    | <delta>  | <conclusion> |
| H-002 | <text>               | ⬜ Not tested | —          | —        | —            |

## Key findings

- `F-001`: <finding>
```

---

## `progress.md` — work log (append-only)

```markdown
# <Project> — Progress Log

## YYYY-MM-DD

### <Topic>

- <what was done>
- Tests: N green, coverage X%
- Next step: <what comes next>
```

Никогда не удаляем старые записи. Compact работает только на `plans/` и `notes/`.

---

## `lessons.md` — anti-patterns

```markdown
# <Project> — Lessons & Antipatterns

## <Category>

### <Pattern name> (EXP-NNN / source)

<Problem description and fix. 2-4 lines.>
```

---

## Directories

### `experiments/` — ML / empirical experiments

Files: `EXP-NNN.md`. Monotonic numbering.

Format: Hypothesis → Setup (baseline + one change) → Results (table with delta, p-value, Cohen's d) → Conclusions → Status.

### `plans/` — detailed plans

Files: `YYYY-MM-DD_<type>_<topic>.md`. Types: `feature`, `fix`, `refactor`, `experiment`.

Completed plans move to `plans/done/` через `mb-plan-done.sh`.

Format: Context → Stages (SMART DoD + TDD) → Risks → Gate.

Stage markers: `<!-- mb-stage:N -->` перед `### Stage N: <title>` — опциональные, позволяют `mb-plan-sync.sh` точно разобрать план.

### `notes/` — knowledge notes

Files: `YYYY-MM-DD_HH-MM_<topic>.md`.

5-15 lines. Focus: conclusions and patterns, not chronology.

Frontmatter опционален, но `importance: low` подсказывает compact'у, что заметку можно архивировать (>90d + no refs).

### `reports/` — free-form reports

Use when a full report will help future sessions.

### `codebase/` — codebase map

Structured snapshot, read on session start and consumed by planning/implementation agents.

| File             | Generator            | Purpose                                                                 |
|------------------|----------------------|-------------------------------------------------------------------------|
| `STACK.md`       | `/mb map stack`      | Languages, runtime, dependencies, external integrations                 |
| `ARCHITECTURE.md`| `/mb map arch`       | Layers, data flow, directory structure, entry points                    |
| `CONVENTIONS.md` | `/mb map quality`    | Naming, style, testing, imports                                         |
| `CONCERNS.md`    | `/mb map concerns`   | Tech debt, known bugs, security risks, performance hotspots             |
| `graph.json`     | `/mb graph --apply`  | JSON Lines — nodes/edges for modules, functions, classes (ast-based)    |
| `god-nodes.md`   | `/mb graph --apply`  | Top-20 nodes by degree (code hotspots)                                  |

**Producer:** subagent `mb-codebase-mapper` (sonnet). Каждый MD doc ≤ 70 строк.
**Consumer:** `scripts/mb-context.sh` — one-line summary в `/mb context`, full body — при `--deep`.

**When to regenerate:**
- After `/mb init`
- Stack change → `/mb map stack`
- Layers refactor → `/mb map arch`
- New lint/test tooling → `/mb map quality`
- Security/perf findings → `/mb map concerns`
- Any large change → `/mb map all` + `/mb graph --apply`

---

## Control envelopes

Переменные окружения для управления lifecycle:

| Variable                      | Default | Effect                                                                 |
|-------------------------------|---------|------------------------------------------------------------------------|
| `MB_RECENT_DONE_LIMIT`        | `10`    | Сколько done-планов хранит `STATUS.md ## Recently done`                |
| `MB_COMPACT_CHECKLIST_DAYS`   | `30`    | Возрастной порог удаления done-секций из `checklist.md` через compact  |
| `MB_COMPACT_PLAN_AGE_DAYS`    | `60`    | Возрастной порог архивирования done-планов                             |
| `MB_COMPACT_NOTE_AGE_DAYS`    | `90`    | Возрастной порог архивирования low-importance notes                    |
| `MB_COMPACT_ACTIVE_WARN_DAYS` | `180`   | Возраст, после которого compact предупреждает об active-планах         |
