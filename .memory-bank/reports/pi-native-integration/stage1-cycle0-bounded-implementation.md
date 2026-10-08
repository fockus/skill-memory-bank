# Stage 1 cycle 0 — bounded retained implementation checkpoint

## STATUS: BLOCKED

The remaining scoped checks are green and a minimal host regression is fixed, but **mandatory actual native-leaf runtime proof is unavailable through the demonstrated Tintin 0.19.0 public boundary**. This is not DONE_WITH_CONCERNS or Stage 1 acceptance. No real leaf/model was launched to race inspection/stop. Plan remains **0/5 accepted**; verifier, configured external Codex/main review, judge and parent acceptance remain open.

### Concrete blocker and what unblocks it

Supervisor authorized one separate model-free leaf inspection attempt only after establishing a public, guaranteed zero-model/provider/network-request pre-model boundary. Producer smoke remains separate with zero model/native-spawn requests.

Public Tintin documentation (`docs/cross-extension-rpc.md`, preserved as `dual-backend-scope/public-docs/tintin-rpc.md`) and actual pinned factory/funnel observations establish:

- `spawnTopLevel`/`spawnResolved` strips internal options and replaces `onSessionCreated` with the activity tracker's callback. Passing an observer there does not give the adapter an inspection boundary.
- Public `onSpawned` receives an ID before asynchronous SDK session construction. Public bound `getRecord(id).session` becomes available later; polling/racing stop would not guarantee zero requests.
- Actual 0.19.0 `src/agent-runner.ts` around lines 1013–1045 binds the child and invokes its internal session-created callback; lines 1089–1113 register abort forwarding and then unconditionally await `session.prompt`. `forwardAbortSignal` at lines 596–602 only adds a future abort listener, without checking an already-aborted signal. An already-aborted spawn signal therefore supplies no demonstrated safe inspection/no-request guarantee.
- No actual leaf startup was invoked. No extra leaf observer extension, callback replacement, private manager/SDK import, alternate executor, provider/role substitution or fallback was introduced.

Unblocking requires an upstream/documented public pre-model paused-start/inspection/abort or equivalent verified boundary, or an explicit owner scope/acceptance decision. The parent/upstream backend owner can decide that; this worker does not weaken the mandatory contract. Actual native leaf tools/provider/model/no-extension/no-nested evidence is **NOT proven by the test-double terminal session records or rendered profile headers**.

## Scope and retained identity

Read and consumed bounded-recovery-handoff, including the previously undelivered clarification: no temporary foreign config replacement; initial settings_loaded alone is insufficient; post-bind/reload/context and late-lifecycle evidence must be separate. Continued only the retained Stage 1 candidate. No broad implementation/reconnaissance restart, new dependency/model/download, real-host install/reload, commits/pushes/reset/stash or foreign edits.

Original baseline.json/baseline.diff, stage1-baseline.json, historical Nico RED/GREEN/report and failed/paused/timeout lineage receipts are preserved. AGR-057/058 authorize the same source/stage; approval is not API compatibility proof.

Existing slot `pi-native-openai-20261005-stage1` was not initialized/reset. Actual precheck ended implement despite the handoff prose saying verify. Appended verify through the existing parallel state mechanic:

```text
MB_WORK_PARALLEL=1 MB_AGENT=pi bash scripts/mb-work-state.sh step verify --run-id pi-native-openai-20261005-stage1 --mb "$PWD/.memory-bank"
exit 0
steps: [implement, verify, verify, implement, verify]
cycle: 0; max_cycles: 2; phase: in-progress; NOT done
source/topic/item and baseline_ref unchanged
```

First state attempt omitted MB_WORK_PARALLEL and correctly refused the missing single-slot path (exit 2); no init or manual JSON rewrite followed. Native Eval remains UNVERIFIED; no pytest receipt is treated as native Eval PASS. No plan/checklist checkbox was changed.

## Exactly five bounded product/test/reference changes

Hashes/modes compared with bounded-recovery-prelaunch/checkpoint.json; final hashes are in stage1-bounded-final-hashes.json:

