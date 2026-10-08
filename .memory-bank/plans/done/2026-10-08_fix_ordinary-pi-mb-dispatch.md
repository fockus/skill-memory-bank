# Ordinary Pi Memory Bank dispatch

**Type:** fix
**Status:** done (2026-10-08, owner request; Stage 1 verified)
**Owner:** Pi parent, sole writer by explicit owner handover (2026-10-08).
**Decision:** AGR-090 and inline bootstrap override AGR-091; ADR-014 and ADR-015.
**Coordination:** Read COORDINATION.md before shared-file edits; existing Pi integration WIP stays intact.

## Goal

Enable the installed MB extension to dispatch named roles through pinned Tintin in ordinary Pi, without replacing Pi or creating another executor. Preserve the optional managed entrypoint and repair its installed ESM launcher.

## Design

The ordinary extension composes the public Tintin factory itself, records actual factory settings and its public registry, and publishes process-local authority bound to the session_start context. Child/bridge contexts never activate this root. Startup refuses an existing Tintin service, incompatible packages or unsafe settings. Shutdown, reload, session replacement and settings changes invalidate authority. Tool calls retain model/provider and tool-scope checks and never fall back to another engine. The existing SDK composition continues to supply its own binding without a second service.

<!-- mb-stage:1 -->
## Stage 1: Ordinary extension activation and installation

**Role:** developer
**Status:** done (2026-10-08)
**Files:** adapters/pi_subagent_extension.ts; adapters/pi_native_host.mjs; adapters/pi_native_bootstrap.mjs; new pi_native component/ordinary helpers; tests/fixtures/pi_native_ordinary_host.mjs; tests/pytest/test_pi_native_ordinary.py; references/pi-native-integration.md.

**Testing:** Behavioral RED before new startup code; real installed public SDK and pinned Tintin in sandbox HOME, no mocked child evidence. Targeted existing native host/command/backend/install tests, Node syntax and Python lint. Live smoke after installation must record a distinct child and an actual read call; a launcher-only or producer-only pass is not child acceptance.

**DoD:**
- [x] Ordinary SDK/Pi startup exposes MB dispatch with an attributed Tintin binding and mentions off; no parent/child model calls during startup.
- [x] Duplicate services, changed settings, shutdown and stale session contexts refuse dispatch; child contexts do not activate an ordinary root.
- [x] Managed bootstrap retains its binding without duplicate Tintin activation.
- [x] Existing ESM launcher fix passes sandbox installation checks and is safely installed with ownership tracking.
- [x] Targeted integration tests and changed-file static checks pass.
- [x] Real installed ordinary Pi launches a named MB leaf with inherited model and expected tools; result and cleanup are observed.
- [x] Independent verification and project completion gates are recorded separately; no stage is accepted solely from fixture results (see "Independent verification" below).

## Evidence (2026-10-08)

- Startup RED: 7 failed / 1 passed; ordinary session had no binding. Logs: process proc_74f2.
- Native regression suite: 118 passed (proc_4b2b); final authority/ordinary suite: 28 passed and Pi dispatch Bats: 22/22 (proc_5b35).
- Actual SDK/Tintin child integration with only external HTTP simulated: one real read tool result, distinct child session, inherited openai/gpt-4.1 fixture model, tools [read], no child extensions, consumed terminal and no running children.
- Node syntax, Ruff, ShellCheck and authoritative generated-template TypeScript compilation exit 0. Raw-template LSP warnings remain inferred-project/module-placeholder advisories, not generated-template failures.
- Owned installer and mb-pi --help exit 0 (proc_5a3d). Hashes of settings.json, auth.json and the ordinary pi launcher are unchanged.
- Completion firewall acceptance probe exits 1 on unrelated paused G-001 (sdd-vision-pipeline). This plan and the original Pi-native plan remain open; no goal, original stage acceptance or source checkboxes are forged.
- The first two CLI probes had open piped stdin and no session output: proc_302d was stopped; proc_9c93 hit its finite 90 s timeout. Bare Pi and MB-only --help both exit 0. Corrected ordinary-Pi probe proc_04d4 closes stdin and reaches real parent model requests; its CLI-default opencode-go/deepseek-v4-pro fails API 400 because the workspace region policy does not permit that Go model (requires Global). It issues no MB dispatch and times out after 120 s even after agent_settled. Live-provider child acceptance remains BLOCKED; do not change privacy or switch providers as an automatic fallback. Repeat in the reloaded current Pi with its working live model or an explicit owner-selected root model. Unrelated pi-supervisor dependency warning was observed but not changed. A direct mb-researcher/Tintin call in the current pre-install parent still returns the old managed-entrypoint prerequisite without launching a child. Restart ordinary Pi to guarantee fresh sibling ESM modules; hot /reload alone has not been demonstrated to invalidate pre-install Node ESM caches.

## Latest verification (owner request: check ordinary Pi)

