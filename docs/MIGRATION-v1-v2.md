# Migration v1 → v2: lowercase filenames

_Since: skill version 2.0.0._

## What changed

Four files renamed:

| v1 (old) | v2 (new) |
|----------|----------|
| `STATUS.md` | `status.md` |
| `BACKLOG.md` | `backlog.md` |
| `RESEARCH.md` | `research.md` |
| `plan.md` | `roadmap.md` (+ new format) |

## Why

- consistent lowercase filename convention
- `plan.md` expanded to a true roadmap with ordering, dependencies, and status per plan (see [design spec](../.memory-bank/specs/mb-skill-v2/design.md))

## How to migrate

From your project root:

```bash
# Preview what will change (no writes)
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-v2.sh --dry-run

# Apply (creates backup in .memory-bank/.migration-backup-<timestamp>/)
bash ~/.claude/skills/memory-bank/scripts/mb-migrate-v2.sh --apply
```

## What the script does

1. Creates a timestamped backup in `.memory-bank/.migration-backup-<ts>/`.
2. Renames the 4 files.
3. Transforms `roadmap.md` content — the legacy `<!-- mb-active-plan -->` block is placed in the new `## Now (in progress)` section; remaining content is preserved under `### Legacy content`.
4. Updates cross-references (`STATUS.md` → `status.md`, etc.) in every `.md` file inside `.memory-bank/` — except the backup directory.
5. Is idempotent — running twice is safe (second run is a no-op that reports "no v1 files detected").

## Backward compatibility window

For 2 skill versions:

- Core scripts fall back to reading old names if new ones are not present.
- `/mb doctor` WARNs when v1 files still exist.
- `/mb start` and `/mb context` autodetect v1 layout and prompt migration before loading context.

After 2 versions, `/mb doctor` will ERROR without migration.

## Rollback

Each `--apply` run creates `.memory-bank/.migration-backup-<timestamp>/`. To rollback:

```bash
BACKUP=.memory-bank/.migration-backup-<ts>   # pick the one you want
cp -r "$BACKUP"/* .memory-bank/
rm .memory-bank/status.md .memory-bank/backlog.md \
   .memory-bank/research.md .memory-bank/roadmap.md
```

Or — if `.memory-bank/` is under version control and was committed before the migration — `git checkout .memory-bank/`.

## Troubleshooting

**"no v1 files detected" on first run:**
Your project is already on v2 (or was never on v1). Nothing to do.

**"both STATUS.md and status.md present":**
You manually created a v2 file alongside v1. The script will skip the rename for that pair. Resolve manually (`mv`, merge content, then re-run).

**"cannot read .memory-bank":**
Either the directory doesn't exist or you're in the wrong cwd. `cd` to your project root and retry.
