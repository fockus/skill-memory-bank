---
type: feature
topic: global-storage-agent-support
status: queued
parallel_safe: false
depends_on: [2026-05-21_feature_global-storage.md]
linked_specs: []
sprint: Sprint 2
phase_of: global-storage
---

# Plan: feature — global-storage-agent-support

**Baseline commit:** f16e5715854828431fe5820c10d0ad062e4f9892

## Context

**Problem:** Sprint 1 introduces agent-agnostic storage resolution and global init mode. To satisfy the user requirement fully, every supported code agent must use the same resolved `mb_path`; otherwise some hooks/adapters will keep reading or writing `<project>/.memory-bank/` and global mode will work only partially.

**Expected result:** Claude Code, Cursor, Codex, OpenCode, Pi, Windsurf, Cline, Kilo and git-hooks fallback either call shared resolver-aware scripts or receive resolved `MB_PATH` explicitly. Docs and tests prove global storage is supported across the full adapter matrix.

**Dependency:** Execute after [feature — global-storage-core](2026-05-21_feature_global-storage.md) Stage 1-5 are green. This Sprint assumes `scripts/_lib.sh` exposes resolver helpers and `scripts/mb-init-bank.sh --storage=global` writes a registry.

**Related files:**
- `install.sh` — global install and project adapter orchestration.
- `adapters/*.sh` — project-level wiring for Cursor, Windsurf, Cline, Kilo, OpenCode, Pi, Codex and git hooks fallback.
- `hooks/*.sh` — session/context hooks that currently assume local paths in several places.
- `adapters/_lib_agents_md.sh` — shared AGENTS.md section renderer.
- `docs/install.md`, `docs/cross-agent-setup.md`, `README.md`, `SKILL.md` — user-facing installation and support matrix.
- `tests/bats/test_*_adapter.bats`, `tests/pytest/test_cursor_hooks_registration.py`, `tests/pytest/test_runtime_contract.py` — adapter contract suite.

## Requirements by example

| Agent | Global bank location example | Required behavior |
|-------|------------------------------|-------------------|
| Claude Code | `$HOME/.claude/memory-bank/projects/api-a1b2c3d4e5f6/.memory-bank` | `/mb start`, hooks and scripts read resolved path. |
| Cursor | `$HOME/.cursor/memory-bank/projects/api-a1b2c3d4e5f6/.memory-bank` | Global sessionStart hook injects context from resolved bank for the active workspace. |
| Codex | `$HOME/.codex/memory-bank/projects/api-a1b2c3d4e5f6/.memory-bank` | Global AGENTS includes quality rules even when no project adapter or `.memory-bank/` exists; hooks do not require project `.memory-bank/`. |
| OpenCode | `$HOME/.config/opencode/memory-bank/projects/api-a1b2c3d4e5f6/.memory-bank` | Plugin auto-capture writes to resolved path, not hard-coded local path. |
| Pi | `$HOME/.pi/agent/memory-bank/projects/api-a1b2c3d4e5f6/.memory-bank` | Pi AGENTS prompt distinguishes global install from resolved bank activation. |
| Windsurf/Cline/Kilo | agent config root from Sprint 1 resolver | If the host has a user/global rules surface, install rules there; otherwise docs clearly require project adapter or manual rules import. Adapter-installed rules and fallback hooks call resolver-aware scripts. |

## Architecture decision for this Sprint

1. Adapters must not duplicate path resolution logic. They either:
   - call shared shell scripts that source `scripts/_lib.sh`; or
   - set `MB_AGENT=<agent>` and `MB_PROJECT_ROOT=<project>` before invoking a shared script.
2. Hook scripts must accept `MB_PATH` as an override and otherwise resolve from cwd/workspace root.
3. JavaScript plugin code for OpenCode must not reimplement registry parsing if avoidable. Preferred approach: generated plugin calls a small bundled shell command that resolves path and performs auto-capture. If direct JS is unavoidable, add a mirrored contract test against the shell resolver examples.
4. All agents remain opt-in for project adapters. Global storage support is a runtime storage feature, not a reason to write new project files unless the user selected that adapter.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Adapter and hook inventory tests

