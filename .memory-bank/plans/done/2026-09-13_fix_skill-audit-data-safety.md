---
type: fix
topic: skill-audit-data-safety
status: done
depends_on: []
parallel_safe: false
linked_specs: []
created: 2026-09-13
---
# Sprint 1 — Skill audit: data safety

**Baseline commit:** f3e23f1c18033e40b0d584d26a7b64bd96dc9422

## Context

User requested fixes for all 15 findings in [audit](../../reports/2026-09-13_skill-audit.md). Preserve existing uncommitted bank changes. No real client install/uninstall, new dependencies, CI changes, commits or publishing. Use temp fixtures and subprocess-scoped HOME. Native Codex agents execute the resolved execution workflow; unavailable Opus model preference is not silently written back to pipeline.yaml.

**Coordination:** see ../../COORDINATION.md, scope skill-audit-remediation. One owner per source file; orchestrator owns all bank state and checkboxes. No destructive git actions. Tests first; record RED and GREEN commands. Run focused tests per fix and one broader regression after integration. Failures existing before our source changes are recorded separately and never reported as green.

## Stages

<!-- mb-stage:1 -->
### Stage 1: Install/uninstall roundtrip and explicit init target
**Role:** devops
**Covers:** R01, R02, R12, R13
**Files:** install.sh, uninstall.sh, scripts/mb-init-bank.sh; isolated regression tests in tests/pytest/test_audit_install_roundtrip.py and existing related installer tests if fixture compatibility needs updating.
**Contract:** original Pi settings and RULES survive install → reinstall → uninstall; cleanup completes when invoked from canonical bundle; both project-root argument forms select the same target and invalid args fail before mutation.
**Implementation:** preserve merge-managed Pi settings and remove only MB entry; carry live backup metadata across idempotent installs; retain uninstall helpers/manifest until cleanup completes; parse init flags with explicit value consumption.
**Testing (TDD):** first write end-to-end temp-home tests for preexisting theme/packages/skills, repeated install backup restoration, canonical bundle cleanup, and init from different cwd (including spaces). Run each failing case before its source fix, then existing installer/storage tests.
**DoD:**
- [x] R01/R02/R12/R13 regressions fail on baseline and pass after changes; no real user settings touched.
- [x] Existing focused install/storage tests pass; shellcheck reports no new errors.
- [x] No dropped custom settings, stale MB project adapters, or orphaned original backup mapping in tested roundtrips.

<!-- mb-stage:2 -->
### Stage 2: Consistent private-span handling in search/index
**Role:** developer
**Covers:** R06, R07, R08
**Files:** scripts/mb-search.sh, scripts/mb-index-json.py; small shared pure sanitizer if useful; tests/pytest/test_audit_privacy.py plus existing privacy/tag/index tests.
**Contract:** closed private spans redact all nested markup; an unclosed span extends only from its actual opener to EOF; public content after a closed span stays searchable; private lessons are excluded before extraction.
**Implementation:** use a shared private-span parser or existing equivalent to avoid incompatible tag/freetext/index logic; keep show-private double opt-in and archive behavior.
**Testing (TDD):** synthetic nested angle-bracket email, multiple inline spans, multiline/unclosed spans, public suffix, private lesson headings and entire records; public counterpart assertions verify no over-redaction. Existing index/private/tag/archive tests must stay green.
**DoD:**
- [x] R06/R07/R08 negative and positive regressions fail before source fixes and pass after.
- [x] No private markers leak in default tag/index output; public tail remains visible.
- [x] Related pytest/Bats and relevant Ruff checks pass; no new dependency.

## Risks and mitigation
- Installer tests can mutate real home or bundle: subprocess-scoped HOME/config paths and copied bundle only.
- Mixed privacy fixes can erase public evidence: paired private/public fixtures and closed/unclosed spans.
- Bank dirty from previous session: preserve all prior hunks and update only this plan's tracking.

## Gate
Every Stage DoD verified against diff; targeted suites green; no source outside declared scope changed without evidence. Broader integration verification follows Sprint 2 before final task completion.

## Verification evidence — 2026-09-14

- Stage 1 RED: five installer roundtrip failures and ten init-target failures; GREEN: 18 new cases, 74 existing Bats. Installs/uninstalls used copied bundles and isolated HOME only.
- Stage 2 RED: 17 privacy failures; GREEN: 24 original regressions, focused 126 pytest and 37 Bats. Packaging follow-up: older installed Python package prevented importing the new sanitizer; a failing subprocess regression now passes, final privacy/index subset 75 passed.
- Independent verifier inspected both stage DoDs, source diffs and test evidence: PASS. Additional sanitizer boundary cases passed.
- Ruff and ShellCheck warning gates passed. These plan stages use external pytest/Bats RED→GREEN evidence; they do not declare executable spec Eval clauses, so work-state's Eval status is explicitly unverified.
- Integration results and any remaining limitations are recorded with the runtime plan and final audit-remediation report.
