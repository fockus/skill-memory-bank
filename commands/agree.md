---
description: Manage the running list of agreements — the canonical registry of confirmed decisions
allowed-tools: [Read, Bash, Grep, Glob]
argument-hint: <subcommand> [args]
---

# Agree: $ARGUMENTS

`/mb agree <subcommand> [args]` is the thin dispatch to `scripts/mb-agree.sh` — the ONLY writer of
`<bank>/agreements.md` (REQ-002). The model never edits the registry or the managed block by hand;
every mutation goes through this script so IDs stay monotonic, the format never drifts, and
parallel sessions serialize safely through the lock. Full protocol (what is/isn't an agreement, the
4 statuses, ADR routing, anti-examples): `references/agreements.md`.

## 0. Validate arguments

If `$ARGUMENTS` is empty, show the subcommand table below and ask which one to run. Do not guess a
subcommand from a bare statement.

## 1. CLI contract

| Subcommand | Args | Effect | Exit |
|---|---|---|---|
| `add "<statement>"` | `[--supersedes N] [--adr NNN] [--source S]` | New active entry (default source `user-confirmed`, lazy-creates `agreements.md` from the template on first use); with `--supersedes N` atomically archives `AGR-N` as superseded and links it to the new entry | `0`; `2` usage (empty/multiline statement); `1` invalid `--supersedes` target or damaged file |
| `defer N` | — | Move active `AGR-N` to `## Deferred` | `0`; `1` not active |
| `reject N` | — | Move active `AGR-N` to `## Archive` marked rejected | `0`; `1` not active |
| `question "<text>"` | — | Append `- Q-NNN: <text>` to `## Open Questions` (no managed-block sync) | `0` |
| `resolve N` | — | Close open question `Q-N` | `0`; `1` not found |
| `list` | `[--all]` | Print `## Active` (default) or the whole registry | `0` |
| `sync` | — | Rebuild the managed block in `CLAUDE.md`/`AGENTS.md` from the file (reconciles hand edits) | `0`; `1` damaged block/file |

Statements are single-line — an embedded newline is a usage error (exit `2`). Every mutating
subcommand takes the `<bank>/.agreements.lock` (same `_lock_acquire`/`_lock_release` idiom as
`mb-work-progress-append.sh`), writes via temp-file + `mv`, then re-syncs the managed block.
`MB_AGREEMENTS=off` (env or a `.mb-config` line) turns every subcommand into an explained no-op,
exit `0`, zero writes.

## 2. Run directly (systems-level, no LLM needed)

```bash
bash "${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-agree.sh" <subcommand> [args] [mb_path]
```

## 3. Typical flow

```
User: /mb agree add "Phase 1 must not depend on a vector database"
→ AGR-001 записано: Phase 1 must not depend on a vector database

User: /mb agree add "Use pgvector instead, deferred to phase 2" --supersedes 1
→ AGR-002 записано: Use pgvector instead, deferred to phase 2
  [AGR-001 marked superseded by AGR-002, moved to Archive]

User: /mb agree question "Should we cache search results?"
→ Q-001 added to Open Questions

User: /mb agree list
## Active
- AGR-002 (2026-07-15, user-confirmed): Use pgvector instead, deferred to phase 2
```

## 4. When to write vs when to ask

- The user just said something equivalent to "yes" / "confirmed" / "go with X" / "decided" →
  `add`, then announce `→ AGR-NNN записано: <statement>` in the same turn.
- The idea is a proposal, a model recommendation, or an implicit assumption nobody confirmed →
  `question`, never `add`. See `references/agreements.md` for concrete anti-examples.
- The user changes a prior decision → `add "<new statement>" --supersedes N`; never leave two
  active entries that contradict each other.
- A decision is hard-to-reverse / surprising / a real trade-off (the `/mb adr` 3-gate) → also run
  `/mb adr` and pass `--adr NNN` to `add` so the registry entry references it (REQ-015).

## 5. Verifier integration

`/mb verify` reads `## Active` from `agreements.md` (when it exists) and classifies every entry as
satisfied / violated / not-applicable against the plan and diff. Any `violated` → the verdict is
FAIL with an explicit choice: fix the implementation, or `mb-agree.sh add "..." --supersedes N`. See
`agents/plan-verifier.md` § Agreement Compliance.

## 6. Summary

Report back to the user:
- The subcommand run and the resulting exit code.
- The assigned/affected `AGR-NNN` (or `Q-NNN`) identifier(s).
- The visible announce line for any `add`.
- A reminder that `agreements.md` is append-only history — `reject`/`supersede` never delete an
  entry, only change its status and section.