**What to do:**
- Add a deterministic audit test that scans `adapters/`, `hooks/`, `commands/`, and `install.sh` for hard-coded runtime reads/writes to `<project>/.memory-bank/`.
- Add a global rules-only audit: every global agent entrypoint must include or point to the critical quality rules independently of Memory Bank activation.
- Whitelist documentation examples and tests that intentionally mention local mode.
- Produce a failing report listing exact files and lines that must be converted to resolver-aware calls or rules-only support.

**Testing (TDD — tests BEFORE implementation):**
- Add `tests/pytest/test_global_storage_contract.py` before implementation.
- The test must fail initially on current hard-coded patterns such as `path.join(app.path.cwd, '.memory-bank')` in the OpenCode plugin template and direct `.memory-bank/progress.md` assumptions in hook/adapters.
- The test must also fail if Codex global `AGENTS.md` omits TDD/SOLID/Clean Architecture/DRY/KISS/YAGNI rules while claiming global support.
- Red command: `pytest -q tests/pytest/test_global_storage_contract.py`.

**DoD (Definition of Done):**
- [ ] Audit test exists and reports actionable file:line failures.
- [ ] Whitelist is narrow and documented inside the test with reason strings.
- [ ] Test distinguishes documentation examples for local mode from runtime hard-coding.
- [ ] Test distinguishes Memory Bank lifecycle guidance from always-on quality rules.
- [ ] No production files are changed in this stage.
- [ ] Red failure confirms the test protects the cross-agent requirement.

**Code rules:** TDD red phase, drift checker for cross-surface requirements, no broad regex false positives without whitelist reason.

---

<!-- mb-stage:2 -->
### Stage 2: Resolver-aware hooks and shared fallback scripts

**What to do:**
- Update hook scripts that read/write Memory Bank data to resolve `MB_PATH` through `scripts/_lib.sh` when possible:
  - `hooks/session-end-autosave.sh`
  - `hooks/mb-session-start-context.sh`
  - `hooks/mb-compact-reminder.sh`
  - `hooks/file-change-log.sh` if it references bank-local state
  - `adapters/git-hooks-fallback.sh` generated hook bodies
- Preserve no-op behavior when no bank is resolved.
- Ensure hook bodies can find the installed skill script directory from global install paths for Claude, Cursor, Codex, OpenCode and Pi.

**Testing (TDD — tests BEFORE implementation):**
- Extend existing bats suites before production changes:
  - `tests/bats/test_auto_capture.bats` for global registry capture.
  - `tests/bats/test_compact_reminder.bats` for global `.last-compact` lookup.
  - `tests/bats/test_git_hooks_fallback.bats` for post-commit writing to external bank.
- Add at least one test with a project path containing spaces.
- Verification commands:
  - `bats tests/bats/test_auto_capture.bats tests/bats/test_compact_reminder.bats tests/bats/test_git_hooks_fallback.bats`
  - `pytest -q tests/pytest/test_global_storage_contract.py`

**DoD (Definition of Done):**
- [ ] Session-end auto-capture appends to global `progress.md` when registry exists and local `.memory-bank/` is absent.
- [ ] Auto-capture remains silent no-op when neither local nor global bank exists.
- [ ] Git hooks fallback uses external bank in global mode and preserves existing local-mode tests.
- [ ] Hooks keep safety semantics: no secret leakage, no unexpected file creation, no crash on missing optional tools.
- [ ] Contract audit no longer flags hook runtime hard-coding.

**Code rules:** Reuse resolver, fail-open for advisory hooks, preserve existing hook safety gates.

---

<!-- mb-stage:3 -->
### Stage 3: Adapter matrix support

**What to do:**
- Update adapters to pass agent identity and project root to generated hooks/rules where needed:
  - `adapters/cursor.sh`
  - `adapters/codex.sh`
  - `adapters/opencode.sh`
  - `adapters/pi.sh`
  - `adapters/windsurf.sh`
  - `adapters/cline.sh`
  - `adapters/kilo.sh`
  - `adapters/git-hooks-fallback.sh`
- Update generated AGENTS/rules snippets to say agents should resolve Memory Bank through the skill scripts, not only check `./.memory-bank/`.
- For OpenCode plugin, replace direct JS local path logic with resolver-aware shell invocation or a generated helper path that calls shell.

