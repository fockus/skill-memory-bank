---
title: Pi native Memory Bank integration
status: in_progress
type: feature
created: 2026-10-05
priority: HIGH
workflow: codex-governed
stages_total: 5
stages_done: 4
approved_design: ../context/pi-native-integration.md
---

# Pi native Memory Bank integration — Implementation Plan

> For agentic workers: execute through `/mb work` with the resolved `codex-governed` workflow. TDD first, fresh independent verification and review, judge before closure. The main session owns acceptance and publication; no commits/pushes in this task.

**Goal:** deliver and install the approved native Pi adapter with proven commands, memory lifecycle, graph/vector tools, guarded named-role execution and safe install/removal.
**Architecture:** thin native glue over portable MB scripts and public Nico/Tintin integration APIs; one selected backend per run, no additional agent executor. Deterministic handlers for mechanics, explicit LLM scenarios for planning/analysis. AGR-057/058 extend the current five stages, preserving their IDs and original TDD evidence: dual backend plus a separate opt-in public-SDK startup of existing Pi runtime/TUI, with an authoritative host binding and no new child executor.
**Tech stack:** existing TypeScript/Node Pi ExtensionAPI, public Nico/Tintin event buses, shell/Python MB scripts and existing FastEmbed. Only the explicitly requested @tintinweb/pi-subagents package and its required dependencies may be added; Nico remains default.
**Baseline commit:** e351a17b8f114bb985dcc2efbdd5709c731736e6
**Baseline evidence:** `reports/pi-native-integration/baseline.json` and `baseline.diff` record the dirty working tree, not just HEAD.
**Coordination:** ⚠️ `COORDINATION.md`, ACK 2026-10-05. No rebase/reset/checkout/whole-tree stash. One writer per cwd. Do not edit foreign dirty hooks, agent partials, install.sh, commands/mb.md, SKILL.md or semantic_index.py; use adapter-specific seams. Before any unavoidable shared change, contact the main session. Planning and reports are scoped additions, progress remains append-only.
**Quality DoD:** `.memory-bank/RULES.md`, `AGENTS.md`, `rules/RULES.md`, approved AGR-055/056/057/058. KISS/SOLID, contracts before implementation, Testing Trophy, argv-safe commands, bounded/cancellable operations. Broad existing red tests are reported with baseline evidence rather than relabeled green.

## Bootstrap and execution contract

The main session may install the existing composed MB role definitions into Pi's empty user agent registry before dispatch; this is onboarding existing artifacts, not inline product implementation. Preserve/backup any file that appeared since discovery. `mb-agent-render.py --host pi` supplies composed instructions and tool names. AGR-056 (2026-10-05, owner correction) controls this run: native implementation, verification and judge inherit the orchestrator's current provider/model; legacy opus/sonnet aliases are not permission to select Anthropic. Omit the model override for those native roles; currently the parent is openai/gpt-6.1-sol. Keep role thinking and all quality gates. Do not edit the shared repository pipeline.yaml. Cross-provider launch requires an explicit run-specific owner override. The configured independent Codex review remains the named codex-cli external runner on the OpenAI service, gpt-5.6-sol/xhigh baked into argv; do not pass unsupported native-runner overrides. Bootstrap is temporary until the tested installer owns the roster. Availability is not authentication proof: launch preflight is authoritative. Any native workflow/child setup failure stops the lane and retains partial diffs; no other transport fallback without Anton's approval.

Resolve before implementation:
```bash
cd /Users/anton-one/Apps/skill-memory-bank
bash scripts/mb-workflow.sh --workflow codex-governed --json
bash scripts/mb-work-resolve.sh pi-native-integration
bash scripts/mb-work-plan.sh --target pi-native-integration --range 1-5 --dry-run
```
Expected: five stages, implement→verify→review→judge→fix→done, bounded configured cycles. Bind each source_path/source_topic/item_no into a distinct durable MB state slot; preserve any existing live run. A missing plan Eval surface is UNVERIFIED, never a native Eval PASS; record actual RED/GREEN receipts separately. Independent reviewers judge the stage's baseline-relative change, not all unrelated uncommitted work.

