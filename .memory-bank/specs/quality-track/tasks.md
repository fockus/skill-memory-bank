# Tasks: quality-track

> Numbered, checkbox-tracked work items. Each task references the
> REQ-IDs it satisfies via the Covers field. Dependency-ordered: core
> before CLI, CLI before agents, integration and docs last.
> Release v6.2.0 — execution starts only after donor v6.1.0 ships
> (evidence core §7.5); Task 6 re-validates that contract first.

<!-- mb-task:1 -->
## Task 1: `quality:` config schema in pipeline.yaml + validator

**Covers:** REQ-011, REQ-017, REQ-026
**Role:** backend

**What to do:**
- Extend `references/pipeline.default.yaml` with the `quality:` block (enabled=false, default_profile, source.kind, suites with argv `command` arrays + adapter + required, gate.block/warn lists, profiles fast/change/release).
- Extend `scripts/mb-pipeline-validate.sh`: suites must carry argv arrays (reject string commands), adapter names from the known set, gate keys from the known vocabulary; absent `quality:` block stays valid.

**Testing (TDD — tests BEFORE implementation):**
- bats: default pipeline validates clean; a suite with a string `command` fails validation; unknown adapter/gate key fails; config without `quality:` validates byte-identically to today.

**DoD:**
- [ ] `quality:` block documented in the default YAML with enabled=false
- [ ] validator rejects string commands and unknown adapter/gate keys
- [ ] absent block ⇒ zero behavior change (regression test)
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:2 -->
## Task 2: Normalized models + source adapters (memory-bank / plan / diff)

**Covers:** REQ-005, REQ-006, REQ-007, REQ-008
**Role:** backend
**Depends on:** Task 1

**What to do:**
- `memory_bank_skill/quality/models.py`: Requirement, Scenario, QACase, TestResult, CaseStatus enum (REQ-013 vocabulary), NormalizedSource (digest, completeness, scope_label).
- `memory_bank_skill/quality/source_resolver.py` + `adapters/{memory_bank_spec,plan,diff}.py`: resolve `specs/<topic>/requirements.md` (reuse existing REQ/scenario parsers), active-plan DoD, and `git diff` scope; each records source digest; diff sets completeness=UNKNOWN, plan sets scope_label=implementation-plan verification.

**Testing (TDD — tests BEFORE implementation):**
- pytest: contract tests over `SourceAdapter` protocol run against all three adapters (any correct implementation passes); diff adapter fixture asserts completeness UNKNOWN; plan adapter asserts scope label; digest changes when the source file changes.

**DoD:**
- [ ] three adapters behind one registry keyed by `source.kind`
- [ ] no source text copied into any second catalog (adapter returns references + digest)
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:3 -->
## Task 3: QA contract format — qa.md parse/render + reference doc

**Covers:** REQ-001, REQ-002, REQ-003, REQ-004
**Role:** backend
**Depends on:** Task 2

**What to do:**
- `memory_bank_skill/quality/contract.py`: parse and render `specs/<topic>/qa.md` — frontmatter (topic, source kind/path/digest, profile), `<!-- mb-case:ID -->` blocks with Covers/Scenario/Origin/Type/Priority/Verification/Preconditions/Action/Oracle/Implementations; deterministic ID assignment (TC-<TOPIC>-NNN monotonic); origin ∈ specified|derived|regression; NEEDS_SPEC status representable.
- `references/qa-contract.md`: the contract format spec (single durable document, no file zoo).

**Testing (TDD — tests BEFORE implementation):**
- pytest: round-trip parse→render is byte-stable; case without oracle rejected; unknown origin rejected; ID monotonicity across updates (never reused); NEEDS_SPEC case renders and re-parses.

**DoD:**
- [ ] qa.md round-trips byte-stable; oracle mandatory per case
- [ ] `references/qa-contract.md` written
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:4 -->
## Task 4: Marker scanner — mb:case / mb:covers + inferred mapping

**Covers:** REQ-009, REQ-010
**Role:** backend
**Depends on:** Task 3

