---
type: spec-requirements
topic: goal-driven-autopilot
status: ready
created: 2026-05-23
linked_design: design.md
linked_tasks: tasks.md
---

# Requirements: Goal-driven autopilot

EARS-validated functional requirements. Patterns:

- **Ubiquitous:** `The <system> shall <behavior>.`
- **Event-driven:** `When <trigger>, the <system> shall <behavior>.`
- **State-driven:** `While <state>, the <system> shall <behavior>.`
- **Optional:** `Where <feature>, the <system> shall <behavior>.`
- **Unwanted:** `If <condition>, then the <system> shall <behavior>.`

Validated by `scripts/mb-ears-validate.sh`. Every REQ bullet is one line.

## Functional Requirements (EARS)

### Memory & configurability invariants

- **REQ-001** The skill shall preserve the existing `.memory-bank/` memory subsystem (status, checklist, plans, progress, lessons, notes, roadmap) unchanged by any new component delivered under this spec.
- **REQ-002** The skill shall keep every new behaviour disabled by default so that an unchanged `pipeline.yaml` and empty `agents.preamble_addons` produce byte-identical dispatch prompts and byte-identical `/mb work` execution to the pre-spec baseline.
- **REQ-003** Where the user opts in to any new component, the skill shall preserve that opt-in across `mb-upgrade` runs without overwriting user-owned configuration files.

### Goal layer

- **REQ-010** When the user runs `/goal init`, the skill shall ask between five and six questions covering project mission, team coding conventions, architectural constraints, stack notes, out-of-scope items, and the active goal description.
- **REQ-011** When the user runs `/goal init` and a prior `goal.md` exists with active status, the skill shall request explicit confirmation before archiving the prior goal.
- **REQ-012** When the user runs `/goal` with no arguments, the skill shall read only `goal.md` and the file referenced by its progress source field and emit goal title, progress percent, acceptance status, and linked plan path.
- **REQ-013** Where `pipeline.yaml goals.enabled` is false and `goal.md` does not exist, the skill shall respond to `/goal` invocations with a one-line activation hint and shall exit zero.
- **REQ-014** When the user runs `/goal done`, the skill shall set status done on `goal.md`, move the file to `goals/done/`, and append a summary entry to `progress.md`.
- **REQ-015** When the user runs `/goal` with a description argument and no decompose flag, the skill shall create `goal.md` without invoking `/mb discuss` or `/mb plan`.

### Worktree isolation

- **REQ-020** Where `pipeline.yaml execution.use_worktree` is always, the skill shall create or reuse an isolated git worktree under the cache directory before dispatching the first stage of `/mb work`.
- **REQ-021** Where `pipeline.yaml execution.use_worktree` is auto, the skill shall create a worktree only when `/mb work` is invoked with autopilot mode.
- **REQ-022** If a worktree ensure operation encounters a detached HEAD or a dirty working tree without force, then the skill shall refuse to create the worktree and shall emit an actionable error message.
- **REQ-023** While `/mb work` is executing inside a worktree, the skill shall dispatch all subagent Tasks with the working directory set to the worktree path.

### mb-debugger agent

- **REQ-030** Where `pipeline.yaml agents.debugger.enabled` is true and auto_on_fail is true, the skill shall dispatch the mb-debugger agent immediately after a plan-verifier verdict of FAIL.
- **REQ-031** When the mb-debugger agent returns its output, the skill shall parse the output with `scripts/mb-debugger-parse.sh` and shall treat malformed JSON as a halt condition.
- **REQ-032** If the mb-debugger returns verdict needs-human or verdict abandon, then the skill shall halt the `/mb work` loop and shall surface the root cause to the user.
- **REQ-033** If the mb-debugger returns verdict fixable with overall_confidence low, then the skill shall halt the loop and shall surface the proposed fix-plan without auto-applying it.
- **REQ-034** When the mb-debugger cycle counter reaches `pipeline.yaml agents.debugger.max_cycles` for a single stage, the skill shall stop the loop according to on_max_cycles and shall not exceed the configured cycle cap.
- **REQ-035** When the user runs `/mb debug` without apply, the skill shall produce a fix-plan and shall not modify any source file or re-dispatch the implementer.

### Parallel waves (DAG)

- **REQ-040** Where `pipeline.yaml execution.parallel_waves` is explicit and at least one work item declares `depends_on`, the skill shall compute a directed acyclic graph and shall dispatch all items of the same wave in a single Task batch.
- **REQ-041** If `scripts/mb-work-dag.sh` detects a cycle or a forward reference, then the skill shall refuse to start `/mb work` and shall emit the offending reference path.
- **REQ-042** While a wave is dispatched in parallel and any item in that wave returns a verify FAIL that is not recovered, the skill shall apply on_wave_failure and shall not start subsequent waves.
- **REQ-043** If the remaining budget is below the estimated wave cost, then the skill shall fall back to sequential dispatch within that wave and shall log the fallback decision.

### Atomic commit per stage

