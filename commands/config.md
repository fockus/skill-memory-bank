---
description: Manage execution pipeline.yaml — init / show / validate / path
allowed-tools: [Bash, Read]
---

# /mb config <subcommand>

Manage the project's execution `pipeline.yaml` — the declarative config consumed by `/mb work` (Phase 3 Sprint 2). Defines roles → agents mapping, per-stage review loop, severity gates, sprint context guard, review rubric, and SDD enforcement policy.

## Why pipeline.yaml?

`/mb work <target>` runs each stage through a configurable `implement → review → verify` loop. Different teams need different defaults — review severity tolerance, max review cycles, role-to-agent mapping, protected-paths policy. Hard-coding these would lock the engine. `pipeline.yaml` makes them per-project and version-controlled.

## Resolution

Effective config = first match wins:

1. `<bank>/pipeline.yaml` (project override, if present)
2. `references/pipeline.default.yaml` (shipped default)

The shipped default is always present and self-validates. Projects do not need to run `init` until they want to override something.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `init [--force]` | Copy bundled default into `<bank>/pipeline.yaml`. Refuses if file exists unless `--force` is given. |
| `show` | Print effective config (project override → default fallback). |
| `path` | Print absolute path to the effective config file. |
| `validate [yaml_file]` | Structural schema check (spec §9). Without an argument: validate the resolved file. With a file argument: validate that file directly. |

All subcommands accept an optional trailing `[mb_path]` to point at an alternative bank location.

## Behavior

- `init` writes a byte-for-byte copy of `references/pipeline.default.yaml` into `<bank>/pipeline.yaml`. Idempotency guard refuses overwrite without `--force`.
- `show` cats the resolved file as-is (preserves comments).
- `path` prints `realpath` of the resolved file.
- `validate` runs `scripts/mb-pipeline-validate.sh` against the resolved (or explicit) path. Exit 0 means schema-clean; exit 1 dumps `[validate] <key>: <reason>` lines to stderr.

## Underlying scripts

```bash
bash scripts/mb-pipeline.sh init [--force] [mb_path]
bash scripts/mb-pipeline.sh show              [mb_path]
bash scripts/mb-pipeline.sh path              [mb_path]
bash scripts/mb-pipeline.sh validate [file]   [mb_path]
```

## Schema (high level)

See spec §9 for the full breakdown. Required top-level keys:

- `version` — currently `1`
- `roles` — `<name>: { agent: <agent-id>, fallback?: <agent-id>, override_if_skill_present?: ... }`
- `stage_pipeline` — list of `implement` / `review` / `verify` step definitions
- `budget` — token budget guards (`warn_at_percent`, `stop_at_percent`)
- `protected_paths` — glob list refused by `/mb work` without `--allow-protected`
- `sprint_context_guard` — `soft_warn_tokens` / `hard_stop_tokens` (190k default hard stop)
- `review_rubric` — `logic / code_rules / security / scalability / tests` checklists for the reviewer agent
- `sdd` — EARS enforcement & `covers_requirements_policy` (warn / block / off)

## Typical flow

```
User: /mb config show
→ prints shipped default

User: /mb config init
→ copies default into .memory-bank/pipeline.yaml

User: edits .memory-bank/pipeline.yaml — bumps minor severity_gate
      from 3 to 5 for this project's tolerance.

User: /mb config validate
→ exit 0 (schema-clean)

User: /mb work auth-refactor --auto
→ engine reads .memory-bank/pipeline.yaml; review-loop uses minor=5.
```

## Out of scope

- Does not edit `pipeline.yaml` for you (use a real editor).
- Does not warn on schema-valid-but-strange values (e.g. zero `max_cycles` would fail validation; `max_cycles: 99` would not).
- Does not migrate older versions — there is only `version: 1` today.

## Related

- `/mb work <target>` — Phase 3 Sprint 2; consumes the resolved pipeline.
- `/mb verify` — uses the same `verify` step defined in `stage_pipeline`.
- `references/pipeline.default.yaml` — bundled defaults.
- `scripts/mb-pipeline-validate.sh` — standalone schema check (also called by `/mb doctor`).
