# /mb plan — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `plan <type> <topic>` — Create a plan

### plan

**Alias** for `/plan` — dispatch to `commands/plan.md`. The canonical planning command lives there: mb-plan.sh scaffold → fill with `<!-- mb-stage:N -->` markers + SMART DoD + TDD per stage → mb-plan-sync.sh to reconcile with `checklist.md` + `roadmap.md`.

Allowed `type` values: `feature`, `fix`, `refactor`, `experiment`. If `type` is missing, ask the user.
