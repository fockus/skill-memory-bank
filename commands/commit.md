---
description: Review staged changes and create a commit
allowed-tools: [Bash, Read]
argument-hint: [message-override]
---

## 0. Pre-flight safety checks

```bash
# Memory Bank drift — if the bank exists
[ -d .memory-bank ] && bash ~/.claude/skills/memory-bank/scripts/mb-drift.sh .

# Conflict markers / whitespace errors in what is about to be committed
git diff --check --cached
git diff --check
```

If `drift_warnings > 0`, show the warnings to the user and ask whether to proceed. If `git diff --check` finds conflict markers or trailing-whitespace errors, stop and surface them — do not commit broken content.

## 1. Show staged changes

```bash
git status --short
git diff --cached --stat
git diff --cached
```

## 2. Scan the staged diff for forbidden patterns

Check for (in added lines only):

- Debug residue: `fmt.Println`, `console.log`, `debugger;`, `print(` (language-appropriate)
- `TODO` / `FIXME` / `HACK` markers in new code
- Commented-out code blocks
- Hardcoded secrets (use the grep shape from `/security-review`)
- Files that should not be committed: `.env`, `*.pem`, `*.key`, `credentials.json`

If any match appears, show the findings and ask whether to continue.

## 3. Draft the commit message

Conventional Commits format: `<type>(<scope>): <subject>`

- Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `perf`, `build`, `ci`, `style`
- Scope: optional, derive from most-changed top-level directory when non-trivial
- Subject: imperative, ≤72 chars, no trailing period

If `$ARGUMENTS` is provided, use it as the subject (or the full message, if it looks complete). Otherwise synthesize from the staged diff.

## 4. Show the final proposed message + file list → confirm

Print:

```
Proposed commit:
  <type>(<scope>): <subject>

  <body if any>

Files (N):
  M <file1>
  A <file2>
  D <file3>

Proceed? (y/N)
```

Default answer = No. Only proceed on explicit `y`.

## 5. Commit

```bash
git commit -m "<message>"
```

If a pre-commit hook fails, investigate and fix the underlying issue — do not bypass with `--no-verify`. After fixing, re-stage and create a new commit.

## 6. Confirm success

```bash
git log -1 --stat
git status --short
```
