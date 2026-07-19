---
topic: sdd-openspec-parity
created: 2026-07-15
status: ready
---

# Context: sdd-openspec-parity

## Purpose & Users

Bring the native SDD engine (`/mb discuss` → `/mb sdd` → `/mb work`) to OpenSpec-level
spec quality — and beyond it where our engine is already stronger (executable tasks,
traceability). Users: skill users authoring specs and the agents that execute them.
Success (qualitative): every new spec has atomic requirements (one SHALL each),
scenario coverage, source provenance (PRD → REQ → task → test), and an explicit "why";
validators enforce all of it deterministically; existing specs keep validating unchanged.

## Research Digest

Facts gathered in Phase 0 — each line one fact + citation.

- OpenSpec two-tier model: `specs/` = living truth per capability, `changes/` = delta proposals — <https://github.com/Fission-AI/OpenSpec/blob/main/docs/concepts.md>
- Delta format `## ADDED / MODIFIED / REMOVED Requirements`; archive merges deltas into living specs — docs/concepts.md, docs/writing-specs.md
- Quality rules: one SHALL per requirement, observable behavior, no vague words, no implementation details, RFC 2119 strength — docs/writing-specs.md
- Strict mode: every requirement needs ≥1 `#### Scenario:` incl. edge cases — docs/writing-specs.md
- OpenSpec has NO PRD/input import — `proposal.md` is authored from scratch; inputs registry makes us stronger here
- Our generator scaffolds the triple; only `- **REQ-NNN**` bullets survive the context→spec copy — `scripts/mb-sdd.sh:81-103`
- Our validator: 9 checks; `--require-scenarios` / `--require-tests` opt-in, default off — `scripts/mb-spec-validate.sh:9-30`
- `scripts/mb-ears-validate.sh` validates syntax of 5 EARS patterns only — no wording-quality lint
- Scenario layer exists and is executable: `scripts/mb-scenario-extract.py`, `mb_work_items.py`
- Traceability keyed by (spec, REQ); REQ grammar single-sourced in `mb_req_id.py` — `scripts/mb-traceability-gen.sh:55-60`
- `plans/done/` exists; `specs/` has no archive — active and finished specs are indistinguishable
- Backlog `I-062` "Ужесточить EARS-валидатор и spec-checking" [MED] — absorbed by this topic
- Iceboxed v6.6.0 = OpenSpec **runtime** integration (REQ-OSA-001…020), not native parity — `.memory-bank/specs/mb-donor-evolution/requirements.md:166-187`, AGR-004
- REQ-OSA-010 already requires digest-bound deltas — our delta format must stay forward-compatible with it

## Decision Log