<!-- mb-stage:1 -->
## Stage 1: Native commands and governed Nico/Tintin backend bridge

**Status:** done 2026-10-08 (implementation; plan-level verify/review/judge pending per AGR-087) — evidence: reports/pi-native-integration/stage1-closure-2026-10-08.md
**Role:** developer
**Depends on:** bootstrap only
**Continuation (2026-10-08, AGR-086/087/088):** taken over by the Claude Code session; executed as one stage by an mb-* executor under the medium preset (verifier once per plan, review + judge before closing). Earlier Pi/GPT lane receipts stay as evidence; the Nico child-inventory blocker is resolved by AGR-088 (Tintin default, Nico ceiling + UNVERIFIED).
**Scope decision (2026-10-05):** AGR-058 resolves Q-002 by authorizing a separate opt-in public-SDK bootstrap of existing Pi runtime/TUI. Ordinary ExtensionAPI's inventory/settings gap remains factual; it is not relabeled supported. Stage 1 now proves the minimal real SDK producer/consumer path without model/child calls, then the dual-backend contracts. Latest retained writer b3772376-ef7e-4a2f-81dd-f20a3051bfd5 may resume only after this scope handoff. Existing paused/failed receipts, ten owned product hashes and original work slot are preserved; no reset, fixture-only producer PASS or stage acceptance.
**Files:** adapters/pi_subagent_extension.ts; adapters/pi_native_commands.mjs; adapters/pi_native_subagents.mjs; adapters/pi_native_work.mjs; new adapters/pi_native_backend*.mjs, adapters/pi_native_tintin*.mjs and adapters/pi_native_roles*.mjs as coherent backend/profile units only when needed; adapter-owned Python/shell argv helper only if needed; tests/pytest/test_pi_native_commands.py; tests/pytest/test_pi_native_work.py; tests/pytest/test_pi_native_backends.py; NEW adapters/pi_native_host.mjs (binding authority/lifecycle contract), adapters/pi_native_bootstrap.mjs (minimal public SDK composition/TUI core), tests/pytest/test_pi_native_host.py and tests/fixtures/pi_native_sdk_host.mjs (actual SDK/no-model smoke); tests/fixtures/pi_native_host.mjs; references/pi-native-integration.md. Leave pi_subagent_dispatch_core.mjs as the unchanged legacy floor. Parent separately approved ONLY the two registration/import Bats blocks around lines 219–232 in tests/bats/test_pi_agents_dispatch.bats; all other legacy assertions remain unchanged.

**Probe authorization (AGR-059, 2026-10-05):** owner approved a SHORT separate actual-leaf feasibility/runtime probe through pinned native engines/public SDK with an isolated test external LLM transport, no real-provider requests and unchanged provider/model identity. Latest retained writer is 83d1fe63-8802-4f35-b8a7-3f8b507badb1; earlier IDs above are historical. Producer smoke stays zero-model/zero-child; simulated model calls in the separate leaf probe are counted explicitly, never live-provider PASS. Only scoped fixtures/pytest/reference and owned temp test configuration may change for this probe; no production API/workaround, extra observer extensions/private callbacks/new executor/dependencies/host modifications. First prove public transport/observation feasibility and isolation with synthetic credentials/no fallback; otherwise BLOCKED. Scope/source/cycles and all remaining mandatory DoD/gates persist, 0/5 accepted.

