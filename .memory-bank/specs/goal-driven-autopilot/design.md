---
type: spec-design
topic: goal-driven-autopilot
status: ready
created: 2026-05-23
authors: [Anton Ivanov]
linked_requirements: requirements.md
linked_tasks: tasks.md
---

# Design: Goal-driven autopilot

## Mission

Make the skill capable of executing a user-defined goal end-to-end with
minimal supervision while keeping the inviolable promise — agents
remember — and every new behaviour fully configurable and
token-economical.

## Context

Borrowed and adapted from two external skills (`open-gsd/get-shit-done-redux`,
`obra/superpowers`) and our user's prior brainstorming. The work consolidates
8 components that together turn `/mb work` from a "stage stepper" into a
goal-aware autopilot that can run for hours, recover from verification
failures via a diagnostic agent, parallelise independent stages, isolate
work in git worktrees, and produce a clean atomic-commit-per-stage
history.

Every component goes through the configurability filter defined in
[`references/design-principles.md`](../../references/design-principles.md).
Defaults preserve current behaviour. All expensive paths are opt-in. The
memory subsystem (`status.md` / `checklist.md` / `plans/` / `progress.md`
/ `lessons.md` / `notes/`) is untouched.

## Design contract checklist (per `references/design-principles.md`)

- **Inviolable memory?** Untouched. New artefacts (`project.md`,
  `goal.md`, `goals/done/`, `notes/debug-*.md`) live alongside, do not
  replace anything.
- **Default behaviour changes?** No. Every component is gated behind a
  `pipeline.yaml` flag or `--flag` whose default leaves the existing
  flow intact.
- **Requires forking skill files?** No. Agent-prompt changes use an
  overlay resolver; rule changes use existing profile system.
- **Token cost per invocation?** Each component bounded; cheap paths
  default. Concrete estimates given in each component section.
- **Graceful under budget?** Yes. Parallel waves fall back to
  sequential; autopilot honours hard stops; debugger caps cycles.
- **Discoverable when opted out?** Yes. Disabled features print a
  one-line activation hint; `/mb config show` lists flags.

## Glossary

- **Goal** — the high-level outcome a session aims to deliver. Single
  active goal at a time, stored in `.memory-bank/goal.md`.
- **Project description** — slowly-changing facts about what the project
  is, stored in `.memory-bank/project.md`. Filled by `/goal init` and
  refreshed by `/mb map` / `/goal --refresh`.
- **Wave** — a set of work items (plan stages or spec tasks) that have
  no `depends_on` relationship and can dispatch in parallel.
- **Worktree** — an isolated git worktree under
  `~/.cache/memory-bank/worktrees/<project-hash>/<plan-slug>/` used to
  contain a `/mb work` invocation.
- **Autopilot** — the `/mb work --autopilot` mode that loops over an
  active goal until acceptance is satisfied, using the diagnostic agent
  for automatic recovery.
- **Addon** — a small markdown fragment prepended to a role-agent's
  base prompt to enforce defensive behaviour. Picked from a fixed set
  via `pipeline.yaml: agents.preamble_addons`.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ GOAL LAYER  (opt-in)                                                 │
│   project.md   ← /goal init, /mb init --with-project, /goal --refresh│
│   goal.md      ← /goal "...", /goal done                             │
│   goals/done/  ← archived completed goals                            │
│   /goal        ← status | init | set | done | list | --refresh       │
└────────────────────────────┬─────────────────────────────────────────┘
                             │ orchestrates
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│ EXECUTION ENGINE  (4 independent opt-in toggles)                     │
│   execution.use_worktree:    off | auto | always   (default off)     │
│   execution.parallel_waves:  off | explicit        (default off)     │
│   execution.auto_commit_code: off | stage          (default off)     │
│   execution.autopilot:       off | on              (default off)     │
└────────────────────────────┬─────────────────────────────────────────┘
                             │ dispatches
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│ AGENT LAYER  (overlay + addons system)                               │
│   Prompt resolver: user-global ◀ project ◀ skill-base                │
│   agents.preamble_addons: [defensive, scope-lock,                    │
│                            fail-loudly, read-before-write]           │
│   mb-debugger (new agent)                                            │
│     trigger: agents.debugger.auto_on_fail | manual /mb debug         │
└──────────────────────────────────────────────────────────────────────┘
```

---

## Components

### Component 1 — Goal layer

#### Artefacts

`.memory-bank/project.md` (slow-changing, ~30–80 lines):

```yaml
---
type: project
name: <project-name>
created: <date>
updated: <date>
---

