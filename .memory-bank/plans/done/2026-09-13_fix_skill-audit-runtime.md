---
type: fix
topic: skill-audit-runtime
status: done
depends_on: [skill-audit-data-safety]
parallel_safe: false
linked_specs: []
created: 2026-09-13
---
# Sprint 2 — Skill audit: runtime and command contracts

**Baseline commit:** f3e23f1c18033e40b0d584d26a7b64bd96dc9422

## Context

User requested fixes for all 15 findings in [audit](../../reports/2026-09-13_skill-audit.md). Preserve existing uncommitted bank changes. No real client install/uninstall, new dependencies, CI changes, commits or publishing. Use temp fixtures and subprocess-scoped HOME. Native Codex agents execute the resolved execution workflow; unavailable Opus model preference is not silently written back to pipeline.yaml.

**Coordination:** see ../../COORDINATION.md, scope skill-audit-remediation. One owner per source file; orchestrator owns all bank state and checkboxes. No destructive git actions. Tests first; record RED and GREEN commands. Run focused tests per fix and one broader regression after integration. Failures existing before our source changes are recorded separately and never reported as green.

## Stages

<!-- mb-stage:1 -->
### Stage 1: Source-bound completion and cwd-independent done gates
**Role:** backend
**Covers:** R03, R04
**Files:** scripts/mb-work-checkbox.sh, scripts/mb-work-state.sh, scripts/mb-work-state-lib.sh, scripts/mb_work_source.py, scripts/mb-done-gates.sh, tests/pytest/test_audit_completion.py, existing checkbox/done tests where legacy fixture bindings must be made honest. Independent review required canonical binding at init and a shared declaration resolver to prevent cwd-dependent legacy bypasses.
**Contract:** a done state certifies only its canonical source plus item; explicit --dir produces the same rules verdict from any cwd, including spaces.
**Testing (TDD):** A Task1 done cannot flip B Task1 with unexecuted Eval; same-source flip remains valid; legacy unbound state fails with diagnostic; real target TODO found both inside/outside cwd.
**DoD:**
- [x] Cross-spec and cwd regressions observed RED then GREEN.
- [x] Correctly bound plan/spec flips remain idempotent; invalid or ambiguous bindings refuse.
- [x] Work-state/eval-proof/checkbox/done focused suites and shellcheck pass.

<!-- mb-stage:2 -->
### Stage 2: Resume drive state and select first actionable item
**Role:** backend
**Covers:** R05, R10
**Files:** commands/drive.md, scripts/mb-drive.sh; a bounded existing/new drive preflight helper if needed; tests/pytest/test_audit_drive.py and existing drive Bats contracts.
**Contract:** resume with same run retains cycle/steps/limits; new valid pending goal selects implement of concrete next item; genuine failed current item selects repair; stop_success still requires full green firewall and complete acceptance.
**Testing (TDD):** execute exact preflight fence twice with cycle=2,max=3; verify limit is retained; integrate default firewall and pending goal without green stub; retain red current-item and broken-check fail-closed tests.
**DoD:**
- [x] R05/R10 regressions observed RED then GREEN with real helpers.
- [x] Resume keeps state, first step is concrete implement, failed current work repairs.
- [x] Full completion firewall cannot be bypassed; focused drive/goal/flow tests pass.

<!-- mb-stage:3 -->
### Stage 3: Keep structural source matches in bounded code context
**Role:** developer
**Covers:** R09
**Files:** scripts/mb_code_context_core.py, tests/pytest/test_code_context.py.
**Contract:** exact source definition remains recommended even with >=10 memory/archive mentions; result bounds and protected-file filtering remain enforced.
**Testing (TDD):** exact graph symbol behind ten notes; mixed docs/source noise; absent graph fallback; semantic candidates remain respected.
**DoD:**
- [x] Starvation regression fails before fix and passes after; recommended reads include source.
- [x] Existing context contracts and relevant Ruff checks pass; output bounds preserved.

<!-- mb-stage:4 -->
### Stage 4: Executable global-bank/session/verify instructions
**Role:** developer
**Covers:** R11, R14, R15
**Files:** commands/start.md, commands/done.md, commands/mb.md, agents/plan-verifier.md; tests/pytest/test_audit_command_contracts.py and existing runtime documentation contracts. The verifier prompt is part of R15: it must interpret spec tasks and the resolved global bank supplied by the caller.
**Contract:** commands use resolved bank and installed skill root from a project cwd; final verify resolves current explicit plan/spec rather than newest unrelated plan.
**Testing (TDD):** execute command setup/fences in temp project with global-only bank; conflicts snippet resolves actual script; spec-only final target; unrelated newer plan cannot win over explicit/current source.
**DoD:**
- [x] R11/R14 executable regressions and R15 routing contract checks observed RED then GREEN.
- [x] No hardcoded local bank overrides in affected actions; spec-only verify explicitly supported.
- [x] Relevant documentation/registration tests pass; full selected regression run and limitations recorded.

## Risks and mitigation
- Legacy work state lacks identity: refuse ambiguous certification and provide re-init hint, retain resolvable legacy paths.
- Drive firewall conflates final acceptance with current-step checks: separate decision signal from final success check; preserve stop_success requirements.
- Instruction tests can assert words only: execute bounded shell snippets and real target resolvers.
- Shared commands file: orchestrator owns commands/start.md,done.md,mb.md; drive owner edits drive.md only.

## Gate
All 15 audit findings mapped to passing regressions or verified instruction contracts; independent plan-verifier checks plan vs diff vs checklist; targeted and broader regression outcomes reported honestly, with preexisting failures separated. No release/install/commit implied.

## Verification evidence — 2026-09-14

- All 6 stages across the two audit plans independently reviewed: PASS after correcting residual cwd/legacy/symlink identity, qualified method discovery, and installed prompt-path defects.
- Final full pytest: **2614 passed, 1 skipped in 578.09s**, exit 0. First integration pass found two metadata/fixture issues (missing helper registration and v1 naming); both fixed, their 37-test subset passed before this clean full run.
- Related Bats passed: drive 217 + 1 timeout-tool skip; completion/state/eval/done 92; command agreements docs 17. Data-safety Bats and tests are recorded in the closed Sprint 1 plan. Final source-specific subsets and Ruff/ShellCheck also passed.
- Final wheel/sdist built successfully with all added modules. A separately installed temp wheel passed real index/private-search and source-bound work-state/checkbox smoke tests.
- Plan stages carry no spec Eval declarations: meaningful RED→GREEN evidence comes from pytest/Bats; no synthetic Eval proof was written into state.
- Full result matrix and limits: [audit remediation report](../../reports/2026-09-14_skill-audit-remediation.md). G-001 remains paused; unrelated backlog and existing size debt were not declared fixed.