**Contract examples:** an unspecified role model/provider inherits the orchestrator; legacy opus/sonnet aliases do not choose Anthropic; a provider-qualified override is validated and honored only when explicitly authorized for that run, otherwise preflight refuses before launch. `/mb context` in bank A executes context.sh against A without an LLM; `/start` does the same restoration path; `/mb work sample --range 1` resolves sample's selected named pipeline and dispatches named implement/verify/review/judge roles in that order, not a prompt-only router. `/mb goal` routes MB goal instructions, while no MB registration takes over `/goal`. Inputs containing quotes/semicolon remain argv data, not shell code. Missing owner/agent/model, malformed verdict, verifier FAIL, reviewer CHANGES_REQUESTED, judge NO_GO, exhausted cycles and explicit cancel never mark done. Work absent a bank fails without creating one. Concurrent /work refuses/queues according to existing state policy without duplicating steps.

**Backend contracts:** selection precedence for a new run is `--backend nico|tintin`, then bank `.mb-config` `pi_subagent_backend`, then Tintin (AGR-088/ADR-013; was Nico). A Nico run registers `registerSubagentCapabilityCeiling` (`allowedTools` = the role allowlist, `allowedAgents: []`, `denyExtensions: true`) before launch, and its runtime tool/resource inventory is reported UNVERIFIED (Nico has no public child-session inventory) instead of blocking closure. Pin backend + parent session + source identity + native child ID in durable state. A conflicting resume/backend, unavailable selected service, unknown/disabled role, effective model/provider drift, unsupported configured runner/control, malformed verdict, wrong-owner event and dropped isolation request refuse execution/closure without sending a request to the other service. With both extensions present, only the explicitly selected backend launches children; unselected delegation tools/automatic mentions cannot bypass MB routing, and child tools remain scoped. Render composed roles into adapter-owned profiles rather than overwriting foreign agents. Public Tintin RPC uses different options and does not expose every Agent-tool operation; validate actual capabilities and escalate a mandatory missing API instead of adding a private import or alternate executor. A native backend never pretends to implement an external CLI runner. Both backends must support the same MB gate semantics; backend-specific extras have explicit capability boundaries.

**Host contracts:** the opt-in SDK root supplies exact live session/runtime generation, authoritative loaded-component inventory and factory-attributed effective Tintin settings; forged tool JSON, missing/hidden tools, missing replies and stale globals cannot supply it. SDK bootstrap preserves ordinary pi, credentials/model selection, supported builtin tools, unrelated discovery/customizations and project trust without foreign config writes. No duplicate backend/MB service; no prompt/model/child execution before startup readiness. Root binding invalidates on replacement/settings reload/failure/disposal. Unknown binding refuses governed dispatch but not deterministic context/start. Enabled/unknown actual Tintin mentions block both selected backends. Tintin auto-commit/dropped/unprovable isolation refuses before launch, never downgrades.

