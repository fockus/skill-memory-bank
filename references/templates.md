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

## Hypothesis in `research.md`

```markdown
| H-NNN | <Hypothesis (SMART: specific, measurable)> | ⬜ Not tested | — | — | — |
```

Statuses: `⬜ Not tested` → `🔬 Testing` → `✅ Confirmed` / `❌ Refuted`

---

## ADR in `backlog.md`

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

## Plan decomposition — Phase → Sprint → Stage

Formal 3-level hierarchy for planning. **Choose the level by the size of the work — not everything needs to be wrapped in a Phase.**

| Level | Purpose | Size threshold | Context |
|-------|---------|----------------|---------|
| **Stage** | Atomic unit of work. Marker `<!-- mb-stage:N -->` inside a plan file | 1-5 files, ~5-15 tests, 5-30 min | Fits in one tool series |
| **Sprint** | Group of related Stages sharing the same architectural context. = **one plan file** | 3-7 stages, ≤15 files, ≤60 tests, ~3000 lines of new code | **≤ 200k tokens** (one session) |
| **Phase** | Major direction with ≥2 Sprints and dependencies between them | ≥2 Sprints, > 1 week of work, has roadmap/gates | Multiple plan files |

### When to use which level

| Work size | Structure | Example |
|-----------|-----------|---------|
| ≤ 3 stages, 1 session | **Plain plan**, no Phase/Sprint | Bugfix, small refactor |
| 3-7 stages, several days | One **Sprint** = one plan file | New mid-size feature |
| ≥ 2 Sprints with dependencies | **Phase** = roadmap + multiple plan files (one per Sprint) | Large initiative |

### 🔴 Hard rule — 200k context window per Sprint

**One Sprint must fit in a single Claude 200k-token context** — from reading code to final verification and Memory Bank actualization.

Budget per Sprint (indicative):
- ~30k — reading inputs (source files + plan + checklist)
- ~30k — planning + TDD red phase
- ~100k — implementation
- ~30k — verification + test runs + output
- ~10k — buffer for errors and corrections

**If you estimate a Sprint at >200k — split it into 2 Sprints** along an architectural boundary. Two clean Sprints beat one truncated Sprint.

**Symptoms that require a split:**
- > 5 large files (>500 lines each) to read
- > 15 new/modified files
- > 3000 lines of new code
- > 60 new tests
- cross-layer refactor (core + service + infra all at once, all large)

### Required per Stage — SMART DoD

Each Stage in a plan file must have:
- **Title** — what is being done
- **Actions** — concrete files/functions
- **Tests (TDD — BEFORE implementation)** — unit / integration / e2e where applicable
- **DoD** (SMART: Specific / Measurable / Achievable / Relevant / Time-bound) as checkboxes; each item answers «how do we verify?»
- **Code rules** — one-line reference to principles (TDD/SOLID/DRY/KISS/Clean Arch)

### Required per Sprint — Gate

Every plan file ends with `## Gate` — the single success criterion. Without a Gate, it's not a Sprint.

### Terminology

Use **Phase / Sprint / Stage** exactly. "Этап" is accepted historically in existing plans (= Stage), but new plans should use the English triple for consistency.

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
├── status.md       # Header + "Current phase: Start"
├── roadmap.md         # Header + "Current focus: define"
├── checklist.md    # Header + empty checklist
├── research.md     # Header + empty hypothesis table
├── backlog.md      # Header + empty sections
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
| `staleness` | `status.md` / `roadmap.md` / `checklist.md` / `progress.md` have not been untouched for >30 days |
| `script_coverage` | `bash scripts/X.sh` references point to existing files (project-local or skill-local) |
| `dependency` | Python version in `status.md` matches `pyproject.toml` (if present) |
| `cross_file` | Counts like "N bats green" are consistent across `status.md`, `checklist.md`, `progress.md` |
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
