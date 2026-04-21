---
description: Load current project context from memory-bank
allowed-tools: [Bash, Read, Task]
---

Canonical session-start command. `/mb start` is an alias that dispatches here.

## 1. Check whether Memory Bank is active

```bash
[ -d ./.memory-bank ] && echo "[MEMORY BANK: ACTIVE]" || echo "[MEMORY BANK: INACTIVE]"
```

If inactive: tell the user and suggest `/mb init` (`--full` for stack auto-detect, `--minimal` for structure only). Stop.

## 2. Collect context through the official script

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-context.sh
```

The script reads `STATUS.md`, `plan.md`, `checklist.md`, `RESEARCH.md`, lists active plans (`plans/*.md` not in `done/`), folds per-document summaries from `.memory-bank/codebase/*.md` if populated, and prints the latest note.

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
- Current phase / where the project is (from `STATUS.md`)
- What the user is working on right now (from active plan + checklist)
- Next step per `plan.md`

Mention metrics (tests passing, coverage) if they appear in `STATUS.md` and have moved recently.

## 6. For deeper actualization

If the user needs MB Manager-level synthesis rather than a raw dump, invoke the MB Manager subagent with `action: context` — its prompt lives at `~/.claude/skills/memory-bank/agents/mb-manager.md`. Pass the output of `mb-context.sh` as input context.
