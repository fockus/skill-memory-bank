# Stage 1 · cycle 0 implementation

**STATUS: DONE_WITH_CONCERNS — implementation handed to verification, not Stage 1 acceptance or closure.**

Native `/mb`, `/start`, `/work` and collision-resistant `/mb-*` aliases now load through the real Pi Jiti factory. Context/start execute portable restoration without an LLM. Work resolves the selected bank/pipeline/item and executes named fresh roles through public pi-subagents RPC with bound outputs, state, cancellation, verification/review/judge gates, budget/protected-file checks and safe resume. Native models inherit the parent; opus/sonnet are not provider grants. Explicit cross-provider requests require an available provider-qualified model and invocation-specific owner authorization, persisted against the run. Configured codex-cli remains a deliberate external reviewer and receives no native model override.

## Scope and files

Product files:
- `adapters/pi_subagent_extension.ts`
- `adapters/pi_native_commands.mjs`
- `adapters/pi_native_subagents.mjs`
- `adapters/pi_native_work.mjs`
- `adapters/pi_native_argv.py` (allowed adapter-owned argv/strict-YAML decoder, using existing dependencies)
- `references/pi-native-integration.md`

Tests: `tests/pytest/test_pi_native_commands.py`, `tests/pytest/test_pi_native_work.py`, `tests/fixtures/pi_native_host.mjs`; **40 new pytest cases**, including parameterized cases. Two existing Bats assertions updated with explicit supervisor authorization, only in `tests/bats/test_pi_agents_dispatch.bats`' registration/import blocks. Other Bats tests and the legacy dispatch core are unchanged.

Original stage snapshot `stage1-baseline.json` preserved. Additional approved Bats scope has separate pre/post hashes and diffs (`stage1-extra-scope-baseline.json/.diff`, `stage1-extra-scope-after.json/.diff`). Before SHA256: `5ba0aa479bc3c1176248a8272eb81ea9a3a17e9c634b5c8005743202646c47c2`; after: `19e9eaa13480de6e46fe93226f16ee04c1eb0af513fa6e03cbe4570b27ba2a35`.

No commits, staging, pushes, resets, stashes, dependency installs or real-host extension installation. Bank plan/checklist/status were not closed. Owned slot `pi-native-openai-20261005-stage1` was initialized only after status showed no prior live slot; source/item binding retained. Final `step verify` exited 0. Portable state retains `phase: in-progress`, steps ending in `verify`, cycle 0, max_cycles 2; it is **not done**. The plan has no native Eval declaration surface (`decl.verdict: NOFILE`); native Eval is **UNVERIFIED**, not PASS.

## Observable RED → GREEN

Read required TDD, verification-before-completion and testing-anti-pattern skills at their exact superpowers paths; read approved design, full plan, project/global rules, coordination board, installed Pi SDK and pi-subagents public API docs. Graph was stale; used read/grep fallback. The documented `mb-work-resolve.sh --target` invocation is unsupported; its positional target form resolved correctly.

Initial command/work tests ran against the actual legacy extension factory, not static string assertions. After correcting harness-only placeholder/init-path setup mistakes, observed **24 behavioral failures in 5.09s**, pytest exit 1: prompt-only context/work, missing aliases and no RPC role dispatch. Additional gate cases preceded the work-driver implementation; **29 failures in 6.11s**, pytest exit 1. One shell wrapper printed tail's exit 0; `stage1-red.md` explicitly corrects that misleading wrapper receipt rather than calling the RED green.

Subsequent observed business-fact REDs before their fixes:
- Alias/resume/runtime-budget evidence: `3 failed, 2 passed, 22 deselected in 5.31s`, exit 1.
- Paused child with exitCode 0: `1 failed, 27 deselected in 1.28s`, exit 1.
- Judge acceptance/backlog/main-review binding: `3 failed, 28 deselected in 4.16s`, exit 1.
- Ensemble gate preservation: `1 failed, 31 deselected in 1.65s`, exit 1.
- Actual public preflight exposed `contract.model` with a thinking suffix. Updated fake DTO to match the real API; inheritance/authorization regressions gave `3 failed, 4 passed, 25 deselected in 5.53s`, exit 1. Known thinking suffixes are normalized only for identity comparison; native default launches still omit model overrides.
- Cancellation during spawn handshake: `1 failed, 32 deselected in 1.00s`, exit 1. The bounded reply handshake now retains the child id for stop/receipt rather than orphaning it on abort.
- Persisted owner authorization / fresh resume output binding: `2 failed, 4 passed, 27 deselected in 6.12s`, exit 1.

All RED logs and pre-fix source hashes are retained in `stage1-red.md` and named `stage1-*-red.log` files.

