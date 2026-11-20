# /mb qa — acceptance QA

<p class="mb-lede" markdown>Unit and e2e tests prove the code; `/mb qa` proves the **user path**.
A scenario is a short markdown file. The `mb-qa-runner` agent walks it against the live product
like a user would and records exactly what it observed.</p>

| | |
|---|---|
| **Use it for** | Checking a running product after a build or stand update, before calling a feature done |
| **Drivers** | `browser` (Playwright MCP or `@playwright/cli`), `cli`, `api` (HTTP) |
| **Writes** | `qa/runs/<run-id>/report.md` with screenshots and output excerpts; `qa/bugs.md` |
| **Hosts** | Claude Code, Codex, OpenCode, Pi |
| **Status in 5.4.1** | New in 5.4. Canonical reference: [`commands/qa.md`](../commands/qa.md) |

## Quick start

```text
/mb qa new checkout/guest-pay    # scaffold a scenario (and qa/README.md on first use)
/mb qa run @smoke                # run by tag
/mb qa run all                   # or everything
/mb qa bugs                      # open bugs, critical first
```

| Subcommand | What it does |
|---|---|
| `new <name>` | Creates `qa/test_cases/<name>.md`; `<name>` may include a suite folder |
| `run [selector …]` | Runs scenarios. Selectors: `all` · `<name>` · `@<tag>` · `<dir>/`. Several give their union |
| `list` | Prints each scenario as `<path> — <title> [tags] driver` |
| `bugs [--all]` | The registry: open bugs, or every bug with `--all` |

## Layout

```text
<bank>/qa/README.md            the target: stand URL or entry point, users, fixtures, diagnostics, data rules
<bank>/qa/test_cases/**/*.md   one file = one scenario; subfolders group suites
<bank>/qa/fixtures/            files that scenarios upload or feed
<bank>/qa/runs/<run-id>/       report.md + screenshots and output excerpts
<bank>/qa/bugs.md              the bug registry, written only by scripts/mb-qa-bug.sh
```

`qa/README.md` is the QA target. Its `## Users` section names logins and **where the credentials
are read from** — an env var, a secret store — never the secret itself.

## A scenario

```markdown
---
tags: [smoke]
driver: browser        # browser | cli | api
covers: [REQ-004]      # spec REQ ids, or DoD-<n> for a plan without REQs
origin: specified      # specified | derived | regression
proof: live            # live | test | both
---
# Guest pays by card

## Preconditions
- A guest session, one item in the catalogue

## Steps
1. Add an item, open the cart → the total is shown
2. Pay with the test card → the order page opens

## Pass criteria
- The order is listed as paid

## Cleanup
- Delete the order created by this scenario
```

A good scenario has one user goal, steps the user would do, and expected results a stranger can
check on screen or in output — text, a status, a count. No internal API URLs in `browser`
scenarios. No secrets anywhere.

## A run

<div class="mb-steps" markdown>

1. **Select**

    Cases marked `status: needs_spec` or `proof: test` are passed to the runner as `not_run`.

2. **Dispatch one runner**

    One `mb-qa-runner` per run: scenarios share a browser session.

3. **Walk**

    The runner performs each step and compares what it sees with the expected result.

4. **Report**

    A strict run report: title line, a `## Bugs` table, a `## Not verified` list.

5. **File bugs**

    Each finding goes to `qa/bugs.md` through `mb-qa-bug.sh` with a severity.

</div>

## The bug registry

| Severity | Blocks closure |
|---|---|
| `critical` | Yes |
| `major` | Yes |
| `medium` | No — listed in the report |
| `low` | No — listed in the report |

```text
mb-qa-bug.sh list --open
mb-qa-bug.sh set BUG-012 fixed          # open | fixed | wontfix
mb-idea.sh "[BUG-012] Order stays pending" HIGH   # promote to planned work
```

An open `critical` or `major` bug is a **firewall blocker** for `/mb work`, `/mb team` and
`/mb drive`. A fixed bug leaves a regression case behind under `qa/test_cases/`.

## QA inside the pipeline

QA is declared when the plan is written, not bolted on afterwards.

| Setting | Effect |
|---|---|
| `qa.enabled: auto` (default) | `on` for standard and larger plans when `qa/README.md` exists; `off` for small |
| `qa.enabled: true` · `false` | Every tier and every run · off |
| `/mb plan … --qa` · `--no-qa` | Force it for one plan |
| `/mb work --qa` | Force it for one run |
| `qa.cadence` | `stage` every item · `plan` last item · `run` last item of the run |
| `qa.position` | `before_review` or `after_review` |
| `qa.gate` | Max open bugs of the run per severity; default `{critical: 0, major: 0}` |
| `qa.prepare` | A shell command that refreshes the stand before every QA run |

`/mb plan` dispatches the `mb-qa` agent once to draft the test cases before any code exists. Inside
`/mb work`, open bugs of the run over `qa.gate` send the item back to the implementer.

## Limits in 5.4.1

- Browser scenarios run in open-source Chromium. The CLI path installs it on first use; a
  Playwright MCP server should be started with `--browser chromium` too.
- One runner per run, so scenarios execute in sequence, not in parallel.
- QA is skipped — not failed — when the bank has no `qa/bugs.md`. Without a QA target
  (`qa/README.md`) plans declare `qa: off — no QA target`.
- The runner does not edit product code and does not run the project's unit test suite.
- A project that copied an old `qa.enabled: false` keeps QA off: change it to `auto`.

!!! agent "For agents"
    1. A failed step is a **finding**, not something to work around. Do not re-run failed
       scenarios and do not soften statuses.
    2. Credentials are read at run time from the source `qa/README.md` names. Never write a secret
       into a scenario, a report or a bug.
    3. Dispatch exactly one `mb-qa-runner` per run. If you are already a subagent, read
       `agents/mb-qa-runner.md` and follow it yourself.
    4. Write bugs only through `scripts/mb-qa-bug.sh`. A regression case goes under
       `qa/test_cases/` and nowhere else.
    5. Relay the runner's title line, `## Bugs` table and `## Not verified` list, plus the report
       path.

## Related

- [/mb work — the execution engine](mb-work.md) · [/mb drive — the goal loop](mb-drive.md)
- [Routes, firewall and cost](routes-and-firewall.md)
- [`pipeline.yaml` schema](pipeline-yaml.md) (`qa:` section)
