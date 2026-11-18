# /mb recap — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `recap <sid>` — Reconstruct a full `progress.md` entry from `session/<sid>*.md` via one Haiku call, replacing that session's auto-capture stub idempotently. Missing session → exit non-zero, no writes; a real (non-stub) entry already present → refuse. `recapped` frontmatter makes a rerun a no-op

### recap <sid>

Reconstruct a full `progress.md` entry from a session file when a session ended on the
auto-capture stub instead of an explicit `/mb done`. One Haiku `claude -p` call renders the
entry from `session/<sid>*.md`; the auto-capture **stub block** is the only line replaced —
every other `progress.md` entry stays byte-for-byte intact (append-only discipline). Run
directly (no subagent):

```bash
bash "$SKILL_DIR/scripts/mb-recap.sh" "${ARGS_AFTER_RECAP[@]}"
```

Guarantees: missing session file → exit non-zero, **no writes**; a real (non-stub) entry already
present for that session → refuse with a hint, no writes; no `claude` on PATH → install hint,
no writes. Idempotent — `recapped: true` frontmatter on the session file makes a rerun a no-op.
Same anti-recursion env as the SessionEnd summarizer (`CLAUDECODE` unset, `MB_CAPTURE_SUBPROCESS=1`,
`--no-session-persistence --strict-mcp-config --no-chrome`). Show the result to the user.
