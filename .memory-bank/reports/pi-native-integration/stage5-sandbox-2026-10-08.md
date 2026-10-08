# Stage 5 — sandbox part (TDD steps 1–4) — 2026-10-08

Executor: Claude Code mb-developer (medium preset, AGR-086/087). There is no commit and no plan checkbox was flipped. The real `~/.pi`, `~/.claude`, `~/.codex`, PATH and rc files were not touched: every install ran under `HOME=$(mktemp -d)` (agentDir and project paths contain spaces). Tintin 0.19.0 and its 4 dependencies were installed only into sandbox prefixes with `--legacy-peer-deps`, which matches Pi's own install flags. Nico 0.76.0 was used read-only through a symlink. The tests made no model or provider requests: there are no credentials and `PI_OFFLINE=1` is set.
Coordinator-approved scope extension: `adapters/pi_native_bootstrap.mjs`. Item (1) drops the duplicate owned MB extension. Item (2) recomposes the native backend packages through public SDK API only.

## Change set

- `adapters/_lib_pi_owned.sh` (new). Ownership ledger `<agentDir>/.mb-pi-native-owned.json`, holding sha256 and preimage per file and updated after every write. A replaced foreign file moves to `.mb-pi-preimages/`. A user-edited owned file is never overwritten or removed. Removal restores preimages.
- `adapters/_lib_pi_extensions.sh`. The template helper gains an `owned` mode. `install_global_extensions` first runs a preflight that refuses a foreign `bin/mb-pi` or unreadable settings. It then marks the manifest `install_state: in_progress` with no capabilities, makes owned writes, records `native` provenance (`skill_dir`, version, `default_backend: tintin`, `tintin_package`, `tintin_entry`, Nico opt-in UNVERIFIED, entrypoint), sets `managed_entrypoint` and marks the run `complete`. A new `uninstall_global_extensions` reverses it.
- `adapters/_lib_pi_subagent.sh`. The roster is now written through ownership. All `pi_native_*.mjs` helpers are copied verbatim next to `memory-bank-subagent.ts`. Adds the `bin/mb-pi` installer and the foreign-file check.
- `adapters/_lib_pi_global.sh`: `pi_settings_tintin add|remove|check`. It appends `{"source":"npm:@tintinweb/pi-subagents@0.19.0","extensions":[]}` additively and leaves any existing entry for the package untouched. Invalid settings refuse with no write.
- `adapters/pi.sh`: new action `uninstall-global-extensions`.
- `adapters/pi_managed_entrypoint.mjs` (new). It is installed as `<agentDir>/bin/mb-pi` and resolves agentDir from its own realpath. The SDK comes from `MB_PI_SDK_ROOT`, otherwise from `pi` on PATH. Packages come from `<agentDir>/npm/node_modules` or `MB_PI_TINTIN_ROOT`/`MB_PI_NICO_ROOT`. It loads the installed `memory-bank-subagent.ts` with the SDK's jiti and calls `createManagedPi`. `--check` prints the binding, tools and extensions, then disposes. Otherwise it starts `InteractiveMode` with the argv messages.
- `adapters/pi_native_bootstrap.mjs`. `managedSettingsStorage` (public `SettingsManager.fromStorage` with the `SettingsStorage` interface) gives the runtime a view of the real settings files. In that view every configured `npm:pi-subagents` / `npm:@tintinweb/pi-subagents` package has `extensions: []`, so its skills and prompts stay, and the discovered owned MB extension is force-excluded. Writes are merged onto the real file content, using the same `<file>.lock` directory Pi takes. A write that would persist `packages`/`extensions` is refused. The ineffective `applyOverrides({packages})` was removed. SDK 1.0.2's `DefaultPackageManager.resolve()` reads `getGlobalSettings()`/`getProjectSettings()`, so that override never reached package resolution. Pre-edit sha256 `e5d04483…`, post-edit `2785defb…`.
- `tests/pytest/test_pi_native_install.py` (new, 18 tests). `references/pi-native-integration.md`: one paragraph on install and removal.

## RED → GREEN receipts

1. Installer RED (`stage5-red-installer.log`): 15 failed, 2 passed in 23.38 s. The failures were behavioral: missing ledger and helpers, `PROJECT_ROOT`, foreign mb-pi not refused, settings not additive, no `native`, no `bin/mb-pi`, TUI never rendered. One assertion was a test bug (`"__MB_"` matched a comment) and was corrected before implementation.
2. Bootstrap RED #1 (`stage5-red-bootstrap-mb-duplicate.log`), after the installer and entrypoint existed: `mb-pi: Managed factory failure: Tool "mb_dispatch_subagent" conflicts with …/extensions/memory-bank-subagent.ts`. The discovered extension and the managed factory both registered the MB extension.
3. Bootstrap RED #2 (`stage5-red-bootstrap-nico.log`), after fix (1): with unfiltered `npm:pi-subagents` in settings, the default Tintin run exposed raw Nico `subagent`. The failure read `raw Nico delegation leaked into the managed runtime`. The other failure in that run came from an over-strict test that counted SDK-created `auth.json`/`models-store.json` as modifications. It was corrected to "pre-existing files unchanged".
4. GREEN: `test_pi_native_install.py` 18 passed. All `tests/pytest/test_pi_native_*.py`: **154 passed, 1 skipped** (FastEmbed model not cached in the sandbox HOME; no download) in 206.89 s (`stage5-green-pytest.log`). `test_managed_settings_view_writes_user_changes_but_never_the_view` was added after GREEN as a characterization test, so it has no RED.
5. Bats, sandbox HOME: test_pi_adapter, test_pi_agents_dispatch, test_pi_session_memory_extension, test_extensions_offer, test_graph_rag_adapters, test_cross_agent_runtime_parity and test_platform_limited_honesty gave **98/98 ok**. test_mb_config_hosts (selected by the graph) gave 30/30 ok, run with `PYTHONUSERBASE` set to the real user base, read-only, for PyYAML. Without it, 27 tests failed on the missing PyYAML, an environment artifact. Pytest selected through the graph and grep: test_docs_drift_recipe plus test_agent_render gave 25 passed.
6. Static: `shellcheck -x` is clean on the four changed or new libs; pi.sh keeps only its 10 pre-existing HEAD findings. `node --check` passes on the bootstrap and the entrypoint. `ruff check` and `ruff format --check` are clean on the test file.

