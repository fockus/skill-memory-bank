# Rules Profile Schema

## Contents

- [File format](#file-format)
- [Top-level fields](#top-level-fields)
- [Key rules selection](#key-rules-selection)
- [Quality settings](#quality-settings)
- [Immutable safety baseline (non-overridable)](#immutable-safety-baseline-non-overridable)
- [Precedence (resolution order, strongest last)](#precedence-resolution-order-strongest-last)
- [Validation errors](#validation-errors)
- [Resolved profile summary](#resolved-profile-summary)

Canonical specification for Memory Bank rule profiles (Sprint 3 of the
`global-storage` Phase). Profiles personalize the configurable layer of
Memory Bank rules without weakening the immutable safety baseline.

## File format

- **Canonical machine format: JSON**. The runtime parser reads `*.json`
  through Python stdlib (`json` module). No runtime YAML dependency is
  added.
- YAML examples appear in documentation only. They must be converted to
  JSON by `mb-profile.sh` (or any equivalent tool) before being stored.
- File name on disk:
  - User scope: `<agent-config>/memory-bank/rules-profile.json` (e.g.
    `~/.claude/memory-bank/rules-profile.json`).
  - Project scope: `<resolved-mb>/rules-profile.json` (e.g.
    `./.memory-bank/rules-profile.json` or
    `~/.claude/memory-bank/projects/<id>/.memory-bank/rules-profile.json`).

## Top-level fields

```json
{
  "schema_version": 1,
  "scope": "user",
  "role": "backend",
  "stack": "go",
  "architecture": "microservices",
  "delivery": "contract-first",
  "strictness": "warn",
  "extras": {
    "api": "protobuf"
  }
}
```

| Field | Type | Required | Allowed values |
|-------|------|----------|----------------|
| `schema_version` | int | yes | currently `1` |
| `scope` | string | yes | `user`, `project` |
| `role` | string | yes | `backend`, `frontend`, `mobile` |
| `stack` | string | yes | `go`, `python`, `javascript`, `typescript`, `java`, `generic` |
| `architecture` | string or list | no (default `["clean", "fsd", "ddd"]`) | `clean`, `hexagonal`, `modular-monolith`, `microservices`, `ddd`, `fsd`, `mobile-udf`, `event-driven`, or `{"custom": "<text>"}`; a list combines them (see [Quality settings](#quality-settings)) |
| `delivery` | string | yes | `tdd`, `contract-first`, `api-first`, `sdd`, `legacy-safe`, `exploratory` |
| `strictness` | string | no (default `warn`) | `advisory`, `warn`, `block` |
| `extras` | object | no | free-form keys; consumers ignore unknown keys |
| `key_rules` | object | no | see [Key rules selection](#key-rules-selection) |
| `quality` | object | no | see [Quality settings](#quality-settings) |
| `discipline` | string | no (default `auto`) | `auto`, `strict`, `calm` — see [Quality settings](#quality-settings) |

Unknown top-level keys are rejected by `validate_profile`.

## Key rules selection

`key_rules` selects which one-line rules from the catalog `rules/key-rules.json`
are active. Every bucket is optional:

```json
{
  "key_rules": {
    "enabled": ["comments-why-only"],
    "disabled": ["contract-first"],
    "custom": ["Prefer composition over inheritance"]
  }
}
```

| Bucket | Type | Meaning |
|--------|------|---------|
| `enabled` | list of catalog ids | turn on rules that are off by default (or that the user scope disabled) |
| `disabled` | list of catalog ids | turn off default-on rules; **locked** rules (`fail-fast`, `no-placeholders`, `root-cause`, `effort-tiers`) cannot be disabled |
| `custom` | list of strings | the user's own rules, one non-empty line each, ≤200 chars |

Resolution (`mb-profile.sh key-rules [--mb=<path>] [--agent=<a>] [--json]`,
Python `memory_bank_skill.key_rules.resolve_key_rules`): start from the catalog
defaults, apply user `enabled` then `disabled`, then project `enabled` then
`disabled` on top; locked rules are always included; the result keeps catalog
order. `custom` = user custom followed by project custom. The resolver reads
only `key_rules`, `quality.principles` and `discipline`, so a profile holding just
those fields is enough.

The principle rules `solid`, `dry`, `kiss`, `yagni` are on by default and can be
turned off (AGR-077), but **only** through `quality.principles.<id>: on|off` — that
field is their single source of truth. Their ids in `key_rules.enabled/disabled` are
rejected (`principle_in_quality`), so the two fields can never disagree;
`memory_bank_skill.key_rules.profile_layer` folds `quality.principles` into the
key-rules layer once, for every consumer. `mb-rules.sh enable|disable <principle>`
writes `quality.principles`.

The catalog rows with a `source` render from the profile settings, not from
`key_rules` (one place per setting, AGR-076): `architecture` (one line per selected
architecture — the preset's `one_liner` from `references/rules-presets/architecture/`,
`custom` → `Architecture: <text>`), `tdd` (`quality.tdd`: `off` → no line, `small+` →
the `variants["small+"]` wording), `testing-trophy` (`quality.testing_trophy`) and
`coverage` (only with `quality.coverage.enabled`, thresholds from the profile).
Their ids — and the former architecture toggles `clean-architecture`, `fsd`,
`ddd-folders`, `mobile-udf`, `backend-macro` — are rejected in any `key_rules` bucket
(`profile_setting`, the message names the `mb-rules.sh set` command).
`mb-rules.sh enable|disable tdd|testing-trophy|coverage` write the `quality` field;
`memory_bank_skill.key_rules.resolve_effective` is the full resolver (buckets, then
the settings).

## Quality settings

Project quality settings live in the same profile (AGR-076): user scope, then the
project scope on top, **per leaf key** (`quality.coverage.core` from the project
does not reset `quality.coverage.overall` from the user). `architecture` is one
value: a project list replaces the user list whole.

```json
{
  "architecture": ["modular-monolith", {"custom": "ports for every adapter"}],
  "quality": {
    "tdd": "small+",
    "testing_trophy": "on",
    "coverage": {"enabled": false, "overall": 85, "core": 95, "infra": 70},
    "principles": {"solid": "on", "dry": "on", "kiss": "off", "yagni": "on"}
  },
  "discipline": "auto"
}
```

| Key | Values | Default |
|-----|--------|---------|
| `quality.tdd` | `on`, `off`, `small+` (TDD from the small effort tier up) | `small+` |
| `quality.testing_trophy` | `on`, `off` | `on` |
| `quality.coverage.enabled` | `true`, `false` | `false` |
| `quality.coverage.overall` / `core` / `infra` | integer 0..100 | `85` / `95` / `70` |
| `quality.principles.solid` / `dry` / `kiss` / `yagni` | `on`, `off` | `on` |
| `architecture` | name, `{"custom": "<one line ≤200 chars>"}`, or a non-empty list of both | `["clean", "fsd", "ddd"]` |
| `discipline` | `auto`, `strict`, `calm` | `auto` |

`discipline: strict` makes `mb-rules.sh render|sync` add the catalog `strict_lines`
(Iron Law essence of `agents/mb-discipline-strict.md`) to the Key rules block in
place of the calm `targeted-verification` line. `auto` renders calm: the host's
main model is not known at render time. `/mb work` picks strict per item from
`pipeline.yaml: discipline.strict_models`.

Resolution: `mb-profile.sh quality [--mb=<path>] [--agent=<a>] [--user=<p>]
[--project=<p>] [--json]`, Python `memory_bank_skill.quality.resolve_quality`.
Text output is one `key = value (source)` line per setting; `--json` prints
`{quality, architecture: {names, custom}, delivery, discipline, sources}` with
`sources` keyed by dotted path (`default` | `user` | `project`). Exit 2 on an
invalid quality field.

Writer: `mb-rules.sh set <key> <value> [--scope=user|project]` — keys `architecture
<name[,name…][,custom:<text>]>`, `tdd`, `trophy`, `coverage off|<overall>/<core>/<infra>`,
`principle <id> on|off`, `discipline` (see `commands/rules.md`).

`mb-rules.sh sync --scope=project` also writes the settings, human-readable, between
`<!-- mb-project-rules:start -->` and `<!-- mb-project-rules:end -->` on top of the
project `RULES.md` (`<repo>/RULES.md`, else `<bank>/RULES.md`): architecture(s) with
the preset rules and their severity, principles, TDD, Trophy, coverage thresholds.
Text outside the block is never touched; the file is created only by
`mb-rules.sh init --scope=project`.

## Immutable safety baseline (non-overridable)

These rules apply regardless of profile or task instruction. A profile that
attempts to disable any of them is rejected at validation time:

- `no-placeholders` — no `TODO`, `...`, or pseudocode in production code.
- `protected-files` — `.env`, `ci/`, Docker/K8s/Terraform changes require
  explicit user request.
- `destructive-confirm` — destructive actions (force-push, hard-reset, mass
  delete) require explicit confirmation.
- `fail-fast` — uncertain implementation → stop and propose a short plan
  instead of guessing.
- `verification-before-completion` — claim "done" only after running the
  declared verification commands.
- `explicit-storage-choice` — storage mode (local/global/rules-only) is the
  user's choice; tooling never silently writes profiles or banks outside
  the explicitly chosen scope.

DRY/KISS/YAGNI (and SOLID) are not part of the baseline: they are on by default and
switchable one by one through `quality.principles` (AGR-077).

A profile may *strengthen* the baseline (e.g. set `strictness=block` for a
configurable rule) but never *weaken* it.

## Precedence (resolution order, strongest last)

```
built-in configurable defaults
  > user global profile (<agent-config>/memory-bank/rules-profile.json)
  > project Memory Bank profile (<resolved-mb>/rules-profile.json)
  > task instruction (this run only; cannot weaken the immutable baseline)
+ immutable safety baseline (always wins)
```

- When no Memory Bank exists, the user global profile is the only
  configurable source plus the immutable baseline.
- Project profile fully overrides user profile for every configurable
  dimension it sets. Dimensions it omits inherit from the user profile.
- Task instruction can adjust `strictness` for a single run only and
  cannot disable any immutable baseline rule.

## Validation errors

`validate_profile(data)` returns a list of `ValidationError` objects.
Empty list means the profile is valid. Each error carries a `field` and a
human-readable `message`. Examples:

- `field="role", message="unknown role 'devops' (allowed: backend, frontend, mobile)"`
- `field="schema_version", message="unsupported schema_version 99 (latest: 1)"`
- `field="baseline.no-placeholders", message="immutable rule cannot be disabled"`

`key_rules` errors lead their message with a reason code:
`not_an_object`, `unknown_key`, `not_a_list`, `unknown_rule` (names the id),
`locked_rule` (e.g. `field="key_rules.disabled.root-cause", message="locked_rule: locked rule 'root-cause' cannot be disabled"`),
`custom_invalid`, `principle_in_quality`, `profile_setting`. Quality fields add `unknown_architecture`
(name outside the list, or an empty list), `custom_invalid` (`custom` architecture
without its text), `coverage_out_of_range` (percentage outside 0..100),
`invalid_value` (wrong value or type) and `unknown_key`.
`mb-profile.sh validate`, `key-rules` and `quality` exit 2 on any of them.

Invalid JSON (`json.JSONDecodeError`) fails closed: the resolver returns
the immutable baseline only and emits a warning to stderr.

## Resolved profile summary

`resolve_profile(...)` returns a `ResolvedProfile` that exposes:

- `role`, `stack`, `architecture`, `delivery`, `strictness` — final values
  after precedence merge (`architecture` flattened to a label, e.g.
  `clean+custom`, for single-value consumers; the full list comes from
  `resolve_quality`).
- `sources: dict[str, str]` — for each dimension, the layer that set it
  (`"baseline"`, `"user"`, `"project"`, `"task"`).
- `immutable_rules: tuple[str, ...]` — fixed list of always-on rules.
- `prompt_summary: str` — compact multi-line text under 4 KB suitable for
  injecting into prompts. The summary is deterministic for the same input.

The 4 KB cap is enforced by tests (`test_rules_profile_schema.py`) so
preset authors keep guidance compact.