**TDD / steps:**
- [x] Create fixtures for local, registered global, legacy and absent banks plus fake public RPC events. Write behavioral command/ordering/negative-gate tests before production changes.
- [x] Run `pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py` and save the observed behavioral RED plus source hashes in `reports/pi-native-integration/stage1-red.md`.
- [x] Preserve original Nico-only RED/GREEN receipts and Stage 1 baseline. At the acknowledged checkpoint write parametrized dual-backend tests FIRST for selection, strict inheritance, capabilities, correlation/consumption, cancellation, wrong-engine controls, resume identity, child tool scoping, concurrent calls and every negative gate. Save a new observed behavioral RED with pre-edit hashes in reports/pi-native-integration/stage1-dual-backend-red.md.
- [x] Before bootstrap/binding production edits, write test_pi_native_host.py and the actual SDK fixture for attributed settings/inventory, ready barrier, forged/unknown/stale bindings, replacement/disposal/late callbacks, failed factory, duplicate components, foreign-setting preservation and harmless mechanical commands. Run `.venv/bin/python -m pytest -q tests/pytest/test_pi_native_host.py` against the current candidate; retain an observed behavioral RED with source hashes in reports/pi-native-integration/stage1-managed-host-red.md, not an import/collection/setup failure.
- [x] Implement the minimal public-SDK root and binding contract in the two approved modules. Run a real pinned-package loader/session/factory smoke using sandbox HOME, actual getExtensions/session identity and no model/child calls. Record exact source/version/paths, actual settings, unique services, lifecycle invalidation and native API/capability boundaries in reports/pi-native-integration/stage1-managed-host-smoke.md; inject fake remote children only in the separate governed contract battery. A missing mandatory public hook still stops the lane rather than introducing a private import or new host product.
- [x] AGR-059 separate leaf probe: write observable external-transport isolation/identity and actual-runtime assertions before fixture implementation; retain honest RED/source hashes, then use the actual pinned engines and public SDK session/tool/inventory/record APIs with only the external LLM service simulated. Preserve inherited provider/model identity and synthetic test credentials; prove no real-provider routing/fallback before launch, bound local calls and cleanup. Record actual native child/session/tool/model/no-extension/no-nested facts separately from zero-call producer smoke and fake governed gate records. Missing public isolation/observation fails BLOCKED; no code/private-hook/provider/runner substitution or Stage 1 acceptance.
- [x] Implement native handlers, one MB pipeline/gate driver and small public backend adapters; reuse pipeline/target/state/severity scripts. No private pi-subagents imports, second executor or model/role/backend fallback. Use fresh reviewer contexts, explicit durable role-output bindings, full source identity and safe cancellation. Keep the existing external Codex reviewer for this development workflow; real Tintin execution must reject incompatible configured runner roles rather than substituting them.
- [x] Run `pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py tests/pytest/test_pi_native_backends.py tests/pytest/test_pi_native_host.py` GREEN, all 22 existing Pi dispatch Bats tests, applicable adapter compatibility tests, Node syntax and shell/Python static checks. Test-specific installs of requested Tintin 0.19.0 use sandbox HOME/storage only. Record public API/capability findings and exact commands/exits; parent alone installs/activates the real host after Stage 5 gates.

**DoD before next stage:**
- [x] Fresh behavioral RED→GREEN proves binding/startup boundaries; a real model-free SDK/pinned-factory integration smoke proves an authoritative producer and one instance of each intended component in the owned runtime. No fake inventory/settings injection is called producer PASS. No model/child dispatch occurs before readiness or on stale/unknown binding; source/factory/session identity and cleanup are evidenced.
- [x] Ordinary pi/foreign config unchanged; mechanical commands remain usable without binding; required tools/model/credentials/trust and unrelated customizations are preserved or unsupported composition refuses explicitly. Runtime-local mentions override is proven honored; worktree/auto-commit requests refuse rather than downgrade. Stage 5 live TUI/child acceptance remains a separate gate.
- [x] Behavioral fixtures prove native mechanic execution and governed step dispatch for at least two different pipelines, including a named pipeline from .mb-config.
- [x] Both selected backends pass the common governed positive/negative contract battery; when both are present, each run dispatches through exactly one backend. Tintin is the default (AGR-088); explicit Nico selection runs under the capability ceiling, works without a hidden Tintin dependency and reports its runtime inventory as UNVERIFIED. Compatible native-role pipelines execute mandatory verify/review/judge unchanged; unsupported configured runners fail before implementation starts.
- [x] All specified negative gates refuse closure and retain recoverable source/run evidence; infrastructure failure is explicit and never executes inline or through another backend. Wrong-engine controls, conflicting resume and effective provider drift fail before side effects. Completion listeners and role-profile tooling do not leak across sessions/backends.
- [x] Alias registrations cover all installed MB command templates, with clear command collisions and explicit agentic-vs-mechanical routing; one MB command surface and no prompt-only /work acceptance. Tests prove child tool scoping and no raw unselected-backend delegation bypass.
- [ ] Independent verify PASS, Codex plus main-session review, and judge GO/GO_WITH_BACKLOG; configured blockers/majors=0. No stage checkbox flip by implementer.

<!-- mb-stage:2 -->
## Stage 2: Project-isolated capture, restore and compaction

