# /mb analyze-task — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `analyze-task` — Auto-classify goal + git-diff scope into ONE route and write it into the `mb-flow` fence (default Dynamic Flow router). See `commands/analyze-task.md` (REQ-DF-020/022)

### analyze-task

**Alias** for `/analyze-task` — dispatch to `commands/analyze-task.md` for the canonical workflow. The **default** Dynamic Flow router (REQ-DF-020): read `goal.md` + `git diff --name-only`, classify ONE candidate route (`bugfix | code-change | arch | migration | research`), then call the resolver, which applies the deterministic route-floor (REQ-DF-022) and writes the resolved `route:` into the `<!-- mb-flow -->` fence in `status.md`.

```bash
# <pick> = the route you classified from goal.md + the diff scope.
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
bash "$SKILL_DIR/scripts/mb-flow-route.sh" --candidate <pick>
```

Report the **resolved** route from the JSON the resolver prints; if `floor_triggered` is `true`, name the `reasons` (the floor overrode your candidate on purpose). On a red phase-boundary `mb-flow-verify.sh` (diff-scope breach / unmet acceptance, REQ-DF-024) HALT and re-run `analyze-task`; on a mid-flight goal change rewrite `goal.md` and re-run (REQ-DF-023).
