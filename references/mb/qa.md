# /mb qa — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `qa <run [all\|<name>\|@<tag>\|<dir>/] \| new <name> \| list \| bugs>` — Acceptance QA: md scenarios in `<bank>/qa/test_cases/` run by the `mb-qa-runner` subagent (browser, CLI, API); strict report in `qa/runs/<run-id>/report.md`, bugs by severity in `qa/bugs.md`. See `commands/qa.md`
