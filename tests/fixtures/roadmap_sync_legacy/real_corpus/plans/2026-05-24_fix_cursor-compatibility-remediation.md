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
- [x] `sessionEnd` auto-capture works with registry path

<!-- mb-stage:5 -->
### Stage 5: Documentation

**Tasks:** cursor-extension Task 6  
**DoD:**
- [x] `cross-agent-setup.md` lists 10 hooks + bundle path semantics
- [x] `SKILL.md` Cursor section accurate
- [x] Optional `docs/cursor-extension.md` (engineering reference — bundle resolution, global registry, testing surface, limitations)

<!-- mb-stage:6 -->
### Stage 6: Parallel pipeline Cursor dispatch (W12 dependency)

**Tasks:** cursor-extension Task 8–9  
**DoD:**
- [x] `adapters/cursor/dispatch.md` exists
- [x] `parallel-pipeline/design.md` Cursor row updated from TBD
- [ ] handoff-v2 hook rename synced when that plan lands — **deferred: blocked on handoff-v2 (Wave 2); falls out of that spec's hook-rename task**

## Verification

- `mb-spec-validate cursor-extension` — PASS
- `bats tests/bats/test_cursor_adapter.bats tests/e2e/test_cursor_global.bats tests/bats/test_skill_root_resolver.bats` — all PASS
- `pytest tests/pytest/test_cursor_hooks_registration.py` — PASS
- Manual: Cursor IDE → edit plan file → checklist/roadmap sync fires

## DoD (plan-level)

- [x] Stages 1–5 complete (Stage 6: dispatch.md + design done; Task 9 hook-rename **deferred to handoff-v2**)
- [x] Audit blockers B1 and gaps C1–C3 closed
- [x] Docs drift W1 resolved
- [x] Verified via tests (2026-06-15): full pytest **1430 passed**; cursor bats (skill_root 5, adapter 8, docs 2) + e2e (global, global_storage incl. new sessionEnd case) + reviewer-resolve 6 + parallel-adapters 2 — all green
- [ ] `mb-spec-validate cursor-extension` clean — orphans (REQ-310→Task 2, 312–317) + Task 9 missing-Testing **fixed** this pass; remaining 13 EARS-phrasing warnings are **pre-existing** (HEAD already exit=1) → backlog **I-071**
- [ ] Stage 6 Task 9 (hook-rename sync) — deferred to handoff-v2 (Wave 2)
