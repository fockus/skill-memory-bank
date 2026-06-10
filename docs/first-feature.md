# Your first feature, end to end

A worked example of the full Memory Bank loop on a real task. Time budget: ~15 minutes of your
attention; the agent does the rest. We'll add a rate limiter to a small API project, but every
step is the same for any feature.

Prerequisites: the skill is installed (`pipx install memory-bank-skill && memory-bank install`)
and you're inside your AI agent (Claude Code, Cursor, OpenCode, …) in the project directory.

## Step 0 — initialize the bank (once per project)

```
/mb init
```

The agent creates `.memory-bank/` (status, checklist, roadmap, progress, plans/, notes/…),
detects your stack, and generates a `CLAUDE.md`/`AGENTS.md` pointing future sessions at the bank.
You'll see `[MEMORY BANK: INITIALIZED]`.

Optional but recommended for non-trivial codebases:

```
/mb map        # writes stack/architecture/conventions docs to .memory-bank/codebase/
/mb graph      # builds the multi-language code graph for structural queries
```

## Step 1 — start the session

```
/mb start
```

The agent loads `status.md`, `checklist.md`, `roadmap.md` and the active plan, then summarizes
where the project stands. On a fresh bank this is short; from session two onward this is the
moment you stop re-explaining your project.

## Step 2 — plan the feature

```
/mb plan feature api-rate-limit
```

The planner subagent writes `.memory-bank/plans/<date>_feature_api-rate-limit.md` with:

- stage breakdown (small, dependency-ordered stages),
- a SMART Definition of Done per stage,
- TDD requirements (which tests must exist and fail first),
- verification scenarios and edge cases (burst traffic, clock skew, multi-tenant keys…).

Read the plan. Edit anything you disagree with — it's just markdown in your repo.

> Bigger or fuzzier feature? Use the spec-driven path instead:
> `/mb discuss api-rate-limit` (requirements interview) → `/mb sdd api-rate-limit`
> (requirements/design/tasks spec triple). `/mb work` executes either form.

## Step 3 — execute

```
/mb work api-rate-limit
```

`/mb work` drives the plan stage by stage through the default pipeline
`implement → verify → done`. For each stage the matching role agent (here: `mb-backend`):

1. writes the failing tests first (TDD),
2. implements until they pass,
3. runs the verification commands from the stage's DoD,
4. flips the checklist item ⬜ → ✅ and moves to the next stage.

Want more rigor on critical code? Add gates per run:

```
/mb work api-rate-limit --review            # + structured code review with severity gate
/mb work api-rate-limit --review --judge    # + independent GO/NO-GO judge
```

## Step 4 — verify against the plan

```
/mb verify
```

The `plan-verifier` agent rereads the plan, inspects the actual `git diff`, and validates every
DoD item against real code and real test output — not against the agent's claims. If something
was skipped, you get a concrete list instead of a vague "all done".

## Step 5 — close the session

```
/mb done
```

This appends a session entry to `progress.md` (append-only log), updates `status.md` and the
checklist, and writes a knowledge note if something worth remembering was learned (e.g. "token
bucket chosen over sliding window — see ADR-007").

## The payoff: session two

Tomorrow — or three weeks from now, or from a teammate's machine, or from a different AI agent:

```
/mb start
```

The agent answers from the bank, not from guesswork: what's done, what's next, why the rate
limiter works the way it does. And if you forget the reasoning yourself:

```
/mb recall "why token bucket"
```

searches past sessions and notes for the decision.

## Where to go next

- [Composable `/mb work` pipeline](../commands/work.md) — flags, presets, `pipeline.yaml`
- [Code graph & semantic search](concepts/code-graph.md) — `/mb graph`, `/mb wiki`, concept queries
- [Cross-session memory](concepts/session-memory.md) — how `/mb recall` works
- [Troubleshooting](troubleshooting.md) — when something doesn't behave
