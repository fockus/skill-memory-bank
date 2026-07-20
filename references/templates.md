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

> **Canonical decomposition note:** When a spec exists under `specs/<topic>/`, the
> `tasks.md` file is the canonical decomposition. Plan files act as sprint slices
> (via `linked_spec` frontmatter) or standalone tactical wrappers when no spec
> exists. Do not duplicate task definitions in both plan stages and spec tasks.

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

## Interview plan template

`<bank>/tmp/interview-plan-<topic>.md` — the white-spot ledger for `/mb discuss` (contract C2). Written before the first question, validated by `mb-interview-artifact-check.sh plan`, installed atomically by `mb-interview-artifact-write.sh install-plan`. Generation is gated on closing every topic (grilling rule 11).

```markdown
## Inherited decisions (do not re-ask)

- <decision carried from parent_context; omit line for a root topic>

## Topics

- [ ] <planned theme>
- [ ] <planned theme>

## Discovered mid-interview

- [ ] <theme that surfaced while grilling>
```

## Glossary template

`.memory-bank/glossary.md` — one line per interview-resolved term, written by `mb-glossary.sh upsert` (contract C12). Created lazily on the first term; `/mb context` prints a one-line `Glossary:` pointer when it exists.

```markdown
<term> — <definition>
```

## Interview transcript template

`context/<topic>-interview.md` — the curated interview transcript for the planner and spec-reviewer (contract C4). Written candidate-first, secret-scanned, and published atomically by `mb-interview-artifact-write.sh publish-transcript`. Grammar validated by `mb-interview-artifact-check.sh transcript`.

```markdown
# Interview transcript: <topic> (<YYYY-MM-DD>[, <free text>])

## Унаследовано (не обсуждалось повторно)

<inherited decisions — JIT slice interviews only; omit for a root topic>

## Q&A

**Q1 (<tag>).** <question>
**A1.** <near-verbatim answer> → **D-01**. Отклонено: <none|rejected alternatives>

**Финальный гейт[, круг 1].** Anything to add?
**Ответ.** <user answer>
```

## Context (`context/<topic>.md`) — `/mb discuss` output (Phase 2 SDD)

Captured by the 5-phase requirements-elicitation interview. Source for `mb-traceability-gen.sh` REQ → Plan → Test matrix.

```markdown
---
topic: <topic>
created: YYYY-MM-DD
status: draft | ready
---

# Context: <topic>

## Purpose & Users

Who uses this, what problem does it solve, what are the success criteria?

## Research Digest

Facts gathered in Phase 0, before the interview — each line one fact + citation (`file:line` or URL).

- `scripts/mb-workflow.sh:42` — <fact the recommendation relied on>
- <https://example.org/spec> — <external prior art / standard>

## Decision Log

Numbered ledger from the interview: what was decided, why, what was rejected.

- **D-01**: <decision> — Rationale: <why>. Rejected: <alternatives and why not>.

## Functional Requirements (EARS)

Each line uses one of the 5 EARS patterns (Ubiquitous / Event-driven / State-driven / Optional / Unwanted).
IDs are **per-spec-local**: the topic owns its REQ namespace, so a brand-new topic starts at `REQ-001` no matter how many REQs other specs already hold. Get the next one via `bash "$SKILL_DIR/scripts/mb-req-next-id.sh" --spec <topic> "$MB_PATH"` (omit `--spec` only when you deliberately want a project-wide max+1).

- **REQ-001** (ubiquitous): The system shall ...
- **REQ-002** (event-driven): When <trigger>, the system shall ...
- **REQ-003** (state-driven): While <state>, the system shall ...
- **REQ-004** (optional): Where <feature>, the system shall ...
- **REQ-005** (unwanted): If <trigger>, then the system shall ...

## Non-Functional Requirements

- **NFR-001**: Performance — ...
- **NFR-002**: Security — ...
- **NFR-003**: Scale — ...

## Constraints

Hard limits (regulatory, technical, organizational) that cannot be relaxed.

## Edge Cases & Failure Modes

What breaks at the boundaries? What happens when dependencies fail?

## Out of Scope

Explicitly excluded — to prevent scope creep during planning.

## Open Questions

Deferred or unresolved — `/mb plan` must address or explicitly park each one.

- <question> (blocked on: <what>)
```

