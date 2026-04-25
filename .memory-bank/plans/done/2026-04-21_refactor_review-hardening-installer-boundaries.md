# Review Findings Hardening and Installer Boundary Refactor
Date: 2026-04-21
Type: refactor
Status: ✅ Done

**Baseline commit:** `941ba42`

## Context

Full-repo review (`.memory-bank/reports/2026-04-21_review_full-repo-v3-1-1.md`) and security audit (`SECURITY_AUDIT_REPORT.md`) surfaced three classes of problems:

1. **P0 security risks** around path traversal and manifest poisoning in `uninstall.sh`, `scripts/_lib.sh`, and `adapters/pi.sh`, plus unsafe override/symlink behavior in installer paths.
2. **Architectural debt**: `install.sh` is a god-object, Cursor global install logic leaks through the universal installer, adapter boilerplate is duplicated across 7 clients, and shell scripts embed too many untestable Python heredocs.
3. **Contract / maintainability drift**: CLI and uninstall are not automation-safe, manifest schemas diverge, `_lib_agents_md.sh` writes state non-atomically, `mb-compact.sh` mixes compaction with migration, and several direct test gaps remain (`mb-note.sh`, `mb-plan.sh`, `_lib_agents_md.sh`).

The review recommendation is explicit: before `v3.1.0`, close the three High security findings and start the installer/adapters refactor so the next release ships on a safer and smaller surface.

## Scope

**In scope**
- All 3 High findings from `SECURITY_AUDIT_REPORT.md`
- Installer / uninstall hardening for destructive file operations
- CLI + manifest contract cleanup needed for safe automation
- Extracting shared Python helpers out of bash heredocs where it directly reduces duplication and clarifies boundaries
- Adapter framework + contract + unified manifest schema
- Moving Cursor global logic out of `install.sh`
- Splitting structural migration back out of `mb-compact.sh`
- Closing direct test gaps called out in review

**Explicitly out of scope**
- Removing `mb-import.py` completely
- Extracting tree-sitter support out of `mb-codegraph.py`
- Reworking `mb-tags-normalize.sh` into a different product shape
- Dropping `es` / `zh` locale scaffolds
- UI / dashboard / benchmark / semantic-search backlog items
- The `mb-index-json.py` `UTC` note from review: project runtime already requires Python `>=3.11` in `pyproject.toml`, so this does not justify code churn in this plan

## Architectural decisions

1. **Security first, then refactor**: destructive-path validation and manifest hardening land before structural cleanup.
2. **Thin orchestrators, reusable helpers**: `install.sh` / `uninstall.sh` remain entrypoints, but shared text/IO behavior moves into package helpers and adapter framework functions.
3. **Adapters own client specifics**: global/project client behavior belongs in `adapters/*.sh`, not in the universal installer.
4. **One manifest schema**: global installer and adapters emit versioned manifests with deterministic ordering so uninstall and tooling can reason about them safely.
5. **TDD and dogfooding**: every risky step starts with failing tests against real fixtures or sandboxed installs.

```text
memory-bank CLI / install.sh / uninstall.sh
                |
                v
      scripts/_lib.sh + adapters/_framework.sh + adapters/_contract.sh
                |
                v
      memory_bank_skill/_io.py + memory_bank_skill/_texttools.py
                |
                v
   adapters/*.sh, settings/merge-hooks.py, mb-compact.sh, mb-migrate-structure.sh
```

This keeps dependency direction clean: shell entrypoints orchestrate, shared shell helpers coordinate, Python modules provide deterministic text/IO primitives, and adapters own client-specific integration.

## Stages

<!-- mb-stage:1 -->
### Stage 1: Security hardening for destructive paths and override entrypoints
**Goal:** Eliminate the 3 High findings and the related symlink / override risks without changing user-visible workflows beyond explicit safety guards.
**Files:**
- Modify: `scripts/_lib.sh`, `install.sh`, `uninstall.sh`, `adapters/pi.sh`, `scripts/mb-metrics.sh`
- Create/Modify tests: `tests/bats/test_lib.bats`, `tests/bats/test_metrics.bats`, `tests/bats/test_pi_adapter.bats`, `tests/e2e/test_install_uninstall.bats`, `tests/pytest/test_cli.py`

