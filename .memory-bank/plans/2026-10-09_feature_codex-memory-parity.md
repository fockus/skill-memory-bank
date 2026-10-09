---
type: feature
topic: codex-memory-parity
status: in_progress
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-10-09
---
# Plan: Codex memory and lifecycle completion

**Baseline commit:** b1bbbbf9a547a38fab02e8fbe30a3cbedd02820d

## Context

The owner approved all six follow-up items after the global-hook audit. The existing uncommitted global installation and resolver fixes are prerequisites and must be preserved. This plan completes model-free Codex conversation capture, child context, portable lifecycle behavior and graph precision, then verifies the complete integration.

**Run configuration:** Native Codex roles supply the actual model/effort for this run. An ephemeral pipeline overlay binds the project role names to those installed definitions, because the historical project pipeline contains Claude-only aliases. The project pipeline is preserved.

**Tier:** extra — durable user-memory writes and privacy boundaries. Use existing dependencies, TDD, task-scoped coverage, independent verification/review and a final judge. The Codex host model mapping is resolved per run; do not dispatch Claude-only aliases on Codex.

**Approved scope:** native hook trust/delivery verification, cross-chat conversation memory, subagent context, remaining portable lifecycle behavior, graph-query precision, final verification and publication preparation. No release, commit or push is implied. Optional embeddings and Codex cost accounting remain separate follow-ups as described to the owner.

**Coordination:** one owner per product file; preserve Pi work, the paused goal, all foreign bank changes and the existing work-state. Use a separate run slot for this plan.

## Stages

<!-- mb-stage:1 -->
### Stage 1: Durable model-free Codex session memory

**Role:** backend

**Files:** `hooks/mb-codex-session.py`, `hooks/lib/codex_session.py`, `tests/pytest/test_codex_session_capture.py`, `tests/pytest/test_codex_session_capture_replay.py`, `tests/pytest/test_codex_session_capture_security.py`

**What to do:**
- Implement bounded incremental ingestion of documented/observed Codex JSONL user and final assistant messages into an existing resolved bank. Reuse private-block and secret filtering; exclude tools, reasoning, developer instructions and child/inherited transcripts.
- Persist cursor and sanitized pending turn state atomically with the session record. Resume and duplicate events must not duplicate turns; malformed/partial records, unavailable transcripts and lock contention fail open without losing previously captured data.
- Produce honest extractive summaries consumable by the existing recent-session and recall paths. Honor capture opt-outs, update an existing recall index through its dirty marker, and never initialize a bank implicitly.

<!-- mb-stage:2 -->
### Stage 2: Preserve graph file identity

**Role:** debugger

**Files:** `scripts/mb_graph_query_core.py`, `memory_bank_skill/codegraph_python.py`, `memory_bank_skill/codegraph_invocations.py`, `tests/pytest/test_graph_query_precision.py`, `tests/pytest/test_codegraph_invocations.py`

**What to do:**
- Fix file-scoped matching once in the shared query path. Preserve qualified symbol identity; ambiguous bare symbols cannot establish a dependency on a particular file.
- Keep unqualified multi-definition queries and unambiguous legacy edges working. Code-context facts, impact and recommended tests must exclude unrelated duplicate symbols while retaining related callers/tests.
- Checkpoint extension: the real native test invokes the runner through subprocess, which the graph builder does not link. Add only statically resolvable Python-script invocation edges from constant argv/path chains; never evaluate source or infer dynamic targets. Verify with a tiny real builder/query fixture and bump its parse-cache version.

<!-- mb-stage:3 -->
### Stage 3: Native child context and bounded lifecycle wiring

**Role:** backend

**Blocked-by:** 1

**Files:** `hooks/mb-codex.py`, `hooks/lib/session-common.sh`, `hooks/tests/session-run-bounded.bats`, `hooks/tests/session-end-summary-v2.bats`, `adapters/codex-native-hooks.py`, `scripts/mb-freshness.sh`, `tests/pytest/test_codex_native_hooks.py`, `tests/pytest/test_codex_native_install.py`, `tests/pytest/test_codex_lifecycle_capture.py`, `adapters/codex.sh`

**What to do:**
- Wire session capture at safe root lifecycle points, including a bounded end fallback. Refresh recent-session retrieval and preserve existing flow/core guards and recursion protection.
- Register and implement SubagentStart context using event-correct additionalContext. Pass existing bank context and applicable rule pointers without initializing a bank or applying root closure to child completion.
- Add the portable Stop freshness reminder with correct context output. Use meaningful model-free session capture as end autosave; do not append a false summary-captured placeholder to progress.
- Keep the SessionEnd operation within the host three-second deadline; cap the whole operation, not merely each helper, and preserve opt-outs.

<!-- mb-stage:4 -->
### Stage 4: Native proof, review and documentation

**Role:** qa

**Blocked-by:** 1, 2, 3

**Files:** `references/codex-native-hooks.md`, `references/session-memory.md`, `references/privacy-and-capture.md`, `references/hosts.md`, `docs/cross-agent-setup.md`, `README.md`, `SKILL.md`, `commands/work.md`, `references/work-reference.md`, `tests/bats/test_mb_work_prod_binding_r3.bats`

