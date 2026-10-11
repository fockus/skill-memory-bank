---
type: feature
topic: mb-team
status: in_progress
depends_on: []
parallel_safe: true
linked_specs: [specs/mb-team]
created: 2026-10-10
---
# Plan: `/mb team` — orchestrator-led parallel tracks

**Baseline commit:** f050443e9d7c70eadf78cc8f1f5b72e6b01888f8

## Context

**Problem:** The orchestrator process that delivered the harness on-prem release (goal with DoD, parallel role-agent
tracks, coordination only through the orchestrator, one branch with orchestrator commits and checkpoints, a shared build
lock with disk preconditions, lens review cycles) exists only as hand-written briefs and a project script
(`with-build-lock.sh`). The owner decided to make it a Memory Bank command (harness AGR-148).

**Expected result:** `/mb team` with layered track pipelines, rendered brief and track prompts, `mb-lock.sh` with a
fair queue and preconditions, a track-aware board, status, checkpoints and scoped commits for git and arc, team review
cycles with an external-reviewer prompt, and collection into `progress.md` and the goal — per `specs/mb-team/`
(requirements, design, examples).

**Tier and execution:** large (new subsystem). Executed by the same process it ships, by hand, because the command does
not exist yet (bootstrap, section Execution). Not through `/mb work` for the bootstrap: the engine flags it needs land
in Stage 6.

**Blocked on:** answers to Q1–Q4 in `specs/mb-team/design.md` §14. Q1 shapes Stage 3 presets, Q2 Stage 2 reclaim,
Q3 and Q4 Stage 6. The plan stays `draft` until they are answered.

**Scope limits:** no worktree mode, no push/PR, no change of default behaviour for projects without `/mb team`
(NFR-TEAM-001), no new dependency, no edits to files owned by the parallel done-gates session without a board
agreement (see Execution).

## Execution (bootstrap of the process)

- **Orchestrator:** the main Claude Code session. It writes the bank, the board and `.memory-bank/reports/mb-team-impl/`;
  it alone commits (scoped `git add`, Conventional Commits in English, AGR-085); push only after the owner's explicit yes.
- **Brief:** `.memory-bank/reports/mb-team-impl/brief.md`, written at start from `specs/mb-team/examples.md` §3: contracts
  C1–C6 of `design.md` §3 frozen as `FREEZE · contract:mb-team` on the board; rules of this repo (`.memory-bank/RULES.md`);
  English in the repo; targeted tests and lint per track, the full suite only by the orchestrator.
- **Track prompts:** short, link the brief, carry the stage below verbatim; reports at
  `.memory-bank/reports/mb-team-impl/<stage-id>.md` with a `STATUS:` first line and test output before/after.
- **Shared tree:** a parallel session (done-gates) holds uncommitted changes in `commands/mb.md`, `references/scripts.md`,
  `commands/done.md`, `scripts/mb-test-run.sh`, `scripts/_test_select.sh`, `scripts/mb-done-gates.sh`, hooks. Stages here
  do not edit them except T-DOCS (`commands/mb.md`, `references/scripts.md`), which first reads `mb-coord.sh active` and
  agrees the order on the board. Legacy FREEZE (adapter-parity, no rebase/reset/checkout) stays binding.
- **Checkpoints:** before wave 2 and before each commit: `git diff f050443 > …diff`, tar of untracked files of this plan,
  sha256 — under `.memory-bank/backups/mb-team/` (git-ignored check first).
- **Track pipelines (per design §4, Q1 option A):** small → direct, TDD, no verifier; standard → direct, TDD,
  plan-verifier; large → direct, TDD, plan-verifier, one reviewer on opus. Executors: opus for large, sonnet otherwise.
- **Team review:** Stage 12, five lenses on opus + lead, cycles until no blocker/major/medium; Codex as the external
  reviewer (AGR-086), launched by the owner from the rendered prompt.

## Waves

| Wave | Stages (parallel inside a wave, disjoint files) | Needs |
|---|---|---|
| 1 | 1 T-GUARD · 2 T-LOCK · 3 T-CFG · 4 T-COORD · 5 T-VCS · 6 T-ENGINE · 7 T-RENDER | contracts C1–C6 frozen; Q1–Q4 answered |
| 2 | 8 T-STATE · 9 T-REVIEW | wave 1 green |
| 3 | 10 T-DOCS | wave 2 green |
| 4 | 11 T-WIRE | Stage 10 done |
| 5 | 12 team review | all stages done |

