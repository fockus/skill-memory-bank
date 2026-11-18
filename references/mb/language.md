# /mb language — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `language <code> [--comments <code>] \| off \| show` — Per-project response / code-comment language (`en ru es pt zh`), overriding the global install choice. Writes a managed block at the top of the project's `AGENTS.md` and `CLAUDE.md`; `off` removes it

### language <code> [--comments <code>] | off | show

Per-project language. The global choice comes from `install.sh --language` / `--comments-language`;
this overrides it for one project, for every agent: the block goes at the top of the project's
`AGENTS.md` (Codex, OpenCode, Pi, Cursor) and `CLAUDE.md` (Claude Code), created if missing.

```bash
python3 "$SKILL_DIR"/scripts/mb-language.py set ru --comments en   # respond in Russian, comments in English
python3 "$SKILL_DIR"/scripts/mb-language.py off                    # back to the global choice
python3 "$SKILL_DIR"/scripts/mb-language.py show
```

Report the files it printed. The block takes effect in the next session (instructions load at start).
