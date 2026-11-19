---
description: "Lists concrete risks of a change and author the failing repro test for a defect. Use when reproducing a defect or before merging."
allowed-tools: [Bash, Read, Write, Grep]
---

# /mb risk-find

Find what can go wrong with a change before it ships, as a dynamic-flow step
(the `bugfix` route uses it to author the failing repro test). It does not
duplicate `mb-qa` or `mb-reviewer`: it names risks and, on request, turns one
into a test.

## Input

- `<target>` — plan, spec, diff scope, or a bug description.
- `.memory-bank/goal.md` — acceptance criteria and constraints.
- Optional `--repro` — also write a failing test for the top defect.

## Output

`.memory-bank/reports/<run>/risks.md` with a table of risks, each row:
`id`, `risk`, `likelihood` (low|med|high), `impact` (low|med|high),
`evidence` (file:line or command output), `mitigation`. Sorted by
likelihood x impact. With `--repro`, the path of the new test and the
command output showing it fails for the stated reason.

## Steps

1. Read the target and the touched code (graph first: `mb-graph.sh impact <Symbol>`).
2. Check the usual sources: trust boundaries, data loss, concurrency, error
   paths, migrations, backward compatibility, missing tests.
3. Keep only risks with evidence; drop speculation.
4. With `--repro`: write the smallest test that fails for the right reason and
   run it; paste the failing output. Do not fix the defect here.
