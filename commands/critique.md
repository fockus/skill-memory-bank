---
description: "Critiques a diff, spec or plan against a checklist, retrying with the failed checks. Use when a flow needs a structured, checkable review step."
allowed-tools: [Bash, Read, Write]
---

# /mb critique

Produce a structured critique of one artifact (a diff, a spec, a plan) as a
dynamic-flow step. It adds a checked critique pass; it does not replace
`mb-reviewer` or the role-agents, and it carries no external dependency.

## Input

- `<target>` — path to the artifact (or `git diff` scope when omitted).
- `.memory-bank/goal.md` — acceptance criteria the critique is measured against.

## Output

`.memory-bank/reports/<run>/critique.md` (or the path the flow step names) with:

1. `## Findings` — each finding: `severity` (blocker|major|minor), `location`
   (`file:line` or section), `evidence` (quote or command output), `fix`.
2. `## Verdict` — one of `pass`, `pass_with_findings`, `fail`.
3. `## Not checked` — what was out of reach.

## Validator-feedback retry

The critique is validated before it is accepted:

1. Run the critique and write the output file.
2. Validate it against this checklist (all must hold):
   - every finding has severity, location, evidence and fix;
   - every blocker/major finding cites evidence that exists in the target;
   - the verdict is consistent with the findings (a blocker implies `fail`);
   - `## Not checked` is present;
   - every acceptance criterion in `goal.md` is mentioned as met, unmet or not checked.
3. If any check fails, feed the failed checks back (quote each one) and
   re-run the critique to fix only those points.
4. Retry up to N attempts (default 2 retries after the first run; override with
   `--max-attempts N`). Stop early as soon as the checklist passes.
5. If checks still fail after the last attempt, write the remaining failures
   into a `## Remaining failures` section and report them; do not loop further.

## Notes

- Read-only on the target; the only write is the critique file.
- Does not invoke other reviewers: for a multi-aspect review use `/review`.
