---
description: "Manage rule profiles and stack presets — personalize the configurable rules layer without weakening the immutable safety baseline"
allowed-tools: [Bash, Read, Write, Edit]
---

# /profile — Rule profiles & stack presets

The `/profile` command manages Memory Bank rule profiles: configurable per-role, per-stack, per-architecture, and per-delivery-method rules that sit on top of the immutable safety baseline.

Underlying script: `scripts/mb-profile.sh`.

---

## Purpose

Memory Bank rules have two layers:

1. **Immutable safety baseline** — always active, cannot be disabled by any profile, task instruction, or user choice (see below).
2. **Configurable preferences** — role, stack, architecture, delivery presets that personalize guidance without weakening safety.

`/profile` controls the configurable layer. It reads from and writes to:
- **User-global profile**: `<agent-config>/memory-bank/rules-profile.json` (e.g. `~/.claude/memory-bank/rules-profile.json`). No project files are written — works even when `[MEMORY BANK: ABSENT]`.
- **Project profile**: `<resolved-mb>/rules-profile.json` (requires an active Memory Bank).

---

## Subcommands

| Subcommand | One-liner |
|------------|-----------|
| `init` | Create a new profile interactively or via flags |
| `show` | Print the resolved merged profile (all layers) |
| `path` | Print the active profile path and which layer it came from |
| `validate` | Validate a profile file — exits 0 if valid, 1 with errors otherwise |
| `set` | Update a single field in user or project profile |

---

## Usage examples

```bash
# Create a user-global backend/Go profile (no project Memory Bank needed):
mb-profile.sh init --scope=user --role=backend --stack=go \
  --architecture=microservices --delivery=contract-first

# Create a project-scoped frontend/TypeScript profile:
mb-profile.sh init --scope=project --role=frontend --stack=typescript \
  --architecture=fsd --delivery=sdd

# Create a mobile/generic profile:
mb-profile.sh init --scope=user --role=mobile --stack=generic \
  --architecture=mobile-udf --delivery=api-first

# Create a Python data service profile:
mb-profile.sh init --scope=project --role=backend --stack=python \
  --architecture=modular-monolith --delivery=tdd

# Create a Java DDD profile:
mb-profile.sh init --scope=project --role=backend --stack=java \
  --architecture=ddd --delivery=api-first

# Show the resolved profile (user + project merged):
mb-profile.sh show

# Show where the active profile file lives:
mb-profile.sh path

# Validate an existing profile:
mb-profile.sh validate .memory-bank/rules-profile.json

# Update a single field (project scope):
mb-profile.sh set --scope=project --strictness=block
```

---

## Storage modes

`--scope=user`
: Profile is written to `<agent-config>/memory-bank/rules-profile.json`. This is the user-global scope — it works even without a project Memory Bank (rules-only mode). No project files are created.

`--scope=project`
: Profile is written to `<resolved-mb>/rules-profile.json` inside the active Memory Bank (local or global). Requires Memory Bank to be initialized.

`--agent=<name>`
: Override the agent name for user-scope resolution (default: `claude-code`). Allowed: `claude-code`, `cursor`, `codex`, `opencode`, `pi`, `windsurf`, `cline`, `kilo`.

`--mb=<path>`
: Override the Memory Bank path for project-scope writes.

Precedence (strongest last):
```
built-in configurable defaults
  > user global profile  (<agent-config>/memory-bank/rules-profile.json)
  > project profile      (<resolved-mb>/rules-profile.json)
  > task instruction     (this run only)
+ immutable safety baseline (always wins, non-overridable)
```

---

## Immutable baseline reminder

The following 7 rules apply regardless of any profile and **cannot be disabled**:

- `no-placeholders` — no `TODO`, `...`, or pseudocode in production code.
- `protected-files` — `.env`, `ci/`, Docker/K8s/Terraform changes require explicit user request.
- `destructive-confirm` — force-push, hard-reset, mass-delete require explicit confirmation.
- `fail-fast` — uncertain implementation → stop and propose a short plan instead of guessing.
- `dry-kiss-yagni` — DRY/KISS/YAGNI baseline always applies.
- `verification-before-completion` — claim "done" only after running declared verification commands.
- `explicit-storage-choice` — tooling never silently writes profiles or banks outside explicitly chosen scope.

A profile may **strengthen** the baseline (e.g. set `strictness=block`) but never **weaken** it.

---

## Rules-only mode

A user-global profile personalizes rules even when no project Memory Bank exists:

```bash
# First session in a project without Memory Bank:
# → agent prints [MEMORY BANK: ABSENT]
# → user-global profile still applies role/stack presets
mb-profile.sh init --scope=user --role=backend --stack=go
```

No project directory is created, no `.memory-bank/` is initialized, no files are written inside the project.

---

## JSON is canonical — YAML is docs-only

Profile files on disk are always JSON (`rules-profile.json`). YAML examples appear in documentation only and must be converted by `mb-profile.sh` or equivalent before storage. The Python stdlib `json` module handles all parsing — no runtime YAML dependency is added.

---

## References

- Schema spec: `references/rules-profile.schema.md`
- Built-in presets: `references/rules-presets/`
- Full guide: `docs/rule-profiles.md`
- Underlying script: `scripts/mb-profile.sh`
