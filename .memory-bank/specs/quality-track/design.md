# Design: quality-track

> Architecture, interfaces, and decisions backing requirements.md.
> Vision source: `mb-quality-track-final-solution.md`; decisions: `context/quality-track.md` (D-01…D-10).
> Release v6.2.0 of the donor program; depends on the v6.1.0 evidence core (§7.5 Evidence Manifest, collectors EV-01…05) — reused, never forked.

## Architecture

Three planes, dependencies pointing inward (deterministic core has zero LLM/agent deps):

```
LLM plane (agents, host-dispatched, optional):
  mb-qa-planner   — testability check, case derivation, NEEDS_SPEC detection
  mb-qa-auditor   — semantic audit: assertions vs oracle (strong/weak/mismatch/uncertain)
  mb-qa (existing)— test generation in write mode (level selection, conventions)
        │ proposes; never computes statuses
        ▼
Deterministic core (memory_bank_skill/quality/):
  models.py            — Requirement / Scenario / QACase / CaseResult / statuses enum
  source_resolver.py   — source adapter registry (memory-bank | plan | diff)
  contract.py          — qa.md parse/render (<!-- mb-case:ID --> blocks, oracle, origin)
  markers.py           — mb:case / mb:covers scanner + inferred-mapping detector
  runner.py            — argv suite execution (no eval), per-suite adapter dispatch
  manifest.py          — evidence manifest read/write (§7.5-compatible)
  freshness.py         — digest comparison → STALE marking
  gate.py              — block/warn evaluation, waiver validity, verdict + exit code
  report.py            — terminal summary + reports/qa-<topic>-latest.md + memory updates
  adapters/            — junit.py, pytest_junit.py, bats_tap.py, exit_code.py,
                         sources: memory_bank_spec.py, plan.py, diff.py
        │ consumed by
        ▼
CLI plane:
  scripts/mb-qa.sh          — dispatcher: plan | generate | run | verify | report
  commands/qa.md            — /mb qa command surface + /mb work --qa wiring
  scripts/mb-test-run.sh    — UNCHANGED compatibility facade for existing callers
```

Data flow (one `/mb work <t> --qa` pass, vision §4.5):

```
resolve source → build/update qa.md → scan markers → [write mode: generate missing]
→ run required suites → parse via adapters → persist manifests → freshness check
→ semantic audit (cached by digest) → gate → report → memory update
```

Artifacts:

- `specs/<topic>/qa.md` — the single durable QA contract (no strategy/checklist/coverage file zoo).
- `.memory-bank/.qa/{manifests,runs,junit,logs}/` — runtime evidence, gitignore-able.
- `.memory-bank/reports/qa-<topic>-latest.md` — rendered report, links artifacts, never inlines dumps.

Pipeline config (`pipeline.yaml`, new `quality:` block; absent block ⇒ feature fully off):

```yaml
quality:
  enabled: false            # default OFF — /mb work byte-identical without opt-in
  default_profile: change   # fast | change | release
  source: {kind: memory-bank}
  suites:
    unit: {cwd: ., command: [pytest, -q, --junitxml=.memory-bank/.qa/junit/unit.xml], adapter: junit, required: true}
    bats: {cwd: ., command: [bats, tests/bats], adapter: bats-tap, required: true}
  gate:
    block: [specified_case_missing, specified_case_failed, required_suite_not_run,
            critical_case_semantic_mismatch, stale_evidence, invalid_waiver]
    warn:  [derived_case_missing, weak_noncritical_assertion, inferred_test_mapping]
```

## Interfaces

Python protocols (contract-first; contract tests precede implementations):