**Implementation:**
1. Add safe path helpers to `scripts/_lib.sh` for canonicalization / subtree validation and reuse them from callers.
2. Sanitize `.claude-workspace` `project_id` in `mb_resolve_path()` and reject traversal / malformed external workspace targets.
3. Update `uninstall.sh` to canonicalize manifest paths before delete / restore and skip anything outside managed roots.
4. Update `adapters/pi.sh` to validate `pi_skill_dir` against `~/.pi/skills/` before `rm -rf`.
5. Harden `install.sh::backup_if_exists()` against symlink targets that escape managed directories.
6. Gate `.memory-bank/metrics.sh` execution behind explicit opt-in (`MB_ALLOW_METRICS_OVERRIDE=1`) with a clear warning path.

**Tests (TDD — written BEFORE implementation):**
- Unit: traversal payload in `.claude-workspace`; manifest path like `$HOME/.claude/../../tmp/x`; invalid `pi_skill_dir`; symlinked backup target; override script blocked by default and allowed only with env opt-in.
- Integration: sandboxed install/uninstall roundtrip preserves managed dirs while refusing poisoned paths.
- E2E: uninstall against a sandbox HOME still removes expected files but never touches outside paths.

**DoD (Definition of Done):**
- [ ] Traversal payloads in `.claude-workspace`, uninstall manifest, and `pi` manifest all fail closed in tests
- [ ] `backup_if_exists()` refuses unsafe symlink targets and keeps the old idempotent path for safe regular files
- [ ] `scripts/mb-metrics.sh` does not execute `.memory-bank/metrics.sh` unless `MB_ALLOW_METRICS_OVERRIDE=1`
- [ ] All new unit + integration + e2e tests for Stage 1 are written first and passing
- [ ] No new `rm -rf` / `mv` path uses an unvalidated manifest-derived path
- [ ] Dependency direction is correct: shared path validation lives in `_lib.sh`, not duplicated across callers
- [ ] Code passed self-review

<!-- mb-stage:2 -->
### Stage 2: CLI and uninstall contract cleanup
**Goal:** Make install/uninstall automation-safe and make global manifest output deterministic and machine-readable.
**Files:**
- Modify: `memory_bank_skill/cli.py`, `install.sh`, `uninstall.sh`
- Create/Modify tests: `tests/pytest/test_cli.py`, `tests/bats/test_install_interactive.bats`, `tests/e2e/test_install_clients.bats`, `tests/e2e/test_install_uninstall.bats`

**Implementation:**
1. Add failing tests for CLI-side client validation, uninstall `--non-interactive` / `-y`, and deterministic manifest ordering.
2. Validate `--clients` in `memory_bank_skill/cli.py` before delegating to shell.
3. Add uninstall flags for non-interactive use and wire them through the Python CLI.
4. Replace `set()`-based manifest dedupe in `install.sh` with stable ordered dedupe.
5. Add `schema_version` to the global install manifest and document exit-code behavior in CLI code/tests.

**Tests (TDD — written BEFORE implementation):**
- Unit: invalid client list rejected in CLI; uninstall command forwards `-y`; manifest preserves deterministic file order.
- Integration: `memory-bank uninstall -y` works in a sandbox without stdin prompt.
- E2E: `install.sh --clients ...` + `uninstall.sh -y` run non-interactively in CI-compatible sandboxes.

**DoD (Definition of Done):**
- [ ] `memory-bank install` fails early on unknown clients with a clear error before `install.sh` runs
- [ ] `memory-bank uninstall -y` and `uninstall.sh -y` both skip the prompt and exit cleanly in tests
- [ ] Global manifest contains `schema_version` and deterministic `files` / `backups` order
- [ ] All Stage 2 unit + integration + e2e tests are written first and passing
- [ ] No CLI path depends on interactive stdin when explicit non-interactive flags are passed
- [ ] No `SOLID` / `DRY` / `KISS` violations introduced to `cli.py` or shell entrypoints
- [ ] Code passed self-review

<!-- mb-stage:3 -->
### Stage 3: Extract shared Python text and IO helpers
**Goal:** Remove the highest-value duplicated heredoc logic from bash and make text/atomic-write behavior directly testable.
**Files:**
- Create: `memory_bank_skill/_io.py`, `memory_bank_skill/_texttools.py`
- Modify: `memory_bank_skill/__main__.py`, `install.sh`, `uninstall.sh`, `adapters/_lib_agents_md.sh`, `scripts/mb-import.py`, `scripts/mb-index-json.py`, `scripts/mb-codegraph.py`
- Create/Modify tests: `tests/pytest/test_merge_hooks.py`, `tests/pytest/test_import.py`, `tests/pytest/test_index_json.py`, `tests/pytest/test_codegraph.py`, new `tests/pytest/test_texttools.py`

