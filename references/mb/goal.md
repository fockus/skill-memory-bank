# /mb goal — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `goal` — Scaffold `.memory-bank/goal.md` + `.memory-bank/project.md` from templates (copy-if-absent), then validate the goal with `scripts/mb-goal-validate.sh`. Phase-1 Dynamic Flow primitive (REQ-DF-001..005). See `commands/goal.md`

### goal

Scaffold and validate the durable Dynamic Flow goal artifacts. See `commands/goal.md` for the full spec.

**Arguments:** none (always acts on `<bank>/goal.md` + `<bank>/project.md`).

**Effect:**

- If `.memory-bank/goal.md` is absent → copy `templates/goal.md` to it. Never overwrites.
- If `.memory-bank/project.md` is absent → copy `templates/project.md` to it. Never overwrites.
- Validate the goal with `scripts/mb-goal-validate.sh`. Valid → `{"ok":true}`; invalid → concrete fix-hint per problem on stderr.

Run directly (no LLM needed — validation is deterministic):

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
. "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path "${BANK:-}")"
[ -f "$BANK/goal.md" ]    || cp "$SKILL_DIR/templates/goal.md"    "$BANK/goal.md"
[ -f "$BANK/project.md" ] || cp "$SKILL_DIR/templates/project.md" "$BANK/project.md"
bash "$SKILL_DIR/scripts/mb-goal-validate.sh" "$BANK/goal.md" "$BANK"
```

After scaffolding, fill in `## Description` + `## Acceptance criteria` + `progress_source` in `goal.md`, then re-run until it exits `0`.