```python
class SourceAdapter(Protocol):
    kind: str  # "memory-bank" | "plan" | "diff"
    def resolve(self, target: str, mb_path: Path) -> NormalizedSource: ...
    # NormalizedSource: requirements[], scenarios[], digest, completeness ("full"|"unknown"), scope_label

class ResultAdapter(Protocol):
    name: str  # "junit" | "bats-tap" | "exit-code"
    def parse(self, raw: bytes, suite: SuiteConfig) -> list[TestResult]: ...
    # TestResult: node_id, outcome ("passed"|"failed"|"skipped"|"error"), duration, failure_head
    # Errors: unparseable input → AdapterError → suite treated NOT_RUN (fail-closed, REQ-016)

class GateInput(TypedDict):
    cases: list[CaseStatus]      # status ∈ REQ-013 enum; semantic ∈ strong|weak|mismatch|uncertain|None
    waivers: list[Waiver]        # id, case_id, reason, owner, expires, approved_by — all required
    profile: str
def evaluate_gate(inp: GateInput, cfg: GateConfig) -> Verdict
    # Verdict: decision ("PASS"|"FAIL"), blocking[], warnings[], exit_code (0 pass / 1 fail / 2 config error)
```

Evidence manifest (JSON, one per suite run) — field-compatible with donor §7.5
(`baseline/head SHA`, digests, producer); Quality Track adds `case_map`:

```json
{"run_id": "<utc>-<sha7>", "git_commit": "...", "source_digest": "sha256:...",
 "qa_contract_digest": "sha256:...", "test_digest": "sha256:...",
 "suite_config_digest": "sha256:...", "profile": "change",
 "suite": "unit", "adapter": "junit", "command": ["pytest", "-q"],
 "started_at": "...", "results": [...], "case_map": {"TC-X-001": ["tests/..::node"]}}
```

Marker grammar (language-agnostic comments, one per line, above the test):
`mb:case <TC-ID>` binds a test node to a case; `mb:covers <REQ-ID>` is informational.
Unknown TC-ID → orphan warning; case with zero markers → MISSING (specified ⇒ gate block).

Exit codes across all `mb-qa` entry points: `0` gate PASS, `1` gate FAIL, `2` usage/config error.

## Decisions

Ledger lives in `context/quality-track.md`; design-binding summary:

- **D-01/D-02/D-03** — donor release v6.2.0 after 6.1.0; reuse §7.5 evidence contract; 6.x tail shifted +1 (AGR-008/AGR-009).
- **D-04** — scope = vision stages 1–3 (foundation + planning + generation + `/mb work --qa`); Playwright/healer excluded (see Out of Scope in context).
- **D-05** — sources: memory-bank + plan + diff behind `source.kind`; OpenSpec adapter deferred, interface reserved.
- **D-06** — semantic audit ships now: input is one case + oracle + mapped test only; cache key = (case digest, test digest); change profile weak→WARN, mismatch→FAIL; release profile critical weak→FAIL.
- **D-07** — Python core + thin shell dispatchers; `mb-test-run.sh` stays a facade.
- **D-08** — profiles fast/change/release as config; `change` default for `--qa`.
- **D-09** — adapters wave 1: pytest JUnit, Bats TAP, generic JUnit, exit-code (suite-only, cannot prove per-case coverage).
- Design-level additions: fail-closed everywhere (unparseable output ⇒ NOT_RUN; invalid waiver ⇒ block; missing config while `--qa` requested ⇒ exit 2, never silent skip); suite commands stored and replayed as argv arrays (no eval, exact command lands in the manifest); generated tests are always semantic-audited before they can satisfy a case.

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Donor §7.5 manifest contract drifts before 6.1.0 lands | M | H | Manifest fields pinned in this design; re-validate against umbrella design.md at slice start (O-03 in context) |
| Semantic-audit token cost on large suites | M | M | Digest-pair cache, minimal input (case+oracle+test), audit only mapped/changed pairs; CI consumes cache only (REQ-029) |
| Marker adoption friction in existing test suites | H | M | Inferred-mapping path (REQ-010) keeps legacy tests visible without granting strict PASS; generator always emits markers |
| Freshness false-positives (any repo change ⇒ STALE) | M | M | Digests are scoped: source, contract, mapped test files, suite config — not whole-tree SHA |
| Generated tests weak or tautological | M | H | Mandatory RED confirmation (REQ-023) + forced semantic audit on generated tests before they count |
| FLAKY detection without retry budget under-specified | M | L | O-02: v6.2.0 detects flake as differing results at identical digests; retry policy deferred to design review at slice start |