**Implementation:**
1. Write failing pytest coverage for shared `atomic_write`, marker stripping, and language-rule substitution behavior.
2. Extract reusable atomic write helper from the Python scripts into `memory_bank_skill/_io.py`.
3. Extract text transforms used by installer/uninstaller (`strip_marked_section`, `localize_language_rule`, similar helpers) into `memory_bank_skill/_texttools.py`.
4. Replace the four duplicated AGENTS cleanup heredocs in `uninstall.sh` with shared helper invocations.
5. Replace duplicated atomic-write implementations in Python scripts with imports from `_io.py`.

**Tests (TDD — written BEFORE implementation):**
- Unit: atomic write rollback on exception; marker-strip keeps user content; localization replaces only the intended language rules.
- Integration: uninstall cleans OpenCode/Codex/Cursor/CLAUDE sections through one shared path.
- E2E: install/uninstall smoke still passes after heredoc removal.

**DoD (Definition of Done):**
- [ ] `memory_bank_skill/_io.py` and `memory_bank_skill/_texttools.py` exist with direct pytest coverage
- [ ] `scripts/mb-import.py`, `scripts/mb-index-json.py`, and `scripts/mb-codegraph.py` no longer each define their own `_atomic_write()`
- [ ] `uninstall.sh` no longer contains four near-identical Python blocks for AGENTS cleanup
- [ ] All Stage 3 unit + integration + e2e tests are written first and passing
- [ ] Installer / uninstaller remain runnable directly from repo checkout and from bundled install layout
- [ ] Dependency direction is correct: shell orchestrates, Python helpers encapsulate text / IO mechanics
- [ ] Code passed self-review

<!-- mb-stage:4 -->
### Stage 4: Adapter framework, contract, and manifest schema unification
**Goal:** Replace the heaviest adapter duplication with a shared framework and one versioned manifest contract.
**Files:**
- Create: `adapters/_framework.sh`, `adapters/_contract.sh`, `references/adapter-manifest-schema.md`
- Modify: `adapters/_lib_agents_md.sh`, `adapters/cursor.sh`, `adapters/windsurf.sh`, `adapters/cline.sh`, `adapters/kilo.sh`, `adapters/opencode.sh`, `adapters/pi.sh`, `adapters/codex.sh`
- Create/Modify tests: direct `tests/bats/test_agents_md_lib.bats`, existing adapter bats suites, `tests/e2e/test_install_clients.bats`

**Implementation:**
1. Write failing tests for `_lib_agents_md.sh` refcount behavior, framework manifest writing, and adapter contract invariants.
2. Define required adapter entrypoints (`install`, `uninstall`) and shared helpers for manifest writing, hook JSON merge, rules-file emission, and uninstall file cleanup.
3. Make `_lib_agents_md.sh` use atomic writes and explicit `jq` preflight.
4. Standardize adapter manifests around `schema_version`, `adapter`, `installed_at`, `files`, and adapter-specific optional keys.
5. Migrate each adapter to the shared framework without changing its public CLI.

**Tests (TDD — written BEFORE implementation):**
- Unit: direct tests for owner refcount transitions, atomic owner-file writes, contract failure when required functions are missing.
- Integration: each adapter still installs and uninstalls through its existing bats suite with the new manifest schema.
- E2E: multi-client install still creates the expected project files and no adapter loses coexistence behavior.

**DoD (Definition of Done):**
- [ ] `adapters/_framework.sh` and `adapters/_contract.sh` exist and are sourced by all 7 adapters
- [ ] `_lib_agents_md.sh` writes owner state atomically and fails clearly when `jq` is missing
- [ ] Adapter manifests share one documented schema with `schema_version`
- [ ] All existing adapter bats suites plus new direct `_lib_agents_md.sh` tests are written first and passing
- [ ] No adapter loses OpenCode/Codex/Pi shared `AGENTS.md` coexistence guarantees
- [ ] No `DRY` violation remains for manifest boilerplate across adapters where framework helpers can own it
- [ ] Code passed self-review

