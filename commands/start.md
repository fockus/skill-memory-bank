---
description: Load current project context from memory-bank
allowed-tools: [Bash, Read, Task]
---

Canonical session-start command. `/mb start` is an alias that dispatches here.

## Pre-flight: detect v1 layout

Before loading context, check whether the project is still on v1 Memory Bank naming. Run:

```bash
ls .memory-bank/ 2>/dev/null | grep -E '^(STATUS|BACKLOG|RESEARCH|plan)\.md$'
```

If any of `STATUS.md / BACKLOG.md / RESEARCH.md / plan.md` appear (and the corresponding lowercase variant — `status.md / backlog.md / research.md / roadmap.md` — is NOT present), the project is on v1 and must be migrated.

Tell the user exactly:

> "Detected v1 Memory Bank layout (uppercase STATUS.md / BACKLOG.md / plan.md). v2 requires lowercase names. Run:
>
> ```
> bash ~/.claude/skills/memory-bank/scripts/mb-migrate-v2.sh --dry-run
> ```
>
> to preview, then `--apply` to execute. Backup is created automatically."

Do NOT proceed with context loading until migration is done, UNLESS the user explicitly says "read v1 anyway" — in which case fall back to reading the old names.

## 1. Check whether Memory Bank is active

```bash
[ -d ./.memory-bank ] && echo "[MEMORY BANK: ACTIVE]" || echo "[MEMORY BANK: INACTIVE]"
```

If inactive: tell the user and suggest `/mb init` (`--full` for stack auto-detect, `--minimal` for structure only). Stop.

## 2. Collect context through the official script

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-context.sh
```

The script reads `status.md`, `roadmap.md`, `checklist.md`, `research.md`, lists active plans (`plans/*.md` not in `done/`), folds per-document summaries from `.memory-bank/codebase/*.md` if populated, and prints the latest note.

For deep-context mode (full contents of codebase docs instead of summaries):

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-context.sh --deep
```

## 3. Read the active plan in full (if any)

If the `Active plans` section in the output lists a file, read it end-to-end before summarizing.

## 4. Check `codebase/` bootstrap state

If `.memory-bank/codebase/` is missing or contains no `*.md` files, surface a suggestion:

```
.memory-bank/codebase/ is empty. Run /mb map all to populate it (subagent: mb-codebase-mapper, sonnet). Default: skip.
```

Do **not** auto-invoke the mapper — the user owns the decision.

## 5. Summarize focus

Produce a 1-3 sentence summary covering:
- Current phase / where the project is (from `status.md`)
- What the user is working on right now (from active plan + checklist)
- Next step per `roadmap.md`

Mention metrics (tests passing, coverage) if they appear in `status.md` and have moved recently.

## 6. For deeper actualization

If the user needs MB Manager-level synthesis rather than a raw dump, invoke the MB Manager subagent with `action: context` — its prompt lives at `~/.claude/skills/memory-bank/agents/mb-manager.md`. Pass the output of `mb-context.sh` as input context.