Validate REQ lines via `bash scripts/mb-ears-validate.sh context/<topic>.md`. Exit 0 = all valid; exit 1 = violations on stderr.

## Spec Requirements (`specs/<topic>/requirements.md`) — Phase 2 Sprint 2

Hybrid requirement list: **Kiro User Stories** + **EARS acceptance criteria**. Created by `bash scripts/mb-sdd.sh <topic>`. If `context/<topic>.md` exists, the EARS section is copied verbatim into the acceptance criteria. `mb-ears-validate.sh` validates only the `- **REQ-NNN** ...` bullets; the `**User Story:**` lines are ignored, so the two layers coexist.

```markdown
# Requirements: <topic>

> Spec triple — see also: design.md, tasks.md.
>
> EARS acceptance criteria (uppercase keywords, REQ-ID bullets):
> - Ubiquitous:        `THE SYSTEM SHALL <response>`
> - Event-driven:      `WHEN <trigger> THE SYSTEM SHALL <response>`
> - State-driven:      `WHILE <state> THE SYSTEM SHALL <response>`
> - Optional feature:  `WHERE <feature> THE SYSTEM SHALL <response>`
> - Unwanted:          `IF <trigger> THEN THE SYSTEM SHALL <response>`

## Requirements (EARS)

### Requirement 1: <short title>

**User Story:** As a <role>, I want <feature>, so that <benefit>.

#### Acceptance Criteria

- **REQ-NNN**: THE SYSTEM SHALL ...
```

## Spec Design (`specs/<topic>/design.md`) — Phase 2 Sprint 2

Architecture + interfaces + decisions backing `requirements.md`.

```markdown
# Design: <topic>

## Architecture

<!-- Layering, data flow, dependency direction. -->

## Interfaces

<!-- Protocol/ABC/interface definitions that anchor contract tests. -->

## Decisions

<!-- ADR-style entries: Context / Options / Decision / Rationale / Consequences. -->

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
|      | H/M/L       | H/M/L  |            |
```

## Spec Tasks v2 (`specs/<topic>/tasks.md`) — executable task block

`specs/<topic>/tasks.md` is a **first-class executable artifact**. Each task is wrapped
in `<!-- mb-task:N -->` markers so `mb_work_items.py` (and `/mb work <topic>`) can parse
and execute it. Spec tasks are the canonical decomposition; plan files may reference them
as sprint slices via `linked_spec` frontmatter.

Validate with `bash scripts/mb-spec-validate.sh <topic>` before running `/mb work`.
Upgrade legacy `## N. ...` style with `bash scripts/mb-spec-tasks-migrate.sh <topic>`.

The v2 block adds machine-checkable fields:

- `**Role:**` takes a **bare** role name (`backend`, `qa`, `architect`) — the parser
  prefixes `mb-` itself, so `Role: mb-backend` silently routes to a nonexistent agent.
- `**Scope:**` is a repo-relative restricted glob (literals + `*` inside a segment + a
  `**` segment; no `..`, absolute paths, or `?`/`[`/`]`/`{`/`}`).
- `**Budget:**` is an integer token budget (task ≤120000, stage sum ≤400000).
- `**Eval:**` MUST carry a machine red anchor — `exit:` and/or `output~:` (a POSIX ERE).

```markdown
# Tasks: <topic>

<!-- mb-task:1 -->
## Task 1: <task title>

**Stage:** 1
**Covers:** REQ-NNN
**Role:** backend
**Blocked-by:** none
**Scope:** scripts/mb-foo.sh, tests/bats/test_mb_foo.bats
**Budget:** 100000
**Eval:** bats tests/bats/test_mb_foo.bats — red: helper not extended, gate absent; exit: 1; output~: not ok [0-9]+ foo_gate

**What to do:**
- <concrete actions — files, functions, behaviour>

**Testing (TDD — tests BEFORE implementation):**
- <unit / integration tests>

**DoD:**
- [ ] concrete, measurable criterion (SMART)
- [ ] tests pass (were red)
- [ ] lint clean
<!-- /mb-task:1 -->
```

