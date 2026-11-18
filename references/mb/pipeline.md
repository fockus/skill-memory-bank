# /mb pipeline — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `pipeline <list\|new\|use\|show\|path\|validate>` — Manage **multiple named pipelines** under `<bank>/pipelines/<name>.yaml` (different models + workflow per pipeline). `list` shows all + active; `new NAME [--agent a,b] [--from NAME] [--default]` scaffolds one; `use NAME` switches the default; `show`/`path`/`validate [--all]` inspect. Each can bind a code-agent host (`agents:`) for auto-selection by `/mb work`.

### pipeline <subcommand>

Manage **multiple named pipelines** in one project. Each `<bank>/pipelines/<name>.yaml` is a full, standalone pipeline (same schema and validator as `pipeline.yaml`) with its own model routing and workflow, plus optional metadata: `pipeline_name`, `default: true`, and `agents: [<host>…]` to bind it to a code-agent. `/mb work` then auto-selects per host (e.g. one pipeline under Claude Code, another under pi/opencode). See `commands/pipeline.md` for the canonical doc.

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `list` | Table of named pipelines (name · default · agents · file); marks the active one (`*`) and the detected host. |
| `new NAME [--agent a,b] [--from NAME\|default] [--default] [--force]` | Scaffold `<bank>/pipelines/NAME.yaml` from the bundled default (or another named pipeline), injecting fresh metadata. |
| `use NAME` | Switch the project default by writing `pipeline=NAME` to `<bank>/.mb-config` (non-destructive). |
| `show [NAME]` / `path [NAME]` | Print the resolved pipeline body / absolute path (with `--pipeline NAME` or via the selection ladder). |
| `validate [NAME \| --all]` | Schema-check one pipeline, or every named pipeline + cross-file conflicts (duplicate names, >1 default, an agent bound twice). |

**Selection ladder** (used by `path`/`show` and `/mb work`): `--pipeline NAME` / `$MB_PIPELINE` → host binding (`agents:`) → `.mb-config pipeline=NAME` → in-file `default: true` → legacy `<bank>/pipeline.yaml` → bundled default. All subcommands accept a trailing `[mb_path]`.

**Underlying:** `bash "$SKILL_DIR"/scripts/mb-pipeline.sh <list|new|use|show|path|validate> [args...]`.
