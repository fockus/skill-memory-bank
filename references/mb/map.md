# /mb map — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `map [focus]` — Scan the codebase and write MD documents to `.memory-bank/codebase/`. Focus: `stack / arch / quality / concerns / all` (default: `all`)

### map [focus]

Scan the codebase and generate structured MD documents in `.memory-bank/codebase/`.

`focus` values (the first word after `map`):

- `stack` — only `STACK.md` (languages, runtime, integrations)
- `arch` — only `ARCHITECTURE.md` (layers, structure, entrypoints)
- `quality` — only `CONVENTIONS.md` (naming, style, testing)
- `concerns` — only `CONCERNS.md` (tech debt, risks)
- `all` (default, if omitted) — all 4 documents

Run the MB Codebase Mapper subagent:

```
Agent(
  subagent_type="mb-codebase-mapper",
  description="MB Codebase Mapper: focus=<focus>",
  prompt="focus: <stack|arch|quality|concerns|all>

Analyze the current project and write MD documents directly to `.memory-bank/codebase/`. Use `mb-metrics.sh` for stack detection, follow the ≤70-line templates, and return confirmation only."
)
```

**After completion:**

- New/updated Markdown docs live in `.memory-bank/codebase/{STACK,ARCHITECTURE,CONVENTIONS,CONCERNS}.md`
- `/mb context` now automatically shows a one-line summary for each doc
- `/mb context --deep` shows the full contents of codebase documents

Tell the user which documents were created/updated, which stack was detected, and suggest `/mb context --deep` for full context.