- Clean native suite: 174 passed, 0 errors (proc_a9b5); Pi adapter/dispatch/session-memory Bats: 49 passed (proc_5658). The preceding suite's checkout guard detected our parallel live smoke writing .pi artifacts, not an assertion failure; its targeted recheck and the subsequent whole native suite both pass. Do not run checkout-writing smoke probes concurrently with that guard.
- Installed 13 native helpers match source bytes; the installed MB template matches after installer trailing-newline normalization and its owned ledger hash matches. Launcher --help, Ruff, Node syntax, generated-template TypeScript and ShellCheck error gate pass. Full ShellCheck also reports existing SC2034/SC2016 advisories in adapters/pi.sh; no unrelated fixes applied.
- Active parent identity is openai/gpt-6.1-sol from PI_PROVIDER/PI_MODEL. Root CLI probes select that same model only for the invocation; no persistent model/provider/privacy settings changed and no child model override or engine fallback used. Global settings.json and the ordinary pi launcher still match the pre-install baseline. auth.json differs from that earlier baseline; attribution is not established and credentials were not inspected or restored.
- Real live-provider MB-only ordinary CLI --print probe (proc_3fd1) returns the held-out file marker and exits 0 in 21 s. Tintin child c76caaf3-c322-423 / owner run mb-role-7df0d160-25f2-417b-aec1-269076d258c6 has a successful complete receipt on openai/gpt-6.1-sol. This proves live dispatch/result/normal process termination in that scope, not actual CLI child extension inventory or a recorded child read toolResult; the stricter read/inventory observation remains fixture-backed.
- Full-profile controlled probe (proc_69bc), same model/task/cwd/MB_PATH and --print, returns the marker via successful child 2f6fa6c1-636a-45c and reaches agent_settled, but the process hangs until its 90 s timeout. MB-only discovery exits normally; the responsible extension/interaction is not established. All probe processes are now terminated.
- Current chat discovery and its inspect snapshot contain no mb_dispatch_subagent; /mb is prompt-sourced, not a native command. Fresh processes register it correctly. Current-session startup/reload cause remains unresolved. Live acceptance and this stage stay open despite green regression tests.

## Remaining-blocker repair (owner-authorized)

- Full-profile hang reproduced independently of model requests through the public SDK: installed pi-inspect 0.5.0 retained its request fs.watch after shutdown. RED: shutdown and reload each timed out with one referenced FSEventWrap (proc_d408); request handling also retained its deduplication timer (proc_dff6).
- Patched only installed ~/.pi/agent/npm/node_modules/pi-inspect/extensions/inspect.ts: close the owned watcher, clear owned expiry timers and context references on session_shutdown; a superseded API cannot close another owner's watcher. No forced exit, provider/privacy change or foreign settings edit. Backup: /tmp/mb-pi-lifecycle-diagnosis.kbqFG0/inspect.before.ts. This local 0.5.0 patch can be overwritten by a package update; an upstream release containing cleanup replaces it.
- Added tests/fixtures/pi_native_lifecycle_host.mjs and tests/pytest/test_pi_native_lifecycle.py. Public SDK shutdown/reload/request cleanup and actual installed MB file-loader cold/reload registration pass without model requests. The host supplies onError binding, as required for SDK reload to emit session_start; no private APIs or simulated registrations. Final targeted run: 16 passed, Ruff and Node syntax pass (proc_c07c); installed inspector TypeScript against the actual SDK and its existing open dependency exits 0. LSP reports no errors, with JavaScript clean status inconclusive; authoritative syntax/type checks remain separate evidence.
- Full-profile ordinary live probe now returns the held-out marker through Tintin child 31c9b734-b877-4d9 on inherited openai/gpt-6.1-sol and exits normally with code 0 in 27 seconds (proc_83a8). No extension exclusion or forced termination. Receipt is complete/success; actual CLI child read-tool/inventory observation remains narrower than the HTTP-boundary fixture evidence.
- Current Pi PID 49237 started at 16:52:03, before the updated MB extension/helpers were installed at 19:08:56/57. Its current tool discovery still has no mb_dispatch_subagent; fresh installed file-loader startup and reload expose both the active tool and native mb command. A complete user-controlled restart is required to replace this historical process and release its old untracked inspector watcher. Do not fabricate a binding in the old process; current-chat acceptance remains pending until restart and a direct native call.
- Read-only native mb-debugger investigation proc_6227 exceeded its finite 180-second budget and produced no accepted result. It is not independent verification or a stage-completion receipt. Original Pi-native acceptance and paused G-001 remain unchanged.

## Current-chat acceptance (2026-10-08, owner-requested check)

