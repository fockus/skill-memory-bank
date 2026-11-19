---
description: "Writes the closing report of a flow: changes, evidence, decisions, follow-ups. Use when a flow ends or a research route's result is the report."
allowed-tools: [Bash, Read, Write]
---

# /mb final-report

Write the closing artifact of a flow as a dynamic-flow step. For the `research`
route the report is the terminal artifact; for code routes it summarises the
merge-ready state. It reports facts already produced; it does not re-verify.

## Input

- `.memory-bank/goal.md` (end-state and acceptance criteria).
- Flow artifacts under `.memory-bank/reports/<run>/` (critique, risks, verify output).
- `git diff --stat` for the change scope.

## Output

`.memory-bank/reports/<run>/final-report.md` with:

1. `## Outcome` — met / partly met / not met, one line per acceptance criterion.
2. `## Changes` — files and behavior, from the diff.
3. `## Evidence` — verification commands and their output tails (quoted, not paraphrased).
4. `## Decisions` — decisions taken and their rationale; an ADR is added when one is significant.
5. `## Follow-ups` — open risks and out-of-scope findings.

## Steps

1. Collect the inputs; if an artifact is missing, list it under `## Follow-ups`.
2. Fill each section from artifacts only; no claim without evidence.
3. Print the report path and the Outcome line.