## Mission
<1–2 sentences>

## Domain
<one line>

## Stack
See codebase/STACK.md

## Non-negotiable constraints
- <hard constraint>

## Team coding conventions
See codebase/CONVENTIONS.md
- <any team-specific rule not yet in CONVENTIONS.md>

## Architecture notes
- <key architectural decisions not yet ADR'd>

## Out of scope
- <what we explicitly do NOT do>
```

`.memory-bank/goal.md` (active, single goal, ~30–50 lines):

```yaml
---
type: goal
id: G-001
status: active            # active | done | abandoned
created: <date>
linked_plan: plans/<file>.md
linked_spec: specs/<topic>
progress_source: checklist  # checklist | plan-stages | spec-tasks
---

# Goal: <title>

## Description
<3–5 sentences>

## Acceptance criteria
- [ ] criterion 1
- [x] criterion 2

## Progress notes
<append-only, brief>
```

Progress percentage is **not stored** in the file; it is computed from
`progress_source` when read.

Archive: `.memory-bank/goals/done/<id>-<slug>.md`.

#### `/goal` command modes

| Mode | Behaviour | Token cost |
|------|-----------|------------|
| `/goal` (no args) | Read goal.md, compute % from `progress_source`, print title + acceptance + linked plan + last activity. | ~1–2k |
| `/goal init` | Interactive setup of `project.md` (if absent) + `goal.md`. Asks 5–6 questions (see below). On existing active goal, asks to archive current. | ~3–8k (interactive) |
| `/goal "<description>"` | Create `goal.md` with description and acceptance criteria. status=active. Does not auto-run `/mb discuss` / `/mb plan`. | ~1–2k |
| `/goal "<description>" --decompose` | Opt-in orchestration: `/mb discuss <slug>` → `/mb plan` → fill `linked_plan`. | ~30–80k depending on size |
| `/goal done` | status → done; move to `goals/done/`; append summary to `progress.md`. | ~2–3k |
| `/goal list` | List active + archived goals (folder scan, no body reads). | ~0.5k |
| `/goal --refresh` | Re-derive `project.md` Stack / Architecture sections from updated `codebase/` docs. | ~1–2k |

#### `/goal init` — interactive question set (max 5–6 questions)

Asked one at a time. Each accepts "skip" — skipped fields get
`<TBD — fill manually>` markers, no blocking.

1. **Mission.** "In one or two sentences, what is this project for?"
   (default heuristic: first paragraph of `README.md` if present)
2. **Team coding conventions.** "Are there team-specific coding rules or
   style guides we should remember? (e.g. mandatory PR template,
   specific commit format, custom lint rules beyond stack defaults)"
3. **Architecture constraints.** "What architectural choices are
   non-negotiable? (e.g. 'must run offline', 'no Postgres extensions',
   'all I/O through repo layer')"
4. **Stack notes.** "Anything notable about the stack the codebase
   scan would not show? (e.g. 'internal forks of library X', 'pinned
   versions for compliance')"
5. **Out of scope.** "What is this project explicitly NOT doing? (e.g.
   'not a mobile app', 'no real-time features in v1')"
6. **Active goal.** "What do you want to achieve in the near term?
   (this becomes `goal.md`'s description and acceptance criteria)"

Question 6 is asked only if no `goal.md` exists yet.

#### Opt-in mechanisms

Three independent ways to activate, any one works:

1. `memory-bank install --profile=goal` → installs `commands/goal.md`
   and sets `goals.enabled: true`.
2. `pipeline.yaml: goals.enabled: true` → activates without install
   profile.
3. File presence: if `.memory-bank/goal.md` exists, `/goal` activates
   even without flags.

When deactivated, `/goal` responds with one-line activation hint and
exits 0.

#### What we don't do (YAGNI)

- No goal-graph (no dependency between goals).
- No parallel active goals in v1.
- No ML-derived ETA — simple `velocity = stages_done / days_since_created`.
- No goal templates.

---

### Component 2 — Worktree isolation

#### Configuration

```yaml
execution:
  use_worktree: off | auto | always   # default off
  worktree_cleanup: keep | merge | prompt   # default prompt
