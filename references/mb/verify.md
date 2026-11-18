# /mb verify — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `verify` — Verify plan execution (plan vs code)

### verify

Plan or spec verification — confirm that code matches the actual work source, all DoD items are satisfied, and nothing important is missing.

1. Set `VERIFY_TARGET` to the explicit user target when supplied. Otherwise use the current run's `source_path` (with `MB_WORK_RUN_ID` for parallel runs). Never choose the newest plan: if no trustworthy source is available, request the exact target. A spec-only bank is supported through `specs/<topic>/tasks.md`; an empty `plans/` does not skip verification.
2. Resolve and enumerate the exact source with the same helpers used by `/mb work`. `mb-work-plan.sh` handles plan wrappers, spec tasks, and their Covers/DoD/Testing metadata. A resolution error stops verification; it is not a passing result.

<!-- mb-verify:resolve -->
```bash
if [ -z "${VERIFY_TARGET:-}" ]; then
  VERIFY_STATE="$(bash "$SKILL_DIR/scripts/mb-work-state.sh" status --mb "$BANK")" || exit 1
  VERIFY_TARGET="$(printf '%s' "$VERIFY_STATE" | python3 -c '
import json, sys
state = json.load(sys.stdin)
path = state.get("source_path") if isinstance(state, dict) else None
print(path if isinstance(path, str) else "")
')" || exit 1
fi
if [ -z "$VERIFY_TARGET" ]; then
  echo "[verify] Specify the exact plan/spec target; current source is unavailable." >&2
  exit 1
fi
VERIFY_SOURCE="$(bash "$SKILL_DIR/scripts/mb-work-resolve.sh" "$VERIFY_TARGET" --mb "$BANK")" || exit 1
bash "$SKILL_DIR/scripts/mb-work-plan.sh" --target "$VERIFY_SOURCE" --mb "$BANK"
```

3. Run the Plan Verifier subagent with the emitted `source_path` and `source` category, resolved `BANK`, and verified item range. For `source=spec`, read sibling `requirements.md` and `design.md` as well as `tasks.md`; check each task's Covers/DoD/Testing and REQ coverage. Do not substitute a plan or infer requirements from memory.

The installed `plan-verifier` agent already carries `agents/mb-tooling-core.md` (graph tools such as `graph_impact` for blast-radius and `graph_tests` for coverage):

```
Agent(
  subagent_type="plan-verifier",
  description="Plan Verifier: plan verification",
  prompt="Source file: <emitted source_path: plan Markdown or spec tasks.md>
Source kind: <plan|spec>
Bank path: <absolute BANK>
Skill path: <absolute SKILL_DIR>

Context: <description of current work, which stages are considered complete>"
)
```

1. Get the Plan Verifier report and show it to the user.
2. If there are CRITICAL issues, **fix them** before proceeding.
3. If there are WARNING issues, tell the user and ask whether they should be fixed.

**Contract checkers (REQ-020/021):** when the spec's contract task is closed, run `bash "$SKILL_DIR/scripts/mb-contract-gate.sh" verify --spec <spec-dir> --mb "$BANK"` before the Plan Verifier verdict. Exit 1 = verification FAIL (a checker is still red). Exit 2 = the red-evidence gate refused and no checker ran; both halt verification. Specs without a contract task skip this step.

**Agreement Compliance (REQ-010/011):** if `<bank>/agreements.md` exists, the Plan Verifier reads
`## Active` and classifies every agreement against the plan + diff as `satisfied`, `violated`, or
`not-applicable`, rendered as an `## Agreement Compliance` report section. Any `violated` entry
forces the overall verdict to FAIL, with the explicit choice: fix the implementation, or
`mb-agree.sh add "..." --supersedes N`. No `agreements.md` in the bank → the step is skipped
silently (lazy contract, REQ-010 does not apply).

**IMPORTANT:** `/mb verify` is **REQUIRED** before `/mb done` when the work followed a plan or spec tasks. Do not close out either source without verification.
