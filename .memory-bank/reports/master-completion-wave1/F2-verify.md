# F2 verify — master-completion Stage 17 (svp-roadmap-backlog-db T3, T4, T5, T7, T8, T9)

## Verdict: PASS_WITH_NOTES

No DoD item failed. Notes below are WARNING/INFO; none blocks Stage 17.

- Baseline commit: 1815bcc (plan header); fallback: none. The work is uncommitted in the working tree (diffed against HEAD; HEAD..baseline has 5 unrelated commits that do not touch these files).
- Tests run: pass (targeted files only; the full suite was not run, as instructed).
- RULES violations: 0 CRITICAL, 2 SRP WARNING (both files were already over 300 lines at baseline), plus style-level type-hint warnings.
- Agreement Compliance: no active agreement violated (AGR-085 English in repo: satisfied; AGR-097/AGR-103 workflow and shortcuts: satisfied; AGR-084 no release: not-applicable, no version bump).

## 1. DoD vs code and tests

| Task | DoD | Evidence | Result |
|---|---|---|---|
| T9 | single allocator; I-079 regression; own allocator removed | scripts/_lib.sh:1185-1228 `mb_next_backlog_id`; mb-idea.sh:127 calls it; test_mb_backlog_id_alloc.bats "I-079 collision…", "…no longer carries its own grep allocator" | met |
| T9 | promote never writes PLANNED; only READY→IN-PROGRESS via shared primitive | mb-idea-promote.sh:90-112 state matrix, :114 `--check` gate, :130 `mb_backlog_transition_locked … --plan`; test_mb_idea_promote_v2.bats 12/12 incl. "no promote path ever writes the PLANNED token", partial-failure ×3 | met |
| T9 | positional mb-idea.sh byte-identical; `--force` / `--` | mb-idea.sh:28-41; base-vs-new comparison under /bin/bash 3.2 (section 4) | met (stdout, exit code and header line identical; body gains the T8-required `**Type:** IDEA` line) |
| T7 | `list` / `list --tree` grammar; fail-fast | mb_backlog_state_engine.py `tree_order` (new, validates before printing), state_main list; mb-backlog-state.sh:171,186-190; hierarchy bats 9/9 | met |
| T3 | C4 table, lock + atomic, grandfather | mb-backlog-migrate.sh:48-57 (lock), mb_backlog_migrate.py TABLE / plan_edits / move_declined / write_atomic; migrate bats 20/20 incl. race test and "no historical entry receives Type IDEA" | met |
| T8 | WONTFIX move + similarity; SPEC not gated; writer = migrator parity | engine transition_main WONTFIX → move_to_out_of_scope (mb_backlog_blocks.py); mb-idea.sh:117-124 similarity (IDEA only), :60-73 SPEC writer; out_of_scope bats 13/13 incl. "SPEC writer is a migrator no-op" | met |
| T4 | 15 codes, deterministic, read-only, legacy vs invalid | mb_bank_lint.py:41 sort (file, line, code); mb_bank_lint_backlog.py LEGACY/STATES split; progress_mismatch delegates to `mb-roadmap-sync.sh --check` (mb_bank_lint_roadmap.py:115-117); lint bats 22/22, one test per code (lines 72-196), "lint never modifies the bank" | met |
| T5 | docs including the promote behaviour change | references/mb/idea-promote.md:7,15,21,24,34; references/templates.md:279-281; CLAUDE.md:66-69 "Backlog Invariants" (outside managed blocks); docs bats 7/7 | met |

- `bash scripts/mb-spec-validate.sh --require-scenarios .memory-bank/specs/svp-roadmap-backlog-db` → rc=0 (3 I-174 notices only).
- Open DoD in tasks.md: `grep -c '^\s*- \[ \]'` = 0.
- REQ coverage (REQ-004…011, read against requirements.md text): REQ-004 lint key=value (bank_lint); REQ-005 single primitive incl. promote (backlog_state + promote_v2); REQ-006 hierarchy; REQ-007 READY brief gate (T2 backlog_state); REQ-008 Out-of-scope precedent + surfacing (out_of_scope); REQ-009 SPEC writer + migration (out_of_scope, migrate); REQ-010 backup + idempotent (migrate); REQ-011 legacy parsed + hint (lint legacy_state, promote legacy exit 2, migrate dry-run). `mb_spec_coverage.py` reports these as `task-only` only because test files do not name REQ IDs; code + test evidence was found by reading.

## 2. Tests (targeted)

All rc=0, 0 `not ok`: id_alloc 17, idea_promote_v2 12, backlog_state_hierarchy 9, backlog_migrate 20, backlog_out_of_scope 13, bank_lint 22, roadmap_backlog_docs 7, roadmap_sync_ice 18, roadmap_sync_group 16, backlog_state 24, lock_helper 21, test_lib 74, plan_done_multi 12, plan_done_v2 3, idea_promote 7, test_idea 8.
`PYTHONPATH=. python3 -m pytest -q tests/pytest/test_doc_counts.py` → 13 passed.
shellcheck (mb-idea, mb-idea-promote, mb-backlog-state, mb-backlog-migrate, mb-bank-lint, mb-plan-done, _lib) → clean. ruff (7 changed/new .py) → clean. No TODO/FIXME/stub in new files.

