# Native Pi adapter contracts

Stage 1 replaces the opted-in subagent extension's prompt-only router with native handlers. Installation/package wiring remains Stage 5; do not copy this extension alone into the host (its sibling helpers are required).

## Boundary ports (contract-first)

- Command host: `registerCommand(name, {description, handler(args, ctx)})`, `sendMessage(message, options)`, `sendUserMessage(text)`.
- Common backend port: `preflight(role, task, output)`, `dispatch(key, child, options)`, `guard()`. One driver consumes the selected adapter; it never retries another engine.
- Public bridge: `events.on(name, listener) -> unsubscribe`, `events.emit(name, request)`. Nico uses version-1 `ping`, `spawn`, `stop` and advertised async completion; Tintin 0.19.0 uses its distinct per-method v2 `ping`, `spawn`, `stop`, `consume` channels and completed/failed events. No private imports or replacement executor.
- Launch preflight: public `resolveSubagentLaunchContract(input) -> {ok, contract|message}`. Parent model and available model snapshot come from the live context. Infrastructure errors halt, never inline/CLI fallback.
- Portable argv runner: fixed script path plus string argv, live project cwd, inherited environment with `MB_AGENT=pi`, finite timeout/cancellation; script failure is an exception.

Mechanical context/start restoration executes `mb-context.sh` against the bank resolved by `_lib.sh`. It injects a custom context message, not a new user request. Work uses pipeline path selection, workflow, work-plan, durable work-state, review parser/severity, budget and protected-path scripts. Other template commands explicitly forward their own instructions to the model. `/mb goal` and `/mb-goal` are MB-owned; `/goal` is never registered. Every command template has a collision-resistant `/mb-<name>` alias; legacy `/start` restoration is registered explicitly. No top-level collision-prone toolkit names are claimed.

Native role model defaults inherit the parent's current provider/model. Legacy `opus`, `sonnet`, `haiku` aliases are ignored as legacy family hints, not provider grants. Nonempty unresolved bare names refuse. Provider-qualified model overrides must be available; cross-provider execution requires explicit owner authorization bound to the current run. Native command syntax `--model provider/id --authorize-provider provider` is an owner opt-in for that invocation, never a tool-facing authorization parameter. External `codex-cli` is selected only by pipeline; its runner owns model/thinking argv, so no native override is sent. Preflight validates the actual resolved native model and refuses cross-provider agent defaults too.

Work errors preserve source identity, state slots, child receipts and output files. Concurrent commands are refused; durable source claims also protect separate sessions. Missing banks are not initialized. Unknown steps are refused rather than silently skipped. The plan's native Eval absence remains UNVERIFIED, separate from test receipts. Independent verification/review/judge and real-host acceptance are separate gates, not attested by the fixture harness.

## Work invocation and recovery

- `/work sample --range 1` and `/mb-work sample --range 1` execute the same native driver as `/mb work sample --range 1`.
- Optional flags: `--backend nico|tintin`, `--pipeline NAME`, `--workflow NAME`, `--budget TOKENS`, `--max-cycles N`, `--model provider/id`, `--authorize-provider PROVIDER`. New-run selection is explicit backend, then bank `.mb-config` `pi_subagent_backend`, then Tintin (default, ADR-013). Unsupported flags refuse instead of being interpreted by a model.
- `/mb work --cancel` stops the extension-owned active lane. An in-flight spawn retains its bounded reply handshake so cancellation can persist and stop the exact child id; normal role runs have a finite deadline. Cancellation/stop failures disclose uncertainty and retain partial files.
- `--resume-run ID` requires one exact live source/item, unchanged source/pipeline hashes, recorded backend/session and agent/model/tool contracts, and a successful implementation terminal receipt. It does not reset state, red/green evidence, budget or cycles; it repeats fresh verification/review/judge. Unreconciled implementation cancellation refuses resume rather than relaunching a potentially live writer.
- When `roles.reviewer.parallel_with: main-agent` is selected, `--main-review FILE` must supply a bound owner receipt: `{ "runId": "...", "sourceHash": "...", "itemNo": 1, "cycle": 0, "review": { "verdict": "APPROVED", "counts": { "blocker": 0, "major": 0, "minor": 0 }, "issues": [] } }`. Read identity/hash/cycle from that run's retained reports/state. Missing/stale/negative main review never closes; no automatic inline reviewer is invented. Review after a fix needs a new cycle-bound receipt.
- GO_WITH_BACKLOG validates the judge acceptance summary and registers each bound suggestion through `mb-idea.sh` before `done`. Registration failure leaves the item open.
- Ensemble review profiles (the bundled `governed` preset) and non-verify fix return steps currently refuse explicitly before dispatch. They are not silently approximated by a single reviewer. Agentic planning workflows also refuse native work execution until an existing executable plan/spec is selected.

