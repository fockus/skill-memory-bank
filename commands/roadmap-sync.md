---
description: "Regenerates the roadmap.md autosync block from plans/*.md frontmatter. Use when plans were added or changed and the roadmap must catch up — «обнови роадмап»."
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

## Skill bundle root

Every bundled helper below runs through the skill bundle root, never a bare `scripts/…` path (the
working directory is the user's project, where `scripts/` is absent or belongs to someone else):

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
```

## Usage

Run this command when plan frontmatter changes (status flip, new plan added, spec linked).

Under the hood it invokes `scripts/mb-roadmap-sync.sh`. Also runs automatically at the end of `/mb plan` and `/mb done`.

```bash
bash "$SKILL_DIR"/scripts/mb-roadmap-sync.sh
```

## Exit codes

- `0` — success
- `1` — `.memory-bank/` not found