**Testing (TDD — tests BEFORE implementation):**
- Extend each adapter bats suite with a global-storage case in a sandboxed `$HOME`:
  - install adapter;
  - initialize global bank for that agent;
  - assert generated files contain `MB_AGENT=<agent>` or equivalent resolver-aware invocation;
  - run the generated hook/plugin smoke where feasible.
- Focused commands:
  - `bats tests/bats/test_cursor_adapter.bats tests/bats/test_codex_adapter.bats tests/bats/test_opencode_adapter.bats`
  - `bats tests/bats/test_pi_adapter.bats tests/bats/test_windsurf_adapter.bats tests/bats/test_cline_adapter.bats tests/bats/test_kilo_adapter.bats`
- Run `pytest -q tests/pytest/test_cursor_hooks_registration.py` for Cursor global hook wiring.

**DoD (Definition of Done):**
- [ ] Every supported adapter has at least one test proving generated integration is compatible with global storage.
- [ ] Existing install/uninstall idempotency tests still pass for all adapters.
- [ ] OpenCode no longer hard-codes `app.path.cwd/.memory-bank` for runtime capture.
- [ ] Pi default `agents-md` and `MB_PI_MODE=skill` both include resolver-aware guidance.
- [ ] Adapter manifests remain safe: uninstall removes only owned files and never deletes external Memory Bank data.

**Code rules:** Adapter contract preservation, no duplicate resolver implementations, uninstall safety, idempotency.

---

<!-- mb-stage:4 -->
### Stage 4: Install flow and user choice documentation

**What to do:**
- Decide and document the exact boundary between `memory-bank install` and `/mb init`:
  - `install` installs global skill/adapters and may explain storage choices;
  - `/mb init` creates the actual project bank in `local` or `global` mode.
- If install has a TTY and selected project adapters, add a short post-install prompt or final message that tells the user to run `/mb init` and choose storage mode; do not create a bank automatically during install.
- Update `docs/install.md`, `docs/cross-agent-setup.md`, `README.md`, and `SKILL.md` support matrix with local vs global storage examples for each agent.
- Add an explicit **rules-only mode** section: users can intentionally work without any Memory Bank in a repository; installed global rules still apply, and Memory Bank commands remain inactive until `/mb init`.
- Add migration guidance: existing local bank users can stay local; moving data to global is intentionally out of scope for this Sprint unless a separate migration plan is created.

**Testing (TDD — tests BEFORE implementation):**
- Extend `tests/bats/test_install_interactive.bats` for final message/help text with storage choices.
- Extend `tests/pytest/test_runtime_contract.py` for docs support matrix entries for all eight clients.
- Add tests that generated global prompts for Claude, Cursor, Codex, OpenCode and Pi include `[MEMORY BANK: ABSENT]` plus TDD/SOLID/Clean Architecture/DRY/KISS/YAGNI rules in the same rules-only surface.
- Verify no install path creates Memory Bank data by default with a sandboxed HOME/project smoke.
- Commands:
  - `bats tests/bats/test_install_interactive.bats`
  - `pytest -q tests/pytest/test_runtime_contract.py`

**DoD (Definition of Done):**
- [ ] Install help/final message explains both storage choices and points to `/mb init`.
- [ ] Docs include one command example for local mode and one for global mode.
- [ ] Docs explicitly say global mode is personal storage and should not be committed to the project repo.
- [ ] Docs explicitly say local mode is for team-shared bank when the team agrees to keep it in git.
- [ ] Docs explicitly say rules-only mode is valid: no local/global Memory Bank, no auto-init, quality rules still apply.
- [ ] Tests prove install does not silently create either local or global bank.

**Code rules:** Clear UX, no hidden side effects, repository cleanliness by default remains user-controlled.

---

<!-- mb-stage:5 -->
### Stage 5: End-to-end cross-agent smoke suite

**What to do:**
- Add a compact end-to-end test path that covers the full story once, not eight expensive full flows:
  - install selected clients in sandboxed HOME;
  - init global bank for one representative shell adapter and one native/global adapter;
  - run context/autocapture flow from a project without `.memory-bank/`;
  - uninstall adapters and verify global bank data remains.
