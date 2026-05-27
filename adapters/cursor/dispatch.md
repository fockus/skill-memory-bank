# Cursor — parallel pipeline dispatch

Cursor has no separate subagent spawn API, but the **orchestrator agent** can issue
multiple native `Task` tool calls in one response — the same pattern as Claude Code.

## Protocol

1. `/mb run` executor writes `wave-<plan>-<phase>-dispatches.json` under `.memory-bank/tmp/`.
2. Control returns to `commands/run.md`, which instructs the main agent to read the file.
3. The main agent issues **N `Task` calls in a single turn** (parallel when Cursor schedules them concurrently).
4. Each subagent writes its result to the `expected_artifact` path from the dispatch entry.
5. The executor resumes via `wait_for_artifacts` polling.

## Dispatch file shape

Same as Claude Code — see `specs/parallel-pipeline/design.md` §10.

## Model routing

Honour `pipeline.yaml` model aliases via `scripts/mb-pipeline-model-resolve.sh`.
Cursor subagents inherit the model selected for each `Task` unless the orchestrator
specifies a model in the Task prompt frontmatter.

## Fallback

If the orchestrator cannot parallelize (single Task per turn), sequential dispatch still
works. Emit stderr WARN:

```
[cursor-dispatch] sequential mode — issue all Task calls in one response for parallelism
```

## Worktree

Worktree-per-plan is agent-agnostic bash (`scripts/mb-worktree-*.sh`) — no Cursor-specific code required.

## Hooks prerequisite

Pipeline stages assume hook parity from `specs/cursor-extension/` (skill-bundle hooks,
`MB_AGENT=cursor`, global storage resolver). Install via `bash install.sh`.
