# /mb statusline — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `statusline [--force]` — Claude Code only. Install the context-window statusline (`% of context filled` + model · branch · project) by running `scripts/mb-statusline.py --install`, which patches `~/.claude/settings.json` (backup first, refuses to clobber an existing `statusLine` unless `--force`)