1. `adapters/pi_native_bootstrap.mjs` — discard Tintin captured settings after settings_changed or non-factory settings_loaded, so a simple session rebind cannot republish stale authority.
2. `tests/pytest/test_pi_native_host.py` — **one new regression case**, settings-rebind.
3. `tests/fixtures/pi_native_sdk_host.mjs` — bounded actual post-bind/reload mention-hook observations, fresh-context/error-listener binding, diagnostic stack and read-only root request counters. No child execution.
4. `tests/bats/test_pi_agents_dispatch.bats` — only the previously approved import assertion block (#17), updated for the common backend's transitive public Nico/Tintin/preflight wiring; remaining assertions unchanged.
5. `references/pi-native-integration.md` — dual selection, managed startup/lifecycle/capability and honest blocked-leaf boundary.

The pre-existing native command/work/subagents/argv/extension/backend/roles/Tintin implementation and other tests are retained WIP from the previous writer, not reimplemented in this recovery. No files staged (`git diff --cached --name-only`: empty).

## RED → minimal GREEN

New pre-edit bootstrap/host SHA-256s: stage1-bounded-rebind-preimages.json. Actual business RED:

```text
.venv/bin/python -m pytest -q tests/pytest/test_pi_native_host.py -k settings-rebind
assert result["refused"] failed: rebind incorrectly reauthorized the stale settings snapshot
1 failed, 15 deselected in 0.78s; exit 1
```

After the two targeted snapshot invalidations:

```text
.venv/bin/python -m pytest -q tests/pytest/test_pi_native_host.py
16 passed in 9.21s; exit 0
```

Full logs: stage1-bounded-rebind-red.log and stage1-bounded-host-green.log. Historical Stage 1 managed-host/dual-backend RED and preimages remain separately preserved, including the four explicit backend-selection assertion failures (4 failed/13 deselected) before the retained backend implementation. This recovery does not overwrite those receipts.

## Fresh final scoped checks — actual output

```text
.venv/bin/python -m pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py tests/pytest/test_pi_native_backends.py tests/pytest/test_pi_native_host.py
73 passed in 105.37s (0:01:45); exit 0

PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_pi_agents_dispatch.bats
1..22; ok 1 through ok 22; exit 0

PATH="$PWD/.venv/bin:$PATH" bats tests/bats/test_pi_adapter.bats
1..16; ok 1 through ok 16; exit 0

.venv/bin/python -m pytest -q tests/pytest/test_mb_pipeline_named.py tests/pytest/test_mb_pipeline_work_integration.py tests/pytest/test_pipeline_yaml.py
16 passed in 1.76s; exit 0

ruff check adapters/pi_native_argv.py tests/pytest/test_pi_native_{commands,work,backends,host}.py
All checks passed!; exit 0
ruff format --check <same five files>
5 files already formatted; exit 0

node --check: eight native JS modules plus two fixtures; all exit 0
Python compile: five scoped files; exit 0
bash -n: seven reused state/pipeline/gate scripts; exit 0
git diff --check -- <assigned scoped files>: exit 0
```

Logs: stage1-bounded-final-native.log, stage1-bounded-dispatch-green.log, stage1-bounded-adapter.log, stage1-bounded-pipeline.log, stage1-bounded-static-green.log. Initial full suite was 72 passed in 101.00s; final 73 includes the new regression. Initial Bats #17 failed on the stale direct-Nico import expectation; its authorized test-only update now passes. Initial static command used nonexistent `.venv/bin/ruff`; rerun used the already installed `/opt/homebrew/bin/ruff`, with no installation. **Standalone type-check NOT RUN:** no tsc installed; successful SDK/Jiti loading is not type-check evidence.

## Real producer/overlay observations — separate from fake governed roles

Exact producer sources/versions/IDs/settings/inventory and assertion evidence: stage1-managed-host-smoke.md, stage1-bounded-final-smoke.json and stderr. Actual public SDK 1.0.2 + Nico 0.76.0 + pinned Tintin 0.19.0 + rendered owned MB extension loaded in sandbox HOME. Public readiness/MB consumer binding, six unique loaded components, 37 MB commands and mb_dispatch_subagent observed.

Actual JSON assertion output, exit 0:

```text
PASS producer observations: SDK 1.0.2; Nico 0.76.0; Tintin 0.19.0; actual owned MB; 6 unique loaded components; 37 commands; after-bind/reload mentions off; real session/generation replacement; old API/disposal refusal; foreign settings/cwd unchanged; observed model/provider requests=0 and native spawn requests=0. NOT leaf runtime or TUI acceptance.
```

Tintin factory-attributed mentions=off was observed after public TUI-mode context binding and relevant SDK settings/resource reload, not only the initial snapshot. Actual reserved-mention input remained continue and no agent_mention reminder appeared in the model-free hook probe; original cwd remained. Real newSession changed real session/generation IDs; old APIs and disposal refuse. Foreign sandbox sidecar is byte-identical. No foreign file was temporarily replaced. A first empty-bindings reload probe correctly had stale ctx/no session_start; the fixture was corrected using the public bound-runtime onError path, not by bypassing ctx guards.

No actual InteractiveMode.run, provider/model request, native child or real-host installation was performed. These observations do not prove arbitrary foreign customization preservation, a live current-parent provider/model, actual leaf tool scope or all possible late-engine callbacks. Fake consumer late-event/session-record tests remain labeled and separate.

## DoD facts supported and remaining

Supported candidate facts: mechanical context/start and aliases; default/named pipelines; legacy model aliases are not Anthropic grants; explicit run-specific cross-provider authorization regression; common selected-engine positives and verify/review/judge negatives; cancellation and recoverable artifacts; explicit unsupported external Tintin runner refusal; public producer inventory/settings/readiness/lifecycle; the new settings rebind fail-closed regression. Existing configured Codex reviewer model/thinking is not replaced with native overrides. Infrastructure paths do not introduce a fallback executor.

**Not yet satisfied:**

- **High / blocking now:** actual safe native-leaf runtime tools/provider/model/no-extension/no-nested proof, as above.
- **High / before Stage 1 acceptance:** complete required both-engine matrix (wrong-engine controls/conflicting continuation before any other-service traffic, role/model/tool drift, unknown/stripped options, malformed/cancel/consume/concurrency/resume and every negative gate). Current 73 green cases are not an assertion that every stated scenario is already parametrized for both engines.
- **High / before Stage 1 acceptance:** generalized original project/resource/provider/model/trust/customization preservation or diagnostic refusal. Current real smoke proves the sandbox cwd/config/inventory cases, not all customizations or cross-project restoration. In current driver order backend readiness can precede conflicting-resume identity checks; this needs a focused regression/assessment, not a fabricated no-side-effect PASS.
- **Medium / before release:** standalone TS check is unavailable here; independent static/runtime review still required.
- **Pending unchanged gates:** independent verify, external Codex plus main review, judge and parent acceptance. Stage 5 separately owns installer/entrypoint/actual TUI, live engines/model and memory/graph/vector acceptance.

No mandatory unknown capability is relabeled as a minor concern. Production wiring is candidate-only: the actual MB factory and consumer are reachable in the real SDK smoke, but the installed entrypoint and actual leaf contract are not accepted.

## Deviations / manual notes

Bounded work added only one regression fix and its observed RED, permitted test import correction, model-free observations and report/reference. The separate actual leaf probe was **not run** because the supervisor's pre-model/no-request condition could not be demonstrated. No deadline extension, broader implementation, private hook or package substitution was attempted. Self-review found mandatory logic/evidence gaps and therefore returns BLOCKED despite green scoped tests. Original evidence/source/cycle history and foreign shared-tree changes remain preserved.

```acceptance-report
{
  "criteriaSatisfied": [{"id":"criterion-1","status":"satisfied","evidence":"Concise BLOCKED checkpoint with actual RED/GREEN/static/producer output, exact five bounded changes and explicit mandatory residual risks; no Stage 1 completion claim."}],
  "changedFiles": ["adapters/pi_native_bootstrap.mjs","tests/pytest/test_pi_native_host.py","tests/fixtures/pi_native_sdk_host.mjs","tests/bats/test_pi_agents_dispatch.bats","references/pi-native-integration.md"],
  "testsAddedOrUpdated": ["tests/pytest/test_pi_native_host.py: one settings-rebind case","tests/fixtures/pi_native_sdk_host.mjs: real model-free after-bind/reload observations","tests/bats/test_pi_agents_dispatch.bats: approved import block only"],
  "commandsRun": [
    {"command":".venv/bin/python -m pytest -q tests/pytest/test_pi_native_host.py -k settings-rebind","result":"failed","summary":"Expected business RED: 1 failed, 15 deselected in 0.78s before the minimal fix."},
    {"command":".venv/bin/python -m pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py tests/pytest/test_pi_native_backends.py tests/pytest/test_pi_native_host.py","result":"passed","summary":"73 passed in 105.37s, exit 0."},
    {"command":"PATH=\"$PWD/.venv/bin:$PATH\" bats tests/bats/test_pi_agents_dispatch.bats","result":"passed","summary":"22/22, exit 0 after approved assertion update."},
    {"command":"PATH=\"$PWD/.venv/bin:$PATH\" bats tests/bats/test_pi_adapter.bats","result":"passed","summary":"16/16, exit 0."},
    {"command":".venv/bin/python -m pytest -q tests/pytest/test_mb_pipeline_named.py tests/pytest/test_mb_pipeline_work_integration.py tests/pytest/test_pipeline_yaml.py","result":"passed","summary":"16 passed in 1.76s, exit 0."},
    {"command":"ruff check and format --check scoped five Python files; node --check scoped ten JS files; Python compile; reused shell syntax; scoped git diff --check","result":"passed","summary":"All checks passed; 5 already formatted; syntax/compile/whitespace exit 0."},
    {"command":"sandbox real public SDK/both pinned factories/owned MB smoke plus JSON assertions","result":"passed","summary":"After-bind/reload mentions off, unique inventory, actual lifecycle IDs, old API/disposal refusal, cwd/foreign sidecar unchanged; observed model/native-spawn requests 0."},
    {"command":"Separate actual native-leaf inspection/startup/abort probe","result":"not-run","summary":"No demonstrated public guaranteed pre-model zero-request boundary; supervisor condition forbids racing launch/stop."},
    {"command":"Standalone TypeScript type-check","result":"not-run","summary":"No standalone tsc installed; no new dependency authorized."},
    {"command":"MB_WORK_PARALLEL=1 MB_AGENT=pi bash scripts/mb-work-state.sh step verify --run-id pi-native-openai-20261005-stage1 --mb $PWD/.memory-bank","result":"passed","summary":"Appended verify, cycle 0/max 2/source/history retained, phase in-progress, never done."}
  ],
  "validationOutput": ["73 passed in 105.37s","Bats: 22/22 dispatch and 16/16 adapter","Pipeline: 16 passed in 1.76s","Ruff: All checks passed!; 5 files already formatted","Producer assertions passed; actual native-leaf runtime proof remains BLOCKED"],
  "residualRisks": ["High: Tintin 0.19.0 has no demonstrated public safe pre-model native-leaf observation/abort boundary; actual leaf model/tools/no-extension/no-nested proof absent.","High: complete both-engine negative/control/resume/concurrency matrix and generalized customization preservation still need evidence or minimal fixes before acceptance.","Medium: standalone TS check unavailable; independent gates and Stage 5 live acceptance not performed."],
  "noStagedFiles": true,
  "diffSummary": "Five bounded scoped changes: stale-settings rebind safety regression/fix, real after-bind/reload observations, authorized Bats import correction and honest reference update; retained implementation otherwise preserved.",
  "reviewFindings": ["blocker: Tintin public RPC overwrites session-created observer and pre-aborted signal does not demonstrate a safe zero-request inspection boundary.","blocker: remaining mandatory both-engine/customization/runtime proof is not established by current fixture GREEN."],
  "manualNotes": "STATUS BLOCKED. Slot ends verify, cycle 0/max 2, source/history preserved, not done. 0/5 stages accepted. No real host/package/settings install, actual leaf/model call, new dependency, private import, fallback, commit or foreign edit. Parent/upstream capability decision is needed; no scope weakening is implied."
}
```
