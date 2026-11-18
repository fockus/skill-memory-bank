# /mb openspec — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `openspec <import\|list\|status\|sync\|export> [args]` — OpenSpec ↔ MB round-trip via `scripts/mb-openspec.sh` (no `openspec` CLI dep): `import` a change into `specs/<topic>/`, three-way `sync [--take openspec|bank]`, dry-run `export [--write] [--allow-delete]`, `export --new` to publish a bank spec as a new change; `/mb work <change-id>` runs it in place. See `### openspec

`/mb openspec <import|list|status|sync|export>` dispatches to `scripts/mb-openspec.sh`, a round-trip adapter between OpenSpec `changes/<id>/` and the MB spec triple `specs/<topic>/`. OpenSpec files are parsed directly (no `openspec` CLI dependency). Import and sync write only `.memory-bank/`; OpenSpec is written only by `export --write`.

- `import <change_dir> [--as <topic>] [--normalize]` — parse proposal + delta specs + tasks into the triple (topic default = change-id slug). Records `openspec_source`/`openspec_hash` frontmatter and a sync baseline. Re-import reuses `REQ-NNN` by requirement name, keeps task check-state by text, and appends orphaned tasks to `backlog.md`.
- `list [--all] [--openspec <root>]` — `openspec/changes/*` with status `imported` / `drifted` / `not-imported` (archived hidden unless `--all`).
- `status <topic>` — drift status of one imported topic.
- `sync [<topic>] [--take openspec|bank] [--normalize]` — per-unit three-way merge into the bank. A hash match is a no-op. Both sides changed the same unit → conflict, exit 1, nothing written; resolve by editing one side or `--take openspec|bank`. Without a topic: every imported topic, all-or-nothing.
- `export <topic> [--write] [--allow-delete]` — diff of bank changes against the OpenSpec change; only `--write` touches OpenSpec, refused if OpenSpec changed since the last sync; `--allow-delete` also removes requirements/scenarios deleted in the bank.
- `export <topic> --new [--id <id>] [--cap <cap>] [--openspec <root>] [--write]` — publish a bank-native spec as a new OpenSpec change.
- `--normalize` (opt-in) fills LLM text slots (EARS, missing scenario, `Covers`), cached by source-requirement hash, fail-open.

**In-place flow.** `/mb work <change-id|openspec/changes/<id>>` imports (new) or syncs (existing) through the resolver, stops on a conflict, works on the bank triple, and at the end shows the dry-run `export` diff and asks before `export --write`.

Run directly: `bash "$SKILL_DIR"/scripts/mb-openspec.sh <sub> ...`. Spec: `.memory-bank/specs/openspec-adapter/`.
