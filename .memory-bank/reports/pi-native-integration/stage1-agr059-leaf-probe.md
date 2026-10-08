# AGR-059 separate native-leaf probe — STATUS BLOCKED

## Result and stopping point

**Neither backend was started. Actual native-leaf runtime evidence remains absent.** This retained child naturally inherits `PI_SUBAGENT_CHILD=1`; the actual managed composition root refuses operator startup before calling any SDK/factory. I preserved the guard and did not reuse the historical producer fixture, whose lines 14–15 explicitly clear ownership markers. No alternate agent, executor, CLI, transport, model or provider was launched.

Read AGR-059, the current plan/design probe paragraph, scope handoff, bounded assessment and active coordination board. Graph status was stale (110h); relevant public documentation/declarations and source inspection were the fallback. No plan/checklist/work-state/cycle/source/deadline changes; Stage 1 remains unaccepted, **0/5 accepted**.

Supervisor decision during this run: keep the inherited guard intact. A finite public-SDK test may subsequently execute in the **main parent's naturally non-child operator context**, after fixture review; that is parent-owned test execution, not authority for this child to clear guards. Tests that cannot run here are NOT RUN, not business RED or runtime PASS. Parent eligibility is supervisor-reported, not observed by this child.

## Observed eligibility assertion

Command (exit **0**):

```sh
node --input-type=module <<'JS'
import assert from 'node:assert/strict';
import { createManagedPi } from './adapters/pi_native_bootstrap.mjs';
assert.equal(process.env.PI_SUBAGENT_CHILD, '1');
let factoryCalls = 0;
await assert.rejects(createManagedPi({memoryBankFactory() { factoryCalls++; }}), /Managed operator startup is unavailable in a native child\/bridge context/);
assert.equal(factoryCalls, 0);
console.log('PASS eligibility boundary: inherited PI_SUBAGENT_CHILD=1 retained; actual createManagedPi refuses before SDK/factory/startup; factoryCalls=0. No leaf or transport instantiated.');
JS
```

Actual output:

```text
PASS eligibility boundary: inherited PI_SUBAGENT_CHILD=1 retained; actual createManagedPi refuses before SDK/factory/startup; factoryCalls=0. No leaf or transport instantiated.
```

This exercises the real guard at `adapters/pi_native_bootstrap.mjs:79`. No SDK/session/constructor/record double is supplied: the SDK argument is absent, and guard refusal occurs before SDK access. The callback only detects an erroneous factory invocation. This is a negative eligibility assertion, **not an actual native-leaf integration test or new failing business RED**.

## Public API feasibility — conditional, not isolated-runtime proof

Sources read from the actual installed/pinned packages:

- Pi SDK **1.0.2**: manifest public `.` export, `docs/models.md`, relevant provider documentation, and declarations for `ModelRuntime`, `ModelRegistry`, `AgentSession`, `ResourceLoader`, provider configuration and `SessionManager`. Declaration/source inspection does not mean importing their private subpaths: no private SDK imports were executed.
- Nico `pi-subagents` **0.76.0**: manifest, documented extension API and published shared declaration contracts.
- Tintin `@tintinweb/pi-subagents` **0.19.0**: pinned manifest/public extension entrypoint `src/index.ts`, documented RPC/service registry contract in the retained public-docs copy, and actual registry source.

Versions were read successfully from the package manifests; no package installation/download occurred. Source package locations for this audit only: SDK `/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent`; Nico `/Users/anton-one/.pi/agent/npm/node_modules/pi-subagents`; Tintin `/tmp/mb-pi-tintin-probe/package/package`. Future fixture roots must remain configurable/discovered; no such paths were added to product or fixtures.

**Transport:** documented `models.json` supports provider `baseUrl` and a literal synthetic `apiKey`; provider-specific model overrides exist. Public `ModelRuntime.create` supports `allowModelNetwork:false` and `refreshOnCreate:false`. Public `ModelRegistry.getApiKeyAndHeaders(model)` resolves `baseUrl`/auth, allowing a pre-launch routing assertion without a model request. `getProviderAuthStatus`/`isUsingOAuth` can distinguish synthetic configured authentication from OAuth. These are promising public seams, not proof that the inherited model's actual API honors that endpoint in a real native child.

Inherited provider/model IDs are **`openai/gpt-6.1-sol`**, recorded in retained launch/context evidence. The complete live parent model descriptor (API type, compatibility/thinking/input/context/cost metadata, model-specific endpoint/headers and customization provenance) was **not obtained or exported** in this child. Do not invent it, infer `openai-responses` from the provider name, manufacture a model alias, substitute a provider's streaming implementation, or change API type to make the simulation work. The main parent must obtain its actual public model descriptor before constructing a reviewed test. If its unchanged transport cannot honor documented loopback configuration, stop BLOCKED.