## Stage 5 TDD / DoD table

| Item | State | Evidence / note |
|---|---|---|
| T1 installer ownership/idempotency/removal/rollback, both packages, backend selection, additive settings, custom agent/mention config, RED first | done | tests 1–12 in `test_pi_native_install.py`; RED log |
| T2 managed entrypoint: two installs identical, spaces/quoting stay argv, no PATH/rc/ordinary-pi change, foreign name refuses, uninstall removes only unchanged owned | done | `…identical_owned_output`, `…keeps_argv`, `…shell_rc_path…`, `…foreign_mb_pi_refuses…`, `…uninstall…` |
| T2 real InteractiveMode with a controlled terminal and no model | done (sandbox) | `test_mb_pi_starts_real_interactive_mode_under_pty_without_model`: real SDK 1.0.2 TUI under a pty lists `<inline:mb-managed-mb>`, `<inline:mb-managed-tintin>`, graph and session; quits with Ctrl+D, exit 0; no model configured |
| T2 runtime settings/credentials/trust persist | partially done | settings writes persist to the real file (`…settings_view_writes…`); SDK-created `auth.json` stays in agentDir. Credential reuse and existing project-trust decisions: UNVERIFIED (no credentials; untrusted-project refusal is covered only by Stage 1 tests) |
| T3 wire helpers + mb-pi into opt-in installer, hashes/preimages, non-clobbering settings | done | lib changes above |
| T3 refresh only owned MB prompt copies with backup | not implemented (by design) | install.sh Step 4 already copies `~/.pi/agent/prompts/*.md` with `backup_if_exists` and is off-limits. Extension commands take precedence over same-name prompt templates (`agent-session.js:_tryExecuteExtensionCommand`) |
| T4 tests + regressions in sandbox HOME, static checks | done | receipts 4–6 |
| T5 independent verify/review/judge, then the parent installs on the real host and runs live acceptance | remaining — parent, needs owner approval | |
| T6 final `/mb verify` | remaining — parent | |
| D1 idempotency/uninstall/rollback; non-owned preserved; helpers packaged and imports resolve | done (sandbox) | helpers ship through the wheel's whole-`adapters` shared-data mapping. They are still **untracked in git**, so a commit must add them |
| D2 opt-in entrypoint starts the real TUI, preserves ordinary pi, attribution, no Tintin autoload outside | done (sandbox), live remaining | `…ordinary_sdk_discovery_does_not_load_requested_tintin`; binding attribution through `--check`; replacement/disposal from Stage 1 host tests (16 passing after the bootstrap change) |
| D3 real installed runtime: start/work, role dispatch through Nico and Tintin, provider/model, capture/restore, compaction, graph, offline vectors | remaining — parent, needs owner approval | requires real provider/model and children |
| D4 real negative verifier/review/judge leaves task open | remaining — parent | |
| D5 final verify/review/judge, `/mb verify` | remaining — parent | |

## What the live real-host acceptance would change on the owner's machine

Running `adapters/pi.sh install-global-extensions` (or install.sh's Pi opt-in) for the real HOME writes the following:
- `~/.pi/agent/extensions/`: `memory-bank-{session,graph-rag,subagent}.ts`, `pi_subagent_dispatch_core.mjs` and 11 `pi_native_*.mjs`. Existing same-name foreign files are moved to `~/.pi/agent/.mb-pi-preimages/`.
- `~/.pi/agent/agents/mb-*.md`, the 28-agent roster, with the same preimage rule.
- `~/.pi/agent/bin/mb-pi`, which is not added to PATH.
- One entry appended to `~/.pi/agent/settings.json` `packages`.
- `.mb-global-extensions-manifest.json` and `.mb-pi-native-owned.json`.

After that, the next ordinary `pi` start downloads `@tintinweb/pi-subagents@0.19.0`, using Pi's own package manager, into `~/.pi/agent/npm`, but does not load its extension. Ordinary `pi` also gains the native `/mb` commands; governed work there refuses and points to mb-pi. The live checks themselves (mb-pi with a real model, Tintin default, `--with-nico`, children, gates, capture/restore, compaction, offline vectors, negative/cancel) need the owner's credentials and make real provider requests.

## Risks / follow-ups

- High: the managed view only recognizes `npm:` sources for the two backend packages. A local-path or git install of Nico or Tintin is not filtered. As a component it hits the existing duplicate refusal; when not selected, its raw tool stays visible.
- Med: when InteractiveMode quits it calls `process.exit`, so the bootstrap's temporary `mb-pi-runtime-*` overlay, which holds a 0600 copy of the project `.pi/subagents.json`, is left in the OS temp dir. Follow-up: an exit-time cleanup in the bootstrap.
- Med: inside mb-pi, settings writes that change `packages`/`extensions` are refused (recorded through `drainErrors`). Package management must be done from ordinary pi.
- Low: the ledger's TSV read escapes paths that contain tab or backslash characters.
- Low: `test_pi_native_install.py` is 552 lines after ruff formatting (neighbours: session 512).
- Nico runtime inventory stays UNVERIFIED (AGR-088). The common battery still runs against doubles; real children are live-only.
