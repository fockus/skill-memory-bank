---
type: feature
topic: team-shared-gates
status: done
depends_on: []
parallel_safe: false
linked_specs: []
qa: off — skill-internal scripts and agent prompts; covered by pytest/bats, no live product
created: 2026-11-17
---
# Plan: feature — team-shared-gates

**Baseline commit:** 22f4c93d891bcdb12287a903f0bbd1052a1a335c

## Context

**Problem:** a real `/mb team` run (Go backend, 4 parallel tracks per wave) produced three failures:
A. copies instead of shared code (7× error mapper, 4× `stripMount`, one idempotency table per section) because
tracks may not touch each other's files and every verifier/reviewer sees only its own track diff;
B. code thresholds never enforced: no rules gate in the track flow, and `mb-rules-enforcer`/`plan-verifier` read
`<bank>/RULES.md` before the project's root `RULES.md`;
C. spec gaps passed verification: a REQ listed in `Covers:` but dropped from the task text was never checked
against code and tests; team tracks verify against their prompt, so nothing ran spec coverage.

**Expected result:** `/mb team` detects shared foundations before dispatch, tells tracks which shared mechanisms to
use, gives them an EXTRACT handover instead of copying, scans the wave for cross-track duplicates, gates every
commit on the project's lint-new command plus the deterministic rules checker, and verifies every REQ of every
team spec at wave end; plan-verifier checks each covered REQ against its own text.

**Related files:** `scripts/mb_team_{tracks,status,ops,render}.py`, `templates/team/*.md`,
`scripts/mb_pipeline_validate_team.py`, `references/pipeline.default.yaml`, `scripts/mb-rules-check.sh`,
`agents/{plan-verifier,mb-rules-enforcer,mb-reviewer,mb-reviewer-quality}.md`, `commands/team.md`.

---

## Stages

<!-- mb-stage:1 -->
### Stage 1: Shared-mechanisms registry, foundation detection, EXTRACT handover (items 1–3)

**Files:** `scripts/mb_team_shared.py` (new), `scripts/mb_team_tracks.py`, `scripts/mb_team_status.py`,
`scripts/mb_team_render.py`, `templates/team/track-prompt.md`, `tests/fixtures/team/golden/*`,
`tests/pytest/test_mb_team_shared.py` (new), `agents/mb-reviewer.md`, `agents/mb-reviewer-quality.md`

