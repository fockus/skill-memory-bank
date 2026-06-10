# Memory Bank Skill

Long-term project memory through `.memory-bank/`, engineering rules, SDD specs, executable `/mb work` tasks, verification, review, and session persistence.

## Hard Rules

1. Resolve the active Memory Bank before project work.
   - Existing bank → print `[MEMORY BANK: ACTIVE]`.
   - No bank → print `[MEMORY BANK: ABSENT]`; do not initialize unless explicitly requested.
2. Read the project rules and Memory Bank context before implementation:
   - global rules: `rules/RULES.md` from this skill bundle;
   - project overrides: `<repo>/AGENTS.md`, `<repo>/RULES.md` or `<bank>/RULES.md` when present;
   - core context: `<bank>/status.md`, `checklist.md`, `roadmap.md`, `research.md` when present (the resolver also detects legacy-cased layouts).
3. New logic requires TDD: failing test first, then implementation, then verification.
4. Do not bypass an existing plan/spec. If work comes from Memory Bank, execute through `/mb work` or the equivalent scripts.

## Mandatory `/mb work` Gate

When a project has an active Memory Bank and the user says: implement, fix, continue, resume, next step, go by the plan, execute the spec, or similar:

1. Resolve workflow from `<bank>/pipeline.yaml` with `scripts/mb-workflow.sh`.
2. Resolve target/range with `scripts/mb-work-resolve.sh` and `scripts/mb-work-plan.sh`.
3. Treat `specs/<topic>/tasks.md` blocks marked `<!-- mb-task:N -->` as executable source of truth.
4. If using a wrapper plan, it must have `linked_spec` or `<!-- mb-stage:N -->` markers. If not, stop and fix the wrapper before coding.
5. Follow resolved steps exactly. For governed workflows this means: `implement → verify → review → judge → fix/backlog → done`.
6. Pass exact `model` and `thinking` from `pipeline.yaml`/JSON lines to subagents. Do not use fuzzy model names.
7. Do not claim completion until configured verification/review/judge gates are satisfied, or the user explicitly chooses a simpler workflow.

Manual inline implementation is only acceptable for trivial non-plan work or an explicit user request to skip `/mb work`; TDD and verification still apply.

## Common Workflows

| Intent | Command |
| --- | --- |
| Load context | `/mb start` or `scripts/mb-context.sh` |
| Create requirements/spec | `/mb discuss <topic>` → `/mb sdd <topic>` |
| Execute existing spec/plan | `/mb work <target> [--range N] [--workflow NAME]` |
| Simple execution override | `/mb work <target> --workflow simple` |
| Verify plan/spec alignment | `/mb verify` |
| Save session | `/mb done` |
| Validate pipeline | `/mb config validate` or `scripts/mb-pipeline-validate.sh` |
| Validate spec | `scripts/mb-spec-validate.sh <topic>` |
| Drift check | `scripts/mb-drift.sh <repo>` |

## Session Discipline

- Start: restore context and summarize current focus in 1–3 sentences.
- During work: update checklist/tasks immediately when a task is truly complete.
- Before completion: run the verification commands required by the current task/workflow.
- End: append progress, update status/checklist, and run `/mb done` when appropriate.

## Compatibility Notes

- `AGENTS.md` is shared across Pi, OpenCode, Codex, and other agents; project `AGENTS.md` can override global defaults.
- `CLAUDE.md` may be legacy in some repos. Prefer `AGENTS.md` when both exist unless project instructions say otherwise.
- Global skill installation does not imply project Memory Bank activation; only an existing/resolved bank does.
