# ~/.claude/commands/pr.md
---
description: Create a PR from the current branch
allowed-tools: [Bash, Read]
---
1. Run `git diff main --stat` — show what changed
2. Read `./.memory-bank/checklist.md` and the latest plan if one exists
3. Generate a PR description:
   - Title in Conventional Commits format
   - "What changed" section — list of changes
   - "How to test" section — steps for the reviewer
   - "Related issues" section — if applicable
4. Run `gh pr create --title "<title>" --body "<body>"`
5. If `$ARGUMENTS` is provided, use it as the title