**Fresh final GREEN command:**
```text
.venv/bin/python -m pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py
........................................                                 [100%]
40 passed in 42.61s
GREEN_EXIT=0
```
Full output: `stage1-green.log`. Tests sandbox HOME; scripts/state/artifacts are real filesystem operations. Only remote children/public-RPC ownership and the default preflight fixture are doubles. A separate sandbox smoke called the **real public preflight API**, resolving four disposable named roles with the installed SDK, then fake RPC children:
```text
PASS: real public preflight resolved four sandbox agents; fake RPC children only. Not authentication or live launch proof.
PUBLIC_PREFLIGHT_EXIT=0
```
Full output: `stage1-public-preflight.log`. Preliminary smoke loader errors were corrected (ESM-only exports / packages exposing main); the actual model-suffix product RED was recorded before fixing it.

## Focused compatibility and static evidence

```text
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_pi_agents_dispatch.bats
1..22
ok 16 ... delegates native /mb registration to its sibling
ok 17 ... native command and public-RPC siblings, not the legacy executor
ok 18 ... unknown role never drops silently
ok 19 ... tmpfile setup failure returns dispatched:false
ok 20 ... role tools/system-prompt scoping
ok 21 ... exact Pi tool-name translation
ok 22 ... legacy thinking/parent behavior
ALL_DISPATCH_EXIT=0
```
All 22 passed. Before the approved surgical Bats adaptation, the suite was 20/22 with two implementation-placement assertions failing; retained separately as `stage1-legacy-static-red.log`. The new assertions retain tool/command registration and correct sibling/public API import obligations, accept single/double quotes, and prohibit the legacy executor import. Runtime pytest tests, not these static assertions, prove the native behavior.

```text
PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_pi_adapter.bats
1..16
ok 16 ... PI registry resolver
ADAPTER_EXIT=0

.venv/bin/python -m pytest -q tests/pytest/test_mb_pipeline_named.py tests/pytest/test_mb_pipeline_work_integration.py
13 passed in 1.46s
PIPELINE_EXIT=0

ruff check adapters/pi_native_argv.py tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py
All checks passed!
node --check adapters/pi_native_commands.mjs: exit 0
node --check adapters/pi_native_work.mjs: exit 0
node --check adapters/pi_native_subagents.mjs: exit 0
node --check tests/fixtures/pi_native_host.mjs: exit 0
Python compile: exit 0
Reused shell syntax: exit 0
Scoped diff whitespace: exit 0
```
Python compile used sandbox cache prefix. Shell syntax checked state/workflow/work-plan/pipeline scripts. TS factory actually transpiles/loads through installed Jiti; **standalone TypeScript type-check not run: no tsc available**. No whole-tree green/lint claim.

Foreign baseline check: **1160 non-bank, non-owned baseline files compared**. Sole mismatch `CLAUDE.md` consists of agreement-mirror additions including AGR-055/056; this worker never edited it and notified the parent. Preserved unchanged. Parent-owned bank changes excluded from this product comparison. Evidence: `stage1-foreign-integrity.json`. Git staged-files query returned `(none)`.

## DoD assessment and residual risks

Implementation-facing evidence satisfied:
- Real bank fixtures for local/registered-global/legacy/absent banks, native mechanic execution, quoted/semicolon argv safety and goal non-collision.
- Two distinct effective pipelines, including `.mb-config` named selection, with correct fresh named role order and real durable bindings/source identity.
- Negative verifier/reviewer/judge and malformed results, explicit cross-provider denial, missing agent, unavailable/ambiguous models, infrastructure failure, cancellation including spawn handshake, exhausted cycles, concurrency/source claims, budget/protected checks, stale main-review receipt and failed judge acceptance all refuse closure.
- Correct native default-provider inheritance, model suffix compatibility and deliberately selected external reviewer behavior; no inline or replacement CLI fallback.
- Safe resume re-verifies without resetting live state/cycles/budget; immutable initial identity and new attempt-specific output files preserve prior evidence. Backlog registration precedes done.
- Runtime registration is wired through the extension entrypoint and exercised by the loader harness.

**Not yet satisfied / parent-owned:** independent verify PASS, Codex + main-session review, judge acceptance and stage closure. Real Pi launch/authentication and installed runtime acceptance are not established by fixtures or preflight smoke. No next-stage authorization is claimed.

Residual risks / explicit deviations:
1. **Med — advanced profiles:** ensemble review and non-verify fix return steps currently fail closed before dispatch, rather than silently dropping gates. Existing-plan/spec execution with single-review profiles is implemented; planning workflows refuse native work until an executable source exists. Decide/extend these capabilities before claiming broad workflow parity.
2. **Med — installation/runtime:** packaging all helpers and inherited-model role definitions is deferred to planned Stage 5; do not install the changed TS file alone. No real-host rollout occurred.
3. **Med — recovery:** an unreconciled/cancelled implementation refuses automatic resume if no successful terminal receipt exists. Owner must reconcile package-owned child identity and partial diff before relaunching a writer. No transport fallback exists.
4. **Low — guard scope:** protected-path postchecks consume changed-file evidence; pre-mutation native tool guards remain Stage 4. This is not an OS sandbox.
5. **Low — validation limits:** no standalone TS compiler; Jiti loading and real public preflight smoke provide narrower API evidence. Full live execution/independent verification remain pending.
6. **Low — foreign baseline:** CLAUDE agreement mirror differs from the pre-AGR baseline and is preserved; parent notified. No blanket all-tree-hashes-unchanged claim.

