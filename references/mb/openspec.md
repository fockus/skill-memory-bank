# /mb openspec — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `openspec <import\|list\|status\|sync> [args]` — One-way import adapter: OpenSpec `changes/<id>/` → MB spec triple `specs/<topic>/` via `scripts/mb-openspec.sh` (no `openspec` CLI dep). `import <dir> [--as <topic>] [--normalize]` writes the triple + drift frontmatter; `list [--all]`/`status <topic>` show imported/drifted/not-imported; `sync [<topic>]` re-imports only on hash drift. Opt-in `--normalize` fills LLM text slots (EARS/scenario/Covers), cached + fail-open. See `### openspec` below.

### openspec

`/mb openspec <import|list|status|sync>` dispatches to `scripts/mb-openspec.sh` — a one-way OpenSpec → Memory Bank import adapter. OpenSpec change files are parsed directly (no `openspec` CLI dependency); the OpenSpec tree is never written to. Every write is asserted under `.memory-bank/`.

- `import <change_dir> [--as <topic>] [--normalize]` — parse an OpenSpec `changes/<id>/` (proposal + delta specs + tasks) and write the MB spec triple under `specs/<topic>/` (topic default = change-id slug). Records `openspec_source`/`openspec_hash` frontmatter for drift detection. Re-import reuses `REQ-NNN` by requirement name, preserves `/mb work` task check-state by text, and appends orphaned tasks to `backlog.md` (never silently dropped).
- `list [--all] [--openspec <root>]` — enumerate `openspec/changes/*` with status `imported` / `drifted` / `not-imported` (archived changes hidden unless `--all`).
- `status <topic>` — drift status of one imported topic.
- `sync [<topic>] [--normalize]` — re-import only topics whose source hash drifted; a hash match is a pure no-op (no write). No topic → sync every imported topic.
- `--normalize` (opt-in) fills LLM text slots (prose-SHALL → EARS, missing scenario, `Covers`), cached by source-requirement hash so an unchanged requirement never regenerates, and fail-open (LLM unavailable → deterministic fallback + warn). Omit for the byte-deterministic path.

Run directly: `bash "$SKILL_DIR"/scripts/mb-openspec.sh <sub> ...`. Spec: `.memory-bank/specs/openspec-adapter/`.

