---

## description: Creates a detailed work plan with DoD and saves it in memory-bank
allowed-tools: [Read, Glob, Grep, Bash, Write]

# Planning: $ARGUMENTS

## 0. Preparation

Read before you start:

1. `~/.claude/CLAUDE.md` — global rules
2. `./.memory-bank/plan.md` — current priorities (if present)
3. `./.memory-bank/checklist.md` — current tasks (if present)
4. `./.memory-bank/lessons.md` — known anti-patterns (if present)

Study the codebase in the context of the task:

```bash
# Project structure
find . -type f -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/venv/*' -not -path '*/__pycache__/*' | head -200
```

Find and read the files relevant to the topic `"$ARGUMENTS"`.

## 1. Analysis

Before writing the plan, answer these questions:

- What problem are we solving?
- Which system components are affected?
- What dependencies and constraints exist?
- What risks and unknowns are there?
- How does this fit the current architecture (Clean Architecture)?

## 2. Draft the plan

Create the directory if it does not exist:

```bash
mkdir -p ./.memory-bank/plans
```

Determine the plan type: `feature | refactor | bugfix | research`

Write it to `./.memory-bank/plans/YYYY-MM-DD_<type>_<kebab-case-title>.md`:

```markdown
# <Task title>
Date: YYYY-MM-DD
Type: feature | refactor | bugfix | research
Status: 🟡 In progress

## Context
<!-- Why is this needed? What problem does it solve? What are the preconditions? -->

## Scope
<!-- What is in scope? What is explicitly out of scope? -->

## Architectural decisions
<!-- Chosen approach, patterns, structure. Why this approach? -->
<!-- Add an ASCII diagram if it helps -->

## Stages

### Stage 1: <title>
**Goal:** <what must be achieved — concrete and measurable>
**Files:** <which files are created/changed>

**Implementation:**
1. <step>
2. <step>
3. ...

**Tests (TDD — written BEFORE implementation):**
- Unit: <what to cover, which scenarios>
- Integration: <which component interactions to verify>
- E2E: <which user journey to validate> (if applicable)

**DoD (Definition of Done):**
- [ ] <criterion — Specific, Measurable, Achievable, Relevant, Time-bound>
- [ ] <criterion>
- [ ] All unit tests are written and passing
- [ ] Integration tests are written and passing (if applicable)
- [ ] No `SOLID` / `DRY` / `KISS` violations
- [ ] Dependency direction is correct (Clean Architecture)
- [ ] Code passed self-review

### Stage 2: <title>
<!-- Same structure -->

### Stage N: Final verification
**Goal:** Verify that everything works together

**Tests:**
- Full unit test run
- Full integration test run
- E2E tests for the main user scenarios

**DoD:**
- [ ] All tests pass
- [ ] Coverage is not below <threshold>% (if configured)
- [ ] No `TODO` / `FIXME` / `HACK` in new code
- [ ] Documentation is updated (if needed)
- [ ] Code review is complete (`/user:review`)

## Risks and mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|---------|------------|
| <risk> | High/Medium/Low | <what might break> | <how to prevent it> |

## Dependencies
<!-- External dependencies, blockers, and what is needed from others -->

## Estimate
<!-- Rough effort estimate by stage -->
```

## 3. Update Memory Bank

After creating the plan:

1. Update `./.memory-bank/checklist.md` — add tasks from the plan as ⬜ items
2. Update `./.memory-bank/plan.md` — add a link to the new plan and refresh priorities
3. Create a note at `./.memory-bank/notes/YYYY-MM-DD_HH-MM_plan-<topic>.md` with a short summary of the plan (5-10 lines)

## Plan quality requirements

- Each stage must be atomic — it should be possible to pick it up and execute it independently
- DoD must be concrete and verifiable — no vague items like "high-quality code"
- Tests must be described BEFORE implementation in every stage (TDD)
- Stages must be ordered by dependency — you cannot start stage 3 before finishing stage 1
- Every DoD criterion must answer the question: "How do we verify this is done?"
- The plan should incorporate lessons from `lessons.md` (if any)

