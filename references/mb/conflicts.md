# /mb conflicts — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `conflicts [--judge] [--threshold N]` — Surface memory entries with high lexical overlap **and** opposing/replacement assertions (en+ru markers) as conflict candidates — `$0` pass (token-set Jaccard > `N`, default 0.3) over `notes/` + `lessons.md` + recent `progress.md`, zero LLM calls. `--judge` confirms/rejects each pair via one Sonnet call and prints a suggested `[SUPERSEDED: YYYY-MM-DD -> <ref>]` marker. PRINT-ONLY — never writes to any bank file

### conflicts [--judge] [--threshold N]

Surface pairs of memory entries that both describe the same subject **and** carry an
opposing/replacement assertion — the typical "this fact was superseded but never marked" drift.
The default pass is **$0** (zero LLM calls): token-set Jaccard overlap (`> N`, default `0.3`)
across `notes/*.md` + `lessons.md` + recent `progress.md` entries, filtered to pairs where at
least one side contains a negation/replacement marker (`no longer | instead | replaced | moved to |
deprecated | вместо | больше не | заменили | устарело`, en+ru). Fewer than two entries → empty
output, exit 0. Run directly (no subagent):

```bash
bash "$SKILL_DIR/scripts/mb-conflicts.sh" "${ARGS_AFTER_CONFLICTS[@]}"
```

`--judge` adds one Sonnet `claude -p` call per candidate to confirm or reject the conflict, and for
confirmed pairs prints a suggested `[SUPERSEDED: YYYY-MM-DD -> <ref>]` marker line (format:
`references/metadata.md`). The judge is **PRINT-ONLY** — the command never writes to any bank file;
apply suggested markers yourself if you agree. No `claude` on PATH → hint on stderr, the `$0`
candidates are still printed, exit 0. Same anti-recursion env as the SessionEnd summarizer
(`CLAUDECODE` unset, `MB_CAPTURE_SUBPROCESS=1`, `--no-session-persistence --strict-mcp-config
--no-chrome`). Show the result to the user.
