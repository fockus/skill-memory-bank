---
description: "Reviews staged changes and creates a commit. Use when the user says «закоммить», «сделай коммит», commit this."
allowed-tools: [Bash, Read]
argument-hint: "[message-override]"
---

## Skill bundle root

Every bundled helper below runs through the skill bundle root, never a bare `scripts/…` path (the
working directory is the user's project, where `scripts/` is absent or belongs to someone else):

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
```

## 0. Pre-flight safety checks

```bash
# Memory Bank drift — if the bank exists
[ -d .memory-bank ] && bash "$SKILL_DIR"/scripts/mb-drift.sh .

# Conflict markers / whitespace errors in what is about to be committed
git diff --check --cached
git diff --check

# Cross-session coordination board — if parallel sessions share this tree
[ -f .memory-bank/COORDINATION.md ] && bash "$SKILL_DIR"/scripts/mb-coord.sh active
```

If `drift_warnings > 0`, show the warnings to the user and ask whether to proceed. If `git diff --check` finds conflict markers or trailing-whitespace errors, stop and surface them — do not commit broken content.

If the coordination board exists, read its recent entries before committing: verify no FREEZE covers your files and the agreed commit ordering allows you to commit now; stage a **scoped file list** (never `git add -A` — the tree contains the other session's uncommitted diff), and append a COMMIT entry (hash + file scope) to the board after committing. Protocol: `references/coordination.md`.

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

## 2b. Full test suite

During work only targeted tests ran (AGR-071); the commit is where the full suite runs once:

```bash
bash "$SKILL_DIR"/scripts/mb-test-run.sh --dir . --out json
```

Skip it only when the full suite already ran green on this same tree state in this session (no edits
since) — then show that earlier output instead of re-running. `tests_pass == false` → show the failures
and ask whether to continue; `null` → say the tests were not measured.

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
