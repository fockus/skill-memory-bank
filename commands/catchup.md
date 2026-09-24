---
description: Reload the current context after a reset or compaction
allowed-tools: [Bash, Read]
---

## Skill bundle root

Every bundled helper below runs through the skill bundle root, never a bare `scripts/…` path (the
working directory is the user's project, where `scripts/` is absent or belongs to someone else):

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
```

## Steps

1. Read `~/.claude/CLAUDE.md`
2. If `./.memory-bank/` exists:
   - Read `status.md`, `checklist.md`, `roadmap.md`, and the latest note from `notes/`
   - If `.memory-bank/codebase/*.md` is populated, include a one-line summary per doc (via `bash "$SKILL_DIR"/scripts/mb-context.sh` or `head -3` on each file)
3. Run `git diff` and `git diff --staged` — show what is currently in progress
4. Run `git log --oneline -5` — show the latest commits
5. Summarize in 3-5 sentences: what is done, what is in progress, and what comes next