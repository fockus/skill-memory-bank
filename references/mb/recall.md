# /mb recall — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `recall <query>` — Lexical recall over session-memory log + notes (ripgrep over `session/` + `notes/`) — session-memory subsystem

### recall <query>

Lexical recall over the **session-memory** log + notes (distinct from semantic `search`). Part of the
session-memory subsystem that auto-logs each session to `.memory-bank/session/` (Stop/SessionEnd/SessionStart
hooks). Run directly (no subagent):

```bash
bash "$SKILL_DIR"/hooks/mb-recall.sh $ARGS_AFTER_RECALL
```

Searches `.memory-bank/session/` + `.memory-bank/notes/` via ripgrep (fallback grep), prints `file:line`
+ context. Off-switch for capture: `MB_SESSION_CAPTURE=off`. Show results to the user.

**Rebuild `_recent.md`** (after pruning empty sessions, or to re-curate the rolling window from existing
session files — `_recent.md` is otherwise only updated incrementally on SessionEnd):

```bash
bash "$SKILL_DIR/scripts/mb-session-recent-rebuild.sh" "$BANK"   # newest MB_RECENT_KEEP (default 5) with a ## Summary
```
