# /mb pipeline <subcommand>

Manage **multiple named execution pipelines** in one project. Where `/mb config`
manages a single `<bank>/pipeline.yaml`, `/mb pipeline` lets a project keep
several pipelines side by side — each with its own model routing and workflow —
and select between them per run or automatically per code-agent host.

## Why named pipelines?

One repository is often driven by more than one agent (Claude Code, pi, opencode,
codex) and more than one regime (a fast solo loop vs. a governed
review-ensemble). Hard-coding a single `pipeline.yaml` forces one compromise.
Named pipelines let you:

- keep a `claude-fast` pipeline and a `pi-governed` pipeline in the same repo;
- give each its own models (`roles.*.model`) and workflow (`workflow.default`);
- bind a pipeline to a host so `/mb work` picks it **automatically** under that
  agent — no flag needed;
- pick one explicitly for a single run with `--pipeline NAME`.

## Storage & metadata

Each named pipeline is a **full, standalone** pipeline file — same schema and
validator as `pipeline.yaml`:

```
.memory-bank/
├── pipeline.yaml            # legacy / fallback default (back-compat)
└── pipelines/
    ├── claude-fast.yaml      # pipeline_name: claude-fast · agents: [claude-code]
    ├── pi-governed.yaml      # pipeline_name: pi-governed · agents: [pi, opencode]
    └── solo.yaml             # pipeline_name: solo · default: true
```

Three **optional** top-level metadata keys distinguish a named pipeline:

| Key | Meaning |
|-----|---------|
| `pipeline_name` | Display name (defaults to the filename stem). |
| `default: true` | The project default when nothing else selects a pipeline. |
| `agents: [<host>…]` | Code-agent hosts this pipeline binds to (`claude-code`, `cursor`, `codex`, `opencode`, `pi`, `windsurf`, `cline`, `kilo`). |

Absent metadata stays valid — a plain copy of `pipeline.default.yaml` is a legal
named pipeline.

## Subcommands

```bash
bash scripts/mb-pipeline.sh <subcommand> [args...] [mb_path]
```

| Subcommand | Behavior |
|------------|----------|
| `list` | Print a table (name · default · agents · file), marking the active selection (`*`) and the detected host. Graceful when no named pipelines exist. |
| `new NAME [--agent a,b] [--from NAME\|default] [--default] [--force]` | Scaffold `<bank>/pipelines/NAME.yaml` from the bundled default (or another named pipeline via `--from`), injecting fresh `pipeline_name`/`default`/`agents`. Rejects unsafe names and refuses to overwrite without `--force`. |
| `use NAME` | Set the project default by writing `pipeline=NAME` into `<bank>/.mb-config` (non-destructive — does not edit pipeline files). |
| `show [--pipeline NAME]` | Print the resolved pipeline body. |
| `path [--pipeline NAME]` | Print the absolute path of the resolved pipeline. |
| `validate [--pipeline NAME]` | Schema-check a single resolved/named pipeline. |
| `validate --all` | Schema-check **every** named pipeline and report cross-file conflicts: duplicate `pipeline_name`, more than one `default: true`, or an agent bound to multiple pipelines. |

## Selection ladder

`path` / `show` and `/mb work` resolve **which** pipeline to use through this
ladder (first match wins):

1. `--pipeline NAME` flag, or the `$MB_PIPELINE` environment variable.
2. **Host binding** — the pipeline whose `agents:` list includes the detected
   code-agent host (`mb_detect_host`: `$MB_PIPELINE_HOST` → `$MB_AGENT` → env
   signatures like `CLAUDECODE`). Among multiple host matches, a `default: true`
   one wins.
3. `<bank>/.mb-config` `pipeline=NAME` (set by `use`).
4. The pipeline marked `default: true`.
5. Legacy `<bank>/pipeline.yaml`.
6. Bundled `references/pipeline.default.yaml`.

If no `pipelines/` directory exists, resolution is byte-for-byte identical to the
pre-existing single-`pipeline.yaml` behavior.

## Threading into `/mb work`

`/mb work` consumers (`mb-work-*.sh`, `mb-workflow.sh`, `mb-reviewer-resolve.sh`)
each resolve their config via `mb-pipeline.sh path`, which honors `$MB_PIPELINE`
and host binding. To run a whole work loop under a chosen pipeline, resolve once
and prefix each consumer call with `MB_PIPELINE=NAME` (host binding needs no env
— it is detected per call). See `commands/work.md` § *Selecting a named pipeline*.

## Examples

```bash
# Create two pipelines bound to different hosts
/mb pipeline new claude-fast --agent claude-code
/mb pipeline new pi-governed --agent pi,opencode --from default

# A repo-wide default for hosts with no binding
/mb pipeline new solo --default

# Inspect & validate
/mb pipeline list
/mb pipeline validate --all

# Run /mb work under a specific pipeline (else auto-by-host)
/mb work my-feature --pipeline pi-governed --range 1
/mb work my-feature            # under Claude Code → claude-fast (host binding)
```

## Related

- `/mb config` — manage the single `<bank>/pipeline.yaml` (one-pipeline projects).
- `/mb work --pipeline NAME` — execute under a named pipeline.
- `scripts/mb-pipeline-validate.sh` — the shared schema validator.
