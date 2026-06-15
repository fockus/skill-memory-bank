---
type: spec-tasks
topic: cursor-extension
status: ready
created: 2026-05-24
linked_requirements: requirements.md
linked_design: design.md
---

# Tasks: Cursor Extension

Executable tasks with `<!-- mb-task:N -->` markers. Ordered by dependency.

---

<!-- mb-task:1 -->
### Task 1: `hooks/_skill_root.sh` — skill bundle resolver

**Covers:** REQ-300, REQ-301, REQ-302, REQ-303

**What to do:**
Implement shared resolver: candidate roots, `mb_skill_script_path`, `mb_hook_resolve_mb_path`, `mb_hook_default_agent`.

**Testing (TDD):**
- `tests/bats/test_skill_root_resolver.bats`:
  - in-repo hook dir resolves repo `scripts/mb-plan-sync.sh`
  - with `HOME/.cursor/skills/memory-bank` symlink resolves bundled scripts
  - `mb_hook_resolve_mb_path` finds local `.memory-bank/`
  - default agent is `cursor` when Cursor skill dir exists

**DoD:**
- [x] `_skill_root.sh` exists, shellcheck-clean
- [x] bats tests PASS (≥4 scenarios)

---

<!-- mb-task:2 -->
### Task 2: Patch script-dependent hooks to use `_skill_root.sh`

**Covers:** REQ-301, REQ-302, REQ-310, REQ-311, REQ-312, REQ-313, REQ-314, REQ-315, REQ-316, REQ-317

**What to do:**
Update: `mb-plan-sync-post-write.sh`, `mb-protected-paths-guard.sh`, `mb-ears-pre-write.sh`, `mb-context-slim-pre-agent.sh`, `mb-sprint-context-guard.sh`, `session-end-autosave.sh`, `mb-session-start-context.sh`, `mb-compact-reminder.sh`, `file-change-log.sh`.

**Testing (TDD):**
- `tests/bats/test_skill_root_resolver.bats`: invoke `mb-plan-sync-post-write.sh` from `/tmp` fake hook dir with `MB_SKILL_ROOT` set → chain scripts found
- Existing `test_hook_ears_pre_write.py` still PASS

**DoD:**
- [x] No hook uses `$SCRIPT_DIR/../scripts` without `_skill_root.sh`
- [x] Cursor log path when `MB_AGENT=cursor`
- [x] Tests PASS

---

<!-- mb-task:3 -->
### Task 3: Refactor `adapters/cursor.sh` — bundle hook references

**Covers:** REQ-304, REQ-305, REQ-306, REQ-307

**What to do:**
Add `cursor_resolve_skill_hooks_dir`, `cursor_hook_env_prefix`, `cursor_remove_legacy_hook_copies`.
Stop copying hooks to `.cursor/hooks/`. Build `hooks.json` with absolute bundle paths + env prefix.

**Testing (TDD):**
- Update `tests/bats/test_cursor_adapter.bats`:
  - install does NOT create `.cursor/hooks/*.sh`
  - `hooks.json` commands contain `memory-bank/hooks/` and `MB_AGENT=cursor`
  - legacy copies removed on reinstall

**DoD:**
- [x] Project + global install use bundle paths
- [x] Manifest tracks hooks.json + skill hooks dir
- [x] Adapter bats PASS

---

<!-- mb-task:4 -->
### Task 4: Update global E2E + pytest contract tests

**Covers:** REQ-304, REQ-307

**What to do:**
Update `tests/e2e/test_cursor_global.bats` and `tests/pytest/test_cursor_hooks_registration.py` for no-copy semantics.

**Testing (TDD):**
- E2E: after `install.sh`, `hooks.json` references bundle; no `~/.cursor/hooks/mb-plan-sync-post-write.sh`
- pytest: manifest lists skill hooks dir, not ten copied files

**DoD:**
- [x] E2E + pytest PASS
- [x] `install.sh` filter for cursor still green

---

<!-- mb-task:5 -->
### Task 5: `mb-reviewer-resolve.sh` multi skills-root

**Covers:** REQ-318

**What to do:**
Probe `~/.cursor/skills` and `~/.claude/skills` for `override_if_skill_present`.

**Testing (TDD):**
- `tests/bats/test_mb_reviewer_resolve.bats` (extend): override found under Cursor skills root only

**DoD:**
- [x] Multi-root resolution implemented
- [x] Test PASS

---

<!-- mb-task:6 -->
### Task 6: Documentation — cross-agent setup + SKILL.md

**Covers:** REQ-319, REQ-320

**What to do:**
Fix hook count (10 not 3), bundle path docs, IDE vs CLI limitation, global storage example for Cursor.

Optional: `docs/cursor-extension.md` troubleshooting (hook debug, legacy migration).

**Testing (TDD):**
- `tests/bats/test_cursor_docs.bats`: grep cross-agent-setup for ten events + skill-bundle path

**DoD:**
- [x] Docs match implementation
- [x] Doc test PASS

---

<!-- mb-task:7 -->
### Task 7: Global storage E2E smoke

**Covers:** REQ-305, REQ-308, REQ-309

**What to do:**
E2E test: sandbox HOME, global bank via registry, run `mb-session-start-context.sh` with `MB_AGENT=cursor` → non-empty context.

**Testing (TDD):**
- `tests/e2e/test_cursor_global_storage.bats` (new)

**DoD:**
- [x] Global bank context injection verified
- [x] E2E PASS (sessionStart context + sessionEnd auto-capture)

---

<!-- mb-task:8 -->
### Task 8: Parallel pipeline — `adapters/cursor/dispatch.md`

**Covers:** REQ-321, REQ-322, REQ-323

**What to do:**
Document Cursor Task-orchestrator dispatch. Update `parallel-pipeline/design.md` matrix row for Cursor.

**Testing (TDD):**
- `tests/bats/test_parallel_pipeline_adapters.bats`: Cursor row not TBD; dispatch.md exists

**DoD:**
- [x] dispatch.md committed
- [x] parallel-pipeline design updated
- [x] Test PASS

---

<!-- mb-task:9 -->
### Task 9: handoff-v2 hook rename sync

**Covers:** REQ-324

**What to do:**
When `handoff-v2` lands, update Cursor `EVENT_BINDINGS` + docs for `mb-pre-compact.sh`.

**Depends on:** handoff-v2 plan merge

**Testing (TDD):**
- When handoff-v2 lands: extend `tests/bats/test_cursor_adapter.bats` to assert the renamed hook (`mb-pre-compact.sh`) is registered in `hooks.json` and the old name is absent from the generated bindings.

**DoD:**
- [ ] Cursor adapter registers renamed hook
- [ ] Old copy removed from MB_HOOKS if renamed

---

## Traceability

| Task | REQ coverage |
|------|-------------|
| 1 | REQ-300..303 |
| 2 | REQ-301,302,311..317 |
| 3 | REQ-304..307 |
| 4 | REQ-304,307 |
| 5 | REQ-318 |
| 6 | REQ-319,320 |
| 7 | REQ-305,308,309 |
| 8 | REQ-321..323 |
| 9 | REQ-324 |
