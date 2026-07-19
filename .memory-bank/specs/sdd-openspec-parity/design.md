# Design: sdd-openspec-parity

> Architecture, interfaces, and decisions backing requirements.md.
> Source of decisions: `context/sdd-openspec-parity.md` (D-01…D-11.1). This file
> designs **Phase 1** (quality layer) in full; **Phase 2** (living specs + deltas)
> is scoped as deferred (see § Phase 2, and D-10 — it gets its own `/mb discuss`).

## Architecture

Native-only. Every Phase-1 capability is a deterministic extension of the existing
shell/Python SDD toolchain — **no OpenSpec runtime, no network, no new service**
(REQ-024). The delta format designed here stays forward-compatible with the iceboxed
donor `REQ-OSA-010` (AGR-004 / v6.6.0 untouched).

The SDD pipeline and where each Phase-1 capability plugs in:

```
/mb discuss ──► context/<topic>.md ──► /mb sdd ──► specs/<topic>/{requirements,design,tasks}.md
   │  (T5: cite inputs           (T4: ## Why,       │
   │   as digest sources)         T5: ## Sources,    │
   │                              T3: scenarios:     │
   │                                  required marker)│
   ▼                                                 ▼
inputs/ registry ◄── T5 canonical copies      mb-spec-validate.sh (the gate)
(T6: secret scan)                               ├─ T1 RFC 2119 modal levels
                                                ├─ T2 wording lint (+ --strict)
                                                ├─ T3 one-SHALL / scenarios-required
                                                ├─ T5 Sources ↔ S-NN resolution
                                                └─ T6 secret scan over inputs/
                                                        │
/mb work ──► implement ──► /mb done / archive ──► specs/done/  (T7 archive gate)
```

All new checks are **additive and gated**: a spec that opts into nothing validates
exactly as it does today (REQ-009 — the "defaults never change without opt-in" design
contract). The `scenarios: required` marker, written by `mb-sdd.sh` for **new** specs
only, is the per-spec opt-in that turns the stricter gates on.

Touchpoints (single source of truth per capability — no second, drifting detection):
- `scripts/mb-sdd.sh` — scaffold generator (`## Why`, `## Sources`, `scenarios: required`).
- `scripts/mb-spec-validate.sh` — the validator; hosts every new check as a discrete function.
- `scripts/mb-ears-validate.sh` — modal-keyword grammar (RFC 2119).
- `scripts/mb-traceability-gen.sh` + `memory_bank_skill/mb_req_id.py` — REQ grammar + non-gated marking.
- `scripts/mb-discuss.sh` (Phase 0) — input-artifact citation.
- New: `scripts/mb-spec-archive.sh` — the archive gate (T7).
- `templates/` — spec-triple templates gain the `## Why` / `## Sources` / `scenarios` anchors.

## Interfaces

Contracts anchor the contract-tests; implementation language is shell + Python (the
existing toolchain). Each is defined by its inputs, outputs, and error conditions —
not step-by-step logic.

### Validator check contract (mb-spec-validate.sh)
Each check is a pure function `check(spec_dir) -> findings[]`, where a finding is
`{severity: error|warning, req: REQ-NNN|null, file, line, message}`. The runner
aggregates findings; **any `error` → exit 1**; warnings → exit 0 unless `--strict`
promotes them (REQ-013). Existing 9 checks keep their exit contract; new checks append.

### RFC 2119 modal grammar (mb-ears-validate.sh)
Accepts `SHALL | MUST | SHOULD | MAY` as the modal in every EARS pattern (REQ-014).
Output tags each REQ with its strength. Gating consumers (task/scenario/test coverage)
filter to `SHALL|MUST` only (REQ-015); `SHOULD|MAY` are surfaced as `non_gated` in the
traceability matrix (REQ-016).

### Sources registry (## Sources ↔ inputs/)
`## Sources` is a numbered list; each entry `S-NN: <title> — <path-or-URL>`. Canonical
input copies live in `specs/<topic>/inputs/` (D-04). A `### Requirement N` block MAY
carry `**Sources:** S-NN[, S-NN…]`. Validator resolves: every referenced S-NN exists
in the registry (REQ-003); every `inputs/`-relative registry path resolves on disk
(REQ-005, error if not).

