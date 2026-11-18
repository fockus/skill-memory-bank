# /mb config — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `config <init\|show\|validate\|path>` — Manage execution `pipeline.yaml` (spec §9). `init` copies bundled default into `<bank>/pipeline.yaml`; `show` prints resolved config; `validate` runs schema check; `path` prints absolute path of resolved file.

### config <subcommand>

Manage the project's execution `pipeline.yaml` (spec §9) — the declarative config consumed by `/mb work`. Defines roles → agents mapping, local workflow modes (`workflow.default` + `workflows.*`), per-item loops, severity gates, sprint context guard, review rubric, and SDD enforcement policy.

**Alias** for `/config` — dispatch to `commands/config.md` for the canonical doc.

**Subcommands:**

| Subcommand | Description |
|------------|-------------|
| `init [--force]` | Copy `references/pipeline.default.yaml` → `<bank>/pipeline.yaml`. Refuses overwrite without `--force`. |
| `show` | Print effective config (`<bank>/pipeline.yaml` if present, otherwise the bundled default). |
| `path` | Print absolute path of the effective config file. |
| `validate [yaml_file]` | Run `scripts/mb-pipeline-validate.sh` against the resolved config (no arg) or a given file. |

All subcommands accept a trailing `[mb_path]` arg pointing at an alternative bank.

**Behavior:**

1. Resolution chain: `<bank>/pipeline.yaml` → `references/pipeline.default.yaml`. The bundled default is always present and self-validates.
2. `init` writes a byte-for-byte copy of the default. Idempotency guard refuses without `--force`.
3. `validate` exits 0 if schema-clean, 1 with `[validate] <key>: <reason>` lines on stderr otherwise.

**Underlying:** `bash "$SKILL_DIR"/scripts/mb-pipeline.sh <subcommand> [args...]`.

**Why pipeline.yaml?** Different teams need different defaults — workflow modes, review tolerance, max review cycles, role-to-agent mapping, protected paths. Hard-coding these would lock the engine. `pipeline.yaml` makes them per-project, version-controlled, and reviewable.