**Status:** done 2026-10-08 (harness-level; live Pi in Stage 5; plan-level verify/review/judge pending) — evidence: reports/pi-native-integration/stage2-2026-10-08.md
**Role:** developer
**Depends on:** Stage 1 accepted
**Files:** adapters/pi_session_memory_extension.ts; adapters/pi_native_session.mjs; tests/pytest/test_pi_native_session.py; tests/fixtures/pi_native_host.mjs; references/pi-native-integration.md. Do not edit shared hooks/mb-session-start.sh; invoke portable hooks/scripts through owned adapter code.

**Contract examples:** session S in A records one header and one completed turn; start/resume/reload S preserves prior turns; switching to B records/restores only B. Extension-sourced input is not a fresh user request. Before compaction writes a real handoff capsule through mb-handoff.sh, subsequent model context receives it once. Shutdown writes a usable summary and rebuilds recent context within a bounded await. Capture off, restoration off and no bank have independent semantics; no stale session state is retained. Forced termination may leave a live log, never a forged completed summary.

**TDD / steps:**
- [x] Write real-filesystem event-harness tests for two banks, resume, reload, summary, restore, compaction, switches, absent bank, kill-switches and write/script failure. Save observed RED before production edits.
- [x] Reuse the existing v2 schema and session/handoff helpers; serialize writes and scope all state/callbacks by live session identity. Bounded summaries must disclose deterministic-vs-LLM mode; do not invoke unauthorised fallback CLIs.
- [x] Run `pytest -q tests/pytest/test_pi_native_session.py`; run compatible `bats tests/bats/test_pi_session_memory_extension.bats`; perform Node/static checks and retain results.

**DoD before next stage:**
- [x] Behavioral tests prove capture→summary/recent rebuild→restoration in a second session and real pre/post-compaction handoff.
- [x] Two-bank and no-bank cases show no leakage/implicit initialization; restart does not duplicate header/turn identifiers.
- [x] Timeout/errors preserve captured evidence and allow normal Pi operation; stale asynchronous callbacks cannot write to a replacement project/session.
- [ ] Independent verify, cross-model review and judge accept the stage with no blockers/majors.

<!-- mb-stage:3 -->
## Stage 3: Native GraphRAG, vector cache and graph lifecycle

**Status:** done 2026-10-08 (real offline embedding proof; live Pi in Stage 5; plan-level verify/review/judge pending) — evidence: reports/pi-native-integration/stage3-2026-10-08.md
**Role:** developer
**Depends on:** Stage 2 accepted
**Files:** adapters/pi_graph_rag_extension.ts; adapters/pi_native_graph.mjs; memory_bank_skill/semantic_embeddings.py; tests/pytest/test_pi_native_graph.py; tests/pytest/test_pi_native_embeddings.py; references/pi-native-integration.md. semantic_index.py and shared graph hooks are foreign; request main-session approval before changing them.

**Contract examples:** code_context/graph_neighbors/graph_impact/graph_tests/search_code execute portable scripts against ctx.cwd's bank with timeouts/cancellation; failure returns an explicit failed/degraded result, never success just because stdout contains JSON. Start and relevant write events trigger compatible catchup/nudge without unnecessary corpus encoding. Embedding query after a process restart succeeds offline from a persistent model cache; FASTEMBED_CACHE_PATH/user overrides retain precedence. Missing/corrupt model is diagnosed, BM25 fallback is labeled and a cold corpus does not block the foreground query. Persisted matrix does not pretend the query encoder is available.

**TDD / steps:**
- [x] Diagnose current offline failure and record the exact cache/model files, metadata mismatch, interpreter and paths without deleting cache. Write constructor/cache/error/graph-event regressions and observe RED before edits.
- [x] Add minimal persistent model-cache plumbing honoring existing overrides; reuse FastEmbed and existing retriever/background-index policy, not a new indexing engine or library.
- [x] Implement native tools and lifecycle wrappers against existing CLI contracts.
- [x] Run `pytest -q tests/pytest/test_pi_native_graph.py tests/pytest/test_pi_native_embeddings.py`; run focused existing embedding/search tests selected by graph/tests; Node/Python/static checks.