**What to do:**
- `<bank>/shared-mechanisms.md` table `| Mechanism | Home | Status | Keywords |` (status `exists|being-extracted`);
  parser + relevance match (name/keyword in the task text, or home under the track's globs).
- `track prompt` renders a "Shared mechanisms" section with the relevant rows ("use X from Y; do not copy").
- `plan` readiness: signals shared by ≥2 tracks (shared path segment `platform|shared|common|kit` in globs or task
  text, `<word> kit|boundary|client|registry` phrases, registry hits) and not resolved by a dependency on one of
  them, an `exists` registry row or `plan --accept-shared` → blocking `shared_foundation` + suggested foundation
  track; `next` answers `stop_human shared-foundation:<signal>` while a track of the group is still planned.
- Brief rule + track prompt: shared code in another track's zone → stop that part, post
  `HANDOVER · extract:<mechanism>`; `next` prints `extract <track> <mechanism>` for each open one.
- Reviewer rubric: a second copy of a registry mechanism outside its home is a blocker.

**Testing (TDD):** parser, relevance, signal extraction, resolution by deps/registry/accept, `next` stop and
extract action, prompt injection through the CLI.

**DoD:**
- [x] `plan --json` of a team whose tracks A and B both name `internal/platform/**` lists the signal under
  `ready.shared_foundation`; adding B `--deps A` clears it (test)
- [x] `next` prints `stop_human shared-foundation:<signal>` for that team and `dispatch` after `--accept-shared` (test)
- [x] the rendered prompt of a track whose task names a registry keyword contains "do not copy" and the home path (test)
- [x] an open `HANDOVER · A: extract:errmap` makes `next` print `extract A errmap` (test)

<!-- mb-stage:2 -->
### Stage 2: Cross-track duplication scan at `collect` (item 4)

**Files:** `scripts/mb_dup_scan.py` (new), `scripts/mb_team_ops.py`, `tests/pytest/test_mb_dup_scan.py` (new)

**What to do:** language-agnostic window hashing over the lines each track added since the team baseline
(`mb_vcs.sh diff`, untracked files whole); identifiers/strings/numbers normalised, trivial lines skipped; pairs
only across different tracks. `collect` prints `duplicate: A path:line ~ B path:line (N lines)` and adds
`duplicates` to `--json`.

**DoD:**
- [x] two tracks adding the same 8-line function under different names → one candidate pair; the same block twice
  inside one track → no pair (test)
- [x] `collect --json` in a git tree with that layout reports the pair (test)

<!-- mb-stage:3 -->
### Stage 3: Rules gate before `team commit`; project root RULES.md first (item 5a, 5b)

**Files:** `scripts/mb_team_gate.py` (new), `scripts/mb_team_ops.py`, `scripts/mb_pipeline_validate_team.py`,
`scripts/mb_team_config.py`, `references/pipeline.default.yaml`, `scripts/mb-rules-check.sh`,
`scripts/mb_rules_check_profile.sh`, `agents/mb-rules-enforcer.md`, `agents/plan-verifier.md`, tests

**What to do:**
- `team.rules_gate: "<command>"` (validated string). `team commit` runs it in the tree, then
  `mb-rules-check.sh --base <baseline>` on each selected track's owned files; a non-zero gate or any CRITICAL →
  that track goes to `fixing`, the commit is refused (exit 1) with the findings; nothing staged.
- `mb-rules-check.sh` JSON gains `rules_source`: `<project>/RULES.md` → `<bank>/RULES.md` → bundled; enforcer and
  plan-verifier read that file, project root first.

**DoD:**
- [x] commit with a failing `rules_gate` → exit 1, track status `fixing`, HEAD unchanged (test)
- [x] commit of a file this change pushed over 300 lines → refused with `solid/srp` (test)
- [x] passing gate → commit lands (existing commit tests stay green)
- [x] `mb-rules-check.sh` in a project with both root and bank RULES.md reports the root one (bats)

<!-- mb-stage:4 -->
### Stage 4: Whole-spec verification at wave end; REQ text check in plan-verifier (items 5c, 6)

**Files:** `scripts/mb_spec_coverage.py` (new), `scripts/mb_team_status.py`, `scripts/mb_team_tracks.py`,
`agents/plan-verifier.md`, tests

**What to do:**
- `mb_spec_coverage.py <spec-dir> [--tree D] [--json]`: every REQ with its text, covering tasks and test files
  naming it; status `tested|task-only|uncovered`; exit 1 on any gap.
- `next`: all tracks done and collected, the team has spec sources (`--plan` or track `--source` under `specs/`)
  and no spec check recorded since the last collect → `spec_verify <spec>`; `team spec-check <spec> --gaps N
  --report F` records it; gaps → `stop_human spec-gaps:<spec>` (orchestrator adds next-wave tracks or backlog).
- plan-verifier: for each REQ in a task's `Covers:` read the REQ's own text and acceptance; no code+test evidence
  → CRITICAL `REQ covered by task text only, no code/test evidence`; spec mode runs `mb_spec_coverage.py`.

**DoD:**
- [x] a spec whose REQ-002 is in `Covers:` but named by no test → `task-only`, exit 1 (test)
- [x] `next` prints `spec_verify <spec>` then, after a check with gaps, `stop_human spec-gaps:<spec>`; with 0 gaps
  → `stop_success` (test)
- [x] plan-verifier prompt states the CRITICAL rule and the spec-mode command (contract test)

<!-- mb-stage:6 -->
### Stage 6: Executable stage contracts — contract-first, minimal (item 7, added 2026-11-17 by the orchestrator session)

**Files:** `scripts/mb_contract.py` (new), `scripts/mb_team_{tracks,render,gate,plan}.py`, `templates/team/track-prompt.md`,
`agents/plan-verifier.md`, `commands/{contract,team}.md`, `tests/pytest/test_mb_contract.py` (new)

**What to do:** `<bank>/contracts/<id>.md` with `**Covers:**`, `## spec` (per REQ), `## rules`, `## dod`; items reuse
the task Eval anchor syntax (`exit:`, `output~:`) plus `output-empty`, or `manual: <reason>`. `mb_contract.py run`
(per-item JSON, covered REQ without an item = fail, drift after freeze = fail) and `freeze` (spec items must be red;
lock with hash + red evidence; `--amend --reason`). Team: `track add --contract`, dispatch refuses an unfrozen one,
prompt names the run command, commit gate runs it, `plan` warns standard+ tracks without one. plan-verifier runs it
first (Step 1.5) and has a `Mode: contract` to write one.

**DoD:**
- [x] `run` reports pass/fail/manual per item, exit 1 on a red item, a covered REQ without an item, or drift (tests)
- [x] `freeze` refuses when a spec item already passes; amend records the reason (tests)
- [x] dispatch refuses an unfrozen contract; commit with a red contract → track `fixing` (tests)
- [x] plan-verifier Step 1.5 runs the contract before the diff inspection (contract test)

<!-- mb-stage:5 -->
### Stage 5: Docs, changelog, full suite

**Files:** `commands/team.md`, `docs/pipeline-yaml.md`, `CHANGELOG.md`

**DoD:**
- [x] `commands/team.md` documents registry, `shared-foundation`, `extract`, `spec_verify`, `spec-check`,
  `rules_gate`, duplicate candidates; `docs/pipeline-yaml.md` documents `team.rules_gate`
- [x] CHANGELOG `[Unreleased]` entry
- [x] full suite (pytest + bats) green, ruff + shellcheck clean on changed files

**Code rules:** SOLID, DRY, KISS, YAGNI, Clean Architecture

---

## Risks and mitigation

| Risk | Probability | Mitigation |
|------|-------------|------------|
| foundation heuristic fires on unrelated tracks | M | bigram phrases only, dependency resolution, `--accept-shared` escape |
| `spec-gaps` blocks projects whose tests never name REQ ids | M | the script is the floor; the verifier judges code/test by REQ text and records `--gaps 0` when evidence exists |
| rules checker false CRITICAL (`tdd/delta`) blocks Go commits | M | Go `_test.go` already matches by stem; the gate prints findings and the user decides |
| file-size growth of `mb_team_status.py` / `mb_team_ops.py` past 300 lines | H | new logic lives in new modules; callers get a few lines |

## Gate (plan success criterion)

All five stages' DoD checked, full pytest + bats suite green, no file pushed over 300 lines by this change.
