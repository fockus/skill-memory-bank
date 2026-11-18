# /mb migrate-structure — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `migrate-structure [--dry-run\|--apply]` — One-shot v3.0 → v3.1 structural migrator. Upgrades singular `<!-- mb-active-plan -->` to plural, adds `mb-active-plans` + `mb-recent-done` blocks to `status.md`, restructures `backlog.md` to the `## Ideas` skeleton, creates `adr.md` if absent. Creates `.pre-migrate/<timestamp>/` backup. Idempotent

### migrate-structure [--dry-run|--apply]

One-shot migrator for the v3.0 → v3.1 Memory Bank file structure. Safe to run on an already-migrated bank (idempotent).

**Detection — triggers if any of:**

- `roadmap.md` has singular `<!-- mb-active-plan -->` marker (but not plural variant).
- `roadmap.md` uses the legacy text-only "## Active plan" + "**Active plan:** `plans/...`" without a HTML-comment block.
- `status.md` is missing `<!-- mb-active-plans -->` or `<!-- mb-recent-done -->` blocks.
- `backlog.md` contains legacy placeholder markers such as `(empty)` or lacks `## Ideas`.
- `adr.md` (the ADR registry) is missing.

**Effect of `--apply`:**

1. Backs up `roadmap.md`, `status.md`, `backlog.md`, `checklist.md` → `.memory-bank/.pre-migrate/<timestamp>/`.
2. Upgrades `roadmap.md` singular → plural marker block, rebuilds `## Active plans` with correct entries.
3. Ensures `status.md` has `## Active plans` + `## Recently done` sections with proper markers.
4. Rewrites `backlog.md` skeleton: strips placeholders, guarantees the `## Ideas` section (ADRs are not stored in `backlog.md`).
5. Creates `adr.md` with the `# Architecture Decision Records` header if absent.
6. Prints a per-action summary.

`--dry-run` (default) — prints the action plan, 0 file changes.

Run directly:

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-migrate-structure.sh $ARGS_AFTER_MIGRATE
```

**Typical flow:**

```
User: /mb migrate-structure
→ mode=dry-run
  actions_pending=3
    - roadmap.md: add <!-- mb-active-plans --> block
    - status.md: add <!-- mb-recent-done --> block
    - backlog.md: restructure to skeleton (## Ideas)

User: /mb migrate-structure --apply
→ [apply] backup → .pre-migrate/20260421_093045/
  [apply] roadmap.md migrated
  [apply] status.md blocks ensured
  [apply] backlog.md skeleton ensured
  [apply] v3.1 structural migration complete
```

**Safety:**

- Running `--apply` twice on an already-migrated bank reports `actions_pending=0` and exits without changes.
- The `.pre-migrate/<timestamp>/` directory is persistent — restore with `cp .memory-bank/.pre-migrate/<ts>/*.md .memory-bank/` if anything goes wrong.
- Does not touch `notes/`, `plans/`, `progress.md`, `lessons.md`, `research.md`, `experiments/`, `codebase/`, or custom files.

**Recommended usage:** once per bank, after upgrading the skill to v3.1.x. Subsequent compaction is handled by `/mb compact`.
