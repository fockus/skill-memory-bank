# Memory Bank — Templates

## Note (`notes/`)

File: `notes/YYYY-MM-DD_HH-MM_<topic>.md`

```markdown
# <Topic>
Date: YYYY-MM-DD HH:MM

## What was done
- <action 1>
- <action 2>
- <action 3>

## New knowledge
- <conclusion, pattern, reusable solution>
- <what to remember for future sessions>
```

5-15 lines. Knowledge, not chronology.

---

## `progress.md` entry (append)

```markdown
## YYYY-MM-DD

### <Topic>
- <what was done, 3-5 bullets>
- Tests: N green, coverage X%
- Next step: <what comes next>
```

Append ONLY to the end of the file. Never edit old entries.

---

## `lessons.md` entry

```markdown
### <Pattern name> (EXP-NNN / source)
<Problem description. What happened.>
<Fix. How it was corrected or avoided.>
<General pattern. When it may recur.>
```

2-4 lines. Group by categories (`ML Architecture`, `ML Methodology`, `Testing`, etc.).

---

## Hypothesis in `RESEARCH.md`

```markdown
| H-NNN | <Hypothesis (SMART: specific, measurable)> | ⬜ Not tested | — | — | — |
```

Statuses: `⬜ Not tested` → `🔬 Testing` → `✅ Confirmed` / `❌ Refuted`

---

## ADR in `BACKLOG.md`

```markdown
- ADR-NNN: <Decision> — <context, considered alternatives, consequences> [YYYY-MM-DD]
```

---

## Experiment (`experiments/EXP-NNN.md`)

```markdown
# EXP-NNN: <Title>

## Hypothesis
H-NNN: <hypothesis text>

## Setup
- Baseline: <baseline configuration description>
- Treatment: <ONE change relative to the baseline>
- Metric: <what is measured, how success is defined>
- Horizon: <N episodes, seeds>
- Configuration: <key hyperparameters>

## Results

| Metric | Baseline | Treatment | Delta | p-value | Cohen's d |
|--------|----------|-----------|-------|---------|-----------|
| reward |          |           |       |         |           |
| entropy|          |           |       |         |           |

## Conclusions
- <main finding>
- <what it means for the project>

## Next steps
- <what to do next based on the results>

## Status: ⬜ Pending / 🔬 Running / ✅ Done / ❌ Failed
```

Principle: one change per experiment (single-change policy).

---

## Plan (`plans/YYYY-MM-DD_<type>_<topic>.md`)

Types: `feature`, `fix`, `refactor`, `experiment`

```markdown
# Plan: <type> — <topic>

## Context

**Problem:** <what triggered this plan>

**Expected result:** <what should be achieved>

**Related files:**
- <links to code, specs, experiments>

---

## Stages

### Stage 1: <name>

**What to do:**
- <concrete actions>

**Testing (TDD — tests BEFORE implementation):**
- <unit tests: what they verify, edge cases>
- <integration tests: which components together>

**DoD (Definition of Done):**
- [ ] <concrete, measurable criterion (SMART)>
- [ ] tests pass
- [ ] lint clean

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

### Stage 2: <name>

**What to do:**
- 

**Testing (TDD):**
- 

**DoD:**
- [ ]

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| <risk> | H/M/L | <how to prevent it> |

## Gate (plan success criterion)

<When the plan is considered fully complete>
```

---

## New Memory Bank initialization (`/mb init`)

Creates the minimal structure:

```text
.memory-bank/
├── STATUS.md       # Header + "Current phase: Start"
├── plan.md         # Header + "Current focus: define"
├── checklist.md    # Header + empty checklist
├── RESEARCH.md     # Header + empty hypothesis table
├── BACKLOG.md      # Header + empty sections
├── progress.md     # Header
├── lessons.md      # Header
├── experiments/    # Empty; filled by experiment authors (EXP-NNN.md)
├── plans/          # Empty; filled by /mb plan (YYYY-MM-DD_<type>_<topic>.md)
│   └── done/       # Empty; archived plans move here via /mb plan-done
├── notes/          # Empty; filled by /mb note (YYYY-MM-DD_HH-MM_<topic>.md)
├── reports/        # Empty; free-form reports useful to future sessions
└── codebase/       # Empty; populated by /mb map (mb-codebase-mapper subagent)
                    #   STACK.md / ARCHITECTURE.md / CONVENTIONS.md / CONCERNS.md
                    #   Optional: graph.json + god-nodes.md via /mb graph --apply
                    #   Consumed by /mb context (summaries) and --deep (full)
```

