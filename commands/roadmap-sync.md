---
description: Regenerate roadmap.md autosync block from plans/*.md frontmatter
allowed-tools: [Bash, Read]
---

# /mb roadmap-sync

Regenerate `.memory-bank/roadmap.md` autosync block from `plans/*.md` frontmatter.

## What it does

Scans `.memory-bank/plans/*.md` (not `plans/done/`) for frontmatter fields:
- `status` — in_progress / queued / paused / cancelled
- `depends_on` — list of plan paths
- `parallel_safe` — true / false
- `linked_specs` — list of spec paths

Regenerates sections between `<!-- mb-roadmap-auto -->` fences:
- `## Now (in progress)`
- `## Next (strict order — depends)`
- `## Parallel-safe (can run now)`
- `## Paused / Archived`
- `## Linked Specs (active)`

Content outside the fence is preserved byte-for-byte. Idempotent.

## Usage

Run this command when plan frontmatter changes (status flip, new plan added, spec linked).

Under the hood it invokes `scripts/mb-roadmap-sync.sh`. Also runs automatically at the end of `/mb plan` and `/mb done`.

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-roadmap-sync.sh
```

## Exit codes

- `0` — success
- `1` — `.memory-bank/` not found
