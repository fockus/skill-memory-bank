# Memory Bank — File Structure

## Root (core) files

### `STATUS.md`
The main overview file for the project. The single source of truth for the current state.

```markdown
# <Project>: Project Status

## Current phase
**Phase N: <Name>.** <Short status description.>

<General project description, 2-3 sentences.>

## Key metrics
- Tests: **NNN** (unit + integration), all green
- Coverage: **NN%+**
- <Project-specific metrics>
- Lint: clean

## Roadmap
### ✅ Completed
- **<Phase/Milestone>**: <description>, N tests

### 🔧 In progress
- **<Phase>**: <what is being worked on>

### ⬜ Next
- **<Phase>**: <what is planned next>
```

### `plan.md`
Current priorities and focus. Update when direction changes.

```markdown
# <Project> — Plan

## Current focus
<What we are doing now, 1-3 sentences>

## Next steps
1. <step>
2. <step>

## Deferred
- <tasks outside the current focus>
```

### `checklist.md`
Task tracker grouped by phases/sections.

```markdown
# <Project> — Checklist

## <Phase/Section>
- ✅ <completed task>
- ⬜ <unfinished task>
```

### `RESEARCH.md`
Research log: hypotheses, findings, current experiment.

```markdown
# <Project> — Research

## Current experiment
EXP-NNN: <title>

## Hypotheses
| ID | Hypothesis | Status | Experiment | Result | Conclusion |
|----|------------|--------|------------|--------|------------|
| H-001 | <text> | ✅ Confirmed | EXP-001 | <delta> | <conclusion> |
| H-002 | <text> | ⬜ Not tested | — | — | — |

## Key findings
- <F-001>: <finding>
```

### `BACKLOG.md`
Ideas and architectural decisions.

```markdown
# Backlog

## Ideas
### HIGH
- <idea with rationale>

### LOW
- <idea>

## Architectural decisions (ADR)
- ADR-001: <Decision> — <context, alternatives> [YYYY-MM-DD]
```

### `progress.md`
Date-based execution log. **APPEND-ONLY** — never delete old entries.

```markdown
# <Project> — Progress Log

## YYYY-MM-DD

### <Topic>
- <what was done>
- Tests: N green, coverage X%
- Next step: <what comes next>
```

### `lessons.md`
Anti-patterns and repeated mistakes. Group by category.

```markdown
# <Project> — Lessons & Antipatterns

## <Category>

### <Pattern name> (EXP-NNN / source)
<Problem description and fix. 2-4 lines.>
```

---

## Directories

### `experiments/` — ML experiments
Files: `EXP-NNN.md`. Monotonic numbering.

Format: Hypothesis → Setup (baseline + one change) → Results (table with delta, p-value, Cohen's d) → Conclusions → Status.

### `plans/` — Detailed plans
Files: `YYYY-MM-DD_<type>_<topic>.md`. Types: `feature`, `fix`, `refactor`, `experiment`.

Completed plans move to `plans/done/`.

Format: Context → Stages (with SMART DoD, TDD) → Risks → Gate.

### `notes/` — Knowledge notes
Files: `YYYY-MM-DD_HH-MM_<topic>.md`.

5-15 lines. Focus on conclusions and patterns, not chronology.

Format: What was done (3-5 bullets) → New knowledge (conclusions, patterns).

### `reports/` — Reports and reviews
Free-form. Use when a full report will help future sessions.

### `codebase/` — Codebase map
Structured snapshot of the project, read on session start and consumed by planning/implementation agents.

**Artifacts:**

| File            | Generator             | Purpose                                                                 |
|-----------------|-----------------------|-------------------------------------------------------------------------|
| `STACK.md`      | `/mb map stack`       | Languages, runtime, dependencies, external integrations                 |
| `ARCHITECTURE.md` | `/mb map arch`      | Layers, data flow, directory structure, entry points                    |
| `CONVENTIONS.md` | `/mb map quality`    | Naming, style, testing, imports                                         |
| `CONCERNS.md`   | `/mb map concerns`    | Tech debt, known bugs, security risks, performance hotspots             |
| `graph.json`    | `/mb graph --apply`   | JSON Lines — nodes/edges for modules, functions, classes (ast-based)    |
| `god-nodes.md`  | `/mb graph --apply`   | Top-20 nodes by degree (code hotspots)                                  |

**Producer:** subagent `mb-codebase-mapper` (prompt: `agents/mb-codebase-mapper.md`, sonnet). Each MD doc is capped at ≤70 lines — details belong in code, not in mirror docs.

**Consumer:** `scripts/mb-context.sh` — injects a one-line summary per doc into `/mb context`, and full contents when called with `--deep`.

**When to regenerate:**
- Right after `/mb init` (bootstrap a new project)
- Stack / major dependency change → `/mb map stack`
- Major refactor of layers / structure → `/mb map arch`
- New lint / test tooling → `/mb map quality`
- Security or performance findings → `/mb map concerns`
- Any large change → `/mb map all` + `/mb graph --apply`
