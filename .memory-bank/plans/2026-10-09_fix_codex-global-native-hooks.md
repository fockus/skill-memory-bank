---
type: fix
topic: codex-global-native-hooks
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-10-09
---
# Plan: fix — codex-global-native-hooks

**Baseline commit:** b1bbbbf9a547a38fab02e8fbe30a3cbedd02820d

## Context

**Problem:** The harness project uses native Codex hooks, but the public installer only wires a legacy project prompt guard.

**Expected result:** Default installation registers global native hooks, preserves user configuration, and explains the Codex trust step. Audit the remaining Codex integration gaps.

**Related files:**
- `install.sh`, `uninstall.sh`, `adapters/codex-native-hooks.py`, `hooks/mb-codex.py`

**Tier:** standard. Existing adapter integration with regression tests.
**Coordination:** See `.memory-bank/COORDINATION.md`; preserve all pre-existing Pi and bank changes.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Global installation and migration

**Status:** done

**Files:** `install.sh`, `uninstall.sh`, `adapters/codex-native-hooks.py`, `adapters/codex.sh`, `tests/pytest/test_codex_native_install.py`, `tests/bats/test_codex_adapter.bats`, `tests/bats/test_platform_limited_honesty.bats`

**What to do:**
- Register the existing native runner globally using a persistent installed path; migrate owned project hooks without touching foreign entries. Preserve trust and existing settings on install, reinstall and uninstall.

<!-- mb-stage:2 -->
### Stage 2: Runtime contracts and audit

**Files:** `hooks/mb-codex.py`, `tests/pytest/test_codex_native_hooks.py`, `references/codex-native-hooks.md`, `references/hosts.md`, `references/session-memory.md`, `docs/cross-agent-setup.md`, `README.md`, `SKILL.md`, `scripts/mb-agent-render.py`, `tests/pytest/test_agent_render.py`

**What to do:**
- Compare harness evidence and current Codex event contracts, fix verified runtime gaps, document remaining limits and native execution evidence.
- Independent ownership boundary: installer and runtime can proceed in parallel; parent owns documentation and bank updates.
- Renderer owner separately fixes incompatible Claude aliases and explicit pipeline reasoning effort in Codex roles; global roles use the shipped pipeline instead of leaking project settings.
- Expanded owner-requested audit covers graph freshness, cross-chat recorded memory, global/nested bank resolution, instruction loading and portable guard parity. Resolver and runtime helpers have separate owners; no new transcript subsystem is included.

**Testing (TDD — tests BEFORE implementation):**
- Add failing regression tests before changes. Use isolated HOME/project directories and real bundled hook checks. Verify native discovery with installed Codex without changing real trust.

**DoD (Definition of Done):**
- [x] Default install registers all seven native events globally through the installed skill alias, independent of project cwd; existing linked-bundle installation semantics remain intact.
- [x] Reinstall/uninstall and migration preserve foreign hooks/config and avoid duplicate owned project registrations.
- [x] Runtime tests cover context, compaction, protected writes, requirement validation, synchronization and stop recursion.
- [ ] Relevant tests and static analysis pass; full-suite results and independent verifier are recorded.
- [x] Codex gaps and trust limitations are reported with concrete evidence.

**Verification evidence:** Installer 13 tests, final native runtime + resolver 45 tests / 12 subtests, renderer 23 tests, and Codex adapter 50 Bats checks passed. Ruff passed; ShellCheck passed with only the pre-existing SC2034/SC2016/SC2012 findings excluded. Independent review found and verified repairs for nested registry precedence, nonexistent MB_PATH bank creation, cross-host registry selection and same-line secret/placeholder warning leakage; no remaining scoped blocker. Both full suites have completed; follow-up results and scoped repairs are recorded in plans/2026-10-09_feature_codex-memory-parity.md. The initial seven-hook discovery was extended by the follow-up: Native CLI 0.160.0 discovers eight user-scope hooks, all already trusted/enabled, with no errors; foreign hooks are preserved. Installed 28 roles were rendered from the shipped profile after correcting Codex final-report delivery instructions; the global AGENTS entry point explicitly requires relevant RULES reads. Follow-up native evidence proves all eight delivered events, including persisted completed compaction and bounded SessionEnd.

**Expanded runtime evidence:** Real isolated runner/CLI probes in `/private/tmp/mb-codex-e2e-proof-6z0fhltv/proof.json` confirmed note edits refresh BM25 recall and source edits refresh the next graph query. Shared resolver regressions: 21 pytest and 39 Bats passed; source/log/security checks: 16 Bats passed. Full pytest completed with 4006 passed, 11 skipped, 6 failed and one teardown error. The changed work-command line-limit failure was repaired and its exact test passed. Three Pi watcher failures report EMFILE; a Pi leaf test reports sandbox EPERM on localhost listen. Optional embedding-store failure reproduces on an extracted HEAD snapshot (`/private/tmp/mb-head-semantic-csfvdybn/result.log`). The teardown guard detected the authorized real-project hook migration performed during the long run; subsequent isolated verification passed. Full Bats has completed; the classified current result is recorded in the parity follow-up plan; earlier legacy Codex fixture failures were repaired and rerun, and both obsolete moving-HEAD extension snapshots were replaced by current declined-install equivalence checks and passed their focused rerun.

**Repository closure gate:** `mb-flow-verify.sh .memory-bank --skip tests` exited 1 (full tests completed separately; classified follow-up evidence is recorded in the parity plan). The two lint findings are in unchanged `tests/bats/fixtures/brief/mkbrief.py` and `tools/prove_assertions.py`; all 14 no-placeholder findings already exist in HEAD; acceptance refers to the unrelated paused SVP goal. No gate or goal was weakened and `/mb done` is not certified. Real global installation exposed user-HOME coupling in legacy Codex test fixtures; both affected fixtures now isolate their profiles and the rerun passed 50 adapter tests plus two relevant platform-honesty tests.

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| User settings overwritten | Medium | Merge only owned entries; invalid inputs remain unchanged; round-trip tests |
| Installed hooks skipped | Medium | Native hooks/list validation and explicit trust instructions |
| Foreign work included | Medium | Scoped diff and no commit of existing changes |

## Gate (plan success criterion)

All DoD items have runnable evidence or an explicitly reported environmental limitation; independent verification finds no blocking defect in the scoped implementation.

**Final follow-up disposition:** Native delivery and scoped implementation are accepted GO_WITH_BACKLOG by the final judge in plans/2026-10-09_feature_codex-memory-parity.md. The unrelated repository firewall remains red; formal /mb done is not certified and no release/commit/push was performed.