Native work preserves source checkboxes for the main owner even after its durable `done` gate passes. The owner closes accepted plan stages separately. An absent native Eval surface is always reported UNVERIFIED; ordinary test RED/GREEN does not manufacture native Eval proof. Protected-path postchecks use reported changed files; pre-mutation tool guards are Stage 4, not an OS sandbox. The Stage 5 installer must package all sibling helpers and prepare inherited-model role definitions before any real host rollout.

## Opt-in managed startup and current acceptance boundary

The minimal `pi_native_bootstrap.mjs` composition uses public Pi SDK services,
DefaultResourceLoader, AgentSessionRuntime and existing InteractiveMode. Stage 5,
not Stage 1, installs the separate owned `<agentDir>/bin/mb-pi` entrypoint. Ordinary
`pi`, PATH, aliases and foreign settings are not replaced. Under AGR-090 the opted-in
MB extension also activates pinned Tintin in ordinary Pi and binds its attributed
public factory/registry to the live session context (`inventoryScope: owned-factories`,
not a claim about all host extensions). Managed startup retains its existing binding
without activating a second engine. Duplicate services, unresolved project trust,
stale sessions and changed settings refuse dispatch; child/bridge contexts never
activate an ordinary operator root. Ordinary Pi supports Tintin; explicit Nico
still requires the optional managed startup.

The root holds process-local authority tied to actual loaded factories, a live
session and a generation. Command/tool JSON cannot create authority. Replacement,
shutdown, disposal and settings changes invalidate it. A settings change discards
the captured snapshot: merely rebinding the session cannot reauthorize an old
snapshot; a fresh factory reload is required. Late events from replaced factories
are ignored. A synchronous factory-only cwd overlay uses an owned temp sidecar,
restores cwd before any queued emissions drain and refuses asynchronous factories;
it never replaces even temporarily a foreign settings file.

Tintin mentions must be actually `off` even when Nico is selected. Candidate
model-free SDK evidence observes unchanged mention input/no reminder after binding
and SDK resource/settings reload, actual source/version/inventory, unique services,
replacement and disposal. This is not actual TUI or native-leaf execution proof.
Unsupported Tintin worktree/auto-commit, required non-builtin tools, memory and
external runner contracts refuse rather than downgrade or substitute `codex-cli`.
Optional native resume/steer are not implemented by the adapter; portable work
resume re-runs gates using retained contracts, not a hidden native continuation.

Adapter-owned leaf profiles retain source prompt/role identity and explicit tool
scope while excluding native delegation surfaces. Nico uses public launch
preflight/digests; Tintin verifies its owned terminal record/session tools/model
and consumes the result. Nico runs only when explicitly selected: before each
child it registers the public `registerSubagentCapabilityCeiling` (role allowlist,
`allowedAgents: []`, `denyExtensions: true`) and refuses launch if that fails; its
runtime tool/resource inventory is reported `UNVERIFIED` (no public child-session
inventory in Nico 0.76). **Stage 1 remains BLOCKED on actual safe, pre-model native
leaf inspection:** Tintin's public RPC overwrites `onSessionCreated`; its public
record arrives asynchronously, and a pre-aborted signal has no demonstrated
zero-request startup boundary. Do not race stop, import private managers, inject
observer extensions into the leaf, replace the executor or claim mocked records
prove runtime leaf isolation. Fixture GREEN, producer evidence, independent gates
and Stage 5 live acceptance are separate. No real-host rollout is authorized by
this candidate reference.

## Session memory (Stage 2)