<!-- mb-stage:5 -->
### Stage 5: Installer boundary cleanup and adapter-driven uninstall
**Goal:** Make `install.sh` a thinner orchestrator by moving Cursor global logic into the adapter layer and teaching uninstall to delegate adapter cleanup.
**Files:**
- Modify: `install.sh`, `uninstall.sh`, `adapters/cursor.sh`, `adapters/opencode.sh`, `adapters/codex.sh`, `adapters/pi.sh`, `adapters/git-hooks-fallback.sh`, `memory_bank_skill/cli.py`
- Create/Modify tests: `tests/e2e/test_cursor_global.bats`, `tests/e2e/test_install_uninstall.bats`, `tests/pytest/test_cli.py`, adapter bats suites

**Implementation:**
1. Write failing tests that prove Cursor global artifacts are installed through adapter-owned logic and removed through adapter-driven uninstall.
2. Move Cursor global hooks / AGENTS / user-rules behavior out of `install.sh` into `adapters/cursor.sh` using explicit mode or helper entrypoints.
3. Reduce `install.sh` to orchestration: canonical skill registration, global shared files, adapter invocation.
4. Make `uninstall.sh` discover adapter manifests and invoke adapter uninstall flows instead of relying only on the global manifest.
5. Record adapter-owned artifacts in a way the global uninstall can safely enumerate or delegate.

**Tests (TDD — written BEFORE implementation):**
- Unit: contract tests for adapter discovery / delegation.
- Integration: Cursor global parity still passes, but the behavior is owned by adapter code rather than hardcoded installer helpers.
- E2E: full install/uninstall roundtrip removes adapter artifacts cleanly with user content preserved.

**DoD (Definition of Done):**
- [ ] `install.sh` no longer contains client-specific Cursor global helper bodies
- [ ] `uninstall.sh` delegates adapter cleanup instead of assuming global manifest coverage is sufficient
- [ ] Cursor global parity tests remain green after the move
- [ ] All Stage 5 unit + integration + e2e tests are written first and passing
- [ ] `install.sh` responsibility count is materially lower (argument parsing + shared install + adapter orchestration)
- [ ] Dependency direction is correct: adapters own client specifics, installer coordinates only
- [ ] Code passed self-review

<!-- mb-stage:6 -->
### Stage 6: Simplification pass and direct coverage-gap closure
**Goal:** Remove the highest-confidence residual complexity from review and close the remaining direct test gaps.
**Files:**
- Modify: `scripts/mb-compact.sh`, `scripts/mb-migrate-structure.sh`, `scripts/_lib.sh`, `scripts/mb-note.sh`, `scripts/mb-plan.sh`, `settings/merge-hooks.py`, `adapters/pi.sh`, `hooks/block-dangerous.sh`, `hooks/file-change-log.sh`
- Create/Modify tests: `tests/bats/test_compact.bats`, `tests/bats/test_migrate_structure.bats`, new `tests/bats/test_mb_note.bats`, new `tests/bats/test_mb_plan.bats`, new `tests/bats/test_agents_md_lib.bats`, `tests/bats/test_hooks.bats`, `tests/pytest/test_merge_hooks.py`, `tests/pytest/test_cli.py`

**Implementation:**
1. Write failing tests for direct `mb-note.sh`, `mb-plan.sh`, `_lib_agents_md.sh`, `run_shell()` failure path, exact 10MB log boundary, and mixed hook ownership in `merge-hooks.py`.
2. Move checklist / roadmap.md structural migration logic out of `mb-compact.sh` and back behind `mb-migrate-structure.sh`, leaving compaction focused on archival decay.
3. Add shared `mb_mtime()` helper to `_lib.sh` and remove duplicated mtime snippets where practical.
4. Tighten `merge-hooks.py` so it strips only MB-owned hook items rather than deleting whole entries.
5. De-scope `MB_PI_MODE=skill` from shipping behavior unless explicit compatibility evidence exists; keep `agents-md` as the only supported path in docs/tests.
6. Keep locale scaffolds and other lower-priority YAGNI items out of code changes, but document their defer in plan note / docs if needed.

**Tests (TDD — written BEFORE implementation):**
- Unit: direct bats for `mb-note.sh`, `mb-plan.sh`, `_lib_agents_md.sh`; pytest for mixed managed/user hook entries.
- Integration: `mb-compact.sh` no longer performs structural migration; `mb-migrate-structure.sh` owns that path.
- E2E: adapter and install flows still pass after `pi` mode simplification and compact/migrate split.

