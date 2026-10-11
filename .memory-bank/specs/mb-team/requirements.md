---
type: spec-requirements
topic: mb-team — orchestrator-led parallel tracks in one working tree, with layered track pipelines, named resource locks, checkpoints and lens review cycles
status: draft
created: 2026-10-10
linked_design: design.md
linked_plan: ../../plans/2026-10-10_feature_mb-team.md
depends_on_specs: [dynamic-flow, drive-loop, reviewer-2.0, work-loop-v2]
relates_to: [parallel-team-execution, parallel-pipeline]
source_decision: "harness AGR-148 (2026-10-10, owner): the orchestrator process becomes /mb team"
authors: [Anton Ivanov]
---

# Requirements: mb-team

> EARS patterns: **Ubiquitous** (`The <system> shall <response>`), **Event** (`When <trigger>, the <system> shall <response>`),
> **State** (`While <state>, the <system> shall <response>`), **Optional** (`Where <feature>, the <system> shall <response>`),
> **Unwanted** (`If <trigger>, then the <system> shall <response>`). Validate with `scripts/mb-ears-validate.sh`.

## Context

For three days an orchestrator session (Claude Code) delivered an on-prem release by running a fixed process by hand:
a goal with acceptance criteria, parallel tracks on Memory Bank role agents, coordination only through the orchestrator,
one integration branch with orchestrator-only commits and checkpoints, a shared build lock with disk preconditions, and
lens review cycles until a clean cycle. Speed came from parallel tracks, reliability from coordination. The owner decided
(harness AGR-148) to make this process a Memory Bank command, `/mb team`.

Most building blocks already exist: `goal.md` + `mb-flow-verify.sh` (firewall and Stop guard), `/mb work` (per-item
engine with per-run slots under `MB_WORK_PARALLEL`), role agents, review ensemble + lead + severity gate,
`COORDINATION.md` + `mb-coord.sh`, `mb-agree.sh`, `mb-work-progress-append.sh`, the owner-token lock primitive in
`_lib.sh`, cost tiers and model profiles. What is missing is the glue: a team-run model, layered track pipelines, a brief
and track prompt rendered from configuration, named resource locks with preconditions and a fair queue, a checkpoint
command that also works with `arc`, a track-aware board, team status, collection, and team-level review cycles.

**Relation to `parallel-team-execution` (draft, frozen at 0/10).** That spec parallelizes units *inside one plan* with a
worktree per unit and a native Team transport. `/mb team` is the shared-tree flavour that was actually used: one
integration tree, file ownership plus locks instead of worktrees, coordination through a lead. REQ-PTE-010..014
(team mode) and REQ-PTE-030..032 (monitoring) are covered here for the shared tree; worktree-per-unit stays in
`parallel-team-execution`.

## Functional requirements

### A. Team run and tracks

- **REQ-TEAM-001** (Ubiquitous): The system shall represent a team run as one manifest `<bank>/reports/<topic>/team.json` holding the goal link, integration tree, optional read-only mirror, VCS kind, baseline revision, known-red tests, tracks, review cycles, checkpoints and commits.
- **REQ-TEAM-002** (Ubiquitous): The system shall give every track an id, task, role, resolved agent, size, resolved pipeline with per-field provenance, owned file globs, dependencies, resources, prompt path, report path and status.
- **REQ-TEAM-003** (Ubiquitous): The system shall let only the orchestrator write `team.json`, through `mb-team.sh`, with a lock and an atomic replace.
- **REQ-TEAM-004** (Event-driven): When `/mb team init` runs without `--no-goal`, the system shall require a `goal.md` that passes `mb-goal-validate.sh` and shall refuse to create the team otherwise.
- **REQ-TEAM-005** (Unwanted): If `mb-team.sh` is invoked with a working directory inside a Memory Bank directory, then the system shall refuse with a hint instead of creating a nested bank.

### B. Track pipeline — layered resolution

- **REQ-TEAM-010** (Ubiquitous): The system shall resolve each track pipeline over the closed keys `mode` (direct|work), `tdd` (required|optional), `verifier` (none|plan-verifier), `review` (none|single|lenses), `lenses`, `models.executor|verifier|reviewer|lead|lenses|lens.<name>` and `effort`.
- **REQ-TEAM-011** (Ubiquitous): The system shall apply layers in this order, later wins: size preset from `pipeline.yaml` `team.presets` (bundled default when absent) → `team.overrides` → team attributes given at `init` → track attributes → explicit instructions from the user prompt.
- **REQ-TEAM-012** (Ubiquitous): The system shall record, for every resolved key, the layer that set it.
- **REQ-TEAM-013** (Event-driven): When the user prompt states a pipeline choice explicitly, the orchestrator shall translate it through the documented closed vocabulary into `--layer prompt` attributes and shall echo the resolved table before dispatch.
- **REQ-TEAM-014** (Unwanted): If a prompt phrase does not map to the closed vocabulary unambiguously, then the orchestrator shall ask the user instead of guessing a value.
- **REQ-TEAM-015** (Ubiquitous): The system shall default the track size from the effort tiers in `references/effort-tiers.md` and shall map each size to a preset that keeps the tier's verification depth.
- **REQ-TEAM-016** (Unwanted): If a track resolves to `mode: work` without a plan or spec source, then the system shall refuse the track with a hint to create one.
- **REQ-TEAM-017** (Ubiquitous): The system shall resolve model values through the existing cost tiers and host model profiles, accepting a slot (`premium`, `mid`), an exact model id or `inherit`.
- **REQ-TEAM-018** (Unwanted): If a resolved model or effort cannot be applied by the host for that role, then the system shall report the mismatch and shall not substitute another value silently.