`mb-work-plan.sh --target <this plan> --dry-run` computes the same waves from the `**Files:**` and `**Blocked-by:**` lines.

Estimates are in LLM-pipeline hours (track wall time, review excluded).

## Stages

<!-- mb-stage:1 -->
### Stage 1: T-GUARD — no nested bank from inside a bank

**Role:** debugger
**Size:** small · **Estimate:** 0.5 h

**Files:** `scripts/_lib.sh` (function `mb_resolve_path` only), `tests/bats/test_mb_resolve_nested_bank.bats`

**What to do:** in the fallback branch of `mb_resolve_path`, when the current directory is itself a bank (basename
`.memory-bank` and a core file present), return it instead of the relative `.memory-bank`. Root cause of the harness
lesson (a run from `.memory-bank/` created `.memory-bank/.memory-bank/`); fixes every caller at once (REQ-TEAM-005).

**DoD:**
- [x] A bats case runs `mb-coord.sh append` and `mb-work-progress-append.sh` with cwd = a fixture bank and asserts no
  `.memory-bank/.memory-bank` appears and the entry lands in the fixture bank; it fails before the change.
- [x] `bats tests/bats/test_lib.bats tests/bats/test_mb_storage_resolver.bats tests/bats/test_mb_resolve_nested_bank.bats` green; `shellcheck -x scripts/_lib.sh` adds no warning.

<!-- mb-stage:2 -->
### Stage 2: T-LOCK — `mb-lock.sh` with a fair queue

**Role:** backend
**Size:** large · **Estimate:** 3 h

**Files:** `scripts/mb-lock.sh`, `scripts/mb_lock_queue.py`, `tests/bats/test_mb_lock_resource.bats`, `tests/pytest/test_mb_lock_queue.py`

**What to do:** design §5 and contracts C3/C4: `acquire|release|status|run|watch|break|maint`; ticket queue with
process-start liveness; preconditions, maintenance under the own lock, stop threshold watchdog; exit codes 75/76/77.
Reads resources through `mb_team_config.py resource` (C3) or `--resource-json`; tests use `--resource-json` only.
Board posts go through `mb-coord.sh append --type BLOCKED --track` (C5); tests assert the call through a PATH shim.
Reuse `mb_pid_alive` and `mb_lock_acquire` from `_lib.sh` without editing `_lib.sh`. Reclaim per the Q2 answer.

**DoD:**
- [x] Three background waiters on one resource acquire in ticket order in 10/10 repeated runs; the test finishes in under 60 s.
- [x] A waiter killed while queued leaves no ticket; a dead ticket is skipped; a wrapper killed with SIGKILL while its child runs keeps the lock until the child exits.
- [x] A lock held by another live process is never removed by `run`, `acquire` or `break`; `break` on a dead holder posts a board entry.
- [x] Exit 77 when preconditions fail after maintenance (command not run); exit 76 and a terminated child when the stop check trips mid-run; exit 75 on `--wait` expiry.
- [x] Maintenance never runs without the caller holding the lock (bats case through `maint` with a foreign token).
- [x] `status --json` matches C4 (pytest schema check); free disk parsed from `df -Pk` output fixtures for macOS and Linux.
- [x] `bats tests/bats/test_mb_lock_resource.bats` and `pytest tests/pytest/test_mb_lock_queue.py` green; `shellcheck -x scripts/mb-lock.sh` and `ruff check scripts/mb_lock_queue.py` clean; both files under 300 lines.

<!-- mb-stage:3 -->
### Stage 3: T-CFG — `team:` schema and layered pipeline resolver

**Role:** backend
**Size:** large · **Estimate:** 2.5 h

**Files:** `references/pipeline.default.yaml`, `scripts/mb_pipeline_minimal_yaml.py`, `scripts/mb_pipeline_validate_team.py`, `scripts/mb_pipeline_validate_core.py`, `scripts/mb_team_config.py`, `scripts/mb_team_pipeline.py`, `tests/pytest/test_mb_team_pipeline.py`, `tests/pytest/test_mb_team_config.py`, `tests/pytest/test_pipeline_default_yaml.py`

