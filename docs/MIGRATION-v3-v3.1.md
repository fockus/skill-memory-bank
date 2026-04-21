# Migration guide — v3.0.x → v3.1.0

v3.1.0 is a **major refactor of the core Memory Bank files** (`STATUS.md`,
`plan.md`, `checklist.md`, `BACKLOG.md`). The on-disk shape changes, but
migration is fully automatic — one command and a timestamped backup.

---

## What changed

### Multi-active plan support

v3.0 tracked exactly one active plan through singular HTML markers:

```md
<!-- mb-active-plan -->
**Active plan:** `plans/2026-04-21_feature_foo.md`
<!-- /mb-active-plan -->
```

v3.1 drops the singular form and tracks any number of active plans through a
plural block in both `plan.md` and `STATUS.md`:

```md
## Active plans

<!-- mb-active-plans -->
- [2026-04-21] [plans/2026-04-21_feature_foo.md](plans/2026-04-21_feature_foo.md) — feature — foo
- [2026-04-21] [plans/2026-04-21_refactor_bar.md](plans/2026-04-21_refactor_bar.md) — refactor — bar
<!-- /mb-active-plans -->
```

`mb-plan-sync.sh` dedupes by basename, so running it twice for the same plan
is idempotent. `mb-plan-done.sh` removes the entry from both files and
prepends the plan to the new `<!-- mb-recent-done -->` block in `STATUS.md`
(trimmed to `MB_RECENT_DONE_LIMIT`, default 10).

### `BACKLOG.md` skeleton

v3.0 `BACKLOG.md` was freeform. v3.1 fixes the skeleton:

```md
# Backlog

## Ideas

### I-001 — Refactor logging layer [HIGH, NEW, 2026-04-20]
**Problem:** …
**Proposal:** …

### I-002 — Add sqlite-vec search [MED, DEFERRED, 2026-04-20]
**Problem:** …
**Proposal:** …

## ADR

### ADR-001 — Use tree-sitter for non-Python code graph [2026-04-20]
**Context:** …
**Options:** …
**Decision:** …
**Rationale:** …
**Consequences:** …
```

- **ID schemes are monotonic project-wide** — `I-NNN` for ideas, `ADR-NNN`
  for ADRs. `mb-idea.sh` / `mb-adr.sh` scan the whole file for the current
  max and +1.
- **Idea lifecycle**: `NEW → TRIAGED → PLANNED → DONE` (or `DEFERRED` /
  `DECLINED`). `mb-idea-promote.sh` flips `NEW/TRIAGED → PLANNED` and adds a
  `**Plan:**` cross-link; `mb-plan-done.sh` flips `PLANNED → DONE` when the
  linked plan completes.

### `checklist.md` / `plan.md` compaction

`scripts/mb-compact.sh` grew two new jobs alongside the existing note-decay
pass:

1. **`checklist.md`** — stage sections whose every item is ticked *and* whose
   linked plan already lives in `plans/done/` for more than
   `MB_COMPACT_CHECKLIST_DAYS` days (default 14) are removed on `--apply`.
2. **`plan.md`** — bullets in `## Отложено` / `## Deferred` and
   `## Отклонено` / `## Declined` sections are migrated into `BACKLOG.md` as
   fresh `I-NNN` ideas with status `DEFERRED` / `DECLINED` respectively, and
   removed from `plan.md` (section heading preserved for future entries).

---

## How to migrate

### 1. Upgrade the skill

```bash
pipx upgrade memory-bank-skill          # or: brew upgrade memory-bank
```

### 2. Preview the changes (dry-run)

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-structure.sh --dry-run .memory-bank
```

Sample output:

```
mode=dry-run
actions_pending=4
  - plan.md: add <!-- mb-active-plans --> block
  - STATUS.md: add <!-- mb-active-plans --> block
  - STATUS.md: add <!-- mb-recent-done --> block
  - BACKLOG.md: restructure to skeleton (## Ideas + ## ADR)
```

### 3. Apply

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-structure.sh --apply .memory-bank
```

This:

- Creates a timestamped backup: `.memory-bank/.pre-migrate/YYYYMMDD_HHMMSS/`
- Upgrades singular `<!-- mb-active-plan -->` markers to plural
  `<!-- mb-active-plans -->` and converts legacy `**Active plan:**` bullets
  into proper block entries.
- Renames heading `## Active plan` → `## Active plans`.
- Ensures `STATUS.md` has the two new marker blocks (empty if you had none).
- Ensures `BACKLOG.md` has `## Ideas` and `## ADR` sections (appended if
  missing, leaves existing content untouched).

Rerunning is a no-op (`actions_pending=0`).

### 4. Verify

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-structure.sh --dry-run .memory-bank
# expected: actions_pending=0

grep -c "<!-- mb-active-plans -->" .memory-bank/plan.md .memory-bank/STATUS.md
# expected: each file reports 1
```

---

## New subcommands

| Command                                      | What it does                                                                         |
| -------------------------------------------- | ------------------------------------------------------------------------------------ |
| `/mb idea "<title>" [HIGH\|MED\|LOW]`        | Append a new idea to `BACKLOG.md ## Ideas` with monotonic `I-NNN`.                   |
| `/mb idea-promote <I-NNN> <type>`            | Promote idea to a plan (`feature\|fix\|refactor\|experiment`); flips status.         |
| `/mb adr "<title>"`                          | Capture an ADR in `BACKLOG.md ## ADR` with the standard skeleton.                    |
| `/mb migrate-structure [--dry-run\|--apply]` | One-shot structural migration (this doc).                                            |
| `/mb compact [--apply]`                      | Existing decay pass — now also compacts `checklist.md` and `plan.md` (see above).    |

---

## Rollback

If the migration misbehaves:

```bash
rm -rf .memory-bank/plan.md .memory-bank/STATUS.md .memory-bank/checklist.md .memory-bank/BACKLOG.md
cp .memory-bank/.pre-migrate/YYYYMMDD_HHMMSS/*.md .memory-bank/
```

The `.pre-migrate/` directory is never touched by subsequent migrations, so
every run adds a fresh timestamped backup.

---

## Environment variables (v3.1)

| Variable                      | Default | Purpose                                                                              |
| ----------------------------- | ------- | ------------------------------------------------------------------------------------ |
| `MB_RECENT_DONE_LIMIT`        | `10`    | How many completed plans to keep in `STATUS.md ## <!-- mb-recent-done -->`.          |
| `MB_COMPACT_CHECKLIST_DAYS`   | `14`    | Age (days) for `mb-compact.sh` to remove a fully-done checklist section.             |
| `MB_COMPACT_AGE_DAYS`         | `90`    | Age (days) for `mb-compact.sh` to archive notes / reports / progress entries.        |

All limits are **recommendations**, not hard enforcement. The scripts never
block on oversize files — they just surface a hint in `mb-doctor` or on
install.

---

## See also

- `references/structure.md` — full v3.1 file-format specification.
- `CHANGELOG.md#310--2026-04-21` — complete change list.
- `commands/mb.md` — updated subcommand reference.