**DoD (Definition of Done):**
- [ ] `mb-compact.sh` no longer owns structural migration logic that belongs to `mb-migrate-structure.sh`
- [ ] Direct tests exist and pass for `mb-note.sh`, `mb-plan.sh`, and `_lib_agents_md.sh`
- [ ] `merge-hooks.py` preserves mixed user entries while removing only MB-owned hook items
- [ ] `MB_PI_MODE=skill` is either removed from supported surface or clearly gated out of normal install/test flows
- [ ] All Stage 6 unit + integration + e2e tests are written first and passing
- [ ] No new `SOLID` / `DRY` / `KISS` violations are introduced while simplifying
- [ ] Code passed self-review

<!-- mb-stage:7 -->
### Stage 7: Final verification, documentation, and release-readiness audit
**Goal:** Verify the hardened/refactored surface works end-to-end and document the changed safety model.
**Files:**
- Modify: `README.md`, `CHANGELOG.md`, `docs/install.md`, `docs/release-process.md`, `SECURITY.md`, `.memory-bank/reports/`, optionally `.memory-bank/lessons.md`
- Verify: `install.sh`, `uninstall.sh`, `adapters/*.sh`, `memory_bank_skill/*.py`, `scripts/*.sh`, `scripts/*.py`

**Implementation:**
1. Update user docs for non-interactive uninstall, hardened metrics override, supported `pi` mode, and any adapter/uninstall behavior changes.
2. Record the hardening work in `CHANGELOG.md` and, if needed, `SECURITY.md` / release process docs.
3. Run full repo verification and compare results to the review baseline.
4. Run a final self-review against the plan and prepare the repo for `/user:review`.

**Tests (TDD — written BEFORE implementation):**
- Unit: doc link / CLI smoke if docs or flags change.
- Integration: full `pytest -q tests/pytest`, `ruff check .`, `shellcheck -x --source-path=SCRIPTDIR scripts/*.sh adapters/*.sh hooks/*.sh install.sh uninstall.sh`.
- E2E: `bats tests/bats tests/e2e` on the refactored tree.

**DoD (Definition of Done):**
- [ ] All tests pass
- [ ] Coverage is not below the current project threshold (85%+ overall, core/business 95%+, infrastructure 70%+ where measured)
- [ ] No `TODO` / `FIXME` / `HACK` in new code
- [ ] Documentation is updated where behavior changed
- [ ] Code review is complete (`/user:review`)
- [ ] The 3 High findings from the audit are closed in code and validated by tests
- [ ] Installer / adapter boundaries are simpler than the review baseline and verified by e2e suites

## Risks and mitigation
| Risk | Probability | Impact | Mitigation |
|------|-------------|---------|------------|
| Security fixes break uninstall for valid managed paths | Medium | Users cannot cleanly remove the skill | Ship traversal tests first, keep sandbox e2e uninstall coverage, log `[SKIP]` instead of deleting on uncertain paths |
| Extracting Python helpers changes install-time runtime assumptions | Medium | Install/uninstall fail in bundled layout | Keep helpers inside `memory_bank_skill/`, cover repo + installed-bundle smoke, avoid new third-party deps |
| Adapter framework refactor breaks one client while fixing duplication | Medium | Cross-agent install regresses for a subset of users | Migrate under existing adapter bats suites, preserve adapter CLI, land schema/framework before moving Cursor global logic |
| Moving Cursor global logic out of `install.sh` leaves orphan artifacts on uninstall | Medium | User config drift in `~/.cursor/` | Add explicit e2e for install/uninstall delegation and adapter manifest discovery before refactor |
| Simplification scope creeps into product changes (`mb-import`, tree-sitter, locale pruning) | High | Plan stalls and release timing slips | Keep them explicitly out of scope here; open follow-up ADR/backlog items instead of expanding this plan |
| `pi` mode simplification surprises early adopters | Low | Small compatibility break for an unstable path | Document de-support clearly and keep `agents-md` as the supported default with existing tests |

## Dependencies
- Existing test harnesses in `tests/bats/`, `tests/e2e/`, and `tests/pytest/`
- `jq`, `python3`, `bash`, `pytest`, `ruff`, `shellcheck`
- Existing active plans remain parallel workstreams: `core-files-v3-1` and `agents-quality`
- No new libraries are required; reuse stdlib and current toolchain only

## Estimate
- Stage 1: 0.5–1 day
- Stage 2: 0.5 day
- Stage 3: 1 day
- Stage 4: 1–1.5 days
- Stage 5: 1 day
- Stage 6: 0.5–1 day
- Stage 7: 0.5 day
- Total: ~5–6 working days with TDD and dogfood verification
