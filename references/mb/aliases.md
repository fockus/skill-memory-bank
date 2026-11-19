# /mb aliases — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `start` — Extended session start — same per-file cap as `context`, `--full` to disable it
- `done` — End session (`actualize + note + progress`; rotates `status.md` via `mb-status-rotate.sh --apply`)

### Aliases for `/start`, `/done`, `/plan`

`/mb start`, `/mb done`, and `/mb plan` are aliases that dispatch to the canonical commands:

- `/mb start` → see `commands/start.md` (reads Memory Bank, suggests `/mb map` if `codebase/` empty)
- `/mb done` → see `commands/done.md` (MB Manager actualize + note + `.session-lock`)
- `/mb plan <type> <topic>` → see `commands/plan.md` (mb-plan.sh scaffold + fill + mb-plan-sync.sh)

Invoking `/mb start` = invoking `/start` — same scripts, same subagents, same outcome. Do not duplicate the logic here; read the primary command file and follow it.

> **Plan hierarchy reminder:** Phase → Sprint → Stage. See `references/templates.md` § *Plan decomposition* for size thresholds. The Russian legacy aliases for Phase, Sprint and Stage are allowed only in archived `plans/done/`.
