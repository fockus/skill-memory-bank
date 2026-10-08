# Stage 1 closure — AGR-088 / ADR-013 delta (2026-10-08)

Executor: Claude Code mb-developer (medium preset, AGR-086/087). No commit, no plan checkbox flipped.
Verifier / review / judge for the whole plan have NOT run yet; nothing below is stage acceptance.

## Change set

- `adapters/pi_native_backend.mjs` — default backend `tintin`; Nico requires `service.registerCapabilityCeiling`
  (else refuses in `createBackend`); each Nico dispatch registers
  `{allowedTools: <role effective allowlist>, allowedAgents: [], denyExtensions: true}` for the parent session
  before `dispatchNative` and disposes it after the terminal; registration failure refuses launch (no Tintin fallback);
  Nico terminal + backend carry `runtimeInventory: {status: "UNVERIFIED", reason}`.
- `adapters/pi_native_work.mjs` — work result carries `runtimeInventory` (Nico only; absent for Tintin).
- `adapters/pi_native_bootstrap.mjs` — Nico component also loads the public `pi-subagents/capability-ceiling`
  export `registerSubagentCapabilityCeiling` (same pattern as `./preflight`).
- `adapters/pi_subagent_extension.ts` — tool parameter description: fallback is Tintin.
- `tests/fixtures/pi_native_host.mjs` — ceiling double records registrations and the ceiling active at each Nico spawn;
  `ceilingFails` / `noCeilingApi` inputs.
- `tests/pytest/test_pi_native_work.py` — `project(backend="nico")` writes `pi_subagent_backend` so the existing
  Nico battery keeps selecting Nico through bank policy after the default flip.
- `tests/pytest/test_pi_native_backends.py` — 5 new tests (8 cases).
- `references/pi-native-integration.md` — default backend + Nico ceiling/UNVERIFIED (4 lines).

Pre-edit sha256: backend 5f2bc5ef…, work b8e39df9…, bootstrap 68e275df…, extension 7a802d8d….
Post-edit sha256: backend 59918aea…, work 04964763…, bootstrap e5d04483…, extension 0b4199df….

## RED (new tests written first, production unchanged)

`.venv/bin/python -m pytest -q tests/pytest/test_pi_native_commands.py tests/pytest/test_pi_native_work.py tests/pytest/test_pi_native_backends.py tests/pytest/test_pi_native_host.py`

```
FAILED test_pi_native_backends.py::test_default_backend_is_tintin_without_flag_or_config
FAILED test_pi_native_backends.py::test_nico_launches_only_under_registered_capability_ceiling
FAILED test_pi_native_backends.py::test_nico_refuses_launch_without_capability_ceiling[ceilingFails]
FAILED test_pi_native_backends.py::test_nico_refuses_launch_without_capability_ceiling[noCeilingApi]
FAILED test_pi_native_backends.py::test_nico_reports_runtime_inventory_unverified_tintin_does_not
5 failed, 76 passed in 143.42s
```

Behavioral failures (launches went to Nico; no ceiling registered; launch not refused; `KeyError: 'runtimeInventory'`),
not collection/import errors. `test_bank_config_and_flag_override_default` (3 cases) passed in RED as a guard on
existing precedence.

## GREEN

- Same four files: `81 passed in 128.64s` (73 prior + 8 new).
- `bats tests/bats/test_pi_agents_dispatch.bats`: 22 ok, 0 not ok.
- `node --check` ok: pi_native_backend.mjs, pi_native_work.mjs, pi_native_bootstrap.mjs, tests/fixtures/pi_native_host.mjs.
- `ruff check` + `ruff format --check` on the two changed pytest files: clean. No shell files changed.
- Real public export probe (sandbox HOME, read-only package): `loadBackendFactory(~/.pi/agent/npm/node_modules/pi-subagents)`
  returned Nico 0.76.0 with `registerCapabilityCeiling`; registration produced
  `{"version":1,"allowedTools":["bash","read"],"allowedAgents":[],"denyExtensions":true,"sources":["memory-bank-native"]}`
  in the globalThis registry; dispose left 0 sessions. Registration only; no Nico child was launched, so actual
  enforcement on a real child is not observed here.

## Stage 1 checkbox map

