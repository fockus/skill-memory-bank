---
type: feature
topic: master-completion
status: in_progress
depends_on: []
parallel_safe: true
linked_specs: [specs/openspec-adapter, specs/dynamic-flow, specs/svp-brief, specs/svp-contract-test-loop, specs/svp-roadmap-backlog-db, specs/svp-adapt-escalation, specs/mb-team]
linked_plans: [plans/2026-07-28_fix_graph-semantic-adoption.md, plans/2026-10-10_feature_mb-team.md, plans/2026-09-24_fix_opus55-prompt-fit.md, plans/2026-05-24_fix_cursor-compatibility-remediation.md, plans/2026-10-09_fix_codex-global-native-hooks.md, plans/2026-10-09_feature_codex-memory-parity.md, plans/2026-10-05_feature_pi-native-integration.md, plans/2026-11-05_feature_unfinished-work-completion.md]
qa: off — tooling and bank work; acceptance is the targeted test files named per stage plus one full suite at the end
created: 2026-11-18
---
# Plan: feature — master-completion

**Baseline commit:** 1815bcc1e16b5b2b5a1c9300c12953261198dd01
**Tier:** extra. **Decisions:** AGR-101 (OpenSpec round-trip), AGR-102 (opus55 only for Opus 5.5 / Fable), AGR-103 (one master plan, parallel tracks, shortcuts allowed, GraphRAG first).

## Context

**Problem.** Eleven plans and specs the owner wants finished are half-open, and several are already done in code but not ticked. The owner asked (2026-11-18) for one master plan that finishes all of them in parallel tracks, cutting corners where that is faster without losing the result. The GraphRAG track has top priority: the code graph and semantic search must become a tool code agents actually use, not just one that exists.

**Recon (2026-11-18, three read-only agents, re-checked where cheap):**
- Graph tooling works (`mb-graph.sh status` fresh; `tests` 1.5 s, `search` 3.5 s; tooling block composed into dev roles, `mb-reviewer`, `plan-verifier` on all hosts). Gaps: nudge suggests junk symbols (`who-calls sed`, `hooks/mb-graph-nudge.sh:139-145`); throttle keyed by `session_id` only (`:88-91`); no graph push block in `/mb work` review/judge prompts (`commands/work.md` §5c–5e); `mb-judge`, `mb-reviewer-{lead,logic,…}` lack the tooling block; no `graph_share` in the cost report; `hooks/mb-context-slim-pre-agent.sh` has no graph line; Pi graph test fixture resolves Pi via `npm root -g` (passes 15/15 with `PI_PACKAGE_ROOT` set).
- `commands/work.md` and `references/work-reference.md` are both exactly 400 lines against the 400 zone limit (`tests/pytest/test_s2_file_size_contract.py`).
- OpenSpec: import works (`scripts/mb-openspec.py:246-352`, 91 tests); `/mb openspec` is already routed (`commands/mb.md:67,117-127`, `c89d5fd`); read-in-place and write-back are missing, write-back was forbidden by D-01 (now superseded by AGR-101). Import drops what export needs (capability name, delta kind, raw text, task ids).
- mb-team: only a single-reviewer report exists (`reports/mb-team/review.md`, CHANGES_REQUESTED); M1–M5 fixed, m1–m7 open; no `master.json`.
- cursor Task 9, codex-global-native-hooks Stage 2, Pi Stage 3, codex-memory-parity Stage 2, `specs/mb-research-tooling-core` — done in code, records stale.
- opus55-prompt-fit: Stage 6 not started (`commands/mb.md` 1792 lines / 111 KB); Stage 7 dropped by AGR-102; Stage 8 partly kept.
- dynamic-flow T13: resolver table already lists pi/opencode, adapters lack `subinvoke` verbs, `scripts/mb-fanout.sh:210` dies instead of running sequentially; T14 is three new skills whose wrapped reflexion/sadd skills are not in this repo.
- SVP: S7 T1/T4 and S8 T4–T8 implemented and green, not ticked; S4 T3–T5, T7–T9 not started; S5 partly covered by ADaPT-lite (`190251c`).

**Out of scope (stay where they are):** S1/S2/S3/S6/S9 and the umbrella of `sdd-vision-pipeline` stay in `plans/2026-11-05_feature_unfinished-work-completion.md` (G-001 paused); `proportional-effort` Sprint 2 Stage 4 needs the owner's real sessions (AGR-072); `codex-memory-parity` Stages 1, 3, 4; `pi-native-integration` acceptance; I-086 config-validation-docs.

## Shortcuts taken (AGR-103)