**What to do:**
- Review exact Memory Bank hook definitions and use the supported Codex trust UI; preserve foreign definitions and approval policy. No trust bypass or direct trust-store edits. Verify actual hook delivery in an isolated project; if a platform/environment block prevents delivery, retain exact evidence and report the missing proof.
- Prove chat A capture and chat B recall, post-compaction restoration, child bootstrap and source-edit graph freshness with real components. Record metadata/effects only; never expose real conversation text or credentials in proof logs.
- Complete appropriate full-suite/static checks, triage failures against unchanged HEAD or explicit environmental limits, then run independent plan verification, review and judge. Update existing docs with the actual contract and remaining limits.

## Testing and DoD

TDD: add a failing behavior regression before each product change. Use isolated HOME/CODEX_HOME/project fixtures, real runner/shared helpers and tiny graph/transcript fixtures; mock only external boundaries. Measure coverage for new capture and changed matching/runner code using installed tools.

- [ ] Session capture persists sanitized user/final-answer memory exactly once across Stop repeats, resume, truncation/partial JSONL and lock contention; opt-outs and missing/mismatched/child transcripts never create a bank or expose secrets/private content.
- [ ] A decision captured from chat A is recalled in chat B without a manually written note; recorded state survives compaction.
- [ ] SubagentStart injects the correct existing bank and relevant rule pointers with native event output; child completion does not run root closure.
- [ ] Source edits refresh the next graph query, and file-scoped queries exclude unrelated duplicate main symbols/tests while preserving valid legacy edges.
- [ ] Stop capture/freshness and bounded SessionEnd autosave are wired; the complete end path respects the three-second host ceiling and opt-outs.
- [ ] Global installation/migration/uninstall preserves foreign settings and registers the required lifecycle events without duplicates; native discovery/trust and actual-delivery evidence are recorded separately.
- [ ] Targeted tests, task coverage and static checks pass; full-suite results, independent verifier/reviewer/judge decisions and any proven baseline/environment limits are recorded. No unrelated goal or gate is weakened.
- [ ] Existing skill/host/privacy docs accurately describe loading, capture, costs, child behavior and trust. Changes are reviewable without a release or remote write.

## Current verification evidence

- Capture: 32 tests pass, including red-first symlink/bounded-read/Unicode-cap repairs. Final security review APPROVED with no remaining issues. Stdlib trace measured 246/262 executable statements (93.9%).
- Graph: 113 affected tests pass; final narrow invocation tests 11 pass. Exact native-script test dependency is proved by a tiny real builder/query. Matcher line probe 147/167 (88.0%), static invocation helper 97/102 (95.1%). No source is evaluated. The real graph catchup preserved docs flags and refreshed to 11,097 nodes / 35,091 edges; the runner test query returns only native/lifecycle/bank-resolution suites.
- Lifecycle: 34 tests / 22 subtests pass after independent fallback and cumulative-deadline regressions. Installer/native migration tests pass; freshness 9 Bats and legacy honesty 3 Bats pass. Runner stdlib trace measures 184/197 executable statements (93.4%); all 34 instrumented tests pass. Test modules were split below 300 lines.
- Independent logic review APPROVED; its recap documentation boundary is now stated. Tests reviewer requested stronger lifecycle evidence; the repaired tests now have APPROVED re-review with no remaining issues. Both full runs completed; failures and focused repair evidence are classified below.
- Global registration now contains eight exact MB commands, including SubagentStart. The owner explicitly authorized trust of those eight commands. A fresh supported hooks/list response shows all eight user-scope MB definitions already trusted/enabled with no discovery errors; three foreign plugin hooks are preserved. No additional trust mutation, bypass or trust-store edit was needed. Actual event-delivery proof is complete: /private/tmp/mb-codex-native-proof-summary.json records all eight user-scope hooks with completed status, capture in chat A and independent recall in chat B, child context, source-edit file/log effects, two persisted completed contextCompaction turns and SessionEnd in 542 ms. Foreign plugin events are distinguished; normal permissions were preserved. No separate progress append is claimed.
- The historical Pi work-state was retained. A dedicated run slot codex-parity-20261009 took over only the stale generic plan-category claim (last updated 2026-10-05), without modifying the Pi state or source files. Effective native models are in an ephemeral overlay at /private/tmp/mb-codex-parity-run-fih_w4t7/pipeline.yaml.

## Risks and mitigation

| Risk | Mitigation |
|---|---|
| Private conversation content reaches durable memory | Reuse redaction/private filtering before persistence; same-line, nested/private, malformed and oversize tests |
| Capture cursor drift or duplicate resume data | Persist cursor/state and content atomically; verify replay/truncation and stable turn identity |
| Root state bleeds into a child or another project | Validate session metadata; resolve bank independently; explicit child context and closure separation |
| SessionEnd exceeds host deadline | Prefer Stop capture; bound the full fallback and test slow helper behavior |
| Query precision fix removes legitimate edges | Keep explicit symbol-query and unambiguous legacy fixtures alongside duplicate-name isolation tests |
| Native delivery cannot be reached in this environment | Supported UI/protocol only; distinguish helper proof from host proof, record the exact blocker |

