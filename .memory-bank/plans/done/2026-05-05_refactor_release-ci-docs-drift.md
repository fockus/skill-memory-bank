---
status: completed-local
type: refactor
created: 2026-05-05
---

# refactor — release-ci-docs-drift

**Type:** refactor
**Date:** 2026-05-05
**Baseline commit:** fd9625621388fc6ecd0b0978fcc7e2c8ca4ef999
**Status:** completed locally

## Context

The repository has release and CI drift after the v4.0.0 source line:

- `VERSION` says `4.0.0`, but `memory_bank_skill.__version__` and PyPI still report `3.1.2`.
- Latest GitHub Actions `test.yml` runs are failing.
- README claims a green full test envelope that is not currently true.
- Bats fixtures still assert legacy uppercase Memory Bank files while the canonical v3.1 layout is lowercase `status.md`, `roadmap.md`, `checklist.md`, `backlog.md`, `research.md`, `progress.md`, `lessons.md`.

## Decision

Prepare a PR-ready patch line `4.0.1`. Do not move the existing `v4.0.0` tag and do not publish PyPI/Homebrew/GitHub releases in this work.

## Stages

<!-- mb-stage:1 -->
### Stage 1: Persist plan and version boundary

- [ ] Add this active plan to Memory Bank and sync roadmap/status/checklist.
- [ ] Set source version files to `4.0.1`.
- [ ] Update README/CHANGELOG/release docs so PyPI publication is described as pending and PyPI latest remains `3.1.2` until a separate release step.

**DoD:** version commands agree locally; docs no longer claim published PyPI `4.x`.

<!-- mb-stage:2 -->
### Stage 2: Restore shell and Bats contracts

- [ ] Fix `shellcheck SC2016` in `scripts/mb-drift.sh`.
- [ ] Fix real script bugs in `mb-compact.sh`, `mb-context.sh`, `mb-drift.sh`, and `mb-config.sh`.
- [ ] Update Bats fixtures that still expect uppercase legacy core files to the canonical lowercase layout.

**DoD:** targeted Bats files and shellcheck pass.

<!-- mb-stage:3 -->
### Stage 3: Normalize docs and security closeout

- [ ] Make README, SKILL, structure/migration/command docs consistently describe lowercase canonical core files.
- [ ] Mention uppercase names only as legacy migration/backward-compat inputs.
- [ ] Add a security audit closeout matrix for High/Medium findings.

**DoD:** repo docs no longer mix `STATUS.md/plan.md` as current targets with `status.md/roadmap.md`.

<!-- mb-stage:4 -->
### Stage 4: Full verification and Memory Bank actualization

- [ ] Run targeted checks from the plan.
- [ ] Run full Bats, pytest coverage, shellcheck, and ruff regression.
- [ ] Update Memory Bank checklist/progress/status only after verification.

**DoD:** all local checks pass; Memory Bank records the verified outcome.

## Verification Plan

- `shellcheck -x --source-path=SCRIPTDIR scripts/*.sh hooks/*.sh`
- `bats tests/bats/test_compact.bats`
- `bats tests/bats/test_context_integration.bats`
- `bats tests/bats/test_drift.bats`
- `bats tests/bats/test_manager_existing_actions.bats`
- `bats tests/bats/test_mb_config.bats`
- `bats tests/bats/test_mb_init_bank.bats`
- `python -m pytest tests/pytest/test_phase4_sprint3_registration.py tests/pytest/test_status_drift.py -q`
- `bats tests/bats/`
- `bats tests/e2e/`
- `python -m pytest tests/pytest/ --cov --cov-report=term-missing --cov-fail-under=85`
- `ruff check settings/ tests/pytest/`

## Verified Outcome — 2026-05-05

- `shellcheck -x --source-path=SCRIPTDIR scripts/*.sh hooks/*.sh` — pass.
- Targeted Bats files — pass, 81 tests.
- `bats tests/bats/` — pass, 545 tests.
- `bats tests/e2e/` — pass, 75 tests.
- `python -m pytest tests/pytest/ --cov --cov-report=term-missing --cov-fail-under=85` — pass, 651 passed / 14 skipped, 92.33% coverage.
- `ruff check settings/ tests/pytest/` — pass.
- `VERSION`, `memory_bank_skill.__version__`, and repository-local CLI (`python -m memory_bank_skill --version`) agree on `4.0.1`.
- Global installed `memory-bank` on this workstation still reports an older package because publish/reinstall was intentionally out of scope for this PR-ready step.
- GitHub Actions verification remains the external post-push gate.