- **D-01**: Full OpenSpec parity in two phases — Phase 1 quality layer (lint, scenarios, RFC 2119, Why, inputs, archive gate), Phase 2 living specs + deltas. — Rationale: closes the structural gap (specs go stale) while cheap wins ship first. Rejected: quality-layer-only; lint-only (I-062 minimum).
- **D-02**: Independent native-only initiative. AGR-004 untouched (v6.6.0 stays iceboxed), no OpenSpec runtime; delta format designed forward-compatible with REQ-OSA-010; donor track wins on release overlap (AGR-003). — Rejected: embed into donor train (cheap wins would queue for months); unfreeze v6.6.0 (no 6.1 metrics yet).
- **D-03**: First-class inputs registry: PRD / JTBD+DoD / architecture plans / mermaid enter the spec via a `## Sources` section; `/mb discuss` Phase 0 ingests them as research-digest sources. — Rejected: absorb into context only (loses originals); status quo (inputs invisible to tooling).
- **D-04**: Canonical input copies live in `specs/<topic>/inputs/` — the spec is self-contained and archives as a unit; `## Sources` may additionally reference external paths/URLs. — Rejected: `context/<topic>/` (link breaks at archive time); hybrid without copies (paths rot).
- **D-05**: Per-requirement provenance: `## Sources` numbers inputs (S-NN); each `### Requirement N` block may carry `**Sources:** S-NN`. EARS bullets untouched — validators unaffected. Closes PRD → REQ → task → test. — Rejected: file-level only (can't answer "where did this REQ come from"); content-digest pinning (deferred to Phase 2, see Open Questions).
- **D-06**: Scenarios mandatory for NEW specs via per-spec marker `scenarios: required` written by `/mb sdd`; global `require_scenarios` default unchanged — honors the "defaults never change without opt-in" design contract. — Rejected: global default flip (breaks existing EARS-only specs); instruction-only (no gate).
- **D-07**: Wording lint — error: >1 SHALL/MUST per REQ bullet (strict specs only); warnings everywhere: vague stop-words ("gracefully", "properly", "robust", …), implementation details in REQ text, unnamed scenarios ("Test 2"); `--strict` promotes warnings to errors. — Rejected: all-errors (heuristics false-positive); one-SHALL only ("handle gracefully" keeps passing).
- **D-08**: RFC 2119 strength levels: validator accepts SHALL/MUST/SHOULD/MAY; hard gates (task, scenario-in-strict, require-tests) apply only to SHALL/MUST; SHOULD/MAY are non-gated and flagged in traceability; templates default to SHALL. — Rejected: SHALL-only (options become pseudo-mandatory); uniform gates (forces implementing MAY).
- **D-09**: `## Why` section at the top of requirements.md, auto-filled by `mb-sdd.sh` from the context file's Purpose (+ what-changes), linking to the full context. Triple stays a triple. — Rejected: fourth file proposal.md (ceremony, "triple" baked into docs/validator/tests); link-only (spec not self-contained, contradicts D-04).
- **D-10**: Phase 2 target model fixed at requirements level: `specs/system/<capability>.md` = living truth; change specs gain ADDED/MODIFIED/REMOVED sections; `/mb done` merges deltas into living specs and archives the change spec to `specs/done/YYYY-MM-DD-<topic>/`. Detailed design → dedicated `/mb discuss` before Phase 2. — Rejected: full Phase-2 design now (would go stale); intent-only (Phase 1 could take incompatible decisions).
- **D-11**: Secret/PII scan over `specs/<topic>/inputs/` is a HARD validation block (user chose stricter than the recommended warning). — Rejected: warning-only; nothing/doc-only.
- **D-11.1**: Escape hatch for false positives: inline pragma `<!-- mb-secret-ok -->` on (or directly above) the flagged line suppresses that specific finding. Visible in diff, reviewable. — Rejected: allowlist file (detached from the finding); `--allow-secrets` flag (disables the whole scan).
- **D-12**: Archive gate: archiving to `specs/done/` requires all tasks checked; explicit `--incomplete` flag with a mandatory reason overrides — reason recorded in the archive header + progress.md, unchecked tasks auto-moved to backlog.md. Stricter than OpenSpec (warn-and-archive). — Rejected: OpenSpec-style warning (tasks silently sink); no-exception ban (abandoned initiatives pollute active specs forever).

## Functional Requirements (EARS)

### Phase 1 — inputs & provenance (D-03, D-04, D-05)

- **REQ-001** (ubiquitous): The system shall store canonical copies of external input artifacts (PRD, JTBD, diagrams, ADR excerpts) under `specs/<topic>/inputs/`.
- **REQ-002** (event-driven): When `/mb sdd` generates requirements.md and input artifacts exist, the system shall render a `## Sources` section assigning each input a stable S-NN identifier.
- **REQ-003** (optional): Where a `### Requirement N` block declares a `**Sources:** S-NN` line, the system shall validate that every referenced S-NN exists in the `## Sources` registry.
- **REQ-004** (event-driven): When `/mb discuss` runs Phase 0 and input artifacts exist for the topic, the system shall cite them as sources in the research digest.
- **REQ-005** (unwanted): If a `## Sources` entry references a path under `inputs/` that does not resolve, then the system shall report a validation error.

### Phase 1 — Why layer (D-09)

- **REQ-006** (event-driven): When `mb-sdd.sh` generates requirements.md from an existing context file, the system shall copy the Purpose summary into a `## Why` section linking to the context file.

### Phase 1 — scenario strictness (D-06)

- **REQ-007** (event-driven): When `mb-sdd.sh` creates a new spec, the system shall write a `scenarios: required` marker into the spec.
- **REQ-008** (state-driven): While a spec carries the `scenarios: required` marker, the system shall report a validation error for every SHALL or MUST requirement lacking a covering scenario.
- **REQ-009** (unwanted): If a spec lacks the `scenarios: required` marker, then the system shall validate it under the pre-existing opt-in rules without behavior change.

### Phase 1 — wording lint (D-07)

- **REQ-010** (state-driven): While validating a spec marked `scenarios: required`, the system shall report an error for any REQ bullet containing more than one SHALL or MUST keyword.
- **REQ-011** (ubiquitous): The system shall emit warnings for REQ bullets containing terms from the vague-wording stop-list.
- **REQ-012** (ubiquitous): The system shall emit warnings for scenario blocks whose titles are generic placeholders.
- **REQ-013** (optional): Where the `--strict` flag is passed to spec validation, the system shall treat wording-lint warnings as errors.

### Phase 1 — RFC 2119 strength (D-08)

- **REQ-014** (ubiquitous): The system shall accept SHALL, MUST, SHOULD and MAY as requirement modal keywords in EARS validation.
- **REQ-015** (ubiquitous): The system shall apply task-coverage, scenario-coverage and test-coverage gates only to SHALL and MUST requirements.
- **REQ-016** (ubiquitous): The system shall mark SHOULD and MAY requirements as non-gated in the traceability matrix.

### Phase 1 — inputs safety (D-11, D-11.1)

- **REQ-017** (unwanted): If a secret or credential pattern is detected in a file under `specs/<topic>/inputs/`, then the system shall fail spec validation with an error naming the file and line.
- **REQ-018** (optional): Where a flagged line carries the `<!-- mb-secret-ok -->` pragma on or directly above it, the system shall suppress that specific finding.

### Phase 1 — archive gate (D-12)

- **REQ-019** (unwanted): If a spec has unchecked tasks, then the system shall refuse archiving it to `specs/done/` unless the `--incomplete` flag with a reason is provided.
- **REQ-020** (event-driven): When a spec is archived with `--incomplete`, the system shall move its unchecked tasks to backlog.md and record the reason in the archive header and progress.md.

### Phase 2 — living specs & deltas (D-10, D-02; model-level)

- **REQ-021** (ubiquitous): The system shall maintain living capability specs under `specs/system/` as the canonical description of current behavior.
- **REQ-022** (optional): Where a change spec contains ADDED, MODIFIED or REMOVED requirement sections, the system shall validate them as deltas against the referenced living spec.
- **REQ-023** (event-driven): When `/mb done` completes a change spec containing delta sections, the system shall merge the deltas into the living specs before archiving.
- **REQ-024** (ubiquitous): The system shall implement all parity features without invoking the OpenSpec runtime.

## Non-Functional Requirements

- **NFR-001**: Offline — all new validation runs without network access.
- **NFR-002**: Compatibility — bash 3.2 + POSIX tools + python3 stdlib only; zero new dependencies (repo convention, see `codebase/CONVENTIONS.md`).
- **NFR-003**: Performance — full validation of a 50-REQ spec completes in < 5 s.
- **NFR-004**: Token economy — all new gates are deterministic scripts, no LLM calls; expensive layers stay opt-in (design contract).
- **NFR-005**: Backwards compatibility — specs without new markers validate byte-identically to today (guarded by regression tests).

## Constraints

- Design contract: defaults never change without explicit opt-in (CLAUDE.md § Memory Bank) — honored via per-spec markers (D-06).
- AGR-003: on release overlap the donor program wins; AGR-004: v6.6.0 (OpenSpec runtime) stays iceboxed — this initiative must not unfreeze it.
- Kiro/Kilo exportability of requirements.md must survive the new `## Why` / `## Sources` sections.
- `progress.md` append-only; REQ/I/ADR ID monotonicity.
- TDD: every validator rule lands with failing bats tests first.

## Edge Cases & Failure Modes

- PRD in `inputs/` contains a real API key → validation hard-fails naming file:line (REQ-017); fix = remove or move to `<private>` in context.
- PRD legitimately shows an example key → `<!-- mb-secret-ok -->` pragma suppresses exactly that finding (REQ-018).
- Spec archived at 8/12 tasks → refused; `--incomplete "priorities changed"` moves 4 tasks to backlog.md and records the reason (REQ-019/020).
- `## Sources` points to a deleted `inputs/prd.md` → validation error (REQ-005); external URL/context links degrade to warnings (see Open Questions).
- Requirement derived from PRD contradicts code reality → `/mb discuss` grilling rule 5 resolves the contradiction before the REQ is recorded; provenance line shows the source either way.
- Legacy spec opts into `scenarios: required` with zero scenarios → deterministic error listing every uncovered SHALL/MUST REQ (REQ-008).

## Out of Scope

- OpenSpec runtime integration (authoring backend, CAS import, workspaces) — iceboxed v6.6.0, REQ-OSA-001…020.
- Content-digest pinning of sources (REQ-OSA-010 alignment) — Phase 2 open question.
- Auto-import from non-file sources (Figma, Notion, URLs-as-inputs).
- Detailed Phase 2 design (merge semantics, capability naming) — dedicated `/mb discuss` before Phase 2.
- GSD execution paths (separate donor releases).

## Open Questions

- Merge-conflict semantics for deltas (two change specs MODIFY the same living requirement) — blocked on: Phase 2 discuss.
- Capability naming/splitting rules for `specs/system/` — blocked on: Phase 2 discuss.
- Source digest pinning (stale-PRD detection; REQ-OSA-010 compatibility) — blocked on: Phase 2 discuss.
- Migration path of existing specs onto the living model — blocked on: Phase 2 discuss.
- Binary/oversized inputs policy (preliminary: warning above 1 MB, binaries allowed for diagrams) — decide at `/mb plan` time.
- Broken external (non-`inputs/`) Sources link severity (preliminary: warning) — decide at `/mb plan` time.