## Gate

All scoped behavior has passing runnable evidence and independent review finds no unresolved blocking defect. Native execution is claimed only when the host delivered trusted hooks; otherwise that criterion remains explicitly open with environmental proof. The unrelated paused project goal is preserved and cannot be used to certify this plan accidentally.

**Full-run triage:** The legacy upgrade-equivalence fixture now explicitly verifies the original local hooks backup byte-for-byte and an empty migrated local registration, then excludes only those two verified migration artifacts; its focused test passes. Unchanged pre-compaction orphan and Go success/failure tests pass outside the restricted sandbox (three tests). The Pi global install focused test passes, closing the transient syntax observation from editing the installer during the original run. Agreement AGR-093 supersedes the obsolete Codex degradation clause of AGR-013 while preserving Pi/OpenCode opt-in behavior.

**Owner-requested work-command audit:** The parent read the full shared command and checked the helper interfaces. Claude Code frontmatter/Task examples remain intact; Codex dispatch is an explicit adapter over the same engine. Driver flags are separated from resolver output selectors, the selected cycle ceiling is passed to each init, fix cycles retain run_id, and declared Eval/checker evidence runs independently of verifier cadence. Judge-less complex workflows use the normalized reviewer severity/approval gate. Both extracted documented commands passed real red-to-green regressions; 309 documentation pytest and 57 Bats passed before the additional complex-gate correction. Hosted dry probes resolve identical medium steps and mb-backend for Claude Code (sonnet) and Codex (gpt-6.1-sol). AGR-094 records compatibility. Return annotations were added; capture_session now passes the annotation rule, while _capture_locked retains an advisory parameter-annotation warning. Scoped Ruff/compile checks pass.

**Repository closure remains separate:** The current firewall report (/tmp/mb-codex-parity-firewall.json) is red on two unchanged lint findings, 32 placeholder-pattern findings all byte-identical in HEAD, and the unrelated paused SVP goal acceptance. No rule, goal or gate was weakened.

**Completed current full pytest:** 4093 passed, 11 skipped, 9 failed, 22 subtests passed in 35m34s. Four changed/stale documentation findings were repaired: host-aware strict report delivery, native SessionEnd matrix contract, long-reference ToC, and Codex global prompt headroom. Their focused repair suite passed 51 tests; final installer/custom-CODEX_HOME/headroom suite passed 14 tests. Four unchanged Pi watcher/loopback tests passed outside the sandbox (4 in 8.05s). The remaining optional embedding-store failure already reproduced on an extracted HEAD snapshot. The completed full Bats result and its classified failures are recorded below; no blanket green is claimed.

**Shared-command audit baseline limit:** Both host probes reproduce init exit 4 for a second independent parallel plan stage, because unchanged helpers claim source categories rather than source/item identities. I-263 tracks the pre-existing optional parallel-run gap. The command now documents authoritative refusal and serial retry after the owner completes; it never overrides a live claim. Ordinary shared workflow and host dispatch remain compatible; no helper/state migration was introduced during the documentation audit.

**Completed full Bats and compatibility repair:** 4035 planned tests yielded 3968 passes, 18 skips, 49 failed cases plus a teardown guard failure. All 50 failed TAP records are classified in /private/tmp/mb-codex-full-bats-triage.json. Remaining unrelated Pi capture, four lexical recall/expand-ID edge-case fixtures and Pi static-source grep failures reproduce on extracted HEAD. The guard saw the authorized parent repo-hook migration during the long suite, not an attributed test write. A real baseline Claude defect found during this audit is now repaired: bounded background execution preserves stdin and terminates/reaps its timer; two new checks went red before the fix. The summary-v2 fixture now uses the established foreground guard for content assertions. All 41 bounded, summary, judge and detach checks pass; shell syntax, scoped lint and diff checks pass. Claude dispatch and localization remain unchanged.

**Final independent acceptance:** The final judge returned GO_WITH_BACKLOG, with zero blocking issues and acceptance_summary.dod_met/verification_passed true. Lead and tests reviews are APPROVED with zero unresolved findings; independent plan verification passes the scoped implementation. I-263 is registered in backlog as the sole non-blocking judge follow-up. All eight criteria have evidence above; formal completion checkboxes remain open because repository-wide closure is not certified. Premature evidence checkmarks were reset rather than being treated as deterministic completion.

**Closure hold and runtime cleanup:** The repository firewall remains red; neither /mb done nor mb-work-state done/checkbox flip was invoked to bypass it. The plan remains in_progress for formal closure. The owned temporary run codex-parity-20261009 is cleared through the official run-id-scoped helpers after preserving its pre-clear state in /private/tmp/mb-codex-parity-held-state.json, so it cannot block the next workflow. The historical Pi run is preserved. Implementation acceptance, completed test results, baseline limits and this formal hold are durable here and in progress.md; no commit, push or release was performed.
