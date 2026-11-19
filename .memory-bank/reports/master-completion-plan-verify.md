## Plan Verification: master-completion (plans/2026-11-18_feature_master-completion.md)

### Status: FAIL — bookkeeping only; every code claim I spot-checked is backed by code and green tests

Verdict detail: 2 CRITICAL (ticked DoD boxes the bank contradicts), 9 WARNING, 6 INFO. Each CRITICAL is a
bank-text fix (minutes, no code). Once they are fixed and the Stage 19 full suite is green or triaged, the
verdict becomes PASS_WITH_NOTES.

**Baseline commit:** 1815bcc1e16b5b2b5a1c9300c12953261198dd01 (fallback: none). Plan commits: d3e4939, 0139fcb, b5a621d, e0a7ee0, f068555.
**Tests run:** targeted only; I did not run the full suite (the orchestrator runs it as Stage 19). All of these passed:
- pytest graph_dispatch_docs, s2_file_size_contract, mb_router_targets, dynamic_flow_skills, doc_counts, mb_cost_report, graph_test_mapping, tooling_core_wiring: 85 passed
- pytest openspec_*: 147 passed
- pytest mb_work_adapt*, pi_native_settle, codex_native_hooks: 107 passed
- pytest pi_native_graph without PI_PACKAGE_ROOT: 16 passed
- bats graph-nudge + subinvoke_pi_opencode: 14 ok
- bats mb_openspec + mb_work_resolve: 32 ok
- bats roadmap_sync_ice/group, backlog_state, lock_helper, bank_lint, backlog_migrate: 122 ok
**Spec validate:** rc=0 for openspec-adapter, svp-brief, svp-contract-test-loop, svp-roadmap-backlog-db, svp-adapt-escalation and dynamic-flow. `--require-scenarios` also gives rc=0 for S7, S8, S4 and S5.
**RULES violations:** not re-run at plan level. The track verifiers recorded 0 CRITICAL in F2-verify and F3b-verify.
**Agreement Compliance:** AGR-101…108 are relevant. None is violated. AGR-084 (no release) is satisfied: VERSION is 5.3.1, the change is under CHANGELOG `[Unreleased]` and there is no tag.

### Stages checked: 21/22 (Stage 19 is open by design)

