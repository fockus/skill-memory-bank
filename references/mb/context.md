# /mb context — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- (empty) or `context` — Collect project context. Each core file is capped at `context_max_bytes` (default 12 KB, `.mb-config` / `MB_CONTEXT_MAX_BYTES`); `--full` prints them whole
- `search <query>` — Search information in the memory bank
- `note <topic>` — Create a note
- `tasks` — Show unfinished tasks
- (unrecognized) — Search by `$ARGUMENTS`

### context / search / note / tasks

**Soft v1-layout detection.** Before invoking the subagent for `context` (or `(empty)`), run the v1-layout probe from `commands/start.md` (Pre-flight section). If v1 files are found without v2 counterparts, surface a one-line warning to the user:

```
WARN: v1 Memory Bank layout detected. Run `bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-migrate-v2.sh --dry-run` to preview the rename, then `--apply`. Context can still be assembled from v1 names during the 2-version backward-compat window.
```

Continue with context loading (do not hard-stop — the scripts fall back to v1 names while the window is open). For `search`, `note`, and `tasks` the warning is optional; the subagent itself handles v1 files.

For these subcommands, run the MB Manager subagent:

```
Agent(
  subagent_type="mb-manager",
  description="MB Manager: <action>",
  prompt="action: <action>

<task description and current-session context>"
)
```

Concrete actions:

- **context** / **(empty)**: `action: context` — also delegated to `/start` for consistent behavior
- **search ****: **`action: search <query>` where `query` is the remainder of `$ARGUMENTS` after `search`
- **note ****: **`action: note <topic>` + pass what was done in the current session
- **tasks**: `action: tasks`