Mechanical commands implemented natively are context/start/work. Other installed command templates route their own explicit agentic instructions; unknown/unsupported work options refuse. All templates have MB-prefixed aliases, while `/goal` remains unregistered. No installer/shared pipeline edits or stage checkbox flips.

```acceptance-report
{
  "criteriaSatisfied": [{"id":"criterion-1","status":"satisfied","evidence":"Concise implementation result, fresh RED/GREEN and compatibility receipts, scoped DoD gaps and rated residual risks are recorded above; stage remains open for independent gates."}],
  "changedFiles": ["adapters/pi_subagent_extension.ts","adapters/pi_native_commands.mjs","adapters/pi_native_subagents.mjs","adapters/pi_native_work.mjs","adapters/pi_native_argv.py","references/pi-native-integration.md","tests/fixtures/pi_native_host.mjs","tests/pytest/test_pi_native_commands.py","tests/pytest/test_pi_native_work.py","tests/bats/test_pi_agents_dispatch.bats"],
  "testsAddedOrUpdated": ["40 new pytest cases across two stage-owned files","Pi loader/public-RPC fixture","2 existing Bats assertion blocks updated with explicit parent approval; all other cases unchanged"],
  "commandsRun": [
    {"command":".venv/bin/python -m pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py (initial RED)","result":"failed","summary":"24 behavioral failures, then 29 with added gate cases; exit 1; retained logs/hashes"},
    {"command":".venv/bin/python -m pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py (final GREEN)","result":"passed","summary":"40 passed in 42.61s; exit 0"},
    {"command":"PATH=$PWD/.venv/bin:$PATH bats tests/bats/test_pi_agents_dispatch.bats","result":"passed","summary":"22/22; exit 0 after approved assertion adaptation"},
    {"command":"PATH=$PWD/.venv/bin:$PATH bats tests/bats/test_pi_adapter.bats","result":"passed","summary":"16/16; exit 0; sandbox HOME"},
    {"command":".venv/bin/python -m pytest -q tests/pytest/test_mb_pipeline_named.py tests/pytest/test_mb_pipeline_work_integration.py","result":"passed","summary":"13 passed in 1.46s; exit 0"},
    {"command":"sandbox real public pi-subagents/preflight smoke with configurable PI_SUBAGENTS_ROOT","result":"passed","summary":"Four disposable roles resolved through actual public API; fake RPC children; exit 0; not auth/launch proof"},
    {"command":"ruff check scoped Python files; node --check four MJS files; sandbox Python compile; reused-shell bash -n; scoped git diff --check","result":"passed","summary":"All checks passed / exit 0; outputs reproduced above"},
    {"command":"standalone TypeScript type-check","result":"not-run","summary":"tsc unavailable; real Jiti loading exercised instead"},
    {"command":"MB_WORK_PARALLEL=1 MB_WORK_RUN_ID=pi-native-openai-20261005-stage1 bash scripts/mb-work-state.sh step verify --run-id pi-native-openai-20261005-stage1 --mb $PWD/.memory-bank","result":"passed","summary":"exit 0; owned slot remains in-progress, not done"}
  ],
  "validationOutput": ["40 passed in 42.61s","22/22 dispatch Bats","16/16 adapter Bats","13 pipeline pytest cases passed","All checks passed!; Node/Python/bash/diff static exits 0","1160 foreign product hashes checked; sole preserved CLAUDE agreement-mirror mismatch"],
  "residualRisks": ["Med: ensemble/unsupported fix-return profiles fail closed; broad workflow parity not claimed","Med: helper packaging and real-host acceptance deferred to Stage 5","Med: unreconciled cancelled implementation needs owner reconciliation before writer resume","Low: pre-mutation guards are Stage 4; not an OS sandbox","Low: standalone TS type-check unavailable","Low: preserved parent CLAUDE agreement mirror differs from initial baseline"],
  "noStagedFiles": true,
  "diffSummary": "Native Pi command/role bridge and governed single-review execution with provider authorization, durable evidence, cancellation/recovery and regression tests; two approved compatibility assertions adapted.",
  "reviewFindings": ["No known failing scoped tests/static checks after fixes; independent verifier/review/judge pending","Explicit unsupported advanced profiles and real-host/packaging limitations remain documented"],
  "manualNotes": "This report does not close Stage 1. Native Eval is UNVERIFIED. The original baseline is preserved; no real host install, commits or stage checkbox flips occurred. Fixture children are not real Pi launch acceptance."
}
```