| Stage | Boxes | Evidence checked | Result |
|---|---|---|---|
| 1 | 3/3 ticked | done/ has cursor (23/23) and codex-global (5/5); I-127 is DONE (backlog.md:714); mb-research-tooling-core is `status: done` | ❌ box 3 (C-1); ⚠️ box 2 literal (W-1) |
| 2 | 2/2 | hooks/tests/graph-nudge.bats has 8 cases, green; A.md shows red 5/8 then green | ⚠️ W-2 (agent_id never confirmed) |
| 3 | 2/2 | test_mb_cost_report green; `mb-cost-report.py --json --since 1` prints graph_share 0.0536 | ✅ |
| 4 | 2/2 | A.md: 400→358 lines, recorded doc-test list, same failures before and after. Now 377 after Stage 5 (planned) | ✅ |
| 5 | 2/2 | `## Graph` at commands/work.md:133/162/258/277; `compose: mb-tooling-core` at agents/mb-judge.md:5, mb-reviewer-lead.md:5, mb-reviewer-logic.md:5; test_graph_dispatch_docs green (includes temp-HOME install render) | ✅ |
| 6 | 2/2 | Codex SubagentStart line + test green; Pi fixture passes 16/16 with no PI_PACKAGE_ROOT (`pi` on PATH) | ⚠️ box 2 (W-3) |
| 7 | 2/2 | reports/2026-11-19_graph-adoption.md: implementer 5/1 and 3/1, reviewers 4 and 3 graph queries | ❌ box 2 (C-2); ⚠️ W-4 |
| 8 | 2/2 | AGR-105 exists; validate rc=0; openspec tests green; `--normalize` at scripts/mb-openspec.sh:10,13,33 | ✅ |
| 9 | 3/3 | export/sync/export_new/roundtrip/sync_safety tests green; the B2 carry-over is tested (test_openspec_sync3.py:95,110); old 777/646-line modules split (mb-openspec.py 277, convert 298); B3-judge GO_WITH_BACKLOG | ✅ (INFO-1) |
| 10 | 2/2 | 6 openspec cases in test_mb_work_resolve.bats (:72-168), green; work.md 377 ≤ 400; references/mb/openspec.md, docs/commands.md:64 and CHANGELOG cover all four directions | ✅ |
| 11 | 2/2 | C-review cycle-1..4 + judge.json GO_WITH_BACKLOG; mb-team plan 47/47 in done/ | ⚠️ W-5 |
| 12 | 2/2 | commands/mb.md is 12099 B; 48 files in references/mb/; test_mb_router_targets green; opus55 Stage 6 ticked, Stage 7 dropped (AGR-102); wheel glob fixed to `references/**/*.md` | ⚠️ W-6 (minor) |
| 13 | 1/1 | reports/2026-11-19_opus55-fable-run.md; b5a621d fix + test | ⚠️ W-7 |
| 14 | 1/1 | test_subinvoke_pi_opencode.bats has 6 cases including sequential+WARN (:62), green; mb-fanout.sh:210-218 | ✅ (INFO-2) |
| 15 | 1/1 | commands/{critique,risk-find,final-report}.md; test_dynamic_flow_skills + test_doc_counts green; dynamic-flow T13/T14 ticked | ✅ |
| 16 | 2/2 | Seams blocks are present; Eval ticks carry `eval_gate=retro-skipped` (shortcut covered); svp-brief and svp-contract-test-loop are not in KNOWN_FAILING; `--require-scenarios` rc=0 | ✅ (INFO-3) |
| 17 | 2/2 | S4 open DoD 0, validate rc=0; the four regression bats green; F2-verify PASS_WITH_NOTES | ✅ |
| 18 | 2/2 | S5 5/5 tasks ticked, validate rc=0; journal under `mb_lock_acquire` (scripts/mb_work_adapt_journal.py:4,39) with test_journal_concurrent_writers_keep_every_line; AGR-107; F3b-verify PASS_WITH_NOTES; work.md 377 | ✅ |
| 19 | 0/2 | open by design (full suite running, this verification) | — |
| 20 | 2/2 | test_pi_native_settle green; live check waived by AGR-108 | ✅ |
| 21 | 2/2 | EXP-pdw-spike.md no-go; ADR-11 at dynamic-flow design.md:162; I-295 | ⚠️ W-8 |
| 22 | 2/2 | On the real graph: `tests scripts/mb_bank_lint_backlog.py` → test_mb_bank_lint.bats, test_mb_roadmap_backlog_docs.bats; `who-calls cmd_checkpoint` → mb_team_ops.py:main; test_graph_test_mapping green | ⚠️ W-9 (minor) |

### CRITICAL (blocking)
1. **C-1, Stage 1 box 3 ("checklist Pi block matches the plan's stage statuses").** checklist.md:28-34 shows `Pi native … — 5/5` with Stage 5 ✅ "Safe installation and real Pi acceptance". But plans/2026-10-05_feature_pi-native-integration.md:141 says `**Status:** pending`, with every Stage 5 box open, and Stage 1 itself says "acceptance stays open". The plan says Stages 1–4 are done "implementation; plan-level verify/review/judge pending". The ✅ for Stage 5 was introduced in d3e4939; at 1815bcc the block was 0/5. Fix: set Stage 5 to ⬜ and the header to 4/5. Stages 1–4 may keep ✅ under AGR-089.
2. **C-2, Stage 7 box 2 ("graph-semantic-adoption 11/11 and moved to plans/done/").** The plan is in done/, but it still has 5 unticked boxes: Stage 5 at :136-137 and Stage 7 at :188-190. The only closure text is the end note at :337. Stage 5 of that plan (the Claude pre-agent graph status line) was never delivered; master Stage 6 deferred it to I-293. Stage 7's 7-day window is deferred by the master plan's shortcut table. Fix: annotate each open box in place. Stage 5 → "superseded by master-completion Stage 5 (`/mb work` push) + I-293 (ad-hoc dispatch)". Stage 7 → tick the demo/tests boxes with the report link and mark the 7-day box "deferred, re-read 2026-11-26 (master Shortcuts)". Alternatively, reword the master DoD to "closed with notes".

