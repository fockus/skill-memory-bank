# Command File — Canonical Template

Shape rules for every file in `commands/` (except `mb.md`, which has a custom router structure).

Read before creating or editing a command so the description, tool whitelist, and argument hint all load into the host UI (Claude Code, OpenCode, Cursor).

---

## Frontmatter contract

Every command starts with a YAML frontmatter block. No commentary, no Markdown heading before it — the file begins with `---` on line 1.

```yaml
---
description: <one-line sentence, imperative mood, ≤80 chars>
allowed-tools: [<list of Claude tools this command actually uses>]
argument-hint: <optional — shown in the slash-command UI when the user starts typing>
---
```

### Keys

| Key              | Required | Notes                                                                                                                                 |
|------------------|----------|---------------------------------------------------------------------------------------------------------------------------------------|
| `description`    | yes      | Imperative voice. Drives the `/`-menu tooltip. One line. No trailing period.                                                          |
| `allowed-tools`  | yes      | Whitelist the tools the body actually invokes. Keep tight — do not list tools the command never calls.                                |
| `argument-hint`  | no       | Shown after the command name in the UI. Good: `<type> <topic>`, `<module-path>`, `[version]`. Skip for commands that take no arguments. |

### Anti-patterns to avoid

- `# ~/.claude/commands/<name>.md` as the first line — kills frontmatter parsing.
- `---` followed by `## description:` as a Markdown heading — treated as heading, not YAML.
- No frontmatter at all — works by luck, no UI surface.
- Listing `[Read, Write, Edit, Bash, Grep, Glob, Task]` as the default — over-privileges and hides intent.

---

## Body structure

After the closing `---`, the body is free-form Markdown. Recommended shape:

1. `# <Command>: $ARGUMENTS` — heading showing what the user invoked.
2. **Optional** Step 0 — guard empty `$ARGUMENTS` (stop and ask) if the command requires a topic.
3. **Optional** Step 1 — stack detection via `bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh` if the command is stack-specific (security review, migrations, observability, test, api-contract).
4. Numbered sections for each phase of the command.
5. **Optional** final step — memory-bank integration (append to `progress.md`, add note, save report to `reports/`).

Destructive operations (`gh pr create`, `git commit`, `DROP TABLE`, etc.) must pause for explicit `y/N` confirmation. Default answer = No.

---

## Example 1 — minimal command (≤20 lines)

```markdown
---
description: Reload the current context after a reset or compaction
allowed-tools: [Bash, Read]
---

1. Read `~/.claude/CLAUDE.md`
2. If `./.memory-bank/` exists, read `status.md`, `roadmap.md`, `checklist.md`, and `.memory-bank/codebase/*.md` summaries (1 line per doc via `head`)
3. Run `git diff` and `git diff --staged` — show what is currently in progress
4. Run `git log --oneline -5` — show the latest commits
5. Summarize in 3-5 sentences: what is done, what is in progress, and what comes next
```

Key traits: one-line description, 2-tool whitelist, 5-step body, no arguments → no `argument-hint`.

---

## Example 2 — complex command with stack detection

```markdown
---
description: Run tests, analyze failures, and propose fixes
allowed-tools: [Bash, Read, Glob, Grep]
argument-hint: [test-filter]
---

# Test: $ARGUMENTS

## 0. Stack detection

```bash
eval "$(bash ~/.claude/skills/memory-bank/scripts/mb-metrics.sh)"
# Exposes: stack, test_cmd, lint_cmd, src_count
```

If `stack=unknown`, ask the user for the test runner before proceeding.

## 1. Run tests

Use `$test_cmd` — optionally narrowed by `$ARGUMENTS` (test file, test name, or marker).

## 2. Analyze

- If pass: show summary and coverage; stop here.
- If fail: read failing test source + code under test, classify as code bug vs. outdated test, propose a concrete fix, ask `y/N` before writing it.

## 3. Memory Bank

If `./.memory-bank/` exists and tests failed with a pattern worth remembering, append to `lessons.md` using the `references/templates.md` format.
```

Key traits: stack-aware via `mb-metrics.sh` with `unknown` fallback, `argument-hint` for UI, explicit confirm before mutating code, memory-bank integration at the end.

---

## Memory Bank integration snippets

**Reading context (session-start commands):**

```markdown
Read `.memory-bank/status.md`, `roadmap.md`, `checklist.md`, `research.md`. If `.memory-bank/codebase/` is populated, run `bash ~/.claude/skills/memory-bank/scripts/mb-context.sh` and include the folded codebase summaries; otherwise suggest `/mb map all` (default answer: skip).
```

**Writing reports (long-running analysis commands):**

```markdown
If `./.memory-bank/` exists, save the report to `./.memory-bank/reports/YYYY-MM-DD_<type>_<short-description>.md` following the format in `references/templates.md`.
```

**Recording notes (discovery commands):**

```markdown
If the session surfaced a reusable pattern, run `bash ~/.claude/skills/memory-bank/scripts/mb-note.sh "<topic>"` and fill the returned file per the `## Note` template in `references/templates.md`.
```

---

## Alias commands

A command can dispatch to another by keeping a thin body that points the reader at the primary:

```markdown
---
description: Alias for /plan — delegates to the primary planning command
allowed-tools: [Bash, Read, Write, Edit]
---

This is an alias. The canonical planning logic lives in `commands/plan.md` and runs the same scripts (`mb-plan.sh` + `mb-plan-sync.sh`). Invoke `/plan <type> <topic>` or `/mb plan <type> <topic>` — both produce the same result.
```

Used when one command is a slash-entrypoint and another is a `/mb`-subcommand with identical behavior.

---

## Validation checklist (before committing a command change)

- [ ] File starts with `^---$` on line 1.
- [ ] Exactly 2 `---` fences (opening + closing).
- [ ] `description:` line present and ≤80 chars.
- [ ] `allowed-tools:` lists only tools the body actually calls.
- [ ] `argument-hint:` present if the body uses `$ARGUMENTS`.
- [ ] Destructive operations have `y/N` confirmation (default = No).
- [ ] Stack-specific commands call `mb-metrics.sh` and have an `unknown`-stack fallback.
- [ ] `bash scripts/mb-drift.sh .` returns `drift_warnings=0`.
