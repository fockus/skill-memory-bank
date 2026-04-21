---

## description: Create an Architecture Decision Record in memory-bank

allowed-tools: [Read, Glob, Grep, Bash, Write]

# ADR: $ARGUMENTS

## 1. Context

- Read existing ADRs in `./.memory-bank/plans/` (files with `_adr_` in the name)
- Study the relevant part of the codebase
- Make sure this decision has not already been recorded or rejected

## 2. Create the ADR

```bash
mkdir -p ./.memory-bank/plans
```

Write it to `./.memory-bank/plans/YYYY-MM-DD_adr_<kebab-case-title>.md`:

```markdown
# ADR: <Decision title>
Date: YYYY-MM-DD
Status: ✅ Accepted | ❌ Rejected | 🔄 Replaced by ADR-XXX

## Context
<!-- What problem are we solving? What constraints exist? Why is this decision needed? -->

## Decision
<!-- What exactly did we decide to do? -->

## Alternatives
<!-- Which options were considered and why were they rejected? -->
<!-- Alternative 1: ... — rejected because ... -->
<!-- Alternative 2: ... — rejected because ... -->

## Consequences
<!-- What changes because of this decision? What trade-offs does it introduce? What becomes easier/harder? -->
```

## 3. Update Memory Bank

- Update `plan.md` — add a link to the new ADR
- Create a note in `notes/`

