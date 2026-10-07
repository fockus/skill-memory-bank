---
description: "Creates an Architecture Decision Record (ADR) in the memory-bank ADR registry (adr.md). Use when a significant architecture decision was made — «запиши ADR», «зафиксируй решение», record a decision."
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
argument-hint: <decision-title>
---

# ADR: $ARGUMENTS

## Skill bundle root

Every bundled helper below runs through the skill bundle root, never a bare `scripts/…` path (the
working directory is the user's project, where `scripts/` is absent or belongs to someone else):

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
```

## 0. Validate arguments

If `$ARGUMENTS` is empty, stop and ask the user for the decision title. Do not proceed with an empty title.

## 1. When to record an ADR (3-gate)

Offer an ADR **only when all three are true** (from `grill-with-docs`):

1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons.

If any gate fails, skip the ADR: an easy-to-reverse decision will just be reversed; an unsurprising one needs no explanation; a no-alternative one records nothing beyond "we did the obvious thing." When the user explicitly asks for an ADR, honour it — but note which gate is weak.

## 2. Context

- ADRs live in `./.memory-bank/adr.md` — the ADR registry: append-only, monotonic `ADR-NNN`, superseded records are marked, never deleted.
- If the bank still keeps old ADRs in its idea registry (`grep -c '^### ADR-' .memory-bank/backlog.md` > 0), move them into `adr.md` first: `bash "$SKILL_DIR"/scripts/mb-adr-migrate.sh --apply`.
- Study the relevant part of the codebase so the decision has real grounding.
- Make sure this decision (or a close variant) is not already recorded or rejected: `grep -i "<keyword>" .memory-bank/adr.md`.

## 3. Draft — only what is key

Show the user a draft before writing. Format (single source: `references/templates.md` § ADR registry) — four fields, **1–2 sentences each, the whole record ≤ 1200 bytes**:

- **Context:** the problem that forced a decision now.
- **Decision:** what was chosen and the one main reason.
- **Alternatives:** which option was rejected and why.
- **Consequences:** what becomes easier and what becomes more expensive.

Leave out chronology, logs, run IDs, file lists and review history. If the reasoning really needs more room, put it in a note (`bash "$SKILL_DIR"/scripts/mb-note.sh "adr-NNN-<slug>"`) and link it with an optional `**Details:** notes/<file>.md` line.

Good:

```markdown
### ADR-013 — Store ADRs in a dedicated adr.md [2026-10-06] · status: accepted

**Context:** ADRs were mixed with 200+ ideas in a 175 KB file and grew to 3 KB each.
**Decision:** A separate append-only adr.md with four short fields — decisions stay findable and cheap to read.
**Alternatives:** Keep them in the idea registry with a size lint — rejected, the mixing was the problem.
**Consequences:** One more core file; old banks need a one-time move (mb-adr-migrate.sh).
```

Bad: a "Context" paragraph retelling the session, a list of every touched file, and a "Rationale" that repeats the Decision.

Ask for confirmation.

## 4. Write the record

```bash
bash "$SKILL_DIR"/scripts/mb-adr.sh "<Decision title>"
```

The script creates `adr.md` when missing, assigns the next monotonic `ADR-NNN` (never reuses an ID, also counting ADRs not yet migrated) and appends the skeleton. Replace the four placeholder comments with the confirmed draft — edit only the new record, never earlier ones.

To replace an older decision, record the new ADR and change only the old heading's status: `· status: superseded by ADR-NNN`.

## 5. Summary

Report:
- `ADR-NNN` identifier assigned and its title
- Optional note path (if created)