**Tintin observation:** documented manager registry `getRecord(id)` returns the actual top-level record; real source filters ownership and returns that manager record, not a synthetic JSON view. Once the genuine record's session exists, public SDK `session.model`, `getAllTools()`, `getActiveToolNames()`, **`getCallableToolNames()`** and `session.resourceLoader.getExtensions()` offer a candidate observation path. Checking only active tools misses callable/deferred delegation tools. There is no proven pre-model inspection boundary; isolated simulated transport must be established before spawn. Do not replace `onSessionCreated`, add an observer extension or race stop.

**Nico observation:** public status/nested summaries expose native run/session IDs/files and `runtimeAcknowledgedExtensions` with `source:"child-runtime"`; declarations explicitly distinguish it from `launchResolvedExtensions` intent. Acknowledgement is best-effort, with an `omitted` count, and is not extension health. A native session journal may supply public SDK model/system-message/tool evidence, but this pass did **not establish complete configured/callable-tool or resource inventory provenance** for the Nico child. Do not reconstruct another session and call that the original runtime, or use launch preflight allowlists as observed runtime evidence. Missing complete public evidence blocks that property independently of Tintin.

Some guessed documentation/source filenames did not exist; they were diagnostic read failures only. Relevant facts above come from the actual entrypoint, retained public documentation and existing declarations, not those missing paths.

## Required contracts before any parent launch

No safe runnable leaf fixture is delivered. No fixture plumbing was edited without an honest business RED. These are acceptance assertions to implement first in a subsequent explicitly scoped parent-context test, **not already-tested behavior**:

1. Natural operator eligibility: child/bridge ownership markers are not active, without deleting or forging them. The actual model descriptor and recorded identity are available and match exactly.
2. Isolated owned HOME/agentDir/project/session directories; no real auth copied, no credential commands, no inherited cloud credentials/proxies. Preserve ownership variables when constructing the test process environment. Disable public model-network refresh. Only explicitly approved factories/resources are composed, not extra observer extensions.
3. Configure only documented synthetic credential/loopback endpoint overrides for the unchanged API. Before any native spawn, resolve auth/routing publicly, assert literal `http://127.0.0.1:<owned-port>/...`, synthetic credentials, no OAuth, unchanged model contract and no fallback route. Validate model-specific overrides too. Identity/missing-route/non-loopback errors must fail before spawn; never test those negatives by allowing a real request. Unknown transport/routing capability stops the lane.
4. Local service binds loopback only, rejects wrong method/path/model/auth and redirects, bounds body size/requests/time, and emits harmless protocol-compatible text with no tool calls. Count simulated requests separately. A counter is observation, not outbound confinement. Document the chosen API's endpoint behavior/no fallback before using it; don't claim real-cloud isolation from absence of observed events.
5. For each eligible engine independently: actual owned child/session IDs, actual model descriptor, required tools present, both engines' delegation surfaces absent from **all configured and callable tools**, actual loaded extension policy, and provenance linked to that child's session. Missing public visibility remains BLOCKED even if the simulated answer succeeds.
6. Finally stop/cancel only owned children, await native terminal state, consume owned result where the public backend supports it, dispose owned SDK sessions, close the local service and remove only owned scratch resources. Capture IDs, terminal/consume acknowledgements and remaining resource inventory. Do not switch engines as fallback after a capability failure.

**Smallest safe command available now is the eligibility assertion above. There is no honest parent leaf-start command yet.** The existing SDK producer fixture must not be presented as such a command: it clears guards, never starts a leaf, uses observation hooks for a different claim, and lacks the inherited-model transport contract. A subsequent reviewed finite fixture must preserve guards and establish its pre-spawn isolation assertions first. Parent's natural context addresses eligibility only, not these transport/observation requirements.

## Per-backend runtime ledger

| Fact | Nico 0.76.0 | Tintin 0.19.0 |
|---|---|---|
| Probe status | BLOCKED before native startup | BLOCKED before native startup |
| Native startup command/exit | NOT RUN: inherited child eligibility refusal | NOT RUN: inherited child eligibility refusal |
| Actual child/session IDs | None created | None created |
| Actual leaf provider/model/tools/resources | UNVERIFIED | UNVERIFIED |
| Simulated service/model calls | 0; service not instantiated | 0; service not instantiated |
| Real-provider model calls | 0 by no launch/request path; not network-monitor attestation | 0 by no launch/request path; not network-monitor attestation |
| Owned children/local servers/temp resources | None created | None created |
| Cancel/consume/termination receipts | N/A: no owned child | N/A: no owned child |