## 3. Deviations outside the planned file list

- Engine `list --tree`, WONTFIX move, `transition-locked --check`: required by T7 (`list --tree`), T8 (move) and T9 (validate before plan creation). The engine is in the T7/T8/T9 Scope lines. Existing callers (mb-backlog-state.sh transition, mb-idea-promote.sh) are covered by backlog_state 24/24 and promote 7+12. Only regression-visible change: `list --tree` no longer exits 2 (test changed to `--bogus`, as T2 itself foresaw).
- Six helper modules: similar 59, blocks 58, migrate 170, bank_lint 49, lint_roadmap 121, lint_backlog 58 lines, all under 300 and listed in the T3/T4/T8/T9 Scope lines.
- test_idea_promote.bats NEW→PLANNED → READY→IN-PROGRESS: justified by T9/C7 (PLANNED is never written); the legacy-refusal case is kept.
- scripts/mb-plan-done.sh:225 adds IN-PROGRESS to the flip tuple (PLANNED kept): needed so plan-done still closes ideas that promote now writes as IN-PROGRESS; new test test_plan_done_multi.bats:250 green, old PLANNED case green.

## 4. Positional mb-idea.sh and Bash 3.2

- Base (HEAD) and new mb-idea.sh run under /bin/bash 3.2.57 on identical fixtures (Ideas mid-file, Ideas at EOF, no Ideas section; new, duplicate, regex-metachar title, bad priority): stdout and exit codes identical (I-004/0, I-003+"already present"/0, I-005/0, rc 2). The only file difference is the `**Type:** IDEA` line T8 requires.
- Spec'd narrowing: a first argument starting with `--`, and a malformed `[SPEC:` title, now exit 2 (C3/C4).
- All changed-script bats files rerun with `bash` = /bin/bash 3.2: all green. `bash -n` clean. No `declare -A`, mapfile or `${x,,}` in the changed scripts.

## 5. Live backlog untouched by the migrator

`git diff HEAD -- .memory-bank/backlog.md`: 12+/3- = I-061 PLANNED→DONE plus plan path, I-127 closed, new I-293/I-294/I-295 (I-295 carries `**Type:** IDEA` from the new writer). These are hand/orchestrator edits plus one mb-idea.sh call. Nothing from the migrator: no `## Out of scope`, no DECLINED move, 19 legacy tokens still present, the only `.pre-migrate/` dir is 20260421_091115 (v3 migration from April). A dry run on a scratch copy gives actions_pending=34, matching the executor's addendum, and the copy stays byte-identical.

## WARNING

1. Existing automated caller can now fail: adapters/pi_native_work.mjs:179 calls `mb-idea.sh "<title> — <rationale> (source…; native run…)"` for every GO_WITH_BACKLOG item. `execute()` rejects on non-zero exit (adapters/pi_native_commands.mjs:23), so the new similarity refusal (exit 1) aborts the Pi native run after the judge said GO. Long concatenated titles match easily because score = |∩|/min(|a|,|b|). Reproduced: Out-of-scope "Retry flaky tests" + title "Harden parser - add retry when tests are flaky (source: review; native run r1)" → `similar_out_of_scope=I-002 score=1.00`, rc=1. Not live in this repo yet (backlog has no `## Out of scope`), but it becomes live after migration or the first WONTFIX. Fix: pass `--force` (or `--`) from the Pi adapter, or treat a similarity refusal as non-fatal there. scripts/mb_team_collect.py:123 only prints a command for a human: low impact.
2. TDD order (executor-admitted): for T3, T4, T8 and T5 the implementation came before the first test run; red was rebuilt by reverting. `mb-work-state.sh eval-red` was not recorded, so red evidence exists only as pasted text in F2.md.
3. SRP: scripts/mb_backlog_state_engine.py 386→441 lines (already over 300 at baseline; +55 by this track); scripts/_lib.sh 1183→1228 (already over). Split candidate for a follow-up.

## INFO

1. mb-idea-promote.sh:118-123 reuses any `plans/*_<type>_<slug>.md` to recover from a partial run. It would also adopt an unrelated active plan with the same type and slug instead of creating a new one (the spec says "exactly this plan").
2. mb-idea-promote.sh:99-107: the IN-PROGRESS heal runs whenever the plan basename is missing from roadmap.md, including when roadmap.md is absent. A re-promote then exits 0 instead of 2.
3. Headings outside the engine's strict grammar are invisible to `list` and lint: 212 of 241 I-headings listed on the live copy; lint shows 17 legacy_state warnings against 19 legacy tokens by grep; OBSOLETE (I-144) gets no lint invalid_state (the migrator does warn). This comes from T2's grammar; follow-up.
4. Executor follow-up 3 still open: no lint code for a duplicate I-NNN.
5. tasks.md:316 (T5 Testing) still says "CLI synopsis in `commands/mb.md`" while Scope/What-to-do point to references/mb/*.md: prose drift only.
6. The plan's Stage 17 DoD checkboxes are still unticked (orchestrator step). Both items are now provable.