**What to do:** bundled `team:` block (presets by size per the Q1 answer, team review defaults with `enabled: false`, no resources); `team` in the
stdlib parser's block list; a validator module for keys, enums, lens names, resource fields; `mb_team_config.py`
(C3 + presets); `mb_team_pipeline.py resolve` (C2) reusing `mb_work_models.resolve_model` for slots → host models.

**DoD:**
- [x] A layer-matrix test covers every key: preset → overrides → team attr → track attr → prompt, with provenance per key.
- [x] Unknown key, unknown value, unknown lens, `mode: work` without source, nested inline map in `team:` → exit 2 naming the field.
- [x] The same `team:` fixture yields identical dicts and identical errors with and without PyYAML.
- [x] A project without `team:` validates byte-identically to before (existing validator tests unchanged and green).
- [x] `mb_team_config.py resource build --json` on `examples.md` §1 prints exactly the C3 JSON of `examples.md` §2 (path aside).
- [x] `pytest tests/pytest/test_mb_team_pipeline.py tests/pytest/test_mb_team_config.py tests/pytest/test_pipeline_default_yaml.py tests/pytest/test_mb_pipeline_validate.py` green; ruff clean; every new file under 300 lines.

<!-- mb-stage:4 -->
### Stage 4: T-COORD — track-aware board

**Role:** backend
**Size:** standard · **Estimate:** 1 h

**Files:** `scripts/mb-coord.sh`, `references/coordination.md`, `tests/bats/test_mb_coord.bats`, `tests/pytest/test_mb_coord_docs.py`

**What to do:** C5 — `BLOCKED` (cancelled by ACK), `COMMIT`, `--track <id>`, `tracks --json`; `active` lists open BLOCKED.

**DoD:**
- [x] bats: BLOCKED shown until an ACK with the same scope; `--track D3` writes `D3: <title>`; invalid track id → exit 1; `tracks --json` matches C5 on a fixture with legacy entries, which stay STATUS and are not attributed.
- [x] Existing `test_mb_coord.bats` cases unchanged and green; `shellcheck -x scripts/mb-coord.sh` clean; the reference table lists the two new types.

<!-- mb-stage:5 -->
### Stage 5: T-VCS — VCS seam and checkpoints

**Role:** devops
**Size:** standard · **Estimate:** 1.5 h

**Files:** `scripts/mb_vcs.sh`, `scripts/mb-team-checkpoint.sh`, `tests/bats/test_mb_vcs.bats`, `tests/bats/test_mb_team_checkpoint.bats`, `tests/fixtures/arc-shim/arc`

**What to do:** C6 ops for git and arc; checkpoint create/verify per design §7 with explicit `--tree --baseline --topic
--dir` flags (the dispatcher passes them in Stage 8). Probe every arc op against the real `arc` on this machine once and
paste the outputs in the report; CI uses the shim.

**DoD:**
- [x] Git fixture: checkpoint writes diff, untracked tar, manifest and sha256; `--verify` passes, then fails after one byte of the tar changes.
- [x] An untracked file over `max_untracked_mb` is listed in `skipped_large` and absent from the tar; ignored files never enter the tar.
- [x] The arc shim run produces the same manifest fields; a directory outside any tree → exit 2.
- [x] Hashes use Python hashlib (no `sha256sum`/`shasum` dependency); `bats tests/bats/test_mb_vcs.bats tests/bats/test_mb_team_checkpoint.bats` green; shellcheck clean.

<!-- mb-stage:6 -->
### Stage 6: T-ENGINE — `/mb work` hooks for work-mode tracks (and `medium` if Q3 = A)

**Role:** backend
**Size:** large · **Estimate:** 2 h

**Files:** `scripts/mb-workflow.sh`, `scripts/mb-work-plan.sh`, `scripts/mb_work_models.py`, `commands/work.md` (§5d, one sentence), `scripts/mb-work-review-parse.sh`, `scripts/mb-work-severity-gate.sh`, `agents/mb-reviewer-lead.md`, `tests/bats/test_mb_workflow_lenses.bats`, `tests/pytest/test_mb_work_step_models.py`, `tests/bats/test_mb_work_severity_medium.bats`

**What to do:** `mb-workflow.sh --lenses <csv>` → JSON `review_lenses` (validated against `review_ensemble`);
`mb-work-plan.sh --step-model role=model` → `step_models`; §5d dispatches only `review_lenses` when present. If Q3 = A:
optional `medium` severity in parser, gate (absent limit = 0, absent count = 0) and lead schema. Scope depends on Q4.