```

| Value | Behaviour |
|-------|-----------|
| `off` | `/mb work` runs in current tree (today's behaviour). |
| `auto` | Worktree created only for `/mb work --autopilot`. |
| `always` | Worktree created for every `/mb work`. |

CLI flags `--worktree` / `--no-worktree` override per invocation.

#### Layout

```
~/.cache/memory-bank/worktrees/<project-hash>/<plan-slug>/
```

`<project-hash>` from `scripts/_lib.sh::mb_project_hash` (same hash used
for global storage registry).

#### Lifecycle

1. `mb-work-worktree.sh ensure <plan-slug>` — creates branch
   `mb-work/<plan-slug>` from HEAD, runs `git worktree add`, returns
   path.
2. `/mb work` executes inside the worktree (subagents dispatched with
   CWD = worktree path).
3. After `/mb done`, `worktree_cleanup` decides:
   - `keep` — worktree kept for manual inspection.
   - `merge` — fast-forward `mb-work/<slug>` onto the original branch,
     `git worktree remove`.
   - `prompt` — ask user (default).
4. On abort or hard-stop, the worktree is kept for forensic review.

Commands: `mb-work-worktree.sh {ensure|status|path|remove|clean}`.

#### Safety refusals

`ensure` refuses when:

- HEAD is detached (no branch base).
- Working tree dirty without `--force` (suggests `git stash`).
- Target branch `mb-work/<slug>` exists and is not merged without
  `--reuse`.

#### Token cost

The script itself is free in agent tokens. Subagents receive identical
prompts; only the CWD changes.

---

### Component 3 — `mb-debugger` agent

#### Purpose

When `plan-verifier` returns FAIL, the engine currently halts. The
debugger consumes the verifier's existing JSON output and the failing
test stdout to produce a structured fix-plan that a role-agent can
apply. No re-running of tests, no re-reading of the codebase.

#### Architecture

```
verify FAIL
   │ verifier JSON + failing test stdout + stage body + slim diff
   ▼
mb-debugger (diagnoses)
   │ produces fix_plan JSON
   ▼
role-agent (mb-developer / mb-backend / ...) applies fix-plan
   │
   ▼
mb-reviewer → plan-verifier (same severity gate, same verify step)
```

Debugger does not Write code itself — separation of concerns:

- the existing role-agent + review/verify pipeline applies to fixes
  identically to original work,
- a debugger that can edit anywhere is dangerous,
- diagnostic and constructive cognition benefit from different prompts.

#### Output schema

```json
{
  "verdict": "fixable | needs-human | abandon",
  "root_cause": "Short single-sentence diagnosis.",
  "fix_plan": [
    {
      "action": "edit | add-test | remove | refactor",
      "file": "path/to/file.py",
      "line": 42,
      "change": "Replace `foo(bar)` with `foo(bar, ctx=ctx)` — missing context propagation.",
      "rationale": "Test test_propagates_ctx asserts ctx in downstream call.",
      "confidence": "high | medium | low"
    }
  ],
  "estimated_cycles": 1,
  "overall_confidence": "high | medium | low"
}
```

Parser: `scripts/mb-debugger-parse.sh`, strict, exits non-zero on
malformed JSON.

#### Verdict gating

| verdict | `overall_confidence` | Behaviour |
|---------|----------------------|-----------|
| `fixable` | `high` | Auto-apply: re-dispatch implementer with fix-plan prepended. |
| `fixable` | `medium` | `--auto` → apply; otherwise surface and ask user. |
| `fixable` | `low` | Halt for human, surface fix-plan. |
| `needs-human` | * | Halt, surface root_cause. |
| `abandon` | * | Halt, mark stage failed, suggest worktree rollback. |

#### Configuration

```yaml
agents:
  debugger:
    enabled: false              # default
    auto_on_fail: false         # debugger available manually but does not auto-trigger
    max_cycles: 3
    on_max_cycles: stop_for_human   # | continue_with_warning
    require_confidence: medium      # min for auto-apply
