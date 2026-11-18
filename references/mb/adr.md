# /mb adr — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `adr <title>` — Capture Architecture Decision Record with auto-generated monotonic `ADR-NNN` ID in the ADR registry `adr.md` — skeleton includes Context / Decision / Alternatives / Consequences (1–2 sentences each, ≤ 1200 bytes)

### adr <title>

Capture an Architecture Decision Record (ADR) in the ADR registry `adr.md`. Full flow and record format: `commands/adr.md`.

**Arguments:**

- `title` — ADR title (free-form).

**Effect:**

- Appends `### ADR-NNN — <title> [YYYY-MM-DD] · status: accepted` to `adr.md` (creates the file if missing).
- ID is monotonic over `adr.md` and any not-yet-migrated ADRs in `backlog.md` (`mb-adr-migrate.sh --apply` moves those).
- Skeleton includes: `**Context:**`, `**Decision:**`, `**Alternatives:**`, `**Consequences:**` — `<!-- hint -->` placeholders, 1–2 sentences each, ≤ 1200 bytes per record.
- Idempotent per call — each invocation creates a new ADR (no de-dup by title; ADR history is cumulative).

Run directly:

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-adr.sh "<title>"
```

**Typical flow:**

```
User: /mb adr "Use OIDC for PyPI publishing"
→ ADR-003
  [writes ### ADR-003 — Use OIDC for PyPI publishing [2026-04-21] · status: accepted + skeleton to adr.md]
```

After capture, open `backlog.md` and fill in Context / Options / Decision / Rationale / Consequences. The skeleton is intentionally short — the value is in the completed reasoning, not the template.