**DoD before next stage:**
- [x] Native tools resolve current bank correctly, return explicit failures, and support bounded cancellation; graph events run without cross-project writes.
- [x] Actual embeddings are inferred in a fresh process with HF_HUB_OFFLINE=1 and no download. A semantic-only fixture has expected top hit and reports embeddings backend; BM25 alone is not a vector PASS.
- [x] Cache model files are outside temp by default; explicit overrides work; cold/corrupt cases preserve user's existing data and disclose fallback.
- [ ] Independent verify, cross-model review and judge accept the stage with no blockers/majors.

<!-- mb-stage:4 -->
## Stage 4: Native guard hooks and synchronization

**Status:** done 2026-10-08 (harness-level; live Pi blocking in Stage 5; plan-level verify/review/judge pending) — evidence: reports/pi-native-integration/stage4-2026-10-08.md
**Role:** developer
**Depends on:** Stage 3 accepted
**Files:** adapters/pi_native_hooks.mjs; existing Pi boundary files for registration only; tests/pytest/test_pi_native_hooks.py; references/pi-native-integration.md. Do not modify portable shared hooks without approval.

**Contract examples:** write/edit to a pipeline-protected path is blocked before mutation; a safe read is allowed; a dangerous shell fixture never executes. Canonical/relative paths and malformed hook input fail according to the explicit blocking policy. Ordinary optional nudge/catchup failures never break a user tool. Successful scoped plan write runs plan-sync; a failed write does not. Guard coverage and limits are named honestly, not presented as a security sandbox.

**TDD / steps:**
- [x] Write safe fixture tests for protected/dangerous commands, error handling, cancellation, post-write synchronization and hooks receiving current bank; observe RED.
- [x] Wire existing guards and post-write scripts with normalized Pi event inputs, safe argv/stdin, bounded execution and no recursive hooks.
- [x] Run `pytest -q tests/pytest/test_pi_native_hooks.py`, compatible existing guard tests and Node/static checks.

**DoD before next stage:**
- [x] Tests prove blocking guards prevent fixture writes/execution, and nonblocking hook failures allow ordinary tools with bounded diagnostics.
- [x] Successful scoped plan changes synchronize once; failed tools and unrelated writes do not cause false closure or unrelated rewrites.
- [ ] Independent verify, cross-model review and judge accept the stage with no blockers/majors.

<!-- mb-stage:5 -->
## Stage 5: Safe dual-backend installation and real Pi acceptance

**Status:** pending
**Carried from Stage 1 (2026-10-08, owner):** prove the actual loaded inventory (tools, extensions, skills, prompts) of a real Tintin child in the live run; Tintin has no public pre-request inspection point, so this is observed post-launch here. Nico inventory stays UNVERIFIED (AGR-088).
**Role:** developer
**Depends on:** Stage 4 accepted
**Files:** adapters/_lib_pi_extensions.sh; adapters/_lib_pi_subagent.sh; adapters/_lib_pi_global.sh only for adapter-specific wiring; adapters/pi.sh; tests/pytest/test_pi_native_install.py; tests/pytest/test_pi_native_live.py; references/pi-native-integration.md. Avoid foreign install.sh/SKILL.md/commands changes; use existing explicit Pi opt-in seam. Real host installation is parent-owned after gates.

**Managed entrypoint:** installer creates only an owned `<Pi agentDir>/bin/mb-pi` executable using the Stage 1 public-SDK bootstrap; do not replace pi, modify PATH/aliases, auto-enable Tintin globally or overwrite a foreign entrypoint. The explicit managed runtime composes installed packages/settings without duplicate services. Request additional bootstrap/package scope only if necessary.