**What to do:**
- `memory_bank_skill/quality/markers.py`: scan test trees for `mb:case` / `mb:covers` comment markers (comment-syntax agnostic: `#`, `//`, `--`), bind test node ids to case ids; detect orphan markers (unknown TC-ID); optional inferred mapping (name/req-id similarity) always tagged `mapping_status: inferred`.

**Testing (TDD — tests BEFORE implementation):**
- pytest: fixtures in python/shell/js comment styles all bind; orphan marker → warning entry; inferred mapping never yields strict PASS eligibility flag; file with no markers yields MISSING for its specified case.

**DoD:**
- [ ] marker binding works across ≥3 comment syntaxes
- [ ] inferred mappings flagged and excluded from strict PASS
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:5 -->
## Task 5: Runner core + result adapters (pytest JUnit / Bats TAP / generic JUnit / exit-code)

**Covers:** REQ-011, REQ-012, REQ-016
**Role:** backend
**Depends on:** Task 1

**What to do:**
- `memory_bank_skill/quality/runner.py`: execute suites from config as argv arrays (`subprocess` list form, no shell), capture stdout/stderr/exit code under `.memory-bank/.qa/runs/`, dispatch to result adapter.
- `adapters/{junit,pytest_junit,bats_tap,exit_code}.py` implementing `ResultAdapter`; unparseable output ⇒ AdapterError ⇒ suite NOT_RUN (fail-closed); exit-code adapter yields suite-level result only (no per-case proof).
- `scripts/mb-test-run.sh` untouched — regression-guard it.

**Testing (TDD — tests BEFORE implementation):**
- pytest: contract tests over `ResultAdapter` for all four; junit fixture with failures parses counts+node ids; truncated junit ⇒ AdapterError ⇒ NOT_RUN; missing binary ⇒ suite NOT_RUN never PASS; command with spaces/quotes survives argv execution (no word-splitting).
- bats: `mb-test-run.sh` output byte-identical on a fixture repo before/after.

**DoD:**
- [ ] four adapters pass shared contract tests
- [ ] fail-closed on unparseable output and missing binaries
- [ ] `mb-test-run.sh` facade regression test green
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:6 -->
## Task 6: Evidence manifests + freshness (donor §7.5 alignment)

**Covers:** REQ-014, REQ-015
**Role:** architect
**Depends on:** Task 5; donor v6.1.0 shipped

**What to do:**
- FIRST: re-validate the §7.5 Evidence Manifest contract as actually shipped in v6.1.0 (closes O-03 from context); adopt its field names verbatim, extend with `case_map`.
- `memory_bank_skill/quality/manifest.py` (write/read/list under `.memory-bank/.qa/manifests/`) + `freshness.py` (compare recorded digests — source, contract, mapped test files, suite config — against current state; any mismatch ⇒ STALE). Scoped digests only, never whole-tree SHA.

**Testing (TDD — tests BEFORE implementation):**
- pytest: manifest round-trip; editing the source spec flips PASS evidence to STALE; editing an unrelated file does NOT; manifest matching current digests stays fresh; field-compat test against the v6.1.0 manifest fixture.

**DoD:**
- [ ] §7.5 compatibility test green against a real v6.1.0 fixture
- [ ] STALE triggers on scoped inputs only
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:7 -->
## Task 7: Case status computation — the evidence graph

**Covers:** REQ-013, REQ-016
**Role:** backend
**Depends on:** Task 4, Task 6

**What to do:**
- Status engine composing contract + markers + manifests into per-case status: PASS / FAIL / MISSING / NOT_RUN / STALE / FLAKY / WAIVED / NEEDS_SPEC (single source of truth for the vocabulary, exhaustive and mutually exclusive); multiple implementations per case ⇒ worst-result wins; FLAKY = differing outcomes across manifests with identical digests (no retry budget in v6.2.0 — O-02).

**Testing (TDD — tests BEFORE implementation):**
- pytest: parametrized truth-table over status precedence (e.g. stale beats pass, missing beats everything except needs_spec); two manifests same digests different outcomes ⇒ FLAKY; skipped critical test never PASS.

**DoD:**
- [ ] exhaustive parametrized truth-table for all 8 statuses
- [ ] worst-of-implementations rule tested
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:8 -->
## Task 8: Deterministic quality gate + waivers