- Restarted ordinary Pi session 01a11bc9-59d9-74eb-838e-cde28594e2f6 registers the native tool: inspect snapshot lists mb_dispatch_subagent in tools and activeTools (70 tools / 57 active), and commands list `mb`, `mb-context`, `mb-start` and `mb-work` with `source: extension`. `scripts/mb-context.sh <bank>` prints `[MEMORY BANK: ACTIVE]` context; its piped invocation did not independently preserve the script's exit status.
- Native dispatch 1 (in-chat call, role mb-researcher): held-out marker MB_CURRENT_PI_READ_5a91cc3fc10041118e2902586180306d returned verbatim. Receipt: runId mb-role-e3f61a71-f8ae-4223-9db9-2d570e751c1d, engine run d9e41689-7f65-423, state complete, success true, exitCode 0, backend tintin, child mb-leaf-cab72341fda77304e7f5 on inherited opencode-go/deepseek-v4.1-flash (= parent PI_PROVIDER/PI_MODEL).
- Native dispatch 2 (role plan-verifier): independent PASS on the same marker with raw bytes and SHA-256 2bc2536f5f61c94695ea2e90a8910e4d00e8674c33a3fd8c91eb7130c1f3b1ca. Receipt: runId mb-role-3f06f132-a38b-46ec-8278-0c45bdc652ad, engine run 37e0d16d-94f8-487, complete/success/exit 0, backend tintin, child mb-leaf-9e56157936e57840afd3 on the same inherited model.
- Child profiles preserve the contract: tools bash/read/grep/find, extensions [], allowNestedSubagents false, mb_origin_agent set, no residual mb-leaf or pi-subagents processes after both dispatches. No provider override, engine fallback or persistent settings change. This satisfied the ordinary-Pi live-smoke DoD item; the independent verification and gate recording follow below.

## Independent verification (2026-10-08)

- Native dispatch of role plan-verifier re-checked Stage 1 against repository, installed and runtime state rather than plan prose: PASS on DoD items 1-6 with 57 tests passed (ordinary 12 + lifecycle 4 + install 25 + host 16), zero RULES violations, Ruff plus ShellCheck -S error, node --check and bash -n clean, ownership ledger 47/47 sha256 match, mb-pi --help exit 0, installed helpers byte-identical to adapters/, marker file bytes equal to both live result.md payloads, and no residual child processes. No stubs or placeholders found in the new helpers or tests.
- Recorded warning: the live child's model/tool inventory is proven by the fixture contract and by the receipt lines above, not re-derivable from result.md alone.
- Project completion gates are recorded separately: the goal firewall mb-flow-verify.sh .memory-bank stays RED on the unrelated paused G-001 (sdd-vision-pipeline). That is not falsified or changed; the original Pi-native plan remains 0/5 and this slice claims neither its acceptance nor a goal closure.

## Pre-commit follow-up (2026-10-08, after closure)

- The first full pre-commit run (proc_f25f) failed the 4 cancel tests (`bash: cancelled`, `cancelled=false`) and took 903 s vs the earlier 257 s at system load ~20. A direct fixture reproduction failed 3/3, and an instrumented copy showed why: `work --cancel` paid the argv-decoder subprocess latency (~100 ms, more under load) before aborting, while the fixture's simulated child lives 100 ms — a late abort landed after the child finished or killed an unrelated bash step.
- Root-cause fix in adapters/pi_native_commands.mjs: `work --cancel` aborts before the decoder (the decoder branch stays for quoted forms), and the decoder wraps `JSON.parse` with a mode-named error. `No active native work run` behavior preserved.
- Evidence: direct reproduction OK 5/5 (error `RPC child cancelled`, cancelled true, controls `['nico']`); the 4 previously failing cancel tests pass 4/4 (proc_938c). This product delta postdates the plan-verifier PASS above; no second independent review is claimed. The owned installer refreshed the installed copy: 13/13 helpers match source bytes, ledger 47/47 hashes match, mb-pi --help exits 0, and settings.json plus the ordinary pi launcher remain unchanged.
- Final Pi-specific pre-commit run (proc_bff3): 178 pytest tests passed in 627.50 s, 57 Bats tests passed, Ruff, ShellCheck -S error, Node syntax and git diff --check passed; the complete command exited 0. This is the complete Pi-native test slice, not the whole repository suite or acceptance of the paused goal.
- Commit readiness check: Ruff also passes on all Pi-native Python tests and both shared semantic modules required by Stage 3; shell syntax and diff whitespace checks pass. The default firewall invocation exceeded a 60-second budget and is not a verdict. A separate acceptance-only firewall probe exits 1 on the five unchecked criteria of paused G-001. The installed pre-commit checks goal presence without honoring paused status (I-261); no commit, push or gate bypass was attempted. A process-local bypass requires explicit owner approval; it does not accept G-001.
- Owner subsequently authorized a one-commit MB_FLOW_CLOSURE=off override and push to main (AGR-092). Keep G-001 paused/RED and all other hooks active. Commit only Pi source, tests, concise evidence and its bank records; preserve unrelated staged work, generated graph changes and runtime artifacts. The local pi-inspect 0.5.0 cleanup patch is outside the repository and is not part of this commit.
