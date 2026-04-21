# ~/.claude/commands/catchup.md

---

## description: Reload the current context after a reset or compaction
allowed-tools: [Bash, Read]

1. Read `~/.claude/CLAUDE.md`
2. If `./.memory-bank/` exists, read `checklist.md`, `plan.md`, and the latest note from `notes/`
3. Run `git diff` and `git diff --staged` — show what is currently in progress
4. Run `git log --oneline -5` — show the latest commits
5. Summarize in 3-5 sentences: what is done, what is in progress, and what comes next