**Covers:** REQ-017, REQ-018, REQ-019, REQ-020, REQ-029
**Role:** backend
**Depends on:** Task 7

**What to do:**
- `memory_bank_skill/quality/gate.py`: evaluate gate config (block/warn vocabularies from Task 1) over case statuses + semantic statuses + waivers; waiver validity = all fields present AND not expired; expired/invalid waiver ⇒ blocking finding; verdict JSON + exit code (0/1/2). Pure function, zero LLM/network imports.

**Testing (TDD — tests BEFORE implementation):**
- pytest: each block condition fires on its fixture (missing specified case, failed test, suite not run, semantic mismatch on critical, stale, invalid waiver); warn-only conditions never flip exit code; expired waiver blocks; import graph test — gate module imports no agent/LLM/network modules.

**DoD:**
- [ ] every REQ-018/019/020 condition covered by a failing-first test
- [ ] verdict machine-readable; exit codes 0/1/2 stable
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:9 -->
## Task 9: Report + memory updates

**Covers:** REQ-027, REQ-028
**Role:** developer
**Depends on:** Task 8

**What to do:**
- `memory_bank_skill/quality/report.py`: terminal summary (vision §19 shape) + `reports/qa-<topic>-latest.md` (scope/digest, coverage, suites, blocking, warnings, links to `.qa/` artifacts — no inlined dumps); memory updates: status.md QA line, checklist.md only unresolved actions, progress.md append-only entry, traceability.md Evidence column hook.

**Testing (TDD — tests BEFORE implementation):**
- pytest: report renders from a fixture verdict with all sections; raw junit/log content absent from markdown (link-only); checklist gains only open actions (passed cases absent); progress entry appended, prior entries byte-identical.

**DoD:**
- [ ] report links artifacts, never inlines
- [ ] append-only progress guarantee tested
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:10 -->
## Task 10: `/mb qa` command surface

**Covers:** REQ-001, REQ-011, REQ-027
**Role:** developer
**Depends on:** Task 9

**What to do:**
- `scripts/mb-qa.sh` dispatcher: `plan | generate | run | verify | report` + `--profile`, `--from plan|diff`, `--write`; safe default mode (no test-code mutation without `--write`); exit codes 0/1/2.
- `commands/qa.md` command doc + `/mb qa` routing row in `commands/mb.md`; registration in install manifest.

**Testing (TDD — tests BEFORE implementation):**
- bats: dispatcher routes each subcommand; unknown subcommand exit 2; `run` without `quality:` config exits 2 with actionable message (never silent); `--write` absent ⇒ test tree untouched (fixture diff empty); registration tests (command file present, mb.md row, manifest).

**DoD:**
- [ ] five subcommands wired end-to-end on a fixture bank
- [ ] safe-by-default proven by fixture-diff test
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:11 -->
## Task 11: mb-qa-planner agent + `/mb qa plan` LLM flow

**Covers:** REQ-001, REQ-002, REQ-003, REQ-004
**Role:** qa
**Depends on:** Task 3, Task 10

**What to do:**
- `agents/mb-qa-planner.md` (sonnet): input = normalized source; output = proposed cases (origin, oracle, verification level, priority) as structured JSON; explicit NEEDS_SPEC rule — never invent assertions; SendMessage report-delivery block (project invariant).
- Wire into `/mb qa plan`: agent proposes → deterministic `contract.py` validates/renders qa.md (agent never writes the file directly).

**Testing (TDD — tests BEFORE implementation):**
- bats: agent registration (frontmatter, tools incl. SendMessage, report-delivery block — extend `test_agent_report_delivery.bats` roster); pytest: planner-output JSON schema validator rejects a case without oracle / with invented assertion on NEEDS_SPEC fixture.

**DoD:**
- [ ] agent registered with report-delivery contract
- [ ] propose→validate→render separation enforced (agent has no Write path to qa.md)
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:12 -->
## Task 12: Semantic audit — mb-qa-auditor + digest cache + gate wiring

**Covers:** REQ-019, REQ-021, REQ-029
**Role:** qa
**Depends on:** Task 4, Task 8