### C. Execution and reuse of `/mb work`

- **REQ-TEAM-020** (Event-driven): When a track with `mode: direct` is dispatched, the orchestrator shall dispatch its role agent once with the rendered track prompt and shall run the configured verifier and review steps after the agent returns.
- **REQ-TEAM-021** (Event-driven): When a track with `mode: work` is dispatched, the orchestrator shall run the existing `/mb work` loop on the track source under `MB_WORK_PARALLEL=1` with its own run id, passing the workflow, verifier cadence, lenses and step models derived from the track pipeline.
- **REQ-TEAM-022** (Ubiquitous): The system shall provide a stateless `mb-team.sh next` that prints the next actions (dispatch, verify, review, fix, collect, team review, stop) from `team.json`, the board and the reports, without dispatching anything itself.
- **REQ-TEAM-023** (State-driven): While a running track owns a file glob, the system shall not report another track whose globs overlap it as ready.
- **REQ-TEAM-024** (Ubiquitous): The system shall bound concurrent dispatched tracks by `team.max_parallel`.
- **REQ-TEAM-025** (Optional): Where a team budget is set, the system shall account track spend through `mb-work-budget.sh` and stop dispatching new tracks once the budget stop threshold is reached.

### D. Brief and track prompt templates

- **REQ-TEAM-030** (Ubiquitous): The system shall render the shared brief from a template with sections for sources and decisions, facts checked by the orchestrator, tracks, out of scope, inter-track contract, working tree, rules, resources, limits, known-red tests and report format.
- **REQ-TEAM-031** (Ubiquitous): The system shall render each track prompt from a template that links the brief and carries the task, owned files, dependencies, DoD, the resolved pipeline in words, the resource commands and the report contract.
- **REQ-TEAM-032** (Ubiquitous): The system shall render every path in a brief or track prompt as an absolute path and every Memory Bank command with an explicit `--mb <bank>`.
- **REQ-TEAM-033** (Unwanted): If the brief still contains an unfilled template hint, then the system shall refuse to report any track as ready.
- **REQ-TEAM-034** (Ubiquitous): The system shall require every track report to start with a `STATUS:` line from DONE, DONE_WITH_CONCERNS, BLOCKED, NEEDS_CONTEXT and to contain files, tests before and after with command output, remaining work, questions and follow-ups.

### E. Named resources and locks

- **REQ-TEAM-040** (Ubiquitous): The system shall declare named resources in `pipeline.yaml` `team.resources` with `kind: mutex`, `scope` (host|bank), start preconditions (`free_disk_gb` on `disk_path`, `check` command), a stop condition, an optional `maintenance` command and a watch interval.
- **REQ-TEAM-041** (Ubiquitous): The system shall provide `mb-lock.sh acquire|release|status|run|watch|break` over those resources.
- **REQ-TEAM-042** (Ubiquitous): The system shall grant a resource in first-come order through a ticket queue, so a released lock goes to the oldest live waiter.
- **REQ-TEAM-043** (Event-driven): When a waiter exits for any reason, the system shall remove its ticket, and any acquirer shall skip tickets whose process is provably gone.
- **REQ-TEAM-044** (Ubiquitous): The system shall never remove a lock whose holder or holder child process is alive.
- **REQ-TEAM-045** (Event-driven): When `mb-lock.sh run` acquires a resource whose start preconditions fail and a maintenance command is configured, the system shall run the maintenance command under the same lock, re-check, and exit 77 without running the command if the preconditions still fail.
- **REQ-TEAM-046** (State-driven): While `mb-lock.sh run` holds a resource with a stop condition, the system shall poll the condition and on breach terminate the command, release the lock, post a board entry and exit 76.
- **REQ-TEAM-047** (Ubiquitous): The system shall run maintenance commands only under the caller's own lock.
- **REQ-TEAM-048** (Ubiquitous): The system shall report in `status` the holder, its age and command, liveness, every queued waiter with wait time, and the current precondition values.
- **REQ-TEAM-049** (Ubiquitous): The system shall implement locks with POSIX tools and Python standard library only, with no dependency on `flock`, GNU-only flags or macOS-only commands.

### F. Coordination

