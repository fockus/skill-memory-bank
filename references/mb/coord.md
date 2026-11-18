# /mb coord — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `coord <active\|append> [args]` — Read/write the cross-session coordination board without loading it. `active [--tail N]` prints active FREEZEs, HANDOVERs with no ACK, the last N entries (default 3) and a totals line — a few hundred bytes instead of a 200 KB append-only file; `append --type <FREEZE\|LIFT\|HANDOVER\|ACK\|STATUS> --title <t> [--body-file <f>]` writes a canonically tagged entry through a locked atomic append. No board → `no board`, exit 0.

### coord <active|append> [args]

Read the cross-session coordination board without paying for its history. Run directly — no subagent:

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-coord.sh $ARGS_AFTER_COORD
```

`active [--tail N] [--mb <path>]` prints the three facts a session must act on — active FREEZEs,
HANDOVERs with no ACK, the last `N` entries verbatim (default 3) — plus a
`board: <entries>, <bytes> — full file: <path>` line. `COORDINATION.md` is append-only and reaches
hundreds of KB; open it in full only when investigating history. No board → one `no board` line, exit 0.

`append --type <FREEZE|LIFT|HANDOVER|ACK|STATUS> --title <t> [--body-file <f>] [--mb <path>]` writes
`## <TYPE> · YYYY-MM-DD · <title>` through a locked atomic append, so the entry is parseable by
`active`. A LIFT cancels an earlier FREEZE with the same title/scope; an ACK cancels an earlier
HANDOVER. Untagged legacy headings read as STATUS, except a body with a **bolded** `FREEZE REQUEST` /
`⚠️ FREEZE` marker, which is reported as a `[legacy]` freeze. Grammar: `references/coordination.md`.
