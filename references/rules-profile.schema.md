# Rules Profile Schema

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
| `architecture` | string | yes | `clean`, `hexagonal`, `modular-monolith`, `microservices`, `ddd`, `fsd`, `mobile-udf`, `event-driven`, `custom` |
| `delivery` | string | yes | `tdd`, `contract-first`, `api-first`, `sdd`, `legacy-safe`, `exploratory` |
| `strictness` | string | no (default `warn`) | `advisory`, `warn`, `block` |
| `extras` | object | no | free-form keys; consumers ignore unknown keys |

Unknown top-level keys are rejected by `validate_profile`.

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
- `dry-kiss-yagni` — DRY/KISS/YAGNI baseline.
- `verification-before-completion` — claim "done" only after running the
  declared verification commands.
- `explicit-storage-choice` — storage mode (local/global/rules-only) is the
  user's choice; tooling never silently writes profiles or banks outside
  the explicitly chosen scope.

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

Invalid JSON (`json.JSONDecodeError`) fails closed: the resolver returns
the immutable baseline only and emits a warning to stderr.

## Resolved profile summary

`resolve_profile(...)` returns a `ResolvedProfile` that exposes:

- `role`, `stack`, `architecture`, `delivery`, `strictness` — final values
  after precedence merge.
- `sources: dict[str, str]` — for each dimension, the layer that set it
  (`"baseline"`, `"user"`, `"project"`, `"task"`).
- `immutable_rules: tuple[str, ...]` — fixed list of always-on rules.
- `prompt_summary: str` — compact multi-line text under 4 KB suitable for
  injecting into prompts. The summary is deterministic for the same input.

The 4 KB cap is enforced by tests (`test_rules_profile_schema.py`) so
preset authors keep guidance compact.