| Where | Full path | Shortcut | Why it is safe |
|---|---|---|---|
| Already-shipped work (Stage 1) | re-run governed cycle | tick with commit + green test evidence | code and tests exist on HEAD |
| S7/S8 closure (Stage 16) | retro-red in worktree + judge (AGR-098 Q2) | green on HEAD + spec validate rc=0, `eval_gate=retro-skipped` recorded | the code has shipped and been in use since July–August |
| Execution workflow | codex-governed per item | AGR-097: direct executor with TDD, plan-verifier at the end; external reviewer only on Stages 9 and 11 | review spent where data loss or a review gate is the point |
| Graph measurement (Stage 7) | 7-day window before closing | demo run closes the track; the 7-day window is read later as a report | adoption is visible in the demo; the window only quantifies it |
| Pi graph fixture (Stage 6) | rework Pi resolution | resolve from `pi` on `PATH`, skip with a reason if absent | fixture-only change |
| dynamic-flow T14 (Stage 15) | wrap external reflexion/sadd skills | self-contained skills, spec text updated | the wrapped skills are not in this repo |
| mb-team minors (Stage 11) | fix all findings | blocker/major/medium fixed; minors to backlog | matches the stage's own DoD |
| Version bump (Stage 13) | 5.3.2 release | CHANGELOG entry only, no tag | AGR-084: no release yet |
| mb-team close (Stage 11) | lead re-review until 0/0/0, plan-verifier PASS, ≤3 cycles | 4 fix cycles (budget 2) then mb-judge GO_WITH_BACKLOG; the judge re-ran the probes and tests in place of a cycle-5 lead pass and of plan-verifier | each cycle found a variant of one root cause; the ownership-marker fix ends it; judge terminates the loop |
| OpenSpec review (Stages 9-10) | codex re-review clean after fixes | judge closed cycle-2 fixes; codex re-pass in Stage 10 found more; shared writer lock and rename journal deferred (I-299) | the remaining items need a lock shared by every bank writer — a separate design |
| mb.md split baseline (Stage 12) | clean pre-split doc-test run | post-split runs + full-corpus line-loss check by the reviewer | the pre-split run was contaminated by parallel tracks |
| Opus/Fable run (Stage 13) | metrics from mb-cost-report | executor/agent usage counters; models set by the dispatch `model` parameter (fable for H1, opus for H2 — team.json keeps the track preset); upgrade check = same-HOME upgrade by the debugger (temp-HOME run was invalid, see upgrade-debug.md) | cost-report has no per-agent model split |
| Graph hints (Stages 2, 6) | agent_id from a captured payload; Claude SubagentStart wired or proven unsupported | agent_id used when present (unconfirmed → I-303); Claude SubagentStart unconfirmed → I-293 | no captured payload or doc in the repo |
| pdw spike (Stage 21) | live run, roster binding, cost | source reading only (no provider auth in the isolated agent dir) | owner's credentials stay out of the spike; no-go stands on the roster-binding finding (AGR-104) |
| Pi live check (Stage 20) | real Pi session | skipped by the owner | AGR-108 |
| Stage 19 full suite | full bats green locally | 5 local-only e2e failures accepted as pre-existing (I-305); verifier PASS_WITH_NOTES accepted | identical failures at baseline 1815bcc, CI green; verifier notes are bank records, fixed |

## Tracks and waves

| Track | Stages | Owner role |
|---|---|---|
| 0 Bookkeeping | 1 | orchestrator |
| A GraphRAG (priority) | 2, 3, 4, 5, 6, 7, 22 | backend / debugger |
| B OpenSpec round-trip | 8, 9, 10 | backend |
| C mb-team close | 11 | reviewer-lead + developer |
| D opus55 (Opus 5.5 / Fable) | 12, 13 | developer |
| E dynamic-flow | 14, 15 | developer |
| F SVP S7/S8/S4/S5 | 16, 17, 18 | qa / backend / architect |
| G Pi continuity and flows | 20, 21 | backend / developer |
| Close | 19 | orchestrator + plan-verifier |

| Wave | Stages (parallel within a wave) | Needs before start | Executors (peak, ≤4) |
|---|---|---|---|
| 1 | 1 · 2→3→4 (one graph executor) · 11 · 12 · 14 | — | 4 |
| 2 | 5→6 · 8 · 15 · 16 · 20 · 13 (owner run) | 4 (for 5), 12 (for 15, 16, 13) | 4 |
| 3 | 9 · 17 · 7 · 21 · (11 fix cycles if open) | 8, 5, 6 | 3–4 |
| 4 | 10 · 18 (spec rebaseline part) | 5, 9, 17 | 2 |
| 5 | 18 (code part, `commands/work.md` after 10) | 10 | 1 |
| 6 | 19 | all | 1 + full suite |

**Shared files — strict order, never two tracks in one wave:**
- `commands/work.md`: 4 → 5 → 10 → 18
- `commands/mb.md`: 12 → 16 (S8 T5 patch, only if still needed) → 17 (S4 T5) → 10 (OpenSpec lines)
- `tests/pytest/test_doc_counts.py`: 12 → 15
- `agents/*.md`: 5, then 18 if its rebaseline needs agent text
- Bank core files (`checklist.md`, `roadmap.md`, `status.md`, `progress.md`, `backlog.md`, `goal.md`), `tests/pytest/test_spec_corpus_battery.py`: orchestrator only

**Execution:** `/mb team` with one track per letter (A–F); each track runs its stages in order, tracks run in parallel; the shared-file order below is enforced with `mb-lock.sh` and by the orchestrator before each dispatch. `mb-work-plan.sh --dry-run` waves are a conservative single-lane view and are not the schedule.

**Commits:** one scoped commit per wave (`git add <files>`, never `-A`); the pre-commit hook runs the full battery (minutes), so run it in the background. Legacy FREEZE on destructive git (`mb-coord.sh active`) stays in force. `.pi/` is a local install artifact and never committed.

**Rules for every stage:** TDD for new logic (failing test first); targeted tests and lint of changed files while working (`bash scripts/mb-test-run.sh --files <changed> --out human`, `shellcheck -x --source-path=SCRIPTDIR <sh>`, `ruff check <py>`); `PYTHONPATH=.` for local pytest; no new dependencies; the full suite runs once, in Stage 19.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Bookkeeping close-out of already-shipped work

**Track:** 0 · **Size:** S · roles: orchestrator
**Role:** developer
**Blocked-by:** none
**Files:** `.memory-bank/checklist.md`, `.memory-bank/roadmap.md`, `.memory-bank/backlog.md`, `.memory-bank/progress.md`, `.memory-bank/plans/2026-05-24_fix_cursor-compatibility-remediation.md`, `.memory-bank/plans/2026-10-09_fix_codex-global-native-hooks.md`, `.memory-bank/plans/2026-10-05_feature_pi-native-integration.md`, `.memory-bank/plans/2026-07-28_fix_graph-semantic-adoption.md`, `.memory-bank/specs/openspec-adapter/tasks.md`, `.memory-bank/specs/cursor-extension/tasks.md`, `.memory-bank/specs/mb-research-tooling-core/*.md`