### WARNING (needs attention)
1. **W-1, Stage 1 box 2.** The literal DoD command `grep -c '\[~\]\|\[ \]' specs/openspec-adapter/tasks.md` returns 2, not 0. Both hits are prose describing the OpenSpec format (`tasks.md:25,53`); there are no real open boxes, so the intent is met but the DoD command as written is false.
2. **W-2, Stage 2.** "Confirm the field name from a captured payload before coding" was not done. A.md says `agent_id` is UNCONFIRMED. If Claude Code does not send `agent_id` in PreToolUse, the per-subagent budget silently falls back to per-session. No shortcut row, AGR or backlog item covers it (I-293 is about SubagentStart only).
3. **W-3, Stage 6 box 2 ("recorded as not supported, with the source").** I-293 records the Claude half as *unconfirmed*, not as not-supported with a source. The docs / claude-code-guide check the stage asked for was not done (A2.md: "confirm against Claude Code docs").
4. **W-4, Stage 7 measurement.**
   - The implementer `graph_share` is computed from the executors' self-reported counts (H1.md, H2.md `Graph:` lines). It is not from `mb-cost-report.py`, which has no implementer role row (its roles are judge, other, research, reviewer and verifier).
   - The demo items were H1 (mb-team, track C) and H2 (S4 bank-lint), not "an item from Track F" as written. H2 is S4-adjacent.
   - The reviewers' grep counts are not given.
5. **W-5, Stage 11.**
   - (a) Box 1 says "latest master.json has 0 medium", but C-review/cycle-4/master.json still has medium C4-M1. It was closed by mb-judge (C-review/judge.json), with no cycle-5 lead pass.
   - (b) "plan-verifier PASS" was replaced by mb-judge verification (mb-team plan :289).
   - (c) 4 fix cycles ran against the "≤3 cycles" limit.
   - (d) The review path is reports/master-completion-wave1/C-review/, not reports/mb-team/review/.
   - All four substitutions are explained in the mb-team plan, but no AGR or shortcut row covers them, and the master box text does not mention them.
6. **W-6, Stage 12.** The recorded doc tests have no clean pre-split run (D report: "my first baseline run was contaminated"), and the router test was written after the split (red shown by measurement only).
7. **W-7, Stage 13.**
   - The models are unverified. team.json records H1 and H2 as `models.executor: "sonnet"` (preset:small) with `review: none`, but the report says Fable and Opus 5.5 executors with an Opus reviewer. No dispatch record shows the model override.
   - The upgrade check deviated from the plan: a same-HOME upgrade passed, and the temp-HOME `--clients claude-code` upgrade was refused by design (I-300).
   - "/mb loads, /mb help work works" is not evidenced in the report.
   - Metrics are approximate agent-usage numbers, not `mb-cost-report.py` output.
8. **W-8, Stage 21 box 1.** "Three measurements" was weakened in place. Only one (tool binding, by source reading) was done; the live run and the cost comparison were not. The box carries a note, but no AGR authorizes skipping them. The no-go verdict matches AGR-104, so the risk is low.
9. **W-9, Stage 22.** `tests scripts/mb_team_ops.py` lists test_mb_team_checkpoint/hardening.bats, but not test_mb_team_cli.bats, which is the main team bats. A3.md says it is reached via lib/team_fixture.bash, which the graph cannot resolve statically. "Lists the team bats" is therefore only partly met.

### INFO
1. Stage 9 box 2: codex did not re-review fix cycle 2. The Stage 10 codex re-pass happened (B4-review part 2), and its deferrals are in I-299. This is noted in the box text.
2. Stage 14: the comment at scripts/mb-fanout.sh:200-202 still says that a resolve failure takes `die_usage` → exit 2. That is stale after T13; the code now falls back sequentially at :210-218.
3. Stage 16: the DoD line at svp-contract-test-loop/tasks.md:251 still says "S8 T5 verify line pending: HANDOVER". The line exists at references/mb/verify.md:56, so the note is stale.
4. The report file names differ from the plan (`reports/2026-11-19_graph-adoption.md` vs `2026-11-graph-adoption.md`, and likewise for opus55). This is harmless.
5. opus55-prompt-fit Stage 8 has no boxes. Its 5.3.2 bump, per-client upgrade and `--language ru` install are dropped by AGR-102 and AGR-084.
6. scripts/mb_openspec_normalize.py is 412 lines (> 300). It was not touched by this plan's split.

