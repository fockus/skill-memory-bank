---
description: Create a detailed work plan with DoD and save it in memory-bank
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
argument-hint: <type> <topic>
---

# Plan: $ARGUMENTS

Canonical planning command. `/mb plan` is an alias that dispatches here.

## 0. Validate arguments

Parse `$ARGUMENTS` into `<type> <topic>`. Allowed `type`: `feature`, `fix`, `refactor`, `experiment`. If `type` is missing or not in the allowed set, stop and ask the user. If `topic` is empty, stop and ask.

> **Hierarchy reminder:** Phase → Sprint → Stage. See `references/templates.md` § *Plan decomposition* for sizing rules. Cyrillic «Этап / Спринт / Фаза» — legacy alias; the scaffold script will soft-warn if you use them in `<topic>`.

## 1. Preparation

Read before you start:

1. `~/.claude/CLAUDE.md` — global rules
2. `~/.claude/skills/memory-bank/references/templates.md` — **MUST read the "Plan decomposition — Phase → Sprint → Stage" section**
3. `./RULES.MD` (project-level, if present) — project-specific decomposition rules + 200k-per-Sprint hard limit
4. `./.memory-bank/roadmap.md` — current priorities (if present)
5. `./.memory-bank/checklist.md` — current tasks (if present)
6. `./.memory-bank/lessons.md` — known anti-patterns (if present)
7. `./.memory-bank/codebase/*.md` — stack / architecture / conventions / concerns summaries (if populated)

Study the codebase in the context of the topic. Find and read the files relevant to `"$ARGUMENTS"`.

## 1.5. Decompose by size — Phase / Sprint / Stage

Before scaffolding, estimate the scope:

| Estimate | Target structure | Plan file(s) |
|----------|------------------|--------------|
| ≤ 3 stages, one session | **Plain plan** (no Phase/Sprint) | 1 file, 3-5 `<!-- mb-stage:N -->` markers |
| 3-7 stages, several days | **One Sprint** = one plan file | 1 file, 5-7 stages |
| ≥ 2 Sprints with dependencies | **Phase** roadmap + one plan file per Sprint | 1 roadmap + N Sprint plan files |

**🔴 Hard check — 200k tokens per Sprint:**
- > 5 large files (>500 lines) to read, OR
- > 15 new/modified files, OR
- > 3000 lines of new code, OR
- > 60 new tests, OR
- cross-layer refactor touching core + service + infra in one pass

→ **Split into 2+ Sprints along an architectural boundary**. State the split explicitly to the user before scaffolding. Two clean Sprints beat one truncated Sprint.

### Phase-level workflow

If the work expands into a **Phase** (≥2 Sprints with dependencies):

1. **Name Sprints up front** — list them with the architectural boundary that separates each, before any scaffolding.
2. **Scaffold one plan file per Sprint** — call `mb-plan.sh` multiple times with suffixed topics, e.g. `<topic>_sprint1`, `<topic>_sprint2`. Each Sprint file gets its own `## Gate`.
3. **Add a Phase entry to `roadmap.md`** — a dedicated section like `## Phase: <topic>` with:
   - One-line goal
   - Sprint list (ordered, with status: `⬜ planned` / `🟡 in progress` / `✅ done`)
   - Cross-Sprint dependencies (which Sprint must finish before another starts)
   - Phase-level Gate (the criterion that closes the Phase, broader than any individual Sprint Gate)
4. **Run `mb-plan-sync.sh` once per Sprint file** so each Sprint gets its own `<!-- mb-active-plan -->` block; only the currently-active Sprint should be marked active in `roadmap.md`.

## 2. Scaffold the plan file

Use the scaffolding script — it creates the file with `<!-- mb-stage:N -->` markers that `mb-plan-sync.sh` relies on later:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>"
# Prints the created path, for example:
# .memory-bank/plans/2026-04-21_refactor_<topic>.md
```

### SDD-lite flags (optional)

When the topic has a pre-written EARS-validated context document under `.memory-bank/context/`, the scaffold can link it automatically:

```bash
# Auto-detect: looks for .memory-bank/context/<sanitized_topic>.md
bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>"

# Explicit context path (any location)
bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>" --context path/to/context.md

# Strict mode: require context AND pass EARS validation (mb-ears-validate.sh exit 0)
bash ~/.claude/skills/memory-bank/scripts/mb-plan.sh <type> "<topic>" --sdd
```

When a context file is resolved (auto-detected or explicit), the scaffold injects a `## Linked context` section right after Context with a Markdown link. Use `--sdd` for spec-driven work where requirements must be EARS-validated before any planning happens — the script fails fast otherwise.

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
- **Gate** — overall success criterion (**mandatory** for a Sprint-level plan; single, measurable)

Stages must be atomic (1-5 files, ~5-15 tests, 5-30 min each), ordered by dependency, and small enough to pick up independently.

**Sprint-level sanity check before proceeding:**
- 3-7 stages total
- ≤ 15 files touched across the Sprint
- ≤ 60 tests total
- All Stages reachable in one 200k context — if not, revisit section 1.5 and split.

If `lessons.md` has entries relevant to this topic, incorporate them into the stages.

## 4. Synchronize with checklist and roadmap.md

After filling the plan, run:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan-sync.sh <plan-file-path>
```

The script is idempotent and:
- Adds missing `## Stage N: <name>` sections to `checklist.md` with `⬜` items per DoD
- Refreshes the `<!-- mb-active-plan -->` block in `roadmap.md`
- Reports `added=N` so you see what changed

Re-run `mb-plan-sync.sh` while iterating on the plan — it will reconcile new stages without touching old ones.

## 5. Update Memory Bank core files

1. `roadmap.md` — already updated by the sync script; add a 1-2 sentence focus line if the direction shifted
2. `status.md` — move relevant phase into "In progress"
3. `notes/` — optional: create `YYYY-MM-DD_HH-MM_plan-<topic>.md` with a 5-10 line summary if the plan is non-trivial

## 6. Next step

Tell the user:
- Path to the plan file
- Number of stages created
- First stage to execute
- Reminder: after work, `/verify` (or `/mb verify`) before `/done`
