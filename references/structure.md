# Memory Bank — File Structure (v3.1)

> **v3.1 note:** the four core files (`status.md`, `roadmap.md`, `checklist.md`, `backlog.md`) now have clearly separated responsibilities and a strict format managed by script-owned markers. If you have an older bank, run `scripts/mb-migrate-structure.sh --apply`.

## Core files — roles matrix

| File           | Coverage                                     | Limit (recommended) | Edited by                                               |
|----------------|----------------------------------------------|---------------------|---------------------------------------------------------|
| `status.md`    | “where the project is right now” snapshot    | ≤ 60 lines          | human + `mb-plan-sync.sh` / `mb-plan-done.sh`           |
| `roadmap.md`      | direction + active plans                     | ≤ 80 lines          | human + `mb-plan-sync.sh` / `mb-plan-done.sh`           |
| `checklist.md` | operational to-do **for active plans only**  | ≤ 100 lines         | in-session agent + `mb-plan-sync.sh` / `mb-plan-done.sh`|
| `backlog.md`   | idea registry + ADRs                         | no limit            | human + `mb-idea.sh` / `mb-idea-promote.sh` / `mb-adr.sh` / `mb-compact.sh` |

Limits are *recommendations*, not hard enforcement. If they are exceeded, the skill may suggest running `/mb compact`.

---

## `status.md` — current snapshot

**Purpose:** in 30 seconds, understand where the project is and what is currently happening.

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

See [backlog.md](backlog.md) for the idea registry and ADRs.
```

**Markers:**
- `<!-- mb-active-plans -->` / `<!-- /mb-active-plans -->` — upsert: one entry per plan basename. Managed by `mb-plan-sync.sh` (add/update) and `mb-plan-done.sh` (remove).
- `<!-- mb-recent-done -->` / `<!-- /mb-recent-done -->` — FIFO newest-first. Trimmed to `MB_RECENT_DONE_LIMIT` (default `10`). Managed by `mb-plan-done.sh`.

---

## `roadmap.md` — direction + active plans

**Purpose:** the single source of truth for what is in progress right now and where the project is heading.

```markdown
# <Project> — Plan

## Current focus

<1-3 sentences describing the current direction>

## Active plans

<!-- mb-active-plans -->
- [2026-04-21] [plans/2026-04-21_refactor_core-files-v3-1.md](plans/2026-04-21_refactor_core-files-v3-1.md) — refactor — core-files-v3-1
<!-- /mb-active-plans -->

## Next up

See [backlog.md](backlog.md) — ideas with priority, ADRs.

## Deferred

<!-- bullets migrate into BACKLOG as DEFERRED via /mb compact --apply -->

## Declined

<!-- bullets migrate into BACKLOG as DECLINED via /mb compact --apply -->
```

**What does NOT belong here:**
- Historical “what was done” notes (`progress.md`).
- Operational to-do items for active plans (`checklist.md`).
- Raw ideas (`backlog.md`).

---

## `checklist.md` — operational to-do

**Purpose:** an operational step list **for active plans only**. It is not an archive.

```markdown
# <Project> — Checklist

## Stage N: <stage title>
- ⬜ <operational step 1>
- ⬜ <operational step 2>
- ✅ <completed step>
```

**Lifecycle:**
1. `mb-plan-sync.sh <plan>` adds a `## Stage N: <title>` section with `⬜` items.
2. The agent flips `⬜ → ✅` during execution.
3. `mb-plan-done.sh <plan>` **removes the entire section** (the durable record already lives in `plans/done/<basename>`).
4. Completed sections without a linked plan file remain until `/mb compact --apply` removes them based on `MB_COMPACT_CHECKLIST_DAYS` (default `30`).

---

## `backlog.md` — ideas + ADR registry

**Purpose:** a live idea parking lot plus an architecture decision journal.

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
- **Idea ID:** `I-NNN` — monotonic across the whole file, zero-padded to 3 digits. Generated by `mb-idea.sh`. If you insert an `I-NNN` manually, automation still uses `max + 1`.
- **ADR ID:** `ADR-NNN` — monotonic across the whole file. Generated by `mb-adr.sh`.

**Idea status lifecycle:** `NEW → TRIAGED → PLANNED → DONE` (or `DEFERRED` / `DECLINED`).

**Idea priorities:** `HIGH | MED | LOW` (case-insensitive on input, uppercase in the file).

**Auto-transitions:**
- `mb-idea-promote.sh I-NNN <type>` → `NEW|TRIAGED` → `PLANNED` + create a plan file + add `**Plan:** [plans/...](...)`.
- `mb-plan-done.sh <plan>` → if an idea is linked to the plan (`**Plan:** plans/...`), `PLANNED` → `DONE` + `**Outcome:** <placeholder>`.
- `mb-compact.sh --apply` → localized `roadmap.md` `Deferred` / `Declined` sections → new `I-NNN` ideas with `DEFERRED` / `DECLINED` status.

---

## `research.md` — hypothesis log

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

Never delete old entries. Compact operates only on `plans/` and `notes/`.

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

Completed plans move to `plans/done/` via `mb-plan-done.sh`.

Format: Context → Stages (SMART DoD + TDD) → Risks → Gate.

Stage markers: `<!-- mb-stage:N -->` before `### Stage N: <title>` — optional, but they let `mb-plan-sync.sh` parse the plan precisely.

### `notes/` — knowledge notes

Files: `YYYY-MM-DD_HH-MM_<topic>.md`.

5-15 lines. Focus: conclusions and patterns, not chronology.

Frontmatter is optional, but `importance: low` hints to compact that the note can be archived (>90d + no refs).

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

**Producer:** subagent `mb-codebase-mapper` (sonnet). Each MD doc should stay within 70 lines.
**Consumer:** `scripts/mb-context.sh` — one-line summary in `/mb context`, full body with `--deep`.

**When to regenerate:**
- After `/mb init`
- Stack change → `/mb map stack`
- Layers refactor → `/mb map arch`
- New lint/test tooling → `/mb map quality`
- Security/perf findings → `/mb map concerns`
- Any large change → `/mb map all` + `/mb graph --apply`

---

## Control envelopes

Environment variables that control lifecycle behavior:

| Variable                      | Default | Effect                                                                 |
|-------------------------------|---------|------------------------------------------------------------------------|
| `MB_RECENT_DONE_LIMIT`        | `10`    | How many completed plans `status.md ## Recently done` keeps            |
| `MB_COMPACT_CHECKLIST_DAYS`   | `30`    | Age threshold for removing completed sections from `checklist.md`      |
| `MB_COMPACT_PLAN_AGE_DAYS`    | `60`    | Age threshold for archiving completed plans                            |
| `MB_COMPACT_NOTE_AGE_DAYS`    | `90`    | Age threshold for archiving low-importance notes                       |
| `MB_COMPACT_ACTIVE_WARN_DAYS` | `180`   | Age after which compact warns about still-active plans                 |