**DoD:**
- [x] Without the new flags, `mb-workflow.sh --json` and `mb-work-plan.sh` output are byte-identical to the baseline on the existing fixtures (golden comparison).
- [x] `--lenses logic,security` yields exactly those two; an unknown lens → exit 2.
- [x] `--step-model reviewer=opus` overrides only the reviewer step model; invalid role → exit 2.
- [x] (Q3 = A) a report with one medium fails a gate `{medium: 0}` and passes the default gate of an existing pipeline.
- [x] `test_mb_work_command_doc.bats` and the new tests green; shellcheck and ruff clean.

<!-- mb-stage:7 -->
### Stage 7: T-RENDER — brief and track prompt templates

**Role:** backend
**Size:** standard · **Estimate:** 1.5 h

**Files:** `templates/team/brief.md`, `templates/team/track-prompt.md`, `scripts/mb_team_render.py`, `tests/pytest/test_mb_team_render.py`, `tests/fixtures/team/team.json`

**What to do:** render from C1/C2 fixtures to the shape of `examples.md` §3–§4: absolute paths, `--mb`, TDD and pipeline
in words, resource commands per used resource, known-red, report contract; the track prompt is a one-stage plan
(a single stage marker around task and DoD). Fill-in hints use one marker grammar; `unfilled(path)` reports them (REQ-TEAM-033).

**DoD:**
- [x] Golden tests for the brief and two track prompts (direct small, direct large with review) from the fixture.
- [x] Every path in the output is absolute; every Memory Bank command carries `--mb`; no hint marker remains except in the scaffold-only sections, and `unfilled()` finds them.
- [x] The rendered track prompt passes `mb-work-plan.sh --target <prompt> --dry-run` as a one-stage plan (or the report records why not and the fallback).
- [x] `pytest tests/pytest/test_mb_team_render.py` green; ruff clean; files under 300 lines.

<!-- mb-stage:8 -->
### Stage 8: T-STATE — `mb-team.sh`, state, `next`, status, collect, commit

**Role:** backend
**Size:** large · **Estimate:** 3.5 h
**Blocked-by:** 2, 3, 4, 5, 7

**Files:** `scripts/mb-team.sh`, `scripts/mb_team_state.py`, `scripts/mb_team_status.py`, `scripts/mb_team_ops.py`, `tests/pytest/test_mb_team_state.py`, `tests/bats/test_mb_team_cli.bats`, `tests/bats/test_mb_team_commit.bats`

**What to do:** C1 writer (lock + atomic replace), `init` (goal check, contract FREEZE), `track add/set`, `plan`,
`prompt`, `next` (design §9), `status` (C4 + C5 + reports + goal), `collect`, `commit` (through `mb_vcs.sh`), `known-red`,
`close`. Refuse cwd inside a bank. Budget through `mb-work-budget.sh` with `team-<topic>` run id.

**DoD:**
- [x] `next` fixtures: deps, glob overlap, `max_parallel`, blocked track → `stop_human`, unfilled brief → `stop_human`, `stop_success` only when all four REQ-TEAM-081 conditions hold.
- [x] `collect` appends exactly one progress entry per newly returned track via `mb-work-progress-append.sh`; a second run appends nothing.
- [x] `commit` stages only owned changed files, lists foreign ones, refuses a co-owned file and an unfinished track, writes a COMMIT board entry, and never calls push (shim asserts); without `--yes` and without a TTY it does nothing.
- [x] `status --json` on a fixture with a held lock, a queued waiter and an open BLOCKED reports all three.
- [x] Two concurrent `track set` calls never lose an update (pytest with processes).
- [x] The listed tests green; shellcheck and ruff clean; every file under 300 lines.

<!-- mb-stage:9 -->
### Stage 9: T-REVIEW — team review cycles and external reviewer

**Role:** backend
**Size:** standard · **Estimate:** 1.5 h
**Blocked-by:** 3, 6, 7

**Files:** `scripts/mb-team-review.sh`, `templates/team/external-review.md`, `tests/bats/test_mb_team_review.bats`

**What to do:** design §8 — `start` (cycle dir + review brief), `gate` (C1 counts vs `clean_when`, issues grouped by
owner track), `external` (prompt from the template, `examples.md` §7), `ingest` (schema check of `findings.json` and
`prior-closure.json`). Reuses `mb-work-review-parse.sh` and `mb-work-severity-gate.sh`.

