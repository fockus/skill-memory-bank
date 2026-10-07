---
description: "Creates a detailed work plan with DoD and saves it in memory-bank. Use when multi-stage work needs planning — «составь план», «распланируй задачу»."
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
argument-hint: <type> <topic>
---

# Plan: $ARGUMENTS

Canonical planning command. `/mb plan` is an alias that dispatches here.

> **Storage note.** Resolve the active bank path through `mb_resolve_path` (in `scripts/_lib.sh`). The plan file ends up at `<resolved-bank>/plans/<YYYY-MM-DD>_<type>_<topic>.md` regardless of whether the bank is local, registered global storage, or legacy `.claude-workspace`. If `[MEMORY BANK: ABSENT]` (rules-only mode), refuse to plan and tell the user to run `/mb init` first — but do **not** auto-initialize.

## Skill bundle root

Every bundled helper below runs through the skill bundle root, never a bare `scripts/…` path (the
working directory is the user's project, where `scripts/` is absent or belongs to someone else):

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
```

## 0. Validate arguments

Parse `$ARGUMENTS` into `<type> <topic>`. Allowed `type`: `feature`, `fix`, `refactor`, `experiment`. If `type` is missing or not in the allowed set, stop and ask the user. If `topic` is empty, stop and ask.

> **Hierarchy reminder:** Phase → Sprint → Stage. See `references/templates.md` § *Plan decomposition* for sizing rules. Cyrillic «Этап / Спринт / Фаза» — legacy alias; the scaffold script will soft-warn if you use them in `<topic>`.

## 1. Preparation

Read before you start:

1. `~/.claude/CLAUDE.md` — global rules
2. `$SKILL_DIR/references/templates.md` — the "Plan decomposition — Phase → Sprint → Stage" section (what a stage is, when to add one)
3. `./RULES.MD` (project-level, if present) — project-specific decomposition rules
4. `./.memory-bank/roadmap.md` — current priorities (if present)
5. `./.memory-bank/checklist.md` — current tasks (if present)
6. `./.memory-bank/lessons.md` — known anti-patterns (if present)
7. `./.memory-bank/codebase/*.md` — stack / architecture / conventions / concerns summaries (if populated)

Study the codebase in the context of the topic. Find and read the files relevant to `"$ARGUMENTS"`.

## 1.5. Decompose — Phase / Sprint / Stage

A stage exists to mark a boundary, not to cap size. Add a new stage only when one of these holds:

- **dependency boundary** — the next part needs the previous one finished and in place;
- **layer or owner change** — e.g. domain → infrastructure, or a different role agent takes over;
- **risky checkpoint** — a point where you want to stop and confirm before going further (a migration, a public contract);
- **parallel chunk** — a piece whose `Files:` are disjoint from the other stages, so it can run in its own wave.

Otherwise keep the work in one stage. A single-stage plan is valid and is the usual shape for
small/standard work (`references/effort-tiers.md`); splitting without a boundary only adds hand-offs
and checks. There is no file, test or time limit per stage and no minimum stage count.
Plan coarse; decompose as needed — ADaPT: an item that turns out too big is split during `/mb work`,
only that item (`references/adapt.md`).

| Shape of the work | Target structure | Plan file(s) |
|-------------------|------------------|--------------|
| One coherent change, one session | **Plain plan** (no Phase/Sprint) | 1 file, usually 1 stage |
| Several boundaries, several days | **One Sprint** = one plan file | 1 file, roughly up to ~7 stages as a guideline |
| ≥ 2 Sprints with dependencies | **Phase** roadmap + one plan file per Sprint | 1 roadmap + N Sprint plan files |

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

Use the scaffolding script — it creates the file with one `<!-- mb-stage:1 -->` stage (markers are what `mb-plan-sync.sh` relies on later); add more stages only at the boundaries from section 1.5:

```bash
bash "$SKILL_DIR"/scripts/mb-plan.sh <type> "<topic>"
# Prints the created path, for example:
# .memory-bank/plans/2026-04-21_refactor_<topic>.md
```

### SDD-lite flags (optional)

When the topic has a pre-written EARS-validated context document under `.memory-bank/context/`, the scaffold can link it automatically:

```bash
# Auto-detect: looks for .memory-bank/context/<sanitized_topic>.md
bash "$SKILL_DIR"/scripts/mb-plan.sh <type> "<topic>"

# Explicit context path (any location)
bash "$SKILL_DIR"/scripts/mb-plan.sh <type> "<topic>" --context path/to/context.md

# Strict mode: require context AND pass EARS validation (mb-ears-validate.sh exit 0)
bash "$SKILL_DIR"/scripts/mb-plan.sh <type> "<topic>" --sdd
```

When a context file is resolved (auto-detected or explicit), the scaffold injects a `## Linked context` section right after Context with a Markdown link. Use `--sdd` for spec-driven work where requirements must be EARS-validated before any planning happens — the script fails fast otherwise.

## 3. Fill in the plan

Open the created file and fill each section. Required structure:

- **Context** — problem, expected result, related files
- **Stages** — each wrapped with `<!-- mb-stage:N -->` markers (do not remove them), with:
  - Clear title
  - *Files:* — the files the stage edits; `/mb work` computes parallel waves from these lines
  - *What to do* — concrete actions
  - *Testing (TDD — tests BEFORE implementation)* and *DoD (SMART)* — for the plan as a whole; give a
    stage its own only when it has its own verifiable boundary. Every DoD item answers «how do we verify?».
  - *Code rules* — one-line reference to the principles that apply
- **Risks and mitigation** — table with Risk / Probability / Mitigation
- **Gate** — overall success criterion (**mandatory** for a Sprint-level plan; single, measurable)

Order stages by dependency. Verification runs once at the end of the plan by default (`/mb work`,
AGR-075), so a stage does not need its own independent check.

**Sanity check before proceeding:** every stage boundary has a reason from section 1.5, and the whole
Sprint fits one session's context — if not, revisit section 1.5.

If `lessons.md` has entries relevant to this topic, incorporate them into the stages.

## 4. Synchronize with checklist and roadmap.md

After filling the plan, run:

```bash
bash "$SKILL_DIR"/scripts/mb-plan-sync.sh <plan-file-path>
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

## Plan as execution wrapper

A plan file can serve as a thin **sprint slice** over an existing spec, rather than
the canonical decomposition itself. Declare the link in the plan's YAML frontmatter:

```yaml
---
linked_spec: specs/inventory-sync
tasks: 1-3
---
```

When `/mb work` resolves `<target>`:
- It detects `linked_spec` in the frontmatter and loads work-items from
  `<linked_spec>/tasks.md` (parsed via `mb_work_items.py`).
- The optional `tasks:` range (e.g., `1-3`) limits execution to that task subset —
  useful for sprint slicing a large spec across multiple plan files.
- The plan basename is used only for **traceability** (the `plan` field in JSON output
  and in `mb-traceability-gen.sh` output) — not for work-item resolution.

Spec tasks (`specs/<topic>/tasks.md`) are the **canonical decomposition**.
Plan files act as sprint slices OR standalone tactical execution wrappers when
no spec exists. Do not duplicate task definitions in both locations.

## 6. Next step

Tell the user:
- Path to the plan file
- Number of stages created
- First stage to execute
- Reminder: after work, `/verify` (or `/mb verify`) before `/done`