```

Autopilot **requires** `enabled: true`; startup refuses with clear error
otherwise.

#### Manual command

```bash
/mb debug                    # debug last verify FAIL in current session
/mb debug --stage N
/mb debug --test <name>
/mb debug --file <path>
/mb debug --apply            # also re-dispatch implementer
/mb debug --dry-run          # default — diagnostic only
```

#### Persistence

Fix-plans archive to `.memory-bank/notes/debug-<YYYY-MM-DD_HH-MM>-<stage-slug>.md`,
indexed by `mb-index.sh`, searchable via `/mb search`.

#### Token cost

| Operation | Estimate |
|-----------|----------|
| `/mb debug --dry-run` single | ~12–20k |
| `/mb debug --apply` | + ~15–30k (one implementer cycle) |
| Autopilot recovery, 1 cycle | ~30–50k |
| Autopilot recovery, max_cycles=3 exhausted | ~90–150k (hard cap) |

---

### Component 4 — Parallel waves (DAG)

#### Marker syntax extension

```
<!-- mb-stage:N -->                     # current syntax, wave = 0
<!-- mb-stage:N depends_on:[1,2] -->    # new optional suffix
<!-- mb-task:N depends_on:[1] -->
```

Parsed by `mb_work_items.py` (extended). Backward compatible.

#### DAG construction

`scripts/mb-work-dag.sh <plan-or-spec>` builds the DAG via topological
sort (longest-path-from-source). Output: ASCII visualisation + JSON
waves.

`mb-work-plan.sh` (extended) adds `wave: N` to every JSON Lines item.

Errors: cycle → exit 1 with the cycle described; forward reference (stage
1 depends on 3) → exit 1.

#### Configuration

```yaml
execution:
  parallel_waves: off | explicit | auto   # default off
  on_wave_failure: stop_for_human | continue_with_warning
```

| Value | Behaviour |
|-------|-----------|
| `off` | `depends_on` ignored, sequential. |
| `explicit` | Parallel where `depends_on` declared; plan without deps stays sequential. |
| `auto` | Reserved alias; equivalent to `explicit` in v1. |

CLI flags `--parallel` / `--no-parallel` override.

#### Dispatch

Within a wave, `/mb work` issues **one message with N `Task` calls** —
true parallel via the Task tool. Each item runs its own
implement → review → fix-cycle → verify loop. Main agent aggregates.

Wave PASS = all items PASS. Any FAIL → wave halts according to
`on_wave_failure`.

#### File-conflict guard (v1: best-effort, not magic)

1. **Pre-wave check:** scan DoD / Covers for file mentions. Overlapping
   items in same wave → warn (auto-decline under `--auto`, fall back to
   sequential for this wave).
2. **Per-item snapshot:** after each item, `git diff --name-only` →
   item → files map. Conflicts surface in end-of-wave summary, suggest
   `/mb debug` on the collision.
3. **What we don't do v1:** no mandatory file-touch declarations in
   DoD. User is responsible for correct `depends_on`.

#### Budget integration

Before each wave:

```
estimated_wave_cost = sum(estimated_item_cost for items in wave)
if budget_remaining < estimated_wave_cost:
    fall back to sequential within this wave
    log: "Wave N reduced to sequential (budget guard)"