### Bank consistency
- **checklist.md master-completion block** (:50-73): 21/22 ✅, Stage 19 ⬜. This matches the plan.
- **checklist.md S5 block** `svp-adapt-escalation — 0/5` (:75-80, `<!-- mb-plan:tasks.md -->`) is stale. S5 tasks are 5/5 ticked. Fix it in Stage 19.
- **checklist.md:21** still queues `graph-semantic-adoption` as the head of mb-work-cost-diet, but that plan is now done.
- **roadmap.md:13** says master-completion is at 83%, done=18, planned=3; the checklist says 21/22. The roadmap is stale; `mb-roadmap-sync.sh` is part of Stage 19.
- **status.md:4** says "19 stages" in tracks A–F. The plan now has 22 stages and track G. Stale.
- **plans/done/** (cursor-compatibility-remediation 23/23, codex-global-native-hooks 5/5, mb-team 47/47, command-skill-root-paths 6/6 with grep DoD re-checked clean, opus55-prompt-fit 27/30 with the 3 open boxes in Stage 7 dropped by AGR-102): really done. graph-semantic-adoption is the exception (C-2).
- **Backlog I-293…I-302:** all 10 entries exist (backlog.md:1153-1184), with severity and evidence links. Three are stale:
  - I-297 is still `NEW`, but Stage 22 (0139fcb) fixed it.
  - I-294 still lists J-1, which H1 fixed.
  - I-296 still lists "no duplicate-ID lint", which H2 fixed.
  - Mark those parts DONE.
- **Uncommitted:** plans/2026-11-05_feature_unfinished-work-completion.md (Stage 19 in progress). `.pi/` is untracked, as the plan intends.

### Gate (overall success criteria): not met yet
- Tracks closed (graph-semantic-adoption, mb-team, cursor, codex-global, opus55 in done/; openspec-adapter ticked 8/8, validate rc=0): met, except the graph-semantic-adoption open boxes (C-2).
- dynamic-flow 14/14: met.
- S4, S5, S7, S8 open DoD = 0 with validate rc=0: met.
- Stage 7 demo `graph_share` > 0 for implementer and reviewer: met by self-reported counts (W-4).
- Full suite green or pre-existing failures logged: pending (Stage 19).
- plan-verifier PASS: not yet (C-1, C-2).

### Verified positively (proof, not just absence of findings)
- The Graph push block is in implementer, review and judge dispatch. Proof: commands/work.md:133,162,258,277 and test_graph_dispatch_docs (temp-HOME render of mb-judge).
- The graph maps bats → sh → py and adds argparse dispatch edges. Proof: real-graph queries above and test_graph_test_mapping.py.
- The OpenSpec round-trip keeps bank-added design sections. Proof: test_openspec_sync3.py:95,110; there are 147 openspec pytest cases.
- `/mb work <change-id>` is resolved through sync. Proof: test_mb_work_resolve.bats:72-168.
- The S5 journal survives concurrent writers. Proof: test_mb_work_adapt_journal.py:142.
- The Pi settle gate caps resumes and fails open. Proof: test_pi_native_settle.py.
- Fan-out falls back to sequential with a WARN. Proof: test_subinvoke_pi_opencode.bats:62.
- `commands/mb.md` stays at or under 16384 bytes (12099) and every router row resolves. Proof: test_mb_router_targets.py.

### Recommendations
1. Fix C-1: checklist Pi block → Stage 5 ⬜, header 4/5.
2. Fix C-2: annotate graph-semantic-adoption Stage 5 and Stage 7 boxes (superseded / deferred, with links), or reword master Stage 7 box 2.
3. Record W-5 (Stage 11 substitutions) and W-8 (Stage 21 measurements skipped) as notes on the master boxes, or with one AGR, and fix the box text of Stage 1 box 2 (W-1).
4. Stage 13: attach evidence of the H1/H2 models (dispatch log), or reword the report; add a `/mb help work` smoke line.
5. Stage 19 bank sync: S5 checklist block, checklist.md:21, roadmap (`mb-roadmap-sync.sh`), status.md focus line, I-294, I-296 and I-297 status.
6. Follow-up (not blocking): confirm `agent_id` in the Claude Code PreToolUse payload and SubagentStart support from the docs (I-293); fix the stale comment at mb-fanout.sh:200.