### Secret-scan contract (over inputs/ only)
Input: files under `specs/<topic>/inputs/`. Patterns: the same credential set already
used by `mb-import.py` PII-wrap (`sk-…`, `sk-ant-…`, `Bearer <long>`, `gh[pousr]_<long>`,
email) — single source, no second regex to drift. A match is a **hard error** naming
file+line (REQ-017), suppressible only by `<!-- mb-secret-ok -->` on or directly above
that line (REQ-018). Scan runs only when an `inputs/` dir exists (lazy).

### Archive gate (mb-spec-archive.sh)
`archive <topic> [--incomplete "<reason>"]`. Refuses when unchecked `- [ ]` tasks remain
unless `--incomplete` with a non-empty reason (REQ-019). On `--incomplete`: move unchecked
task lines to `backlog.md`, write the reason into the archived spec's header **and** a
`progress.md` entry, then `git mv specs/<topic>/ → specs/done/YYYY-MM-DD-<topic>/` (REQ-020).

## Decisions

Condensed from `context/sdd-openspec-parity.md` — read there for full Options/Rejected.

- **D-01/D-02** Two-phase, native-only. Phase 1 = quality layer (this design). Phase 2
  = living specs + deltas (deferred, own `/mb discuss`). No OpenSpec runtime; delta format
  forward-compatible with `REQ-OSA-010`; AGR-004 / v6.6.0 stays iceboxed.
- **D-03/D-04/D-05** First-class inputs registry: canonical copies in `specs/<topic>/inputs/`,
  numbered `## Sources` (S-NN), per-requirement `**Sources:**` provenance. Closes PRD→REQ→task→test.
- **D-06** Scenarios mandatory for **new** specs via per-spec `scenarios: required` marker
  written by `mb-sdd.sh`; global `require_scenarios` default unchanged (opt-in preserved).
- **D-07** Wording lint: **error** on >1 SHALL/MUST per REQ bullet (strict specs); **warnings**
  for vague stop-words and generic scenario titles; `--strict` promotes warnings to errors.
- **D-08** RFC 2119 strength: accept SHALL/MUST/SHOULD/MAY; hard gates apply to SHALL/MUST only;
  SHOULD/MAY non-gated + flagged in traceability; templates default to SHALL.
- **D-09** `## Why` at the top of requirements.md, auto-filled by `mb-sdd.sh` from the context
  Purpose. Triple stays a triple (no fourth proposal.md file).
- **D-11/D-11.1** Secret/PII scan over `inputs/` is a **hard block** (user chose stricter than
  the recommended warning); inline `<!-- mb-secret-ok -->` pragma suppresses a specific finding.
- **D-10** Phase 2 target: `specs/system/<capability>.md` living truth + ADDED/MODIFIED/REMOVED
  change specs merged by `/mb done` and archived to `specs/done/`. Detailed design deferred.

## Phase 2 (deferred — REQ-021/022/023)

Living capability specs + delta change-specs. **Not designed here by decision D-10** — it
needs its own `/mb discuss` before implementation so Phase 1 cannot bake in an incompatible
model. tasks.md carries a single deferred task that `Covers:` REQ-021/022/023 so they are
tracked, not orphaned. The archive gate (T7) and `specs/done/` layout built in Phase 1 are
the substrate Phase 2 builds on, so Phase 1 leaves them delta-ready.

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| New gates break existing specs (behavior change) | M | H | Every gate opt-in via `scenarios: required` marker; REQ-009 contract test proves an unmarked spec validates unchanged; run the full existing spec corpus through the new validator in CI |
| Second secret regex drifts from `mb-import.py` | M | M | Reuse the existing pattern set as a single source (T6); a test asserts parity with `mb-import.py` |
| Wording lint false-positives annoy authors | M | L | Stop-words are **warnings** by default (not errors); `--strict` is opt-in (D-07) |
| Archive `git mv` on a dirty/parallel tree loses work | L | H | Gate refuses on unchecked tasks without a reason; scoped `git mv` only; never `-A`; parallel-session coordination via COORDINATION.md |
| Phase-1 delta substrate incompatible with Phase-2 model | L | M | Archive header + `specs/done/` layout kept forward-compatible with `REQ-OSA-010`; Phase 2 re-opens design before committing |
