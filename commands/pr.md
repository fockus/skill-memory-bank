---
description: Create a PR from the current branch
allowed-tools: [Bash, Read]
argument-hint: [title-override]
---

## 0. Pre-flight checks

```bash
# Must NOT be on main / master
BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ] && echo "ERROR: refusing to open PR from $BRANCH" && exit 1

# Must have commits ahead of the integration branch
git fetch origin main 2>/dev/null || git fetch origin master 2>/dev/null
AHEAD=$(git rev-list --count origin/main..HEAD 2>/dev/null || git rev-list --count origin/master..HEAD 2>/dev/null || echo 0)
[ "$AHEAD" = "0" ] && echo "WARN: 0 commits ahead of main — nothing to PR" && exit 1

# Surface which workflows will run against the PR
gh workflow list 2>/dev/null | head -10
```

If on main / master, stop and tell the user to create a feature branch first. If 0 commits ahead, tell the user there is nothing to PR.

## 1. Gather context

```bash
git diff origin/main --stat         # or origin/master
git log origin/main..HEAD --oneline
```

Read `./.memory-bank/checklist.md` and the active plan (if any) to understand what the PR delivers. If `.memory-bank/codebase/` is populated, fold its summaries into the PR body for reviewer orientation.

## 2. Draft the PR content

- **Title** — Conventional Commits format, ≤70 chars. Use `$ARGUMENTS` if provided.
- **Body** — Markdown with:
  - `## Summary` — 1-3 bullets on what changed and why
  - `## Test plan` — checklist items the reviewer can run
  - `## Codebase context` (optional, if `.memory-bank/codebase/` is populated) — one line summary pulled from each of `STACK.md`, `ARCHITECTURE.md`, `CONVENTIONS.md`, `CONCERNS.md` (whichever exist); use `grep -m1 -v '^#'` to get the first non-heading line per file
  - `## Related issues` — `Closes #N`, `Refs #M` if applicable

## 3. Show preview → confirm

Print the full title + body as it will appear on GitHub. Ask:

```
Create PR with this title and body? (y/N)
```

Default = No. Only proceed on explicit `y`.

## 4. Create the PR

```bash
gh pr create --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

## 5. Show result

Return the PR URL to the user.
