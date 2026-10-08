# Stage 1 managed producer — bounded model-free observations

Candidate evidence, **not Stage 1 acceptance, actual native-leaf proof or live TUI acceptance**. Historical smoke/RED/GREEN artifacts are preserved.

## Actual packages and runtime

Public SDK 1.0.2, Nico `pi-subagents` 0.76.0 and pinned `@tintinweb/pi-subagents` 0.19.0. Factories are loaded from their manifest-declared public entries; SDK peers resolve only public ESM exports. No private SDK/manager imports or new dependencies. The actual rendered owned MB extension is loaded alongside both actual backend factories in sandbox HOME. Package roots are configurable (`PI_SDK_ROOT`, `PI_NICO_ROOT`, `PI_TINTIN_ROOT`); the fixture discovers SDK root using local `npm root -g` when not configured. Source paths, real session IDs and generation IDs are recorded in `stage1-bounded-final-smoke.json`, without credential/settings dumps.

The fixture models operator startup by clearing only inherited native child/bridge markers in its isolated process. Product startup refuses those contexts rather than changing them. The first historical Nico readiness attempt inherited the retained worker's child marker and could not supply an active Nico service; that attempt was not compatibility PASS.

## Command and assertion result

Ran `node tests/fixtures/pi_native_sdk_host.mjs` with JSON `{home: <sandbox>/home, cwd: <sandbox>/project, scenario: real-tintin}`, sandbox HOME and configured already-installed package roots. Exit 0. Then independently asserted the resulting JSON (a caught fixture error is not accepted merely because Node exited 0).

Actual assertion output:

```text
PASS producer observations: SDK 1.0.2; Nico 0.76.0; Tintin 0.19.0; actual owned MB; 6 unique loaded components; 37 commands; after-bind/reload mentions off; real session/generation replacement; old API/disposal refusal; foreign settings/cwd unchanged; observed model/provider requests=0 and native spawn requests=0. NOT leaf runtime or TUI acceptance.
```

The six actual `getExtensions()` objects are builtin codemode/tool_search/MCP plus exactly one owned wrapper each for Tintin, Nico and MB. MB has 37 command registrations and `mb_dispatch_subagent`; consumer binding/public service readiness succeeds.

## Overlay and lifecycle observations

- Foreign project sidecar begins with mentions enabled and maxConcurrent=7. Product writes only its owned mkdtemp sidecar; the original sandbox foreign file remains byte-identical. Original cwd is restored before emissions are drained.
- The real Tintin factory emits attributed settings with `agentMentions=off` while executing the owned synchronous overlay.
- After public SDK TUI-mode context binding, `ExtensionRunner.emitInput('@main KEEP_PROJECT_CONTEXT', ..., 'interactive')` returns `continue`; a model-free before-agent-start hook probe produces no `agent_mention` reminder. No model prompt or native spawn is invoked.
- After public SDK settings/resource reload with a normal error-listener binding (required by SDK 1.0.2 to emit session_start on reload), the same real hook observations remain `continue`, no reminder, original cwd and mentions=off. Inventory remains unique and the old API refuses.
- Real SDK newSession changes the actual session ID and generation; old API access and disposal access refuse. Fixture late-event checks are separate consumer-contract evidence, not invented actual engine events.
- Read-only public before-provider-request and native RPC spawn observers report zero requests. This does not attest all network activity or an actual model/provider selection: no live credentials/model request is exercised.

A first reload probe used only mode with otherwise empty SDK bindings. SDK reload correctly did not emit session_start; its old context was stale. The fixture was corrected to exercise the documented bound-runtime path with onError, not by reusing stale ctx or replacing the runtime.

## Separately blocked leaf evidence

No real leaf was invoked. Supervisor authorized only a separate probe with a demonstrated guaranteed zero-request pre-model boundary; one focused source/API attempt found none for Tintin 0.19.0 public RPC. Public spawn replaces onSessionCreated; onSpawned exposes only an ID before asynchronous session construction; getRecord exposes session later. The runner's abort forwarding registers a future listener without checking an already-aborted signal, then unconditionally awaits session.prompt. Racing record inspection/stop would violate authorization. Actual native leaf model/tools/no-extension/no-nested proof remains BLOCKED. Common gate fixture session records are explicitly test doubles, not this missing proof. Exact capability observations and remaining DoD are in the authoritative bounded implementation report.
