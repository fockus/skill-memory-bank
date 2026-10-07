# CLAUDE.md Template

Template used by `/mb init --full` to generate `CLAUDE.md`.
Variables in `{VARIABLE}` are filled through auto-detection. Keep the generated file short: only facts
Claude needs in every session. Engineering rules and the status-line rule come from the global
`~/.claude/CLAUDE.md` — do not copy them here.

---

## Project

**{PROJECT_NAME}** — {PROJECT_DESCRIPTION}

## Commands

```bash
{BUILD_CMD}    # build / install
{TEST_CMD}     # run tests
{LINT_CMD}     # lint + type-check
{RUN_CMD}      # run locally
```

## Stack & conventions

- {LANGUAGE} {LANGUAGE_VERSION}+ with {FRAMEWORKS}; package manager: {PACKAGE_MANAGER}
- {STACK_FACTS} <!-- 1–3 facts not derivable from code: runtime quirks, env setup, generated dirs -->
- Full stack, naming and code style: `.memory-bank/codebase/STACK.md`, `.memory-bank/codebase/CONVENTIONS.md`

## Architecture

{ARCHITECTURE_DETAILS}
<!-- generator: describe this project's layout — backend: layers and where they live (Clean Architecture);
     frontend: FSD slices in use. State facts about this codebase, not the general rule. -->

## Project rules

Engineering rules come from the global `~/.claude/CLAUDE.md` + `~/.claude/RULES.md` (plus `.memory-bank/RULES.md` when present); list only this project's overrides here.

{PROJECT_RULE_OVERRIDES}

## Memory Bank

- Size the task first — memory-bank skill § Task routing (`references/effort-tiers.md`); trivial and small tasks need no plan.
- `/mb work` runs when the task refers to an existing plan or spec in `.memory-bank/`; planned work: `/mb plan <type> <topic>` → `/mb work` → `/mb verify` → `/mb done`.
- Run `/mb verify` before `/mb done` when work followed a plan — it checks every DoD item against the code.
- Parallel sessions in one working tree: read `.memory-bank/COORDINATION.md` via `scripts/mb-coord.sh active` before stages and commits; scoped `git add` only.
- Key files: `status.md` (current state), `checklist.md` (active tasks), `roadmap.md` (priorities), `plans/` (stage plans), `progress.md` (append-only log).
- Code graph & search → memory-bank skill (`/mb graph`, `mb-graph.sh`; opt-in `/mb wiki`).