### §Contract seam block (design.md, C9)

Record the machine-readable seam block in `design.md` §Contract. Default is
**exactly one** seam (existing seams > new; pick the highest). A `**Seam
rationale:**` line is required **only** when there are ≥2 seams.

```markdown
**Seams:**
- <the single, highest seam>
**Seam rationale:** <why more than one seam is agreed> ← required ONLY when ≥2 seams
```

### Structural Eval sample (docs / config task, REQ-049)

A task with no runtime surface still declares a **structural** Eval — file
presence, a required section, or a linter exit — so the gate is real, not a
prose promise:

```markdown
**Eval:** bash -c 'grep -q "## Migration" docs/guide.md' — red: section missing; exit: 1; output~:
```

(Structural Evals assert existence/shape; behavioural red is deferred to the
first `/mb work` step.)

### Waiver form (non-gated only)

A non-gated task may waive its Eval — an **explicit exception, never a silent
substitute**. A waiver on a gated (SHALL/MUST) task is rejected by the validator.

```markdown
**Eval:** none — waiver: docs-only task, no behavioural surface (non-gated only)
```

### Escalation menu (D-35) — size overflow at generation time

When the C3 budget gate reports an overflow, present these four options:

1. **Split now** — decompose into smaller tasks/stages and regenerate the candidate.
2. **MVP-trim → registry** — cut to an MVP; defer the rest as child specs via
   `mb-idea.sh "[SPEC:<group>] <child-topic>"` (orchestrator is the sole registry writer).
3. **Umbrella + JIT** — keep an umbrella spec, slice releases just-in-time.
4. **`budget_override: user`** — accept a `spec=over` spec via `requirements.md`
   frontmatter. Lifts **only** `spec=over` and **only** when `task_over=none ∧
   stage_over=none`. The D-13 hard caps (task ≤120000, stage ≤400000) are
   **never overridable**.

---

## Plan as execution wrapper

A plan file can be a thin sprint slice over an existing spec. Declare the link in
YAML frontmatter at the top of the plan file:

```yaml
---
linked_spec: specs/inventory-sync
tasks: 1-3
---
```

`linked_spec` — path to the spec directory (relative to `.memory-bank/`).
`tasks` — optional range; limits `/mb work` to that task subset for sprint slicing.

The plan basename is used for traceability only. Spec tasks remain the source of truth.

---

## Brief one-pager (`briefs/<topic>/brief.md`)

Written by `/mb brief` into the candidate, then published by `scripts/mb-brief.sh create`.
All nine `##` sections are required, spelled exactly as below (case sensitive, no
aliases, no duplicates). Frontmatter is a CLOSED key set: `topic`, `created`,
`status`, `inputs` are required; `assumptions_note` appears only under `--auto`
and must be non-empty. Target 60–100 lines; over 120 the validator warns.

Attachments carries exactly one `- [<basename>](inputs/<encoded-basename>)` line
per `--input`, in command-line order, percent-encoded per RFC 3986 with the safe
set `A-Za-z0-9-._~` (space → `%20`, `#` → `%23`). With no sources the body is
exactly `- None`.

```markdown
---
topic: <topic>
created: YYYY-MM-DD
status: ready
inputs:
  - inputs/<basename>
---

# Brief: <topic>

## Essence
What is being asked for, in two or three sentences. Never empty.

## Goal & Impact
The outcome and the measurable effect it should have. Never empty.

## References
Prior art, tickets, documents worth reading.

## Solution (JTBD)
When <situation>, I want <motivation>, so that <expected outcome>.

## Scenarios
- The main success path, one line.
- The edge cases worth naming this early.

## Constraints
- What is fixed: deadlines, stack, integrations that must not change.

## UX
How the user meets the result.

## Done Criteria
- Checkable statements that decide whether this is finished.

## Attachments
- [<basename>](inputs/<encoded-basename>)
```

Validate with `scripts/mb-brief-validate.sh <brief.md>`: `brief=ok` / `brief=invalid`
on stdout, diagnostics on stderr, exit 0/1/2.