- **REQ-TEAM-050** (Ubiquitous): The system shall extend the board grammar with `BLOCKED` (cancelled by a later `ACK` of the same scope) and `COMMIT`, and with a `--track <id>` option that prefixes the title with `<id>: `.
- **REQ-TEAM-051** (Ubiquitous): The system shall provide `mb-coord.sh tracks --json` with the latest entry per track and every open BLOCKED and HANDOVER.
- **REQ-TEAM-052** (Ubiquitous): The system shall instruct tracks, in the brief and the prompt, to report to the orchestrator only and never to message other tracks; a change of the inter-track contract goes through a HANDOVER and an orchestrator decision.
- **REQ-TEAM-053** (Ubiquitous): The system shall provide `/mb team status` combining `team.json`, the latest board entry per track, report STATUS lines, lock holders and queues, goal acceptance and the last review cycle.

### G. Branch, checkpoints, commits

- **REQ-TEAM-060** (Ubiquitous): The system shall provide `/mb team checkpoint [label]` that writes the tracked diff against the team baseline, a tar of untracked files, a manifest and a sha256 file, and `--verify <id>` that re-checks the hashes.
- **REQ-TEAM-061** (Ubiquitous): The system shall support git and arc integration trees through one small VCS seam.
- **REQ-TEAM-062** (Unwanted): If an untracked file exceeds the checkpoint size cap, then the system shall list it in the manifest as skipped instead of dropping it silently.
- **REQ-TEAM-063** (Ubiquitous): The system shall let only `/mb team commit` stage files, staging exactly the changed files owned by the selected finished tracks and listing every excluded foreign file.
- **REQ-TEAM-064** (Unwanted): If a changed file is owned by a selected track and by an unfinished unselected track, then the system shall refuse the commit and name the file.
- **REQ-TEAM-065** (Ubiquitous): The system shall contain no push, PR creation or destructive VCS operation.

### H. Review

- **REQ-TEAM-070** (Optional): Where `team.review.enabled` is true, the system shall run team-level lens review cycles over the integrated diff with the configured lens reviewers and the lead reviewer, storing `reports/<topic>/review/cycle-N/{<lens>.json,master.json,master.md}`.
- **REQ-TEAM-071** (Event-driven): When a cycle's master report exceeds `team.review.clean_when`, the system shall route each issue to its owner track as a fix and start the next cycle after the fixes return.
- **REQ-TEAM-072** (Unwanted): If `team.review.max_cycles` is reached without a clean cycle, then the system shall stop for the user.
- **REQ-TEAM-073** (Ubiquitous): The system shall render a self-contained prompt for an external reviewer that the user runs, and shall ingest its JSON findings into the next lead cycle after schema validation.
- **REQ-TEAM-074** (Ubiquitous): The system shall pass the list of known open items to every reviewer with the instruction not to reopen them without new facts.

### I. Collection and goal

- **REQ-TEAM-080** (Event-driven): When `/mb team collect` runs, the system shall append one progress entry per newly returned track through `mb-work-progress-append.sh`, list goal criteria with candidate evidence, list questions for `mb-agree.sh question`, list follow-ups for `mb-idea.sh`, and mark those tracks collected.
- **REQ-TEAM-081** (Ubiquitous): The system shall report `stop_success` only when every track is collected, the last team review is clean when team review is enabled, goal acceptance is 100 % and `mb-flow-verify.sh` exits 0.
- **REQ-TEAM-082** (Ubiquitous): The system shall keep known-red tests in `team.json`, render them in the brief, and require track reports to classify each failing test as new or known-red.

### J. Safety

- **REQ-TEAM-090** (Ubiquitous): The system shall state in every brief that tracks do not commit, push, change permissions or configuration, read secrets, or touch protected paths.
- **REQ-TEAM-091** (Unwanted): If a track returns a refusal from a safety filter, then the orchestrator shall escalate to the user and shall not re-dispatch the same task to another agent or model.
- **REQ-TEAM-092** (Ubiquitous): The system shall change a track model after dispatch only on an explicit user decision.

## Non-functional requirements

- **NFR-TEAM-001** (Compatibility): projects that never run `/mb team` behave byte-identically; the bundled `team:` block is read only by team scripts.
- **NFR-TEAM-002** (Portability): every script runs on macOS and Linux (bash 3.2+, Python 3.9+ stdlib); host differences (`stat`, `df`, `ps`, `sha256`) go through tested helpers.
- **NFR-TEAM-003** (Agent-native): no daemon or dispatcher process; the host agent dispatches; scripts are stateless brains plus single-writer state.
- **NFR-TEAM-004** (Determinism): status, readiness, layering, gates and stop decisions are computed by scripts with exit codes and JSON; judgment stays with the orchestrator.
- **NFR-TEAM-005** (Size): every new file stays under 300 lines; `commands/team.md` under 400.
- **NFR-TEAM-006** (Host parity): Claude Code is first-class; Codex and Pi dispatch the same roles with their own tools; mid-flight relay degrades to relay at track boundary on hosts without a message tool.

## Out of scope

- Worktree per track (stays in `parallel-team-execution`), automatic merge.
- Push, PR, release, automatic model fallback, inter-track messaging.
- A scheduler that preempts lock holders; lock priorities.
- Restoring a checkpoint automatically (the command prints the restore commands).
