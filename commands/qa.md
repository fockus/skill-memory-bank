---
description: "Runs md acceptance scenarios against a live product (browser, CLI, API) in a subagent, files bugs by severity. Use when asked «прогони приёмку», «QA», check a live stand."
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, Task, mcp__plugin_playwright_playwright, mcp__playwright]
argument-hint: "<run [all|<name>|@<tag>|<dir>/ …] | new <name> | list | bugs [--all]>"
---

# /mb qa: $ARGUMENTS

Acceptance QA, not a test framework: a scenario is a short md file, the `mb-qa-runner` agent walks it against the live
product like a user and records what it observes. Unit and e2e tests prove the code; `/mb qa run` proves the user path.

Set `SKILL_DIR` to the absolute directory containing the loaded `SKILL.md` (or `MB_SKILLS_ROOT`); run this setup in
the same shell as each command below. `<bank>` below is `$BANK`.

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:?Set SKILL_DIR from the loaded skill path}}"
source "$SKILL_DIR/scripts/_lib.sh"
BANK="$(mb_resolve_path)"
[ -d "$BANK" ] || { echo "[MEMORY BANK: ABSENT] — /mb init first"; exit 0; }
```

## Layout

```
<bank>/qa/README.md            target: stand URL or entry point, users, credentials source, fixtures, Diagnostics, Data rules
<bank>/qa/test_cases/**/*.md   one file = one scenario; subfolders group suites
<bank>/qa/fixtures/            files scenarios upload or feed
<bank>/qa/runs/<run-id>/       report.md + screenshots and output excerpts   (run-id = YYYY-MM-DD_HHMM)
<bank>/qa/bugs.md              bug registry, written only by scripts/mb-qa-bug.sh
```

## `new <name>`

Create `<bank>/qa/test_cases/<name>.md` (`<name>` may include a suite folder, `checkout/guest-pay`). If
`qa/README.md` is absent, create it with the sections `## Target`, `## Users` (logins and where the credentials are
read from — env var, secret store; never the secret itself), `## Fixtures`, `## Diagnostics` (commands that fetch
logs for a request id or time window), `## Data rules` (what scenarios may create and must delete).

```markdown
---
tags: [smoke]          # free-form; `run @smoke` selects by tag
driver: browser        # browser | cli | api
id: checkout-pay       # catalog cases only: the file stem
covers: [REQ-001]      # spec REQ ids, or DoD-<n> for a plan without REQs
origin: specified      # specified | derived | regression
proof: live            # live | test | both
status: needs_spec     # only when the expected result is not derivable from the requirements or DoD; omit otherwise
---
# <Title — the user goal>

## Preconditions
- <user, state, fixtures from qa/fixtures; no secrets>

## Steps
1. <one user action> → <observable expected result>
2. <one user action> → <observable expected result>

## Pass criteria
- <what must be true at the end>

## Cleanup
- <what the scenario created and how to remove it>
```

A good scenario: one user goal, steps the user would do, expected results a stranger can check on screen or in
output (text, status, count) in any locale and data state the README pins, no internal API URLs for `browser`
scenarios, no secrets anywhere.

Browser scenarios run in open-source Chromium: the CLI path passes `--browser chromium` and installs it on first use;
a Playwright MCP server should be started with `--browser chromium` too.

## `run [selector …]` (default `all`)

1. Select scenarios; several selectors give their union in file order:
   `all` · `<name>` (file stem or path under `test_cases/`) · `@<tag>` (frontmatter `tags:`) · `<dir>/` (a suite).
   Drop cases with `status: needs_spec` or `proof: test` from the list and pass them to the runner as `not_run`.
   Nothing left to run → say so and stop.
2. Create `<bank>/qa/runs/<run-id>/`.
3. Dispatch **one** `mb-qa-runner` with `skill_dir`, `bank`, `run_dir`, `run_id`, `selection` and the ordered file
   list (scenarios share one browser session, so one runner per run):
   - **Claude Code** — Agent/Task tool, `subagent_type="mb-qa-runner"`.
   - **Codex** — `spawn_agent(agent_type="mb-qa-runner", message=<same input>)`.
   - **OpenCode** — the Task tool with the `mb-qa-runner` subagent.
   - **Pi** — the pi subagent extension with role `mb-qa-runner`.
   - **Already a subagent, or no dispatch tool** — read `$SKILL_DIR/agents/mb-qa-runner.md` and follow it yourself.
4. Relay the runner's report: its title line, the `## Bugs` table and `## Not verified`, plus the report path. Do not
   re-run failed scenarios and do not soften statuses.

## `list`

Print each scenario as `<path> — <title> [tags] driver`.

## `bugs [--all]`

`bash "$SKILL_DIR/scripts/mb-qa-bug.sh" list --open` (or `list` with `--all`), critical first. Change a status after
triage or a fix: `mb-qa-bug.sh set BUG-NNN open|fixed|wontfix`. A bug that needs planned work is promoted like any
idea: `mb-idea.sh "[BUG-NNN] <title>" HIGH`.

## When to run

After a stand or build update and before calling a feature done. Inside `/mb work` it runs when `pipeline.yaml`
`qa.enabled: true`, the plan declares `qa: on`, or `/mb work --qa`: `qa.selector` at `qa.cadence`/`qa.position`, open bugs of the run over
`qa.gate` (default: any `critical` or `major`) send the item back to the implementer (`commands/work.md` § 5c2,
`docs/pipeline-yaml.md` § qa).

## Rules

- Scenarios hold user actions and visible results only; credentials are read at run time, never written down.
- A failed step is a finding, not something to work around.
- Do not run the project's unit test suite here; this command verifies the live product.
