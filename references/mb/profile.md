# /mb profile — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `profile <subcommand>` — Manage rule profiles: `init`, `show`, `path`, `validate`, `set`. See `commands/profile.md`. Example: `mb-profile.sh init --scope=user --role=backend --stack=go`

### profile <subcommand>

Manage rule profiles — configurable role, stack, architecture, and delivery presets layered on top of the immutable safety baseline. See the full command documentation in `commands/profile.md`.

**Quick examples:**

```bash
# User-global profile (no project Memory Bank required):
mb-profile.sh init --scope=user --role=backend --stack=go \
  --architecture=microservices --delivery=contract-first

# Project profile:
mb-profile.sh init --scope=project --role=frontend --stack=typescript \
  --architecture=fsd --delivery=sdd

# Show resolved profile:
mb-profile.sh show

# Validate:
mb-profile.sh validate .memory-bank/rules-profile.json
```

**Dispatch:** run `scripts/mb-profile.sh <subcommand> [flags]` directly. Full subcommand reference: `commands/profile.md`.

**Immutable baseline reminder:** skipping a profile keeps the immutable baseline active (no-placeholders, protected-files, destructive-confirm, fail-fast, DRY/KISS/YAGNI, verification-before-completion, explicit-storage-choice). The immutable baseline cannot be disabled by any profile.
