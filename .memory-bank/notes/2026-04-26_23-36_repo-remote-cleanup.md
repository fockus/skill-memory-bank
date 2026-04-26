# repo-remote-cleanup
Date: 2026-04-26 23:36

## What was done
- Removed dead `old-origin` remote (`github.com/fockus/claude-skill-memory-bank` — pre-rename URL); branch `main` upstream switched from `old-origin` → `origin` (`github.com/fockus/skill-memory-bank`).
- `git rm --cached -f --ignore-unmatch .memory-bank/.session-lock` — ephemeral lock no longer in index.
- `.gitignore` — added `.memory-bank/.session-lock` and `.memory-bank/.auto-lock` under a new "Memory Bank runtime artifacts" section.
- `rm -rf dist/` — purged stale `3.0.0rc1` wheels (gitignored, never committed; just local cleanup).
- `tests/pytest/test_gitignore_invariants.py` — 5 contract tests locking the invariants in.

## New knowledge
- After a GitHub repo rename, the old URL keeps redirecting indefinitely, but the redirect ages oddly: keeping `old-origin` as a "safety net" is just dead weight that misleads future readers. Remove the moment the new URL is confirmed working (`git rev-list origin/main..HEAD = 0`).
- `git rm --cached` works even when the file is already deleted in the worktree — it just records the deletion in the index. No need for `--force` unless paths conflict.
- Ephemeral runtime locks (`.session-lock`, `.auto-lock`) belong in `.gitignore` from day one of any tool that creates them; missing the gitignore = `git status` noise compounds across every session and dirties commit hygiene.