---

## Drift checks (`scripts/mb-drift.sh`)

Deterministic consistency checks for `.memory-bank/` without AI calls. `mb-doctor` uses it in step 0 to save tokens when the bank is already clean.

### Usage

```bash
# Current project
bash ~/.claude/skills/memory-bank/scripts/mb-drift.sh .

# Another project
bash ~/.claude/skills/memory-bank/scripts/mb-drift.sh /path/to/project
```

### Output (stdout — `key=value`)

```text
drift_check_path=ok
drift_check_staleness=ok
drift_check_script_coverage=ok
drift_check_dependency=skip
drift_check_cross_file=ok
drift_check_index_sync=skip
drift_check_command=ok
drift_check_frontmatter=ok
drift_warnings=0
```

**Values:** `ok` (no problems), `warn` (drift found), `skip` (check not applicable — for example `dependency=skip` if there is no `pyproject.toml` / `package.json` / `go.mod`).

Diagnostic messages go to stderr with the `[drift:<name>]` prefix.

**Exit code:** 0 when `drift_warnings=0`, otherwise 1 (works for a pre-commit hook).

### 8 checkers

| Name | What it checks |
|------|-----------------|
| `path` | Links like `notes/X.md`, `plans/X.md`, `reports/X.md`, `experiments/X.md` in core files actually exist |
| `staleness` | `STATUS.md` / `plan.md` / `checklist.md` / `progress.md` have not been untouched for >30 days |
| `script_coverage` | `bash scripts/X.sh` references point to existing files (project-local or skill-local) |
| `dependency` | Python version in `STATUS.md` matches `pyproject.toml` (if present) |
| `cross_file` | Counts like "N bats green" are consistent across `STATUS.md`, `checklist.md`, `progress.md` |
| `index_sync` | `index.json` mtime is newer than all `notes/*.md` files (otherwise reindexing is needed) |
| `command` | `npm run X` / `make X` references point to existing scripts/targets |
| `frontmatter` | `notes/*.md` files starting with `---` also contain a closing fence |

### Integration with `mb-doctor`

`mb-doctor` runs `mb-drift.sh` first:
- `drift_warnings=0` → report "ok", no LLM analysis needed
- `drift_warnings>0` → read warnings and then run agent Steps 1-4 (cross-reference checks, Edit fixes)

This saves ~80% of tokens in standard cases where the bank is already clean.

### Pre-commit hook (optional)

```bash
# .git/hooks/pre-commit
#!/bin/bash
bash ~/.claude/skills/memory-bank/scripts/mb-drift.sh . || {
  echo "Memory Bank drift detected — run /mb doctor to fix"
  exit 1
}
```

---

## Custom metrics override (`.memory-bank/metrics.sh`)

Optional file. If present, `mb-metrics.sh` calls it instead of auto-detect. Use it when:
- the project has a non-standard structure (monorepo, multiple languages together)
- you need project-specific metrics (custom test runner, Kubernetes readiness, ML reward, etc.)
- auto-detect returns `stack=unknown`

The script must print `key=value` lines to stdout:

```bash
#!/usr/bin/env bash
# .memory-bank/metrics.sh — custom metrics for this project.

set -euo pipefail

echo "stack=custom"                       # arbitrary label
echo "test_cmd=make test"                 # how to run tests
echo "lint_cmd=make lint"                 # how to lint
echo "src_count=$(find src -type f | wc -l | tr -d ' ')"

# Any extra metrics (passed through to MB Manager as-is):
echo "coverage=$(coverage report | tail -1 | awk '{print $4}')"
echo "reward_mean=$(jq '.mean' results.json)"
```

After creating it, run `chmod +x .memory-bank/metrics.sh`. Validation: `bash scripts/mb-metrics.sh` should return `source=override` instead of `source=auto`.