**Contract examples:** install requested Tintin and native adapter into sandbox HOME twice keeps identical owned output and preserves unrelated settings/prompts/roles; generated templates have empty global PROJECT_ROOT and resolvable helper imports. Package/role provenance and selected backend are recorded; Tintin is the default (AGR-088). Only one MB surface and the selected delegation surface are available to managed work, even with both packages installed. Unknown roles/providers never fall through to another agent, model or backend. Removal only removes unchanged owned files, preserves user-edited files and restores replaced preimages. Interrupted install does not declare capabilities that did not load. Runtime API acceptance observes native handlers/tools/roles and actual session/gate behavior, not static grep alone.

**TDD / steps:**
- [ ] Write installer ownership/idempotency/removal/rollback and real-runtime harness tests before install code changes; observe RED. Include both-package coexistence, owned backend/profile selection, additive package/settings updates and preservation of custom agent/mention configuration. Runtime discovery may use configurable installed Pi path, never a committed personal path. Tintin candidate 0.19.0 and its required dependencies are expressly authorized; other optional downloads remain prohibited.
- [ ] Add test-first sandbox acceptance for the owned managed entrypoint: two installs are identical; quoting/cwd/agentDir with spaces stay argv; supported runtime settings/tools/credentials/trust persist; no PATH/global-autoload or ordinary pi changes; foreign name collision refuses; uninstall/rollback removes only unchanged owned files. Observe RED before installer changes. Stage 5 tests exercise real InteractiveMode initialization with a controlled terminal/runtime and do not substitute a new UI or model loop.
- [ ] Wire helpers and `<Pi agentDir>/bin/mb-pi` into the opt-in installer with artifact ownership hashes/preimages and non-clobbering setting updates. Refresh only owned MB prompt copies with backup.
- [ ] Run `pytest -q tests/pytest/test_pi_native_install.py`; run existing Pi installer/agent/render/packaging regressions in sandbox HOME and static checks.
- [ ] Independent verify/review/judge before parent installs requested Tintin and the verified candidate into real ~/.pi/agent. Do not reload the live parent while its governed children are active. Parent then launches the installed opt-in managed entrypoint with the existing Pi InteractiveMode/runtime and runs real acceptance in isolated sessions/banks: attributed ready binding, unique loaded services, ordinary-startup refusal without automatic fallback, Tintin default and explicit Nico (capability ceiling, inventory UNVERIFIED) with both packages installed, actual model/provider, one backend/run, mandatory gates and negative no-fallback/cancellation cases. Record unsupported optional controls separately; fixture preflight is not live child/model proof.
- [ ] Final `/mb verify`: compare every DoD with actual artifacts, all foreign-baseline hashes and residual risks. Append progress and update status/checklist only for accepted stages; entire plan remains open until runtime acceptance passes.

**DoD for completion:**
- [ ] Idempotency, uninstall and rollback tests pass, non-owned settings/files and foreign production diffs are preserved; helper files are packaged/installed and imports resolve.
- [ ] Owned opt-in entrypoint starts the existing real Pi TUI/runtime, preserves ordinary pi and foreign configuration, proves runtime-generation/factory attribution and safe replacement/disposal, and does not auto-load requested Tintin outside that managed runtime. No private imports, alternate child executor or model-loop implementation.
- [ ] Real installed Pi runtime demonstrates native start/work and governed role dispatch via Nico and Tintin with both installed; actual selected provider/model, no substituted role/engine, preserved ownership and cancellation are evidenced. Shared capture then second-session restore, compaction handoff, native graph tools/hooks and offline vector search after restart remain mandatory, with no duplicated memory services.
- [ ] Real negative work verifier/review/judge fixture leaves task open; no unavailable API is claimed supported. Infrastructure failures stop with exact identity/path diagnostics.
- [ ] Final independent verification, Codex plus parent review, judge and `/mb verify` pass; scoped reports include commands/exits/artifact paths and any preexisting failures. No publish/commit and no blanket host-parity claim beyond measured scenarios.
