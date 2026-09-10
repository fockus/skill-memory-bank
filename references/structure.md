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

**Format v2 — one block per plan** (a registry of plans in flight, not a per-stage log):

```markdown
# <Project> — Checklist

> Convention. Open work only; hard cap ≤100 lines. Closed plans live in `progress.md`.

<!-- mb-plan:2026-09-05_fix_widget-pipeline.md -->
## Widget pipeline — 1/3
- ✅ Stage 1 — build the widget
- ⬜ Stage 2 — ship the widget
- ⬜ Stage 3 — document the widget
```

One `<!-- mb-plan:<basename> -->` marker per plan (not per stage), heading = plan title + `k/n` done, one line per stage. Plans with `status: planned|paused` get a single line (title + link) under `## ⏭ Next` / `## ⏸ Paused`; the `## 🔄 Active` prose stays ≤ 10 lines.

**Lifecycle:**
1. `mb-plan-sync.sh <plan>` upserts the plan's v2 block, adding only stages the block does not have yet (idempotent by marker + stage number; never resets a ✅).
2. `mb-work-checkbox.sh flip` mirrors a gated DoD flip onto the matching `Stage N` line and recomputes `k/n`. The agent may also flip by hand.
3. `mb-plan-done.sh <plan>` moves the plan into `plans/done/`; `mb-checklist-prune.sh --apply` then copies the whole block **verbatim** into `progress.md` under `## [checklist archive] <date> — <plan>` and only then removes it from the checklist. An append it cannot confirm leaves the block in place — nothing is ever deleted.
4. `mb-checklist-prune.sh --apply` also folds legacy v1 per-stage blocks of one plan into its single v2 block, and archives fully-done `### ` sections linking `plans/done/…` the same way.
5. **Cap:** `MB_CHECKLIST_MAX_LINES` → `<bank>/.mb-config` `checklist_max_lines=` → `100`. Still over the cap after compaction → exit 3 with a per-plan diagnostic (`<plan>: k open`). Live work is never cut to fit: the answer is to pause or close plans.

---

## Core-file caps

`status.md` and `checklist.md` are strict registries, not archives (AGR-043): the first holds only
the current state, the second only the plans in flight. Both carry a hard LINE cap enforced by code —
`bash scripts/mb-core-cap.sh check --mb <bank>` exits 1 when either is over, and the Stop hook
`mb-core-cap-guard.sh` says so once per session.

- **Caps:** `MB_STATUS_MAX_LINES` / `MB_CHECKLIST_MAX_LINES` → `<bank>/.mb-config` `status_max_lines=` /
  `checklist_max_lines=` → **60 / 100**. `MB_CORE_CAP=off` (or `core_cap=off` in `.mb-config`) disables the layer.
- **Repair, in order:** `mb-core-cap.sh fix` (rotation + v2 compaction, deterministic) → still over →
  MB Manager `action: actualize --strict` → still over → the owner decides.
- **Nothing is deleted.** Every block leaving a core file is verified in `progress.md` first.
  Open `⬜` lines never move: exit 3 ("N plans in flight") is a signal to pause or close plans, never to trim.

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
| `MB_CHECKLIST_MAX_LINES`      | `100`   | `checklist.md` line cap (`.mb-config` `checklist_max_lines=` overrides the default) |
| `MB_STATUS_MAX_LINES`         | `60`    | `status.md` line cap (`.mb-config` `status_max_lines=` overrides the default) |
| `MB_CORE_CAP`                 | `on`    | `off` disables `mb-core-cap.sh` and its Stop hook entirely (`.mb-config` `core_cap=off` is the per-bank form) |
| `MB_COMPACT_CHECKLIST_DAYS`   | `30`    | Age threshold for removing completed sections from `checklist.md`      |
| `MB_COMPACT_PLAN_AGE_DAYS`    | `60`    | Age threshold for archiving completed plans                            |
| `MB_COMPACT_NOTE_AGE_DAYS`    | `90`    | Age threshold for archiving low-importance notes                       |
| `MB_COMPACT_ACTIVE_WARN_DAYS` | `180`   | Age after which compact warns about still-active plans                 |
| `MB_UPDATE_CHECK`             | `on`    | SessionStart "newer release?" notice; `off` disables the check entirely (no network, no cache writes) |
| `MB_UPDATE_CHECK_TTL`         | `86400` | Update-check cache TTL, seconds (24h) — at most one network call per window |
| `MB_AUTO_UPDATE`              | `off`   | `on` auto-applies an available update for a clean git-clone install only; pipx/pip/brew installs are never auto-run |
