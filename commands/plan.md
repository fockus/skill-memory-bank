---
description: Create a detailed work plan with DoD and save it in memory-bank
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
argument-hint: <type> <topic>
---

# Plan: $ARGUMENTS

Canonical planning command. `/mb plan` is an alias that dispatches here.

## 0. Validate arguments

Parse `$ARGUMENTS` into `<type> <topic>`. Allowed `type`: `feature`, `fix`, `refactor`, `experiment`. If `type` is missing or not in the allowed set, stop and ask the user. If `topic` is empty, stop and ask.

## 1. Preparation

Read before you start:

1. `~/.claude/CLAUDE.md` — global rules
2. `./.memory-bank/plan.md` — current priorities (if present)
3. `./.memory-bank/checklist.md` — current tasks (if present)
4. `./.memory-bank/lessons.md` — known anti-patterns (if present)
5. `./.memory-bank/codebase/*.md` — stack / architecture / conventions / concerns summaries (if populated)

Study the codebase in the context of the topic. Find and read the files relevant to `"$ARGUMENTS"`.

## 2. Scaffold the plan file

Use the scaffolding script — it creates the file with `<!-- mb-stage:N -->` markers that `mb-plan-sync.sh` relies on later:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>"
# Prints the created path, for example:
# .memory-bank/plans/2026-04-21_refactor_<topic>.md
```

## 3. Fill in the plan

Open the created file and fill each section. Required structure:

- **Context** — problem, expected result, related files
- **Stages** — each wrapped with `<!-- mb-stage:N -->` markers (do not remove them), with:
  - Clear title
  - *What to do* — concrete actions
  - *Testing (TDD — tests BEFORE implementation)* — unit / integration / e2e per applicability
  - *DoD (SMART)* — specific, measurable, achievable, relevant, time-bound checkboxes. Every DoD item must answer «how do we verify?». Include TDD, lint, SOLID/DRY/KISS adherence, architectural direction.
  - *Code rules* — one-line reference to the principles that apply
- **Risks and mitigation** — table with Risk / Probability / Mitigation
- **Gate** — overall success criterion

Stages must be atomic, ordered by dependency, and small enough to pick up independently.

If `lessons.md` has entries relevant to this topic, incorporate them into the stages.

## 4. Synchronize with checklist and plan.md

After filling the plan, run:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan-sync.sh <plan-file-path>
```

The script is idempotent and:
- Adds missing `## Stage N: <name>` sections to `checklist.md` with `⬜` items per DoD
- Refreshes the `<!-- mb-active-plan -->` block in `plan.md`
- Reports `added=N` so you see what changed

Re-run `mb-plan-sync.sh` while iterating on the plan — it will reconcile new stages without touching old ones.

## 5. Update Memory Bank core files

1. `plan.md` — already updated by the sync script; add a 1-2 sentence focus line if the direction shifted
2. `STATUS.md` — move relevant phase into "In progress"
3. `notes/` — optional: create `YYYY-MM-DD_HH-MM_plan-<topic>.md` with a 5-10 line summary if the plan is non-trivial

## 6. Next step

Tell the user:
- Path to the plan file
- Number of stages created
- First stage to execute
- Reminder: after work, `/verify` (or `/mb verify`) before `/done`