```

`estimated_item_cost = 15k * (1 + dod_lines/10)` — rough but enough for
graceful degradation.

#### CLI

```bash
/mb work <target> --dry-run --show-dag
/mb work <target> --parallel
/mb work <target> --parallel --budget 150000
/mb work <target> --no-parallel
```

---

### Component 5 — Atomic commit per stage

#### Configuration

```yaml
execution:
  auto_commit_code: off | stage         # default off
  commit_message_template: |
    feat({{role}}/{{plan_slug}}): {{heading}}

    Stage: {{stage_no}}
    Plan: {{plan_path}}
    {{#covers}}Covers: {{covers}}{{/covers}}
  commit_trailer: |
    Co-Authored-By: {{git_user_name}} <{{git_user_email}}>
```

CLI: `--commit-per-stage` / `--no-commit-per-stage`.

#### When the commit happens

Only after **verify PASS** for the stage. Verify FAIL never commits.

#### 4 safety gates (reused from `mb-auto-commit.sh`)

1. **Pre-stage clean state.** Worktree clean at stage start. Otherwise
   stage-commit disables itself for the session with warning.
2. **No protected paths in diff.** Existing
   `scripts/mb-work-protected-check.sh` (Section 3b of `/mb work`)
   already enforces this; commit only happens after a successful step
   3b.
3. **No `<private>` blocks in committed files.** Scan staged diff for
   the marker; halt commit with clear message.
4. **Tests pass.** Implicitly satisfied — commit only after verify PASS.

#### Snapshot mechanic

At stage start (step 3a of `/mb work`), `$STAGE_START_SHA = git rev-parse HEAD`
is saved in session state. After verify PASS:

```bash
git add -A $(git diff --name-only "$STAGE_START_SHA")
git commit -m "$rendered_template" --trailer "$rendered_trailer"
```

`-A` limited to changed files → no accidental pickup of untracked
artefacts.

#### Commit message — structured trailers

```
feat(backend/inventory-sync): Add persistence layer

Stage: 2
Plan: .memory-bank/plans/2026-05-23_feature_inventory-sync.md
Covers: REQ-001, REQ-003

Co-Authored-By: Anton Ivanov <fockus@gmail.com>
```

Enables `/mb verify` to cross-check git history against plan, and
`git log --grep="Plan: .memory-bank/plans/..."` retrieval.

#### Worktree interaction

Atomic commits write to `mb-work/<slug>` when worktree mode is active.
`worktree_cleanup: merge` fast-forwards them onto the original branch
as one operation.

#### Edge cases

| Case | Behaviour |
|------|-----------|
| Stage changed 0 tracked files | `git diff --quiet` → skip commit, log "no changes committed". |
| Stage commit already exists (re-run) | git refuses idempotently; surface "stage N already committed at sha XYZ". |
| Stage with `linked_spec` | `covers` comes from spec `mb-task:N` marker. |
| Pre-existing dirty worktree | Gate 1 disables stage-commit for the whole session. |

#### Token cost

Zero additional tokens. Uses already-computed diff and snapshot.

---

### Component 6 — Autopilot (`/mb work --autopilot`)

#### Purpose

Run an active goal to completion with auto-recovery. The user starts
the session, runs `/mb work --autopilot`, and walks away. The loop
continues until acceptance criteria pass, a hard stop fires, or the user
cancels.

#### Prerequisites (startup check)

The CLI refuses to start unless:

- `.memory-bank/goal.md` exists and is `status: active`.
- `goal.md` has `linked_plan` or `linked_spec`.
- `pipeline.yaml: agents.debugger.enabled: true`.

If any prerequisite is missing, surface a concrete fix-hint and exit 1.

#### Recommended companions (warn but allow)

If `execution.use_worktree: off` and `execution.auto_commit_code: off`,
print a warning that autopilot runs without isolation and atomic
checkpoints. In `--auto` mode, the warning is logged and execution
proceeds (graceful degradation per design principles).

#### Loop

```
LOOP:
  resolve next pending item from linked_plan / linked_spec
  if none → mark goal as done, /mb done, exit 0
  dispatch implement (role-agent)
  review (severity gate; fix-cycle as in /mb work)
  verify (plan-verifier)
  if verify PASS:
    atomic-commit-per-stage (if enabled)
    continue LOOP
  else:
    dispatch mb-debugger
    apply verdict gating (Component 3)
    if recovered → continue LOOP
    if halted → exit with reason
```

#### Hard stops

| Trigger | Source |
|---------|--------|
| Protected path write without `--allow-protected` | step 3b |
| `--budget` exhausted | `mb-work-budget.sh check` exit 2 |
| `sprint_context_guard.hard_stop_tokens` | session monitor |
| `agents.debugger.max_cycles` exceeded on same stage | step 3e |
| `autopilot.max_iterations` (default 50, configurable) | loop counter |
| `autopilot.max_stall_iterations` (no progress for N cycles) | loop counter |
| User `Ctrl+C` / cancel | runtime |

Any hard stop halts and surfaces the trigger + state + suggested next
action.

#### Configuration

```yaml
execution:
  autopilot:
    max_iterations: 50
    max_stall_iterations: 3
    cancel_on_goal_change: true
```

#### CLI

```bash
/mb work --autopilot
/mb work --autopilot --budget 500000
/mb work --autopilot --max-iterations 20
/mb work --autopilot --dry-run     # show planned items + waves + estimates
```

#### Goal acceptance check

After each PASS item, the loop re-reads `goal.md`. If every
`acceptance` item is `[x]` (manually checked off by the user out of
band) or all linked plan stages are done, the loop sets goal status to
`done` and runs `/goal done` + `/mb done`.

#### Token cost

Per-iteration cost dominated by stage implement + review + verify
(~30–80k). 10 iterations ≈ 300–800k tokens. `--budget` and
`sprint_context_guard` are the practical limits.

---

### Component 7 — Prompt overlay system + addons

#### Resolution order

For every dispatch the engine resolves the role-agent prompt file:

1. `$HOME/.<host>/memory-bank/agents/mb-<role>.md` (user-global)
2. `<project>/.memory-bank/agents/mb-<role>.md` (project)
3. `<skill-bundle>/agents/mb-<role>.md` (base, shipped)

First match wins. Implementation: `scripts/mb-agent-resolve.sh <role>`
returns the resolved path; if multiple matches exist, the higher
precedence wins, no merging.

#### Addons

Small markdown fragments shipped under `agents/addons/`. Each addon is
~150–250 tokens. Prepended in the order listed in
`pipeline.yaml: agents.preamble_addons`. Empty array = current
behaviour.

Initial addon set:

- **`defensive.md`** — "You are an isolated subagent. You have no
  conversation history. Do not assume context that is not in this
  prompt."
- **`scope-lock.md`** — "You may only edit files listed in the stage
  DoD or referenced by Covers. You may not add new libraries,
  dependencies, files, or refactor outside the stated scope. If you
  believe scope is wrong, return EXPLICITLY with the reasoning; do not
  expand silently."
- **`fail-loudly.md`** — "If you cannot complete the task, return with
  an explicit blocker description. Do not fabricate code. Do not return
  partial code that looks complete. Do not invent file paths or APIs."
- **`read-before-write.md`** — "Before writing any code: read every
  file mentioned in the DoD, Covers, or stage body. Confirm the
  function/class/module exists before referencing it. Use Grep / Glob /
  Read tools to verify."

#### Configuration

```yaml
agents:
  preamble_addons: []                       # default empty
  # Recommended starter set for autopilot:
  # preamble_addons: [defensive, scope-lock, fail-loudly, read-before-write]
```

#### `mb-work` integration

When dispatching a Task, the engine builds:

```
prompt = (
    "\n\n".join(read_addons(preamble_addons))
    + "\n\n---\n\n"
    + read(resolve_agent(role))
    + "\n\n" + stage_context
)
```

If `preamble_addons` is empty and no overlay exists, the prompt is
byte-identical to today's.

#### `mb-debugger` integration

`mb-debugger.md` ships with the recommended addons hard-applied in its
own prompt (defensive + scope-lock + fail-loudly) — the diagnostic
agent is most at risk of fabrication.

#### Token cost

Each addon ~150–250 tokens. Four-addon stack ≈ 600–1000 tokens added per
dispatch. Negligible for `/mb work` stages that already cost 15–50k.

---

### Component 8 — Documentation deliverable (cross-cutting)

Each new component above ships with at least one user-facing page in
the existing `docs/` structure (Phase A scaffolding already in place):

- `docs/workflows/goal-driven.md`
- `docs/workflows/autopilot.md`
- `docs/workflows/debugging.md`
- `docs/features/worktree-isolation.md`
- `docs/features/parallel-waves.md`
- `docs/features/atomic-commit.md`
- `docs/features/token-economy.md`
- `docs/concepts/overlay-system.md`
- `docs/commands/goal.md`
- `docs/commands/debug.md`

`docs/README.md` index already reserves slots for all of these.

---

## Cross-component interactions

| Pair | Interaction |
|------|-------------|
| Goal layer ↔ `/mb work` | Autopilot reads `goal.md`; everything else orchestrates through existing `/mb work`. |
| Worktree ↔ Atomic commit | Atomic commits write to `mb-work/<slug>` branch; cleanup fast-forwards. |
| Worktree ↔ Parallel waves | Items in same wave share one worktree; file-conflict guard mitigates collisions. |
| Worktree ↔ Autopilot | `use_worktree: auto` is recommended for autopilot; warning if `off`. |
| Atomic commit ↔ Autopilot | Atomic commit per stage = recovery checkpoint; warning if disabled. |
| mb-debugger ↔ Autopilot | Debugger required (`enabled: true`); autopilot refuses to start otherwise. |
| Parallel waves ↔ Autopilot | Autopilot uses configured parallelism transparently; budget guard applies. |
| Overlay + addons ↔ All role-agents | Resolver runs on every dispatch; addons prepended; zero cost if empty. |
| Overlay + addons ↔ mb-debugger | Debugger ships with recommended addons baked into its own prompt. |

## Out of scope (explicit YAGNI)

- No goal-graph (dependencies between goals).
- No parallel active goals.
- No auto-derived `depends_on` from DoD heuristics.
- No worktree-per-stage or worktree-per-agent.
- No remote / cross-machine worktrees.
- No automatic PR/push per stage commit.
- No conventional-commits validation.
- No automatic squash on merge.
- No automatic tagging.
- No commits for FAILED stages.
- No cross-stage debugging.
- No real-time integration with pdb/gdb.
- No backfill of docs for existing features (separate later sprint).
- No structured "two-stage review" (kept for future spec).
- No per-agent model profiles (kept for future spec).
- No `/mb next` smart router (kept for future spec).
- No install profile addition for goal/autopilot in v1 (file-presence +
  `pipeline.yaml` flag are enough activation paths).

## Risks and mitigations

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Autopilot drifts off goal | M | `autopilot.max_stall_iterations`; goal acceptance check every iteration. |
| Debugger fabricates fix-plan | M | Strict JSON schema + parser; `require_confidence: medium` default; halt on `low`. |
| Parallel waves corrupt files | M | File-conflict guard (pre-wave + per-item snapshot); user owns `depends_on`. |
| Worktree leaks disk | L | `mb-work-worktree.sh clean --all` exists; documented in autopilot workflow. |
| Atomic commit lands `<private>` content | L | Gate 3 scans diff; auto-commit refuses with clear message. |
| Overlay system breaks existing dispatch | L | Resolver returns skill-base path when no overlay exists; empty addons array is the default; byte-identical prompt fallback. |
| Token budget explosion in autopilot | M | `sprint_context_guard`, `--budget`, per-iteration estimates with graceful fallback to sequential. |
| Goal layer rot (`goal.md` stale) | L | `/goal` (no args) shows last activity timestamp; weekly compact reminder could flag stale active goals. |

## Definition of Done (spec-level)

- [ ] All 8 components implemented behind opt-in flags or via overlay.
- [ ] Default behaviour byte-identical to today when every new flag is
      `off` and `preamble_addons: []`.
- [ ] `pipeline.yaml` schema extended; `mb-pipeline-validate.sh` accepts
      new fields; `references/pipeline.default.yaml` updated with new
      fields commented out.
- [ ] `references/design-principles.md` checklist passes for every
      component.
- [ ] Docs scaffolding (`docs/` index + overview) shipped; per-feature
      pages exist for all 7 new feature components.
- [ ] Tests: per-script unit tests; integration tests for autopilot
      loop end-to-end on a sample plan; rules-enforcer happy on new
      code; `mb-drift.sh` clean on this repo's bank.
- [ ] `CHANGELOG.md` documents each component under a single
      "goal-driven-autopilot" entry with opt-in instructions.
- [ ] No regressions in existing `/mb work` flow when all new flags are
      off (covered by tests).

## Self-review

- **Placeholders.** No `TBD` / `TODO` markers in the spec itself.
- **Internal consistency.** Cross-component interaction matrix
  cross-checked against each component section.
- **Scope.** 8 components — large but explicitly chosen Big Bang. The
  implementation order below decomposes into 7 sprints, none of which
  exceeds the 200k context budget.
- **Ambiguity.** Terms with overlapping meaning (`auto` in three
  different flags) are disambiguated in their respective component
  sections with explicit behaviour tables.

## Implementation order

Dependency-ordered. Each sprint is a separate plan file (`plans/`) and
fits within one 200k-token context window.

| # | Sprint | Components | Depends on | Risk |
|---|--------|------------|------------|------|
| 1 | Prompt overlay + addons | C7 | — | Low |
| 2 | mb-debugger agent + `/mb debug` | C3 | Sprint 1 | Low |
| 3 | Worktree isolation | C2 | — | Med |
| 4 | Atomic commit per stage | C5 | — | Low |
| 5 | Parallel waves (DAG) | C4 | — | Med |
| 6 | Goal layer + `/goal` | C1 | — | Low |
| 7 | Autopilot loop | C6 | All previous | High |

Sprint 1 ships first (low risk, improves every subsequent dispatch).
Sprint 7 ships last (consumes everything else).
