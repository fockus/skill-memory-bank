---
type: fix
scope: cursor-compatibility-remediation
created: 2026-05-24
status: in_progress
priority: HIGH
linked_specs: [specs/cursor-extension]
linked_audit: reports/2026-05-24_cursor-compatibility-audit.md
---

# Fix: Cursor Compatibility Remediation

Closes the compatibility gap in `reports/2026-05-24_cursor-compatibility-audit.md`.

## Goal

Make Cursor work as documented: ten CC-compat hooks fully functional, global
storage resolver-aware, skill-bundle script resolution, accurate docs. No
TypeScript extension required (unlike Pi).

## Stages

<!-- mb-stage:1 -->
### Stage 1: Hook infrastructure (`_skill_root.sh`)

**Tasks:** cursor-extension Task 1–2  
**TDD:** `tests/bats/test_skill_root_resolver.bats` RED → GREEN  
**DoD:**
- [x] `_skill_root.sh` resolves skill root and scripts from Cursor global install path
- [x] All script-dependent hooks source `_skill_root.sh`
- [x] No `$SCRIPT_DIR/../scripts` without resolver

<!-- mb-stage:2 -->
### Stage 2: Adapter refactor (bundle paths, no copies)

**Tasks:** cursor-extension Task 3  
**TDD:** Update `test_cursor_adapter.bats` first  
**DoD:**
- [x] `hooks.json` commands use absolute skill-bundle paths + `MB_AGENT=cursor`
- [x] Legacy `.cursor/hooks/*.sh` copies removed on install
- [x] Global install does not copy hooks to `~/.cursor/hooks/`

<!-- mb-stage:3 -->
### Stage 3: Test suite alignment

**Tasks:** cursor-extension Task 4–5  
**DoD:**
- [x] `test_cursor_global.bats` expects bundle references, not copies
- [x] `test_cursor_hooks_registration.py` manifest contract updated
- [x] `mb-reviewer-resolve.sh` probes Cursor skills root

<!-- mb-stage:4 -->
### Stage 4: Global storage E2E

**Tasks:** cursor-extension Task 7  
**DoD:**
- [x] `sessionStart` injects context for global bank without local `.memory-bank/`
- [ ] `sessionEnd` auto-capture works with registry path

<!-- mb-stage:5 -->
### Stage 5: Documentation

**Tasks:** cursor-extension Task 6  
**DoD:**
- [x] `cross-agent-setup.md` lists 10 hooks + bundle path semantics
- [x] `SKILL.md` Cursor section accurate
- [ ] Optional `docs/cursor-extension.md`

<!-- mb-stage:6 -->
### Stage 6: Parallel pipeline Cursor dispatch (W12 dependency)

**Tasks:** cursor-extension Task 8–9  
**DoD:**
- [x] `adapters/cursor/dispatch.md` exists
- [x] `parallel-pipeline/design.md` Cursor row updated from TBD
- [ ] handoff-v2 hook rename synced when that plan lands

## Verification

- `mb-spec-validate cursor-extension` — PASS
- `bats tests/bats/test_cursor_adapter.bats tests/e2e/test_cursor_global.bats tests/bats/test_skill_root_resolver.bats` — all PASS
- `pytest tests/pytest/test_cursor_hooks_registration.py` — PASS
- Manual: Cursor IDE → edit plan file → checklist/roadmap sync fires

## DoD (plan-level)

- [ ] All six stages complete
- [ ] Audit blockers B1 and gaps C1–C3 closed
- [ ] Docs drift W1 resolved
- [ ] `/mb verify` PASS against this plan
