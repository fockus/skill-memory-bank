# /mb flow — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `flow <route>` — Explicitly select a route (skip auto-classification); the deterministic route-floor + firewall STILL apply. Escape-hatch. See `commands/flow.md` (REQ-DF-025)

### flow <route>

**Alias** for `/flow` — dispatch to `commands/flow.md` for the canonical workflow. The explicit override escape-hatch (REQ-DF-025), mirroring `/mb work --workflow`: select `<route>` directly and **skip auto-classification** (no LLM step). The deterministic route-floor (REQ-DF-022) and the firewall (REQ-DF-040) STILL apply — an override below the floor is raised to the floor, never honored blindly.

```bash
# <route> ∈ bugfix | code-change | arch | migration | research
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
bash "$SKILL_DIR/scripts/mb-flow-route.sh" --route <route>
```

Auto-routing (`/mb analyze-task`) is the default; reach for `/mb flow <route>` only to deliberately pin a route.