**What to do:**
- `agents/mb-qa-auditor.md` (sonnet): input = one case + oracle + mapped test source + minimal fixtures; output strict JSON {semantic_status, rationale}; statuses strong/weak/mismatch/uncertain.
- Cache `.memory-bank/.qa/audit-cache.json` keyed by (case digest, test digest); unchanged pair never re-audited; CI path reads cache only (no dispatch).
- Gate wiring: change profile weak→warn, mismatch→fail; release profile critical weak→fail.

**Testing (TDD — tests BEFORE implementation):**
- pytest: cache hit skips dispatch (call-counter fixture); cache invalidates on either digest change; gate matrix profile×status parametrized; auditor JSON schema rejects unknown status.
- bats: agent registration + report-delivery roster.

**DoD:**
- [ ] audit cached and CI-consumable without LLM
- [ ] profile-dependent gate rules tested
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:13 -->
## Task 13: Test generation — `/mb qa generate` + `--write` + RED confirmation

**Covers:** REQ-022, REQ-023, REQ-024
**Role:** qa
**Depends on:** Task 11, Task 12

**What to do:**
- Generation flow reusing `agents/mb-qa.md`: for each MISSING case pick lowest suitable level (REQ-024 mapping table from vision §3.5), generate test with `mb:case`/`mb:covers` markers following detected project conventions; run it: expected-RED confirmed for unimplemented behavior; unexpected GREEN ⇒ forced semantic audit (strong ⇒ already-implemented note, weak/uncertain ⇒ warning, mismatch ⇒ fail) per context edge-case rule; generated tests always semantic-audited before satisfying a case.

**Testing (TDD — tests BEFORE implementation):**
- pytest: level-selection table parametrized (business rule ⇒ unit/integration, never e2e); generated fixture carries markers; RED-confirmation gate refuses to mark case covered on unexpected GREEN without audit verdict.
- bats: `--write` creates files only under configured test roots; without `--write` generation refuses.

**DoD:**
- [ ] RED-confirmation loop tested both ways (expected RED, unexpected GREEN)
- [ ] no E2E generated for non-critical-flow fixtures
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:14 -->
## Task 14: `/mb work --qa` integration

**Covers:** REQ-025, REQ-026
**Role:** backend
**Depends on:** Task 10, Task 13

**What to do:**
- `--qa` flag in `/mb work` (+ `quality.enabled` config path): attach quality actions inside existing canonical stages — plan→quality.plan, implement→quality.generate-red, verify→quality.run/audit/gate/report, done→memory update — via `mb-workflow.sh` step resolution; no new mandatory stage names in the canonical list; gate verdict feeds the existing severity-gate decision point.

**Testing (TDD — tests BEFORE implementation):**
- bats: workflow JSON without `--qa` and without `quality.enabled` byte-identical to current output on fixture bank (golden-file test); with `--qa` quality steps appear nested under existing stages only; `--qa` with no `quality:` config exits 2.

**DoD:**
- [ ] byte-identical golden test green (REQ-026)
- [ ] canonical stage list unchanged (REQ-025)
- [ ] tests pass
- [ ] lint clean

<!-- mb-task:15 -->
## Task 15: Docs + release notes

**Covers:** REQ-001, REQ-017, REQ-025, REQ-029
**Role:** analyst
**Depends on:** Task 14

**What to do:**
- `docs/features/quality-track.md` (user guide: chain, profiles, sources, gate, waivers, CI usage), README section + hooks/env-vars tables where relevant, SKILL.md agent roster additions, CHANGELOG `[6.2.0]` entry, `commands/qa.md` cross-links; document what v6.2.0 explicitly does NOT do (Playwright, healer, OpenSpec source — pointer to later slices).

**Testing (TDD — tests BEFORE implementation):**
- bats: docs-registration tests (feature doc exists and is linked from README; CHANGELOG contains 6.2.0 section; every new agent/command referenced in SKILL.md).

**DoD:**
- [ ] user can run the full flow from docs alone (checked on fixture project)
- [ ] out-of-scope stated explicitly
- [ ] tests pass
- [ ] lint clean