- Use existing bats/pytest structure; do not introduce a new runner.

**Testing (TDD — tests BEFORE implementation):**
- Add `tests/e2e/test_global_storage.bats` before wiring the final implementation.
- Red cases:
  - `global storage e2e: context works without project .memory-bank`.
  - `global storage e2e: uninstall preserves external bank data`.
  - `global storage e2e: local mode remains default`.
- Verification command: `bats tests/e2e/test_global_storage.bats`.

**DoD (Definition of Done):**
- [ ] E2E suite passes in a sandboxed `$HOME` and project temp dir.
- [ ] E2E suite asserts project directory has no `.memory-bank/` in global mode.
- [ ] E2E suite asserts external `progress.md` survives adapter uninstall.
- [ ] Runtime remains stdlib-only plus existing shell tools; no new package dependency is added.
- [ ] Test duration remains acceptable for CI by avoiding a full matrix explosion.

**Code rules:** Testing Trophy integration focus, user data safety, no new dependencies.

---

<!-- mb-stage:6 -->
### Stage 6: Full verification, release notes and Memory Bank closure

**What to do:**
- Run focused suites from both Sprints, then repository-level checks.
- Update `CHANGELOG.md` under `[Unreleased]` with user-facing storage feature summary.
- Update Memory Bank checklist/status as stages complete; run `/mb verify` before `/mb done` because work follows this plan.

**Testing (TDD):**
- Focused global-storage suite:
  - `bats tests/bats/test_mb_storage_resolver.bats tests/bats/test_mb_init_storage.bats tests/e2e/test_global_storage.bats`
  - `pytest -q tests/pytest/test_global_storage_contract.py tests/pytest/test_runtime_contract.py tests/pytest/test_global_prompt_guard.py`
- Adapter suite:
  - `bats tests/bats/test_cursor_adapter.bats tests/bats/test_codex_adapter.bats tests/bats/test_opencode_adapter.bats tests/bats/test_pi_adapter.bats tests/bats/test_windsurf_adapter.bats tests/bats/test_cline_adapter.bats tests/bats/test_kilo_adapter.bats tests/bats/test_git_hooks_fallback.bats`
- Full smoke:
  - `pytest -q`
  - `bats tests/bats tests/e2e`
  - `ruff check .`
  - `shellcheck install.sh scripts/*.sh adapters/*.sh hooks/*.sh`

**DoD:**
- [ ] All focused global-storage tests pass.
- [ ] Full pytest passes or every pre-existing failure is documented with proof it predates this plan.
- [ ] Full bats passes or every pre-existing failure is documented with proof it predates this plan.
- [ ] Ruff and shellcheck are clean for changed files; repo-wide shellcheck is clean if it was clean before the Sprint.
- [ ] `CHANGELOG.md` documents local/global storage, supported agents, and backward compatibility.
- [ ] `/mb verify` reports no CRITICAL items for both Sprint plans.

**Code rules:** Verification before completion, changelog for user-visible feature, protected files remain untouched.

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Adapter matrix creates too many slow tests | High | Add one focused global case per adapter plus one compact E2E; avoid duplicating full workflows. |
| OpenCode JS plugin cannot call shell reliably on all platforms | Medium | Keep fallback local no-op with clear warning only if shell missing; test shell-present path because skill requires bash. |
| Generated prompts drift from resolver semantics | Medium | Add contract test scanning generated docs for local-only active-state wording. |
| Uninstall accidentally deletes global bank data | Medium | Manifest tests assert external bank path is not tracked as adapter-owned file. |
| Agent config root differs on a user's machine | Medium | Support documented `MB_AGENT_CONFIG_DIR` or `MB_GLOBAL_STORAGE_ROOT` override if Sprint 1 implements it; include docs and tests. |
| Existing local project teams are confused by new option | Low | Keep local as default and docs phrase global as personal opt-in storage. |

## Gate (Sprint 2 success criterion)

Sprint 2 is complete when every supported adapter and hook either delegates Memory Bank path resolution to the shared resolver or passes an explicit resolved `MB_PATH`, documentation shows local/global storage choices for all supported agents, uninstall never removes global bank data, and the focused global-storage plus adapter suites pass.