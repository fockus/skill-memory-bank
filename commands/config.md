---
description: "Manages the execution pipeline.yaml — init / show / validate / path. Use when setting up or checking /mb work roles, models, workflows or gates — «настрой пайплайн»."
allowed-tools: [Bash, Read]
---

# /mb config <subcommand>

Manage the project's execution `pipeline.yaml` — the declarative config consumed by `/mb work`. Defines roles → agents mapping, local workflow modes (`workflow.default` + `workflows.*`), per-item loops, severity gates, sprint context guard, review rubric, and SDD enforcement policy.

## Skill bundle root

Every bundled helper below runs through the skill bundle root, never a bare `scripts/…` path (the
working directory is the user's project, where `scripts/` is absent or belongs to someone else):

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
```

## Why pipeline.yaml?

`/mb work <target>` resolves a named workflow from `pipeline.yaml`, defaulting to `medium` (`implement → verify → done`, verifier once at plan end — **review is off by default**). Complexity presets: `simple` < `medium` < `complex` < `governed` (old names `execution` / `governed-execution` stay as aliases). Opt into review/judge per run (`--review`/`--judge`) or persist with `review.enabled: true` / `<stage>.enabled: true`; projects can also select `full` (the whole chain), `full-cycle`, planning-only, review-only, or custom loops with different `max_cycles`. Different teams need different defaults — review severity tolerance, max review cycles, role-to-agent mapping, protected-paths policy. Hard-coding these would lock the engine. `pipeline.yaml` makes them per-project and version-controlled.

## Resolution

Effective config = first match wins:

1. `<bank>/pipeline.yaml` (project override, if present)
2. `references/pipeline.default.yaml` (shipped default)

The shipped default is always present and self-validates. Projects do not need to run `init` until they want to override something.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `init [--force]` | Copy bundled default into `<bank>/pipeline.yaml`. Refuses if file exists unless `--force` is given. |
| `init --host <claude-code\|codex\|pi\|opencode\|cursor> [--preset simple\|medium\|complex\|governed] [--cost premium\|optimal\|economy] [--model-premium X] [--model-mid Y] [--force]` | Write `<bank>/pipeline.yaml` from the default with `workflow.default`, `cost` and that host's `model_profiles` entry set (comments kept, result validated). |
| `show [--host H] [--cost C] [--preset P] [--verify V]` | Print the effective matrix: workflow steps + verify cadence, then per role agent → model → model_source → discipline, plus host notes and the project quality settings with their source (`mb-profile.sh quality`). |
| `show --raw` | Print the effective config file as-is (project override → default fallback). |
| `path` | Print absolute path to the effective config file. |
| `validate [yaml_file]` | Structural schema check (spec §9). Without an argument: validate the resolved file. With a file argument: validate that file directly. |

All subcommands accept an optional trailing `[mb_path]` to point at an alternative bank location.

## Behavior

- `init` writes a byte-for-byte copy of `references/pipeline.default.yaml` into `<bank>/pipeline.yaml`. Idempotency guard refuses overwrite without `--force`.
- `init --host` model ids: `claude-code`, `codex`, `cursor` use the profiles shipped in the default
  (`--model-premium` / `--model-mid` replace either slot). `pi` and `opencode` work with any
  provider, so nothing is shipped: premium is the host's current model (Pi: `defaultProvider/defaultModel`
  from `.pi/settings.json`, else `~/.pi/agent/settings.json`; OpenCode: `model` from `opencode.json`,
  global → `$OPENCODE_CONFIG` → project, never `small_model`) or `--model-premium`; mid always comes
  from `--model-mid <provider/id>` (Pi: same provider as premium). A missing or malformed value
  exits 2 and writes nothing — no placeholder ever lands in `pipeline.yaml`.
- `init --host` on an existing `pipeline.yaml` without `--force` **refuses** (exit 1) and prints the
  keys it would have set, so you add them by hand; your edits are never merged into or rewritten.
  `--force` rewrites the file from the template (edits lost).
- OpenCode and Cursor read the subagent model statically from the installed agent files:
  `init --host opencode|cursor` re-renders them with the tier models (`model:` frontmatter), and
  adapter install reads the project `pipeline.yaml` too. Codex `.toml` roles get `model = "<id>"`.
- `show` resolves through `mb-workflow.sh` (steps, cadence, host detection) and
  `scripts/mb_work_models.py` (models), the same code `/mb work` uses. Explicit
  `roles.<role>.model` shows as `role`, tier picks as `profile`, nothing as `inherit`.
- `show --raw` cats the resolved file as-is (preserves comments).
- `path` prints `realpath` of the resolved file.
- `validate` runs `scripts/mb-pipeline-validate.sh` against the resolved (or explicit) path. Exit 0 means schema-clean; exit 1 dumps `[validate] <key>: <reason>` lines to stderr.

## Underlying scripts

```bash
bash "$SKILL_DIR"/scripts/mb-pipeline.sh init [--force] [mb_path]
bash "$SKILL_DIR"/scripts/mb-pipeline.sh init --host H [--preset P] [--cost C] \
     [--model-premium X] [--model-mid Y] [--force] [mb_path]
bash "$SKILL_DIR"/scripts/mb-pipeline.sh matrix [--host H] [--cost C] [--preset P] [--verify V] [mb_path]   # /mb config show
bash "$SKILL_DIR"/scripts/mb-pipeline.sh show              [mb_path]   # /mb config show --raw
bash "$SKILL_DIR"/scripts/mb-pipeline.sh path              [mb_path]
bash "$SKILL_DIR"/scripts/mb-pipeline.sh validate [file]   [mb_path]
```

## Schema (high level)

See spec §9 for the full breakdown. Required top-level keys:

- `version` — currently `1`
- `roles` — `<name>: { agent: <agent-id>, fallback?: <agent-id>, override_if_skill_present?: ... }`
- `workflow` — default workflow name and aliases for `/mb work --workflow`
- `workflows` — named local workflow modes; each has `steps` and optional `loop` (includes the `full` preset = the whole chain)
- `review` — opt-in single-reviewer block (`enabled: false` default) carrying `severity_gate` / `max_cycles`; per-stage `discuss`/`sdd`/`plan`/`judge` blocks expose the same `enabled` toggle for composing the pipeline
- `stage_pipeline` — backward-compatible per-item execution pipeline for older orchestrators (review-free default: `implement → verify → done`)
- `budget` — token budget guards (`warn_at_percent`, `stop_at_percent`)
- `protected_paths` — glob list refused by `/mb work` without `--allow-protected`
- `sprint_context_guard` — `soft_warn_tokens` / `hard_stop_tokens` (190k default hard stop)
- `review_rubric` — `logic / code_rules / security / scalability / tests` checklists for the reviewer agent
- `sdd` — EARS enforcement & `covers_requirements_policy` (warn / block / off)

## Typical flow

```
User: /mb config init --host codex --preset complex --cost optimal
→ writes .memory-bank/pipeline.yaml with the codex profile (gpt-6-astra / gpt-6.1-sol)

User: /mb config show
→ prints steps + cadence and the role → agent → model → source matrix

User: edits .memory-bank/pipeline.yaml — sets workflow.default=complex,
      adds a full-cycle mode, or changes workflows.governed.loop.max_cycles.

User: /mb config validate
→ exit 0 (schema-clean)

User: /mb work auth-refactor --auto
→ engine reads .memory-bank/pipeline.yaml, resolves workflow.default, and runs that loop.
```

## Out of scope

- Does not edit an existing `pipeline.yaml` for you (use a real editor; `init --force` rewrites it).
- Does not warn on schema-valid-but-strange values (e.g. zero `max_cycles` would fail validation; `max_cycles: 99` would not).
- Does not migrate older versions — there is only `version: 1` today.

## Related

- `/mb work <target>` — consumes the resolved pipeline and selected workflow.
- `/mb verify` — can be run standalone or as a workflow step.
- `references/pipeline.default.yaml` — bundled defaults.
- `scripts/mb-pipeline-validate.sh` — standalone schema check (also called by `/mb doctor`).
