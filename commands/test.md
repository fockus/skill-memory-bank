---
description: Run tests, analyze failures, and propose fixes
allowed-tools: [Bash, Read, Glob, Grep, Task]
argument-hint: "[test-filter]"
---

## 1. Run the suite

```bash
bash "${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-test-run.sh" --dir . --out both
```

The script detects the stack via `mb-metrics.sh`, runs the tests with per-stack parsing, and prints
structured JSON — `{stack, tests_pass, tests_total, tests_failed, failures[], coverage, duration_ms}` —
plus a human summary. It exits 0 even when tests fail; use `tests_pass` as the verdict for the rest of
this flow.

If `stack=unknown` or no runner applies, `tests_pass` is `null`. Offer to create
`.memory-bank/metrics.sh` (see `references/templates.md`).

If `$ARGUMENTS` provided a filter (test file, name, marker), pass it in the invocation context so the agent can narrow the run. Stage 3 of the runner does full-suite; filter support is follow-up work.

## 2. If `tests_pass == true`

Show the verdict + counts + duration from the agent's human summary. Done.

## 3. If `tests_pass == false`

For each failure (prioritize entries with `touches_session == true`):

- Read the failing test source and the code under test in full
- Check `.memory-bank/lessons.md` for known flaky patterns or recurring anti-patterns
- Classify: code bug vs. outdated test vs. environmental (flaky) issue
- Propose a concrete fix — show the diff
- Ask `y/N` before applying the fix (default = No)

The agent's `failures[].likely_cause` is a hint, not authority — always read the file yourself before proposing a fix.

## 4. If `tests_pass == null` (NOT-RUN)

Do not treat as pass. Report the reason (unknown stack, runner missing, zero tests collected) and offer the user a choice: install the runner, add `.memory-bank/metrics.sh`, or proceed without verification (flagged explicitly in the session log).

## 5. Memory Bank

If the run surfaced a recurring pattern worth remembering (flakiness, shared setup bug, environment issue), append to `lessons.md` using the template in `references/templates.md`.