`pi_session_memory_extension.ts` registers handlers synchronously and delegates to `<skill>/adapters/pi_native_session.mjs`; a missing module disables capture with a notice, never blocks Pi. Session files use the canonical v2 name `<date>_<hhmm>_<sid8>.md` (`agent: pi` in frontmatter); start/reload/resume reuse the file found by full `session_id`. Restore (`_recent.md` + `handoff/latest.md`, `MB_AUTOLOAD_CONTEXT=off`), capture (`MB_SESSION_CAPTURE=off`) and pre-compaction `mb-handoff.sh` (`MB_PRECOMPACT_HANDOFF=off`, `MB_PRECOMPACT_BUDGET`) are independent; restore and the post-compaction capsule enter model context once as custom messages, never as user input. Shutdown runs `hooks/mb-session-summarize.sh` under the inherited backend policy (Pi default: no CLI) within `MB_SESSION_LLM_TIMEOUT` (default 30 s), otherwise writes a `summary_mode: deterministic` summary (`summarized` stays false), then `mb-session-recent-rebuild.sh`. Writes are serialized process-wide and bound to the live session generation.

## GraphRAG and vectors (Stage 3)

`pi_graph_rag_extension.ts` is thin glue over `<skill>/adapters/pi_native_graph.mjs`: `code_context`, `search_code`, `graph_neighbors|impact|tests` resolve the bank of the live `ctx.cwd` via `_lib.sh` (no model-supplied bank path), run the portable scripts with a 90 s bound and the tool's abort signal, throw on nonzero exit / `ok:false` even when stdout is JSON, and label weaker answers `status: degraded` (BM25 fallback, stale graph catch-up, warnings). `session_start` dispatches `mb-graph-query.py catchup` in the background (`MB_GRAPH_CATCHUP=off`, log `codebase/.graph-catchup.log`); successful `write`/`edit` of code files inside the project append to `codebase/.graph-dirty`; structural `grep`/`bash` results get the `mb-graph-nudge.sh` hint appended (`MB_GRAPH_NUDGE=off`); `session_compact` resets its counter.
FastEmbed model files live in `FASTEMBED_CACHE_PATH`, else `~/.cache/fastembed` (same as session recall), never the OS temp dir by default; a model only present in the legacy `<tmp>/fastembed_cache` is read in place. A missing/corrupt model with a warm matrix answers with BM25 plus an `embedding model unavailable (… from <dir>)` warning instead of crashing.

## Guard hooks (Stage 4)

`pi_native_hooks.mjs` (registered by the graph extension, which ships in both install tiers) reuses the portable scripts: `write`/`edit` → `hooks/mb-protected-paths-guard.sh` (forced `MB_PROTECTED_MODE=deny`, bank `pipeline.yaml` via `MB_PATH`, the path canonicalized and made project-relative first), `bash` → `hooks/block-dangerous.sh` then the protected guard. Exit 0 allows; any other outcome — guard exit 2, crash, 15 s timeout, cancellation, malformed input — blocks before the tool runs, with a bounded reason. A successful write/edit of `<bank>/plans/*.md` runs `mb-plan-sync.sh <plan> <bank>` once, of `<bank>/specs/**.md` runs roadmap-sync + traceability-gen; failures only append a bounded note. The bank resolver walks up from a project subfolder like `mb-graph.sh`.
Limits: this is a pattern guard over Pi's built-in `write`/`edit`/`bash`, not a sandbox — other tools (custom/extension tools, `powershell`, the user's own `!` shell), interpreter-level writes and redirects the regex parser misses (e.g. absolute targets outside a git checkout) are not checked; `MB_ALLOW_PROTECTED=1` bypasses the protected guard; plans written via `bash` are not synced.

## Managed entrypoint install (Stage 5)

`adapters/pi.sh install-global-extensions` (the opt-in Pi path) also installs the `pi_native_*.mjs` helpers next to the extensions, requests `npm:@tintinweb/pi-subagents@0.19.0` in `settings.json` with `extensions: []` (Pi installs it; the MB extension owns its activation, not standalone package discovery) and the owned `<agentDir>/bin/mb-pi`; a foreign `mb-pi` refuses the install. Run `mb-pi [--with-nico] [--check] [--] [message ...]` (SDK from `MB_PI_SDK_ROOT`, the agentDir managed install, or `pi` on PATH); its managed settings view hides every configured Nico/Tintin package extension and the discovered MB extension so each loads once. `adapters/pi.sh uninstall-global-extensions` removes only unchanged owned files (ledger `.mb-pi-native-owned.json`), restores replaced files from `.mb-pi-preimages/` and keeps user edits.
