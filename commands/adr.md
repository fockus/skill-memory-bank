---
description: Create an Architecture Decision Record in memory-bank BACKLOG
allowed-tools: [Read, Glob, Grep, Bash, Edit, Write]
argument-hint: <decision-title>
---

# ADR: $ARGUMENTS

## 0. Validate arguments

If `$ARGUMENTS` is empty, stop and ask the user for the decision title. Do not proceed with an empty title.

## 1. Context

- Read `./.memory-bank/BACKLOG.md` — existing ADRs live in the `## Architectural decisions (ADR)` section.
- If no `## Architectural decisions` section exists, create it at the bottom of `BACKLOG.md` under a `---` divider.
- Study the relevant part of the codebase so the decision has real grounding.
- Make sure this decision (or a close variant) has not already been recorded or rejected — search with `grep -i "<keyword>" .memory-bank/BACKLOG.md`.

## 2. Determine the next ADR number

```bash
grep -oE 'ADR-[0-9]+' .memory-bank/BACKLOG.md | sort -V | tail -1
# Take the numeric part, add 1. Zero-pad to 3 digits (ADR-001, ADR-002, ...).
# If no existing ADR → start from ADR-001.
```

Numbering is monotonic — never reuse an ID, even if an ADR was later rejected or replaced.

## 3. Draft the decision

Show the user a draft before writing. Required parts:

- **Context** — what problem are we solving, what constraints exist, why this decision is needed now
- **Decision** — what exactly we decided to do
- **Alternatives** — which options were considered and why each was rejected
- **Consequences** — what changes because of this decision, what trade-offs, what becomes easier / harder

Ask for confirmation.

## 4. Append to `BACKLOG.md`

Use the ADR line format from `references/templates.md`:

```markdown
- ADR-NNN: <Decision title> — <context, considered alternatives, consequences> [YYYY-MM-DD]
```

Append under the `## Architectural decisions (ADR)` section. Do not rewrite existing ADRs. If the decision is long enough that one line is insufficient, split onto multiple bullet points under ADR-NNN (keep the header line as the identifier).

## 5. Optional cross-link

If the decision is significant enough that future sessions will benefit from a full note:

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-note.sh "adr-NNN-<slug>"
```

Fill the returned file with frontmatter (`type: decision`, relevant `tags`, `importance: high`) and expand each section of the ADR.

## 6. Summary

Report:
- `ADR-NNN` identifier assigned
- Position in `BACKLOG.md`
- Optional note path (if created)
- Reminder that `BACKLOG.md` is never rewritten — new ADRs are appended, superseded ones are marked (e.g., `ADR-005: superseded by ADR-012`).
