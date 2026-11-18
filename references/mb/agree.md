# /mb agree — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `agree <subcommand>` — Manage the running list of agreements — the canonical registry of confirmed decisions in `<bank>/agreements.md` (`add [--supersedes N] \| defer \| reject \| question \| resolve \| list \| sync`), auto-synced into a managed block in `CLAUDE.md`/`AGENTS.md`. See `commands/agree.md` + `references/agreements.md`

### agree <subcommand> [args]

**Alias** for `/mb agree` — dispatch to `commands/agree.md` for the full CLI contract. Manages the
running list of agreements: the canonical registry of confirmed decisions in
`<bank>/agreements.md`, separate from `progress.md` (narrative) and ADRs (rationale). Full
maintenance protocol (what is/isn't an agreement, anti-examples, the 4 statuses, ADR routing,
lazy activation, subagents propose-never-write) → `references/agreements.md`.

**Subcommands:** `add "<statement>" [--supersedes N] [--adr NNN] [--source S]`, `defer N`,
`reject N`, `question "<text>"`, `resolve N`, `list [--all]`, `sync`.

**Arguments:**

- `subcommand` — one of the seven above (first positional).
- remaining words — subcommand-specific args, passed through verbatim.

**Effect:**

- Every mutation is written exclusively by `scripts/mb-agree.sh` (never a direct model edit) —
  locked, atomic (temp-file + `mv`), monotonic never-reused `AGR-NNN` IDs.
- `add` lazily creates `agreements.md` from the template on first use in a bank that does not have
  one yet — zero artifacts before the first call.
- Every mutating subcommand re-syncs the managed block (`<!-- mb-agreements:start -->` …
  `<!-- mb-agreements:end -->`) into project-root `CLAUDE.md` and `AGENTS.md` with one-liner
  active agreements + a pointer to `<bank>/agreements.md`.
- `question`/`resolve` touch only `## Open Questions` — no managed-block sync (Open Questions are
  not injected).
- `MB_AGREEMENTS=off` (env or `.mb-config`) makes every subcommand an explained no-op, no writes.

Run directly (systems-level, no LLM needed for the write itself):

```bash
bash "${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-agree.sh" <subcommand> [args]
```

**Typical flow:**

```
User: /mb agree add "Phase 1 must not depend on a vector database"
→ AGR-001 записано: Phase 1 must not depend on a vector database

User: /mb agree add "Use pgvector instead" --supersedes 1
→ AGR-002 записано: Use pgvector instead
  [AGR-001 marked superseded by AGR-002, moved to Archive]
```

**When to write vs when to ask (model conduct, REQ-009):** only an explicitly confirmed user
decision becomes `add` + the visible announce `→ AGR-NNN записано: <statement>` in the same turn.
Proposals, model recommendations, and implicit assumptions go to `question` instead — never
Active. A changed decision uses `--supersedes N`; never leave two contradicting active entries.

**Verifier integration:** `/mb verify` reads `## Active` (when `agreements.md` exists) and
classifies each entry against the plan/diff — see `### verify` in `$SKILL_DIR/references/mb/verify.md` and
`agents/plan-verifier.md` § Agreement Compliance.