**What to do:**
- openspec-adapter: tick `tasks.md:114` (router row landed in `c89d5fd`), close I-127, drop the open line from `checklist.md:34` and `roadmap.md:133`; add `--normalize` to the usage text of `scripts/mb-openspec.sh` (one line, in Stage 8's file set — do it there).
- cursor Task 9: tick plan `:76`, `:92` and spec `tasks.md:181-182` with evidence `adapters/cursor.sh:62,100,208-213` + `tests/bats/test_cursor_adapter.bats:103,374-383`; box `:91` (13 EARS warnings) — accept, link I-071; plan → `plans/done/` via `mb-plan-done.sh`.
- codex-global-native-hooks Stage 2: link the recorded full-suite classification and the GO_WITH_BACKLOG judge (`plans/2026-10-09_feature_codex-memory-parity.md:130`), tick, close the plan.
- pi-native-integration: sync the checklist block with the plan (Stages 1–4 `done` in the plan; Stage 3 verify/review/judge replaced by AGR-089); acceptance stays open.
- `specs/mb-research-tooling-core`: frontmatter `status: done` with links to `plans/done/2026-06-09_*` and `progress.md`.
- graph-semantic-adoption Stage 7: record the already-done sub-items (`8d21698` compose; graph-first in `agents/mb-engineering-core.md:22`).

**DoD:**
- [x] cursor-compatibility-remediation and codex-global-native-hooks are in `plans/done/`; `mb-plan-done.sh` exit 0 for both
- [x] `grep -c '\[~\]\|\[ \]' .memory-bank/specs/openspec-adapter/tasks.md` = 0; I-127 closed in `backlog.md`
- [x] checklist Pi block matches the plan's stage statuses; `bash scripts/mb-drift.sh .` reports no new drift for these plans

<!-- mb-stage:2 -->
### Stage 2: Graph nudge that suggests useful queries, per-subagent budget

**Track:** A · **Size:** S
**Role:** debugger
**Blocked-by:** none
**Files:** `hooks/mb-graph-nudge.sh`, `hooks/tests/graph-nudge*.bats` (existing file names — find with `bash scripts/mb-graph.sh tests hooks/mb-graph-nudge.sh`)

**What to do:**
- Fix the symbol picker (`:139-145`): never suggest shell builtins/commands (`sed`, `grep`, `awk`, `cat`, `find`, …) or plain lowercase English words; prefer identifiers that exist in the graph (`mb-graph.sh` lookup, fail-open when the graph is absent); no suggestion beats a wrong one.
- Key the throttle marker by `agent_id` when the PreToolUse payload carries it, else `session_id` (`:88-91`); confirm the field name from a captured payload before coding.
- Clear stale `.graph-nudge.*` markers older than 24 h on each run (64 currently in `.memory-bank/.index/`).

**Testing (TDD):** bats first — `grep sed foo` yields no `who-calls sed`; a payload grep for `mb_resolve_path` yields `who-calls mb_resolve_path`; two `agent_id`s each get their own budget; a 2-day-old marker is removed.

**DoD:**
- [x] new bats cases red before, green after; the existing nudge bats stay green
- [x] `shellcheck -x hooks/mb-graph-nudge.sh` clean

<!-- mb-stage:3 -->
### Stage 3: Graph share in the cost report

**Track:** A · **Size:** S
**Role:** backend
**Blocked-by:** none
**Files:** `memory_bank_skill/cost_report.py`, `scripts/mb-cost-report.py`, `tests/pytest/test_mb_cost_report.py`

**What to do:** count per role and per subagent the `mb-graph.sh`/graph-tool calls vs `Grep`/`grep` calls from transcripts; print `graph_share = graph / (graph + grep)` in text and JSON output.

**Testing (TDD):** two pytest cases on a fixture transcript — mixed calls give the exact share; no calls give `graph_share: null`, not a division error.

**DoD:**
- [x] `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_mb_cost_report.py` green; `ruff check` clean on both files
- [x] `python3 scripts/mb-cost-report.py --json` on this machine prints a `graph_share` key

<!-- mb-stage:4 -->
### Stage 4: Make room in `commands/work.md`

**Track:** A · **Size:** S
**Role:** developer
**Blocked-by:** none
**Files:** `commands/work.md`, `references/work-loop-reference.md` (new), tests that pin moved text (`grep -rl "commands/work.md" tests/`)

**What to do:** move ≥40 lines of reference material (flag tables, explanations — not executable steps, not clauses a test extracts) from `commands/work.md` into a new `references/work-loop-reference.md` (the existing `references/work-reference.md` is also at 400); leave a one-line pointer. Do not rename headings tests cut between.

**Testing:** run every doc test that reads `commands/work.md` before the move (record the list) and after.

**DoD:**
- [x] `wc -l < commands/work.md` ≤ 360; `test_s2_file_size_contract.py` green
- [x] the recorded doc tests green before and after

<!-- mb-stage:5 -->
### Stage 5: Graph context pushed into every `/mb work` dispatch

**Track:** A · **Size:** M
**Role:** backend
**Blocked-by:** 4
**Files:** `commands/work.md`, `agents/mb-judge.md`, `agents/mb-reviewer-lead.md`, `agents/mb-reviewer-logic.md`, `agents/mb-engineering-core.md`, `agents/plan-verifier.md`, `tests/pytest/test_graph_dispatch_docs.py` (new)

**What to do:**
- `commands/work.md` §5c–5e: before dispatching implementer, reviewer and judge, run `mb-graph.sh tests|impact` for the item's `Files:` and paste ≤40 lines under `## Graph` in the prompt; fail-open with one line when the graph is stale or absent.
- Add `compose: mb-tooling-core` to `mb-judge`, `mb-reviewer-lead`, `mb-reviewer-logic`.
- Implementer report gets an optional `Graph: <n> queries` line (`mb-engineering-core.md`); `plan-verifier` emits INFO (not a failure) when it is missing.

**Testing (TDD):** `test_graph_dispatch_docs.py` first — asserts the `## Graph` step exists in §5c, §5d, §5e, the three agents compose the tooling block, and the rendered Claude/Codex agent files contain `mb-graph.sh`.

**DoD:**
- [x] new test red before, green after; `test_tooling_core_wiring.py` and `test_s2_file_size_contract.py` green
- [x] `bash install.sh --clients claude-code,codex` in a temp HOME renders `mb-graph.sh` into `mb-judge`

<!-- mb-stage:6 -->
### Stage 6: Graph status on ad-hoc dispatch; Pi graph test fixture

**Track:** A · **Size:** S · order: 5 (same executor, sequential)
**Role:** debugger
**Blocked-by:** 5
**Files:** `hooks/mb-codex.py`, `hooks/mb-context-slim-pre-agent.sh`, `settings/hooks.json`, `tests/pytest/test_codex_native_hooks.py`, `tests/fixtures/pi_native_graph_host.mjs`, `tests/pytest/test_pi_native_graph.py`, hook bats for the pre-agent hook

**What to do:**
- Codex: add one graph status line (fresh/stale, the `mb-graph.sh` commands) to the `SubagentStart` additionalContext (`hooks/mb-codex.py:119`, ≤4000 chars kept).
- Claude Code: check whether `SubagentStart` exists and honours `additionalContext` (claude-code-guide or docs). If yes — register a hook that emits the same line; if not — drop this half (Stage 5 covers `/mb work`; record I-number in backlog). Do not rely on the pre-agent hook's orchestrator-only context.
- Pi fixture: resolve Pi from the `pi` binary on `PATH` (realpath → package root), else `pytest.skip` with the reason.

**DoD:**
- [x] `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_codex_native_hooks.py tests/pytest/test_pi_native_graph.py` green (15/15 Pi without `PI_PACKAGE_ROOT`)
- [x] Claude half either wired with a test or recorded as not supported, with the source

<!-- mb-stage:7 -->
### Stage 7: Graph adoption demo and measurement

**Track:** A · **Size:** M
**Role:** qa
**Blocked-by:** 2, 3, 5, 6
**Files:** `.memory-bank/reports/2026-11-graph-adoption.md` (new), `.memory-bank/plans/2026-07-28_fix_graph-semantic-adoption.md`

**What to do:** run one real `/mb work` item from Track F through implementer + reviewer; record from `mb-cost-report.py` the `graph_share` per role and two concrete places where a graph answer replaced a grep sweep; start a 7-day window and note the date to re-read (report appendix, not a gate). Close graph-semantic-adoption Stages 5 and 7.

**DoD:**
- [x] report shows `graph_share` > 0 for implementer and reviewer in the demo run
- [x] graph-semantic-adoption 11/11 and moved to `plans/done/`

<!-- mb-stage:8 -->
### Stage 8: OpenSpec contract decisions; import keeps what export needs

**Track:** B · **Size:** M · roles: architect then backend · order: — (risky checkpoint: owner confirms decisions before code)
**Role:** architect
**Blocked-by:** none
**Files:** `.memory-bank/context/openspec-adapter.md`, `.memory-bank/specs/openspec-adapter/{requirements,design,tasks}.md`, `scripts/mb_openspec_parse.py`, `scripts/mb_openspec_model.py`, `scripts/mb_openspec_convert.py`, `scripts/mb-openspec.sh`, `tests/pytest/test_openspec_*.py`, golden fixtures under `tests/fixtures/openspec*`

**What to do:**
- Decisions: done — `context/openspec-adapter.md` § Round-trip (AGR-101), accepted by the owner as AGR-105 (track B, 2026-11-18).
- Import writes the per-requirement meta line (cap, kind) before the anchor, keys tasks by their `N.M` id (text fallback), keeps Covers/Role bank-side after the first import, emits RENAMED deltas, and writes the committed `specs/<topic>/openspec-sync.json` sidecar with per-unit hashes of both sides; `sync` adopts a baseline for imports that predate the sidecar (AGR-105).
- Add `--normalize` to the `mb-openspec.sh` usage text.

**Testing (TDD):** golden fixtures updated deliberately (NFR-001 byte output changes are expected and reviewed); a parse test asserts capability and kind survive; an old-format import re-imports cleanly.

**DoD:**
- [x] decisions AGR recorded; `bash scripts/mb-spec-validate.sh .memory-bank/specs/openspec-adapter` rc=0
- [x] all `tests/pytest/test_openspec_*.py` and `tests/bats/test_mb_openspec.bats` green

<!-- mb-stage:9 -->
### Stage 9: OpenSpec export and three-way sync

**Track:** B · **Size:** L · roles: backend + external reviewer
**Role:** backend
**Blocked-by:** 8
**Files:** `scripts/mb-openspec.py`, `scripts/mb_openspec_export.py` (new), `scripts/mb-openspec.sh`, `tests/pytest/test_openspec_export.py` (new), `tests/pytest/test_openspec_sync3.py` (new), `tests/bats/test_mb_openspec.bats`

**What to do:**
- `export <topic>`: splice only the changed units back into `openspec/changes/<id>/` (unchanged units keep OpenSpec bytes, REQ-IDs stripped). Dry-run diff by default, `--write` to apply; refuse when OpenSpec drifted since the last sync and point to `sync` (no `--force`, AGR-105); deletions only with `--allow-delete`; atomic writes; write guard limited to that one change directory.
- `sync` becomes per-unit three-way against the sidecar and writes only the bank: only OpenSpec changed → update the bank; only ours → print "run export"; both changed differently → conflict report, exit non-zero, nothing written; `sync --take openspec|bank` resolves.
- `export --new <topic>`: a spec authored in the bank becomes a new OpenSpec change.
- Import keeps its no-write-outside-`.memory-bank/` guard.
- Carry-over from Stage 8 (B2, medium): an explicit `import`, or `sync` with an unchanged bank, still rewrites `requirements.md`/`design.md` whole, so bank-added design sections and task prose are lost — the per-unit splice must cover every bank write path, with a test that a bank-added design section survives `import` and `sync`.
- Split `scripts/mb-openspec.py` (777 lines) and `scripts/mb_openspec_convert.py` (646) along the new export module rather than growing them.

**Testing (TDD):** round-trip golden: import → export → byte-identical to the source; both-changed fixture → conflict, no file touched (mtime/hash check); write guard refuses a path outside the change dir; `--new` produces a change the importer reads back to the same triple.

**DoD:**
- [x] new tests red before, green after; existing OpenSpec tests green
- [x] external review (codex-reviewer) has no blocker/major open — cycle 1 and 2 by codex; the cycle-2 fixes verified and closed by mb-judge (GO_WITH_BACKLOG, B3-judge.json) after the fix budget ran out; codex re-pass moves to the Stage 10 review
- [x] `ruff check` clean on changed Python

<!-- mb-stage:10 -->
### Stage 10: `/mb work` over an OpenSpec change; docs

**Track:** B · **Size:** M · order: 5 (`commands/work.md`), 9, 12 (`commands/mb.md`), 17 (`commands/mb.md`)
**Role:** backend
**Blocked-by:** 5, 9, 12, 17
**Files:** `scripts/mb-work-resolve.sh`, `scripts/mb_work_source.py`, `commands/work.md`, `commands/mb.md` (or its `references/mb/` part after Stage 12), `docs/` OpenSpec page, `CHANGELOG.md`, `tests/bats/test_mb_work_resolve*.bats`

**What to do:** `/mb work <openspec-change-id|openspec/changes/<id>>` runs `sync` (import when new), then works on the bank triple; on item completion, the run ends with a dry-run `export` diff and asks before `--write`. Document `export`, `sync`, `--new` and the in-place flow in the `/mb openspec` section and docs; CHANGELOG line.

**Testing (TDD):** resolver bats — a change id resolves to the synced triple; an unknown id fails with a clear message; a native topic resolves as before.

**DoD:**
- [x] resolver tests green; `wc -l < commands/work.md` ≤ 400
- [x] docs and `/mb openspec` section list all four directions

<!-- mb-stage:11 -->
### Stage 11: mb-team review until clean

**Track:** C · **Size:** L · roles: reviewer-lead + developer
**Role:** developer
**Blocked-by:** none
**Files:** `scripts/mb_team_status.py`, `scripts/mb_team_ops.py`, `scripts/mb_team_review.py`, `scripts/mb_team_render.py`, `scripts/mb-lock.sh`, `scripts/mb_lock_*.py`, `scripts/mb_vcs.sh`, `scripts/mb-team-checkpoint.sh`, `commands/team.md`, `.memory-bank/specs/mb-team/design.md`, team tests under `tests/bats/` and `tests/pytest/`, `.memory-bank/reports/mb-team/review/`, `.memory-bank/plans/2026-10-10_feature_mb-team.md`

**What to do:** run `/mb team review` (ensemble + lead) over `git diff f050443..HEAD` restricted to team files; fix blocker/major/medium; the lead classifies m1–m4, m6, m7 from `reports/mb-team/fix-verify.md:198-205` — medium gets fixed, the rest goes to backlog; repeat ≤3 cycles; then plan-verifier.

**DoD:**
- [x] latest `reports/mb-team/review/cycle-N/master.json` has 0 blocker, 0 major, 0 medium
- [x] team bats/pytest green; plan-verifier PASS; mb-team plan 47/47 and in `plans/done/`

<!-- mb-stage:12 -->
### Stage 12: Split `commands/mb.md` for Opus 5.5 / Fable

**Track:** D · **Size:** L
**Role:** developer
**Blocked-by:** none
**Files:** `commands/mb.md`, `references/mb/*.md` (new), `commands/done.md`, `tests/pytest/test_doc_counts.py`, tests that read `commands/mb.md` (`grep -rl "commands/mb.md" tests/`), `.memory-bank/plans/2026-09-24_fix_opus55-prompt-fit.md`

**What to do:** keep in `commands/mb.md` only the router table and the always-needed rules (target ≤ 4K tokens ≈ 16 KB); move each subcommand section to `references/mb/<sub>.md`, loaded on route; add `/mb help <sub>`. Clauses tests extract move with their test path updated in the same change. `mb-done-finalize.sh` box is dropped (optional in the plan). Mark Stage 7 of opus55-prompt-fit `dropped (AGR-102)`.

**Testing:** list of doc tests reading `commands/mb.md` recorded and green before; after — same tests green against the new paths; one new test: every router row points at an existing `references/mb/*.md`.

**DoD:**
- [x] `wc -c < commands/mb.md` ≤ 16384; router-row test green; recorded doc tests green
- [x] opus55-prompt-fit Stage 6 ticked, Stage 7 marked dropped

<!-- mb-stage:13 -->
### Stage 13: Opus 5.5 / Fable acceptance run

**Track:** D · **Size:** M · roles: developer + owner
**Role:** developer
**Blocked-by:** 12
**Files:** `.memory-bank/reports/2026-11-opus55-fable-run.md` (new), `CHANGELOG.md`, `.memory-bank/plans/2026-09-24_fix_opus55-prompt-fit.md`

**What to do:** Claude Code upgrade check in a temp HOME (`install.sh --clients claude-code` over the previous install, `/mb` loads, `/mb help work` works); one real `/mb work` item on Fable and one on Opus 5.5 with `mb-cost-report.py` metrics (tokens, turns, `graph_share`); CHANGELOG `Unreleased` entry; no version bump or tag (AGR-084).

**DoD:**
- [x] report with both runs and the upgrade check; opus55-prompt-fit closed and moved to `plans/done/`

<!-- mb-stage:14 -->
### Stage 14: dynamic-flow T13 — Pi and OpenCode sub-invoke

**Track:** E · **Size:** M
**Role:** developer
**Blocked-by:** none
**Files:** `adapters/pi.sh`, `adapters/opencode.sh`, `scripts/mb-fanout.sh`, `scripts/mb-subinvoke-resolve.sh`, `tests/bats/test_mb_fanout*.bats`, `tests/bats/test_*subinvoke*.bats`, `.memory-bank/specs/dynamic-flow/tasks.md`

**What to do:** add `pi_subinvoke_cmd` / `opencode_subinvoke_cmd` and a `subinvoke` verb mirroring `adapters/codex.sh:503-603`, preferring the native dispatch (`adapters/pi_subagent_extension.ts:21`, `adapters/opencode_workflow.mjs:191-207`); `mb-fanout.sh:210` runs sequentially with a WARN instead of `die_usage` when sub-invoke is unresolvable.

**Testing (TDD):** bats with stub `pi`/`opencode` binaries on `PATH` — the verb prints the expected command; with neither available, fan-out runs sequentially and prints WARN, exit 0.

**DoD:**
- [x] new bats red before, green after; `shellcheck` clean on changed `.sh`; T13 ticked through `mb-work-state.sh done`

<!-- mb-stage:15 -->
### Stage 15: dynamic-flow T14 — critique, risk-find, final-report skills

**Track:** E · **Size:** M · order: 12 (`tests/pytest/test_doc_counts.py`)
**Role:** developer
**Blocked-by:** 12
**Files:** `commands/critique.md`, `commands/risk-find.md`, `commands/final-report.md` (new), `tests/pytest/test_doc_counts.py`, `tests/pytest/test_dynamic_flow_skills.py` (new), `.memory-bank/specs/dynamic-flow/{design,tasks}.md`

**What to do:** three self-contained commands in the shape of `commands/analyze-task.md`; update T14 text to drop the reflexion/sadd wrap (shortcut); usable as dynamic-flow steps (frontmatter the flow templates read).

**DoD:**
- [x] new test (frontmatter + flow-template reference) green; doc counts updated; dynamic-flow 14/14

<!-- mb-stage:16 -->
### Stage 16: Close S7 svp-brief and S8 svp-contract-test-loop (shipped, unticked)

**Track:** F · **Size:** M · order: 12 (only if the S8 T5 `commands/mb.md` patch is still needed)
**Role:** qa
**Blocked-by:** 12
**Files:** `.memory-bank/specs/svp-brief/{design,tasks}.md`, `.memory-bank/specs/svp-contract-test-loop/{design,tasks}.md`, `commands/mb.md` (conditional)

**What to do:** conformance — `**Seams:**` block in both designs (REQ-051), REQ-049 for S7 T3, eight CPR-D declarations in S8 `design.md` byte-identical with `tasks.md`; check whether S8 T5's `commands/mb.md` patch is still missing and apply it if so; run the Eval files on HEAD; tick through `mb-work-state.sh done` with `eval_gate=retro-skipped` noted (shortcut replaces AGR-098 Q2 for these two specs, AGR-103).

**Testing:** `bats tests/bats/test_mb_secret_scan_brief_input.bats tests/bats/test_mb_brief_command.bats tests/bats/test_mb_brief_docs.bats tests/bats/test_mb_contract_gate.bats`; `PYTHONPATH=. python3 -m pytest -q tests/pytest/test_sdd_layers_render.py tests/pytest/test_quality_dod_delivery.py tests/pytest/test_integration_contract_test_loop.py tests/pytest/test_e2e_contract_test_loop.py`.

**DoD:**
- [x] `bash scripts/mb-spec-validate.sh --require-scenarios` rc=0 for both specs; open DoD = 0 in both
- [x] orchestrator removes both from `KNOWN_FAILING`; `test_spec_corpus_battery.py` green

<!-- mb-stage:17 -->
### Stage 17: S4 svp-roadmap-backlog-db remainder

**Track:** F · **Size:** L · order: 12 (`commands/mb.md` for T5)
**Role:** backend
**Blocked-by:** 12
**Files:** `scripts/_lib.sh`, `scripts/mb-idea.sh`, `scripts/mb-idea-promote.sh`, `scripts/mb-backlog-state.sh`, `scripts/mb-backlog-migrate.sh` (new), `scripts/mb-bank-lint.sh` (new), `commands/mb.md` (T5), `references/templates.md` (T5), `CLAUDE.md` (T5), Eval test files of T3/T4/T5/T7/T8/T9, `.memory-bank/specs/svp-roadmap-backlog-db/{design,tasks}.md`

**What to do:** `/mb work svp-roadmap-backlog-db --range 3-9` with the AGR-097 workflow: T9 and T7 first (disjoint files), then T3 → T8 → T4 → T5; conformance (Seams, REQ-049 for T5).

**Testing (TDD):** each task's Eval red before code — T9 `test_mb_backlog_id_alloc.bats` + `test_mb_idea_promote_v2.bats`; T7 `test_mb_backlog_state_hierarchy.bats`; T3 `test_mb_backlog_migrate.bats`; T8 `test_mb_backlog_out_of_scope.bats`; T4 `test_mb_bank_lint.bats`; T5 `test_mb_roadmap_backlog_docs.bats`. Migrator runs on a copy of `backlog.md`, never the live file.

**DoD:**
- [x] open DoD = 0; validate rc=0; regressions `test_mb_roadmap_sync_ice.bats`, `test_mb_roadmap_sync_group.bats`, `test_mb_backlog_state.bats`, `test_mb_lock_helper.bats` green
- [x] positional `mb-idea.sh` calls byte-identical (existing tests)

<!-- mb-stage:18 -->
### Stage 18: S5 svp-adapt-escalation — rebaseline on ADaPT-lite and remainder

**Track:** F · **Size:** L · roles: architect then backend · order: 17; code that edits `commands/work.md` — after 10
**Role:** architect
**Blocked-by:** 10, 17
**Files:** `.memory-bank/specs/svp-adapt-escalation/{requirements,design,tasks}.md`, `references/adapt.md`, `scripts/mb_work_adapt.py`, `references/pipeline.default.yaml`, `scripts/mb-pipeline-validate.sh`, `commands/work.md`, Eval test files of the rebased tasks

**What to do:** map REQ-001…010 onto ADaPT-lite (`190251c`, AGR-080/082): covered parts → waiver with the commit link; the rest stays as tasks on the existing files (`mb_work_adapt.py`, `adapt:` block) — stubs (REQ-004), escalation journal under `mb_lock_acquire` (REQ-007/008), cascade (REQ-010); the scope guard (REQ-002) uses a minimal check inside `mb_work_adapt.py` against the item's `Files:` instead of waiting for S3's `mb-work-scope-check.sh` (S3 out of scope). `adapt.verify_fail_cycles: 3` default unchanged.

**Testing (TDD):** Eval per remaining task red first; existing `grep -rl mb_work_adapt tests/` tests stay green.

**DoD:**
- [x] open DoD = 0; validate rc=0; escalations written as JSONL under the lock (test)
- [x] `wc -l < commands/work.md` ≤ 400

<!-- mb-stage:19 -->
### Stage 19: Final verification and bank sync

**Track:** close · **Size:** M · roles: orchestrator + plan-verifier · order: 1–18
**Role:** qa
**Blocked-by:** 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 21, 22
**Files:** `.memory-bank/{roadmap,status,checklist,progress,backlog}.md`, `tests/pytest/test_spec_corpus_battery.py`, `.memory-bank/plans/2026-11-05_feature_unfinished-work-completion.md`

**What to do:** full suite once in the background (`bats tests/bats/ tests/e2e/ hooks/tests/*.bats`; `PYTHONPATH=. python3 -m pytest hooks/tests/ tests/pytest/`; `shellcheck` error gate; `ruff check`); failures triaged against a clean HEAD worktree — pre-existing ones go to backlog with evidence; plan-verifier on this plan; rewrite `unfinished-work-completion` to hold only S1/S2/S3/S6/S9 + umbrella; `mb-roadmap-sync.sh`; close this plan.

**DoD:**
- [x] full suite green or every failure proven pre-existing on HEAD and logged — pytest green after track Z; bats 43 failures: 31 fixed in 156b5b9, 7 env leaks fixed (same fixes also on origin for 3 files), Pi gate phrase restored; 5 install_reliability failures fail identically at baseline 1815bcc, green in CI → I-305
- [x] plan-verifier PASS; all stages ticked; this plan in `plans/done/` — PASS_WITH_NOTES, notes 1–3 fixed in the bank (roadmap rows, bogus `plans/tasks.md` → I-304, closure line)

<!-- mb-stage:20 -->
### Stage 20: Pi keeps working until the task is done (settle-resume gate)

**Track:** G · **Size:** M · roles: backend
**Role:** backend
**Blocked-by:** none

**Evidence (2026-11-18 research):** over 40 days of the owner's Pi sessions, 567 turns ended with `stop` (text only) vs 7007 `toolUse`; many end with "next step … not started" or a permission question and the owner types "продолжи". Pi ends a turn when a response has no tool calls and has no max-turns setting (`docs/how-pi-works.md`). Our extension never handles Pi's `agent_before_settle` hook (`docs/extensions.md:663-695`), the last point where an extension can return `continue: true`; `hooks/mb-drive-resume-gate.sh:5-8` covers only Claude Code and Codex. Our hooks were ruled out as the cause (refusal texts appear in 0 sessions). 66 turns ended on provider errors, which Pi treats as hard exits.

**Files:** `adapters/pi_native_settle.mjs` (new), `adapters/pi_graph_rag_extension.ts`, `adapters/_lib_pi_global.sh`, `adapters/pi.sh`, `adapters/pi_subagent_extension.ts`, `tests/pytest/test_pi_native_settle.py` (new), `docs/cross-agent-setup.md`

**What to do:**
- `agent_before_settle` handler, registered with the other native hooks: runs the same read-only decision as `hooks/mb-drive-resume-gate.sh` (drive run in `execution`, goal unmet) and the `/mb work` state (`.work-state/<run>.json` with an unfinished step); when work is unfinished, add a hidden custom message naming the next command and return `continue: true`. Cap at 3 resumes per settle cycle, fail open on any error, never on error/aborted responses.
- Persistence lines in the Pi AGENTS.md block (`adapters/pi.sh` / `_lib_pi_global.sh`): inside an approved plan or workflow, do not end the turn with a status update — keep calling tools until a gate or a real blocker; ask only for decisions outside the granted scope.
- `pi_subagent_extension.ts:25`: "retry once if the failure is transient, then report and stop".
- Docs: recommended `retry.maxRetries`, `retry.maxAgentDelayMs`, `httpIdleTimeoutMs` for `~/.pi/agent/settings.json` (owner's file — documented, not written).

**Testing (TDD):** pytest driving the handler through the existing Pi host fixture: unfinished drive run → `continue: true` with the message; finished run → no continue; 4th resume in one cycle → no continue; corrupt state file → no continue, no throw; error response → untouched.

**DoD:**
- [x] new tests red before, green after; existing `tests/pytest/test_pi_native_*.py` green (173 passed, 17 skipped, 2026-11-18)
- [x] live check: skipped by the owner (AGR-108, 2026-11-19); accepted on the automated tests

<!-- mb-stage:21 -->
### Stage 21: pi-dynamic-workflows — borrow now, spike as an optional Pi accelerator

**Track:** G · **Size:** M · roles: researcher then developer · decided: AGR-104 (borrow + spike, not the engine)
**Role:** developer
**Blocked-by:** 15

**Evidence (2026-11-18 research):** `@quintinshaw/pi-dynamic-workflows` v3.15.2 (MIT, active) is an LLM-authored JS workflow runtime with its own journal in `~/.pi/workflows/`; its children are in-process sessions that bypass our Tintin/Nico backends and capability ceilings (AGR-088/090); its `verify`/`judgePanel` are LLM votes. dynamic-flow REQ-DF-061/085 forbid a JS runtime and journal on the critical path; REQ-DF-083 allows a native feature as an optional optimization.

**Files:** `.memory-bank/experiments/EXP-pdw-spike.md` (new), `.memory-bank/specs/dynamic-flow/design.md`, `flow-templates/patterns/*.md`, `adapters/pi_native_bootstrap.mjs` (only if the spike passes)

**What to do:**
- Borrow (no dependency): `gate(thunk, validator, attempts)` validator-feedback retry into the T14 `critique` design; schema check of branch output next to REQ-DF-084; `loopUntilDry` stop rule as a pattern note.
- Spike (no product code): on Pi with pdw installed, run `fanout-synthesize` for a read-only research task with `agentType: "mb-researcher"`, pipe the result into `mb-flow-verify.sh`; record whether our roster's `tools:`/`compose:` bind, the tool scope children actually get, and cost vs `mb-fanout.sh` + `pi -p`.
- Only if the spike passes: runtime detection of the package (like `pi_native_bootstrap.mjs:88-91`), read-only branches only, a "Pi native optimization" note in each pattern template.

**DoD:**
- [x] EXP report with the three measurements and a go/no-go (no-go: roster tool names are exact-case, compose:/effort: ignored; live run not done — no provider auth in the isolated agent dir; cost not measured; EXP-pdw-spike.md)
- [x] borrowed ideas present in dynamic-flow design.md (ADR-11, loop-until-done dry-round stop); no-go → backlog entry

<!-- mb-stage:22 -->
### Stage 22: Graph sees tests through shell entry points and argparse dispatch (I-297)

**Track:** A · **Size:** M
**Role:** backend
**Blocked-by:** 5

**Evidence (2026-11-19, Stage 7 demo runs H1/H2):** `mb-graph.sh tests scripts/mb_bank_lint_backlog.py` and `tests scripts/mb_team_ops.py` return no tests, although bats files cover them through `mb-bank-lint.sh` / `mb-team.sh`; argparse-dispatched `cmd_*` functions have no incoming call edges, so `who-calls cmd_checkpoint` is empty. Agents that trust the graph get an incomplete test set.

**Files:** `memory_bank_skill/codegraph_invocations.py`, `memory_bank_skill/codegraph_python.py`, `memory_bank_skill/codegraph_shell.py`, `scripts/mb_graph_query_core.py`, `tests/pytest/test_codegraph_invocations.py`, `tests/pytest/test_graph_query_precision.py`, `tests/pytest/test_graph_test_mapping.py` (new)

**What to do:** link statically resolvable sh→py invocation edges (`python3 "$SCRIPT_DIR/x.py"`, `exec python3 …/x.py`) and bats→sh edges so `tests <py>` follows bats → sh → py; add argparse dispatch edges (`set_defaults(func=cmd_x)`, `{"name": cmd_x}` tables) as calls from the module's `main`; constant paths only, no evaluation; bump the parse-cache version.

**DoD:**
- [x] new tests red before, green after: `tests scripts/mb_bank_lint_backlog.py` lists tests/bats/test_mb_bank_lint.bats; `tests scripts/mb_team_ops.py` lists the team bats; `who-calls cmd_checkpoint` is non-empty; existing graph tests green
- [x] `/mb graph --apply` on this repo rebuilds without error and the three queries above answer on the real graph

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| Two tracks edit `commands/work.md` / `commands/mb.md` at once | H | strict order in § Tracks and waves; orchestrator checks `Files:` before each wave |
| Pre-commit hook runs the full battery on every wave commit | H | one commit per wave, run in the background |
| OpenSpec export overwrites someone's OpenSpec edits | M | dry-run default, hash-drift refusal, three-way conflict report, write guard on one change dir, round-trip golden test, external review |
| `commands/mb.md` split breaks clauses tests extract | M | tests recorded before, moved with paths in the same change; router-row test |
| Claude Code has no usable `SubagentStart` context | M | Stage 5 covers `/mb work`; the ad-hoc half is recorded, not faked |
| Green only on the working tree with other sessions' WIP | M | final check on a clean HEAD worktree (Stage 19) |
| S7/S8 shortcut hides a regression | L | Eval files run green on HEAD; the code has been live since July–August |

## Gate (plan success criterion)

Every listed track is closed: graph-semantic-adoption, mb-team, cursor-compatibility-remediation, codex-global-native-hooks, opus55-prompt-fit, openspec-adapter (now round-trip) in `plans/done/` or ticked; dynamic-flow 14/14; S4, S5, S7, S8 open DoD = 0 with validate rc=0; the Stage 7 demo shows `graph_share` > 0 for implementer and reviewer; full suite green or pre-existing failures logged; plan-verifier PASS.