**DoD:**
- [x] `gate` returns 0 on a clean master, 1 with owner-grouped fixes on a dirty one, 2 on malformed JSON; `max_cycles` reached → `stop_human review-cycles` in `next`.
- [x] The external prompt names the commit, the read-from-commit rule, the known open items and both output schemas; `ingest` rejects a finding without file/line/severity.
- [x] Tests green; shellcheck clean.

<!-- mb-stage:10 -->
### Stage 10: T-DOCS — command contract and docs

**Role:** developer
**Size:** standard · **Estimate:** 1.5 h
**Blocked-by:** 8, 9

**Files:** `commands/team.md`, `commands/mb.md` (one router row), `SKILL.md` (index + count), `README.md` (count), `install.sh` (header count comment only), `docs/pipeline-yaml.md` (`team:` section), `references/scripts.md` (rows), `CHANGELOG.md` (two lines), `tests/pytest/test_mb_team_command.py`

**What to do:** `commands/team.md` per `references/command-template.md`: subcommands and attributes (design §10), the
orchestrator loop over `next`, the prompt vocabulary (design §4), host dispatch notes (Claude Code, Codex, Pi), the
safety rules (REQ-TEAM-090..092). Board check before touching `commands/mb.md` and `references/scripts.md`.

**DoD:**
- [x] `commands/team.md` under 400 lines; its documented bash blocks run from a project path with spaces (pattern of `test_audit_command_contracts.py`).
- [x] `pytest tests/pytest/test_doc_counts.py tests/pytest/test_command_descriptions.py tests/pytest/test_mb_team_command.py tests/pytest/test_skill_guide_compliance.py` green with the new count.
- [x] `bash scripts/mb-drift.sh .` reports `drift_warnings=0`.

<!-- mb-stage:11 -->
### Stage 11: T-WIRE — install, e2e, full suite

**Role:** qa
**Size:** standard · **Estimate:** 1.5 h
**Blocked-by:** 10

**Files:** `tests/e2e/test_mb_team_e2e.bats`, installer manifest tests only if new paths need registration

**What to do:** confirm `install.sh` ships `templates/team/` and the new scripts (manifest test), then one end-to-end
run without model calls: init → two tracks → `next` → simulated returns → collect → checkpoint → commit (git) → status.
The orchestrator runs the full suite once.

**DoD:**
- [x] The e2e test passes in a temp project with spaces in its path.
- [x] A fresh install into a temp HOME contains `scripts/mb-team.sh`, `scripts/mb-lock.sh` and `templates/team/*.md`; uninstall removes them.
- [x] Full suite `PATH="$PWD/.venv/bin:$PATH" bash scripts/mb-test-run.sh --dir . --out json` green, or each failure classified as pre-existing with evidence from the baseline run.

<!-- mb-stage:12 -->
### Stage 12: Team review until clean

**Role:** reviewer_lead (run by the orchestrator: five lens reviewers + `mb-reviewer-lead`)
**Estimate:** 2–4 h
**Blocked-by:** 11

**What to do:** lens review of `git diff f050443` limited to this plan's files; lead closure check each cycle; fixes
routed to stage owners; Codex external review from the rendered prompt when the owner launches it.

**DoD:**
- [ ] The last `master.json` has 0 blocker, 0 major, 0 medium; earlier issues marked resolved by the lead.
- [ ] `/mb verify` against this plan passes; the owner reviews the diff before any commit beyond the local branch.

## Risks and mitigation

| Risk | P | Mitigation |
|---|---|---|
| Contract drift between parallel stages | M | C1–C6 frozen on the board; change only by HANDOVER + orchestrator decision |
| Collision with the parallel done-gates session | M | disjoint files; board check before `commands/mb.md` / `references/scripts.md`; scoped staging |
| FIFO test flakes under load | M | condition-based waiting, generous timeout, 10 repeated runs in DoD |
| Track prompt not accepted by `plan-verifier` / `mb-review.sh` | M | Stage 8 DoD checks it; documented fallback payload |
| Real arc differs from the shim | M | Stage 5 probes real arc and records outputs |

## Gate

Done when stages 1–11 meet their DoD, the team review is clean (Stage 12), `/mb verify` passes, and the owner has
seen the diff. Commit and push follow the owner's decision.
