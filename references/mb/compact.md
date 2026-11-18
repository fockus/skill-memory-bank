# /mb compact — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `compact [--dry-run\|--apply]` — Status-based decay: plans in `done/` older than 60d → BACKLOG archive, low-importance notes older than 90d → `notes/archive/`. Active plans are not touched. `--dry-run` (default) = reasoning only

### compact [--dry-run|--apply]

Status-based archival decay. Cleans up old completed plans and unused low-importance notes, **without touching active work**.

**Criteria (AND, not OR):**


| Candidate                              | Age threshold | Done-signal (required)                                                                                                                  |
| -------------------------------------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Plan in `plans/done/`                  | `>60d` mtime  | Primary: already physically in `plans/done/`                                                                                            |
| Plan in `plans/*.md` (active location) | `>60d` mtime  | `✅` / `[x]` marker in `checklist.md` line with the basename, OR mention in `progress.md`/`status.md` as `completed|done|closed|shipped` |
| Note in `notes/*.md`                   | `>90d` mtime  | `importance: low` in frontmatter + **no** basename references in `roadmap.md`/`status.md`/`checklist.md`/`research.md`/`backlog.md`        |


**Safety net:** active plans (not done) are **NOT archived** even if >180d old. Instead, emit a warning like "plan X is older than 180d but not done — check whether it is still relevant".

**Effects of `--apply`:**

- Plans → compressed into one line inside `backlog.md ## Archived plans`, original file deleted. Source path is preserved as `(was: plans/done/<file>.md)` — git history keeps the full text.
- Notes → moved to `notes/archive/` + body compressed to 3 non-empty lines + marker `<!-- archived on YYYY-MM-DD -->`. Entries get `archived: true` in `index.json`.
- Touched `.memory-bank/.last-compact` timestamp.

`--dry-run` (default) — prints reasoning per candidate to stdout, 0 file changes.

Run directly (systems-level, no LLM needed for the decision logic — it is deterministic):

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-compact.sh $ARGS_AFTER_COMPACT
```

**Searching the archive:** default `mb-search` does NOT include archived items. Opt in via `mb-search.sh --include-archived <query>` or `--include-archived --tag <tag>`.

**Typical flow:**

```
User: /mb compact
→ dry-run output:
  mode=dry-run
  plans_candidates=2
  notes_candidates=5
  candidates=7

  # Plans to archive:
    archive: plans/done/2026-01-10_feature_x.md (reason=in_done_dir, age=100d)
    archive: plans/done/2026-02-01_fix_auth.md (reason=in_done_dir, age=78d)

  # Notes to archive:
    archive: notes/2025-12-15_experiment.md (reason=low_age_unref, age=125d)
    ...

  # Warnings — active plans older than 180d:
    warning: plans/2025-09-01_long_feature.md is 230d old but not done — check whether it is still relevant

User: /mb compact --apply
→ [apply] archived plan: plans/done/2026-01-10_feature_x.md (reason=in_done_dir)
  [apply] archived note: notes/2025-12-15_experiment.md → notes/archive/
  ...
```