Producer zero-model/zero-child smoke was **not rerun or modified**; historical GREEN and smoke logs remain separate evidence. No real-provider parity/TUI/live acceptance or no-nested runtime PASS is claimed. Independent verify/Codex/main review/judge/parent gates and both-engine matrix/customization gaps remain untouched.

## Preservation and validation

Only this authoritative report was written. Product, fixtures, tests and reference were not edited; tests added/changed **0**. Type/lint/full suites were **not run** for a report-only bounded probe, and historical GREEN is not relabeled as a fresh run. No staged files (`git diff --cached --name-only`, exit 0, empty output).

Read-only pre-edit SHA-256s (no code editing followed):

```text
68e275df44144015126a5530ef106f039038dad249bd28f0cb55765068cdd284 adapters/pi_native_bootstrap.mjs
ee8878f979f033e4f306db5a00e83a9dfc7368becaea7fd10498a1587fbd275d tests/fixtures/pi_native_sdk_host.mjs
0ecb5583601e2999dcc1ad45db3159baac4c3b91e8c01c11abebe4dbb30de75b tests/pytest/test_pi_native_host.py
549b0d87cc7699c2c270a5c7be46d53d4a8a611756923f67029b0009217b7e07 tests/pytest/test_pi_native_backends.py
5656627fbb11e652a85151ff40fce7e6d24ae86f1093c55a7d3f0bb33c84eaff references/pi-native-integration.md
```

Satisfied: concise bounded feasibility result, preserved native eligibility/identity constraints, no prohibited launch or edits, per-backend ledger and precise public prerequisites. Not satisfied: actual leaf/provider/tool/extension evidence, transport isolation/negative runtime tests, genuine fixture RED→GREEN and child cleanup receipts; no child was eligible/launched. Deviation: parent-directed read-only preparation replaces child leaf execution because ownership guard is binding. Residual severity **High** for actual runtime/transport evidence and Nico inventory completeness; resolve before claiming Stage 1 probe PASS. Stage acceptance remains parent-owned.

```acceptance-report
{
  "criteriaSatisfied": [
    {"id":"criterion-1","status":"satisfied","evidence":"Bounded per-backend BLOCKED ledger, actual guard assertion output, public API sources, precise isolation/observation prerequisites and residual risks recorded."}
  ],
  "changedFiles": [".memory-bank/reports/pi-native-integration/stage1-agr059-leaf-probe.md"],
  "testsAddedOrUpdated": [],
  "commandsRun": [
    {"command":"bash scripts/mb-coord.sh active","result":"passed","summary":"Active freeze read; no conflicting write or destructive git operation performed."},
    {"command":"mb-graph.sh status","result":"passed","summary":"Graph stale at 110h; read-only public-doc/source fallback used."},
    {"command":"node --input-type=module: real createManagedPi eligibility assertion","result":"passed","summary":"Exit 0: inherited child guard retained; actual composition refuses before SDK/factory access, factoryCalls=0."},
    {"command":"Native Nico/Tintin isolated leaf integration tests","result":"not-run","summary":"Inherited PI_SUBAGENT_CHILD=1; no safe unchanged-model transport fixture or complete per-backend observation contract established."},
    {"command":"git diff --cached --name-only","result":"passed","summary":"Exit 0, empty output; no staged files."},
    {"command":"Lint/type/full test suite","result":"not-run","summary":"Report-only bounded feasibility pass; no source/test/reference edits."}
  ],
  "validationOutput": ["PASS eligibility boundary: inherited PI_SUBAGENT_CHILD=1 retained; actual createManagedPi refuses before SDK/factory/startup; factoryCalls=0. No leaf or transport instantiated.","Manifest versions: SDK 1.0.2; Nico 0.76.0; Tintin 0.19.0."],
  "residualRisks": ["High: actual leaf runtime model/tools/extensions/no-nested proof absent for both engines.","High: documented endpoint override is conditional; unchanged inherited model API/metadata and no-fallback routing not established.","High: complete public Nico child configured/callable-tool and loaded-resource provenance not established.","Remaining Stage 1 matrix/customization, independent gates and Stage 5 live acceptance remain required."],
  "noStagedFiles": true,
  "diffSummary": "Only authoritative probe report added; existing implementation, fixtures, reference, source/history/cycles and producer evidence unchanged by this worker.",
  "reviewFindings": ["blocker: adapters/pi_native_bootstrap.mjs:79 - naturally child-scoped retained worker is ineligible for managed operator startup; refusal correctly preserved.","blocker: transport and actual per-backend runtime observation contracts remain unverified; no native leaf launch authorized in this process."],
  "manualNotes": "Supervisor explicitly preserved guard and reserved finite reviewed test execution for main parent's natural operator context. No fixture prepared without genuine RED; no unsafe startup command supplied. STATUS BLOCKED; 0/5 accepted."
}
```