- **REQ-050** When a stage completes verify PASS and `pipeline.yaml execution.auto_commit_code` is stage, the skill shall create exactly one git commit containing files changed since the stage-start SHA.
- **REQ-051** If atomic-commit safety gate one detects a dirty working tree at the start of a stage, then the skill shall disable atomic-commit for the current `/mb work` session and shall log a warning.
- **REQ-052** If files staged for an atomic commit contain private content markers, then the skill shall refuse the commit and shall surface the offending files.
- **REQ-053** When the stage diff against the stage-start SHA is empty, the skill shall skip the atomic commit and shall log no-changes-committed.

### Autopilot

- **REQ-060** When the user runs `/mb work --autopilot` and `agents.debugger.enabled` is false, the skill shall refuse to start and shall emit a fix-hint pointing to the missing flag.
- **REQ-061** When the user runs `/mb work --autopilot` and `goal.md` is missing or its linked_plan or linked_spec is empty, the skill shall refuse to start and shall emit a fix-hint pointing to `/goal init` or `/goal set`.
- **REQ-062** While autopilot is running and no hard stop has fired, the skill shall iterate over pending items of the active goal linked plan or spec until all items reach PASS.
- **REQ-063** If autopilot max_iterations is reached, then the skill shall halt the loop and shall surface the trigger and the current item state.
- **REQ-064** If progress stalls for autopilot max_stall_iterations consecutive cycles without any PASS observed, then the skill shall halt the loop and shall surface the stall trigger.
- **REQ-065** When all linked plan stages or spec tasks reach PASS and the goal acceptance items are checked, the skill shall set the goal status to done, run `/goal done`, and run `/mb done`.

### Overlay system & addons

- **REQ-070** The skill shall resolve role-agent prompts in the precedence order user-global then project then skill-base, using the first match found.
- **REQ-071** Where `pipeline.yaml agents.preamble_addons` is a non-empty array, the skill shall prepend each named addon content to the resolved role-agent prompt in the declared order before dispatching a Task.
- **REQ-072** If a referenced addon does not exist on disk, then the skill shall refuse to dispatch the Task and shall surface the missing addon name.
- **REQ-073** When agents.preamble_addons is empty and no project or user-global overlay exists for the resolved role, the skill shall dispatch a Task with a prompt byte-identical to the pre-spec baseline.

### Documentation

- **REQ-080** The skill shall publish a user-facing documentation page under the docs directory for each new component delivered under this spec, matching the paths reserved in `docs/README.md`.

## Non-Functional Requirements (NFR)

- **NFR-001** Adding any single new opt-in component to a typical `/mb work` stage dispatch shall not increase token consumption of that dispatch by more than ten percent compared to the pre-spec baseline when measured on the project existing test plans.
- **NFR-002** Default-off behaviour of all new components shall be covered by automated tests that verify byte-identical dispatch prompts on at least one representative plan and one representative spec.
- **NFR-003** Subagent dispatch under autopilot shall respect the existing `sprint_context_guard.hard_stop_tokens` limit; no new long-running flow may exempt itself from this guard.
- **NFR-004** New scripts under the scripts directory shall pass shellcheck and shall follow existing skill conventions (`set -euo pipefail`, POSIX-compatible utilities, `mb_resolve_path` for bank discovery).

## Constraints + Out-of-Scope

- **CON-001** The memory subsystem (status, checklist, plans, progress, lessons, notes, roadmap, backlog, research) shall not change format, ordering, or semantics under this spec.
- **CON-002** The mb-upgrade script shall not overwrite user-owned files introduced or modified by this spec (pipeline.yaml, rules-profile.json, project agents overlays, project.md, goal.md).
- **CON-003** All new components shall be removable by reverting the relevant pipeline.yaml flags and removing any opt-in artefacts (goal.md, overlay files); no manual cleanup beyond that shall be required.

Out of scope:
- No goal-graph, no parallel active goals.
- No automatic PR / push / tag / squash on stage commits.
- No two-stage review, no per-agent model profile, no `/mb next` smart router — deferred to follow-up specs.
- No backfill of documentation for pre-existing features — separate later sprint.

## Edge Cases & Failure Modes

- **EDGE-001** First-time use on a project without `codebase/STACK.md` — `/goal init` falls back to manual entry for the Stack section without blocking.
- **EDGE-002** `mb-work-worktree.sh ensure` on a branch named `mb-work/<slug>` that already exists and is fully merged — the script shall reuse it transparently.
- **EDGE-003** `mb-work-worktree.sh ensure` on a branch named `mb-work/<slug>` that exists but is not merged — the script shall refuse without reuse flag.
- **EDGE-004** Autopilot starts, completes one stage, the user manually checks an acceptance item in `goal.md` — the loop notices on next iteration and may exit early if acceptance is complete.
- **EDGE-005** mb-debugger returns valid JSON with an unknown verdict value — parser exits non-zero; loop treats as needs-human fallback.
- **EDGE-006** Two parallel items in the same wave both touch the same file (DoD did not declare it) — collision surfaces in end-of-wave summary; user invokes `/mb debug` on the result.
- **EDGE-007** Atomic commit triggers on a stage whose work was a pure doc edit producing zero tracked-file changes — gate logs no-changes-committed, does not fail the stage.
- **EDGE-008** `agents.preamble_addons` references an addon name added in a future skill version — mb-upgrade ships new addons; validate-on-load surfaces missing addons before dispatch.