| # | Checkbox | State | Evidence / what remains |
|---|----------|-------|-------------------------|
| T1 | Fixtures for local/global/legacy/absent banks + fake RPC; behavioral tests first | done | `tests/pytest/test_pi_native_commands.py` (layouts, no-bank), `tests/fixtures/pi_native_host.mjs`; `stage1-red.md` |
| T2 | Commands/work RED + source hashes in `stage1-red.md` | done | `stage1-red.md`, `stage1-red.log` |
| T3 | Dual-backend tests first; RED in `stage1-dual-backend-red.md` | done | `stage1-dual-backend-red.md/.log`, `stage1-dual-backend-preimages.json`; AGR-088 delta RED above |
| T4 | Host tests + SDK fixture; RED in `stage1-managed-host-red.md` | done | `tests/pytest/test_pi_native_host.py`, `stage1-managed-host-red.md` |
| T5 | Minimal public-SDK root + real model-free smoke | done | `stage1-managed-host-smoke.md` (SDK 1.0.2, Nico 0.76.0, Tintin 0.19.0, 0 model/spawn requests) |
| T6 | AGR-059 leaf probe | UNVERIFIED | `stage1-agr059-leaf-probe.md` = BLOCKED: no public zero-request pre-model boundary for Tintin; real leaf never run. For Nico, AGR-088 accepts UNVERIFIED inventory; the Tintin leaf proof is still open (see DoD D4) |
| T7 | Native handlers, one gate driver, public adapters, no private imports/fallback | done | `adapters/pi_native_{commands,work,backend,subagents,tintin,roles}.mjs`; ceiling via public `pi-subagents/capability-ceiling` export only |
| T8 | Four pytest files GREEN, 22 Bats, compat, node/static | done (fixture level) | 81 passed / 22 ok / node --check / ruff above. Adapter-compat suites outside these files were not re-run in this delta (prior `stage1-adapter-compat.log`) |
| D1 | Binding/startup RED→GREEN + real model-free SDK smoke | done | T4/T5 evidence; `test_pi_native_host.py` GREEN |
| D2 | Ordinary pi/foreign config unchanged; mechanical commands without binding; mentions override; worktree/auto-commit refuse | done (fixture + smoke) | `test_runtime_overlay_preserves_foreign_settings_and_cwd`, `test_enabled_or_unknown_tintin_mentions_block_either_engine`, `test_tintin_external_runner_and_isolation_refuse_before_implementation`. Live TUI is Stage 5 |
| D3 | Mechanic execution + governed dispatch for ≥2 pipelines incl. named from `.mb-config` | done | `test_named_pipeline_dispatch_and_durable_outputs`, `test_selected_engine_runs_common_native_pipeline[named]` |
| D4 | Both backends pass common battery; one backend per run; Tintin default; Nico under ceiling + UNVERIFIED; unsupported runners fail early | partially done | Done: `test_selected_engine_runs_common_native_pipeline`, `test_both_engines_enforce_negative_gates`, new default/ceiling/UNVERIFIED tests. UNVERIFIED: the common battery runs against contract doubles, not real Nico/Tintin children; real Tintin leaf runtime inventory (T6) is not demonstrated |
| D5 | Negative gates refuse closure; no cross-backend execution; wrong-engine/resume/provider drift fail early; no listener leaks | done (fixture level) | `test_negative_gate_retains_open_source_and_run`, `test_malformed_verdict_never_closes`, `test_cancel_stops_only_selected_owned_child`, resume/model tests in `test_pi_native_work.py`, ceiling refusal tests. Cross-session listener leakage is tested only within one fixture process |
| D6 | Alias registrations for all MB templates; agentic vs mechanical routing; child tool scoping; no unselected-backend bypass | done (fixture level) | `test_goal_collision_and_all_template_aliases`, Nico ceiling `allowedTools`/`allowedAgents: []` test; leaf-profile `allowedAgents: []` in `pi_native_roles.mjs`. Real child scoping enforcement UNVERIFIED (no live child) |
| D7 | Independent verify PASS, Codex + main review, judge GO | remaining | Not run; scheduled once per plan under the medium preset (AGR-087) |

Totals: done 12 (T1–T5, T7, T8, D1–D3, D5, D6; T8/D2/D5/D6 at fixture level), partially done 1 (D4),
UNVERIFIED 1 (T6), remaining 1 (D7) — 15 rows.

Remaining before closure:
1. D7: plan-level verifier, Codex + main-session review, judge.
2. D4/T6: real Tintin leaf runtime-inventory proof (blocked on a public pre-model boundary) — needs an owner decision:
   accept it as UNVERIFIED like Nico, or defer it to the Stage 5 live acceptance.
3. Live Pi TUI / real-provider acceptance is Stage 5 and is not claimed here.

## Risks

- The ceiling is session-scoped: while a Nico child is in flight, the parent session's own `subagent` calls are
  limited by the same ceiling (it is disposed once the terminal arrives). Per the public docs the snapshot carries
  over to async children at launch, so disposing after the terminal is safe; this was not observed on a real child.
- Nico enforcement of the ceiling on the RPC `spawn` path is assumed from public docs + source call sites
  (`async-execution.js` resolves the current-session ceiling); not exercised with a live child.
- The default flip changes behavior for any bank without `pi_subagent_backend`: such banks now need Tintin 0.19.0
  loaded in the managed runtime, or the run fails closed with "Selected tintin backend is unavailable".
