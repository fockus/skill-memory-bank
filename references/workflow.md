# Memory Bank — Workflow

## Session start

```text
1. Check whether .memory-bank/ exists
   ├── Yes → [MEMORY BANK: ACTIVE]
   │   ├── Run mb-context.sh or /mb start
   │   ├── Read: STATUS.md, plan.md, checklist.md, RESEARCH.md
   │   ├── Check .memory-bank/codebase/
   │   │   ├── Missing or empty → suggest /mb map all (mb-codebase-mapper, sonnet)
   │   │   └── Populated → mb-context.sh already folded summaries into context
   │   └── Summarize focus in 1-3 sentences
   └── No → [MEMORY BANK: INACTIVE], work without the bank
```

**Bootstrap rule:** On the very first `/mb start` after `/mb init`, or whenever `.memory-bank/codebase/` contains no `*.md` files, the agent must surface the suggestion `run /mb map` (default answer = skip). Do not auto-invoke the mapper — the user owns the decision.

## During work

### When to update each file

```text
checklist.md    ← Every completed task (⬜ → ✅)
                   Every newly discovered task (+ ⬜ <task>)

STATUS.md       ← A stage or milestone completes
                   Key metrics changed (tests, coverage, reward)
                   Roadmap moved

plan.md         ← Focus or priorities changed
                   Current phase completed, new phase starts

RESEARCH.md     ← New hypothesis (H-NNN)
                   Experiment finished (result + conclusion)
                   New finding

BACKLOG.md      ← New idea (HIGH/LOW)
                   Architectural decision (ADR-NNN)

lessons.md      ← Anti-pattern or repeated mistake detected
                   Insight from an ML experiment

progress.md     ← End of session (APPEND-ONLY)

codebase/       ← Stack or major dependency changed → /mb map stack
                   Architecture / layer boundaries changed → /mb map arch
                   Lint / test tooling changed → /mb map quality
                   Security or performance finding → /mb map concerns
                   Whole project snapshot needed → /mb map all
                   Code graph needs refresh → /mb graph --apply
```

### When to create files

```text
notes/          ← A task or stage completed
                   Something reusable was discovered
                   Knowledge, not chronology (5-15 lines)

experiments/    ← Before running an ML experiment
                   Format: hypothesis → baseline → one change → metrics

plans/          ← Before complex multi-stage work
                   Format: context → stages (DoD, TDD) → risks → gate
                   ⚠️ AFTER creating the plan, update plan.md + STATUS.md + checklist.md

reports/        ← When a full report will be useful to future sessions

codebase/       ← After /mb init (bootstrap) — run /mb map all
                   Whenever STACK / ARCHITECTURE / CONVENTIONS / CONCERNS drifts
                   Populated by mb-codebase-mapper subagent (sonnet)
                   Consumed by /mb context (summaries) / /mb context --deep (full)
```

### Plan consistency (REQUIRED)

```text
When creating a new plan (/mb plan):
    plans/<file>.md  → create the detailed plan
    plan.md          → update "Active plan" + focus
    STATUS.md        → update roadmap ("In progress")
    checklist.md     → add tasks as ⬜ items

When completing a plan:
    plans/<file>.md  → move to plans/done/
    plan.md          → clear/change "Active plan"
    STATUS.md        → move it to "Completed"
    checklist.md     → all tasks in the plan = ✅

Chain: plan.md → plans/<file>.md → checklist.md → STATUS.md
All 4 files MUST stay synchronized.
```

### Decision tree: who updates what

```text
Mechanical actualization (checklist, progress, STATUS metrics)
    → MB Manager (Sonnet subagent)

Plan creation (plans/)
    → Main agent (requires deeper reasoning)

Architectural decisions (ADR)
    → Main agent formulates + MB Manager stores in BACKLOG.md

ML results
    → Main agent interprets + MB Manager updates RESEARCH.md
```

## Session finish

```text
1. If work followed a plan:
   ├── /mb verify — REQUIRED before closing
   │   ├── Plan Verifier rereads the plan, checks git diff
   │   ├── CRITICAL → must fix
   │   └── WARNING → ask the user
   └── Only after verification → /mb done

2. Run /mb done or MB Manager (actualize + note):
   ├── checklist.md: mark completed ✅, add new ⬜
   ├── progress.md: append at the end (APPEND-ONLY)
   ├── STATUS.md: update if milestone changed
   ├── RESEARCH.md: update if there are ML results
   ├── lessons.md: add if an anti-pattern was found
   ├── BACKLOG.md: add if there is an idea/ADR
   ├── plan.md: update if focus changed
   └── notes/: create a note about the completed work

3. Or manually:
   ├── /mb update (actualize core files)
   └── /mb note <topic> (write a note)
```

## Before compaction

```text
1. Run MB Manager (action: actualize) to save current progress
2. All useful knowledge from the session must be in the bank BEFORE compaction
3. After compaction — run /mb start to restore context
```
