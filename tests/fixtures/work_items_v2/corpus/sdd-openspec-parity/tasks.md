# Tasks: sdd-openspec-parity

> Numbered, checkbox-tracked work items. Each task references the REQ-IDs it
> satisfies via the Covers field. **Phase 1** (quality layer) is authored in full
> below (Tasks 1–8, REQ-001…020 + REQ-024). **Phase 2** (living specs + deltas)
> is a single deferred task (Task 9, REQ-021…023) — see design.md § Phase 2 / D-10.
>
> Dependency order: T1 (modal grammar) is the foundation the lint/gate tasks read;
> T3 depends on T1; the rest are independent and can run in any order after T1.
> Every task is native-only (REQ-024) — no OpenSpec runtime, verified by T8.
> Global invariant: an unmarked spec must validate byte-for-byte as today (REQ-009),
> asserted in T3's regression test — carry that fixture through every task.

<!-- mb-task:1 -->
## Task 1: RFC 2119 modal strength levels

**Covers:** REQ-014, REQ-015, REQ-016
**Role:** backend

**What to do:**
- `mb-ears-validate.sh`: accept `SHALL | MUST | SHOULD | MAY` as the modal keyword in all five EARS patterns (today only SHALL). Emit each REQ's parsed strength.
- `mb-traceability-gen.sh` + `memory_bank_skill/mb_req_id.py`: tag SHOULD/MAY requirements `non_gated` in the matrix; keep SHALL/MUST gated.
- Ensure downstream coverage gates (task/scenario/test) read the strength and apply only to SHALL/MUST.

**Testing (TDD — tests BEFORE implementation):**
- EARS fixture with one REQ per modal → all four validate (REQ-014); a bogus modal still fails.
- Traceability fixture: a SHOULD REQ renders as `non_gated`, a SHALL REQ as gated (REQ-016).
- Coverage-gate test: an uncovered SHOULD REQ does NOT fail the gate; an uncovered SHALL does (REQ-015).

**DoD:**
- [ ] SHALL/MUST/SHOULD/MAY all EARS-validate; gates fire only on SHALL/MUST; SHOULD/MAY show `non_gated` in traceability.
- [ ] Existing SHALL-only specs validate unchanged (no regression).
- [ ] tests pass · shellcheck + ruff clean · bash 3.2 + Python 3.11.

<!-- mb-task:2 -->
## Task 2: Wording lint (vague stop-words + generic scenario titles, --strict)

**Covers:** REQ-011, REQ-012, REQ-013
**Role:** backend

**What to do:**
- `mb-spec-validate.sh`: add a wording-lint check emitting **warnings** for REQ bullets containing stop-list terms (`gracefully, properly, robust, efficient, appropriate, as needed, etc.` — closed list in `references/`), and for scenario blocks whose titles are generic placeholders (`Test 2`, `Scenario`, unnamed).
- Add `--strict`: promote every wording-lint warning to an error (exit 1).

**Testing (TDD — tests BEFORE implementation):**
- REQ with "handle errors gracefully" → warning, exit 0 without `--strict` (REQ-011); with `--strict` → exit 1 (REQ-013).
- Scenario titled `### Scenario: Test 2` → warning (REQ-012); a descriptively-named scenario → none.
- A clean spec → zero wording findings.

**DoD:**
- [ ] Stop-word + generic-title warnings emitted with file:line; `--strict` promotes them to errors.
- [ ] Default (no `--strict`) never changes exit code vs today for a warning-only spec.
- [ ] tests pass · shellcheck + ruff clean.

<!-- mb-task:3 -->
## Task 3: scenarios: required marker + one-SHALL-per-REQ + opt-in preservation

**Covers:** REQ-007, REQ-008, REQ-009, REQ-010
**Role:** backend

**What to do:**
- `mb-sdd.sh`: write a `scenarios: required` marker into every **new** spec it scaffolds (frontmatter or a documented anchor); the global `require_scenarios` default stays off.
- `mb-spec-validate.sh`: while a spec carries the marker, error on any SHALL/MUST REQ with no covering `**Covers:**` scenario (REQ-008) and on any REQ bullet with >1 SHALL/MUST keyword (REQ-010).
- A spec WITHOUT the marker validates exactly under today's opt-in rules — no behavior change (REQ-009).

**Testing (TDD — tests BEFORE implementation):**
- New `mb-sdd.sh` output contains `scenarios: required` (REQ-007).
- Marked spec, one SHALL REQ with no scenario → error (REQ-008); add the scenario → passes.
- Marked spec, a REQ bullet with two SHALLs → error (REQ-010).
- **Regression fixture (the global invariant):** an existing unmarked spec validates byte-for-byte identically before/after this change (REQ-009). Reuse this fixture in every later task.

**DoD:**
- [ ] `mb-sdd.sh` marks new specs; marked specs enforce scenario-coverage + one-SHALL; unmarked specs unchanged.
- [ ] REQ-009 regression fixture green (diff-identical validator output on an unmarked spec).
- [ ] tests pass · shellcheck + ruff clean.

<!-- mb-task:4 -->
## Task 4: ## Why section auto-filled from context

**Covers:** REQ-006
**Role:** backend

**What to do:**
- `mb-sdd.sh`: when `context/<topic>.md` exists, copy its Purpose summary into a `## Why` section at the top of the generated `requirements.md`, linking back to the context file. Update `templates/` so the anchor exists.

**Testing (TDD — tests BEFORE implementation):**
- `mb-sdd.sh` on a topic with a context Purpose → `requirements.md` has a `## Why` section containing the purpose text + a relative link to the context file (REQ-006).
- No context file → no `## Why` injected (graceful, spec still valid).

**DoD:**
- [ ] Generated `## Why` carries the purpose + context link; absent context → no section, no error.
- [ ] The triple stays a triple (no fourth file).
- [ ] tests pass · shellcheck clean.

<!-- mb-task:5 -->
## Task 5: Inputs registry + ## Sources provenance

**Covers:** REQ-001, REQ-002, REQ-003, REQ-004, REQ-005
**Role:** backend

**What to do:**
- Establish `specs/<topic>/inputs/` as the canonical home for external artifacts (PRD, JTBD, diagrams, ADR excerpts) (REQ-001).
- `mb-sdd.sh`: when input artifacts exist, render a numbered `## Sources` section (S-NN → title → path/URL) (REQ-002).
- `mb-discuss.sh` Phase 0: cite existing input artifacts for the topic as research-digest sources (REQ-004).
- `mb-spec-validate.sh`: every `**Sources:** S-NN` reference must resolve to a registry entry (REQ-003); every `inputs/`-relative registry path must resolve on disk, else error (REQ-005).

**Testing (TDD — tests BEFORE implementation):**
- Topic with an `inputs/prd.md` → generated `## Sources` lists it as `S-01` (REQ-002).
- Requirement block `**Sources:** S-01` with S-01 present → passes; `S-99` absent → error (REQ-003).
- `## Sources` entry pointing at a deleted `inputs/prd.md` → validation error naming it (REQ-005).
- `/mb discuss` Phase 0 digest cites the input (REQ-004).

**DoD:**
- [ ] `inputs/` copies are canonical; `## Sources` numbered; per-REQ `**Sources:**` resolved; unresolved S-NN or path → error.
- [ ] discuss Phase 0 cites inputs.
- [ ] tests pass · shellcheck + ruff clean.

<!-- mb-task:6 -->
## Task 6: Secret/PII scan over inputs/ (hard block + pragma)

**Covers:** REQ-017, REQ-018
**Role:** backend

**What to do:**
- `mb-spec-validate.sh`: scan files under `specs/<topic>/inputs/` for credential patterns, reusing the **exact** pattern set from `mb-import.py` PII-wrap (single source — no second regex). A match is a hard error (exit 1) naming file+line (REQ-017).
- Honor `<!-- mb-secret-ok -->` on or directly above the flagged line to suppress that specific finding (REQ-018). Scan runs only when `inputs/` exists.

**Testing (TDD — tests BEFORE implementation):**
- `inputs/` file with an `sk-…` key → validation error naming file+line, exit 1 (REQ-017).
- Same file with `<!-- mb-secret-ok -->` above the line → finding suppressed, exit 0 (REQ-018); a pragma elsewhere does NOT suppress.
- Parity test: the scanner's pattern set equals `mb-import.py`'s (guards against drift).
- No `inputs/` dir → scan is a no-op.

**DoD:**
- [ ] Secret in `inputs/` hard-fails with file:line; pragma suppresses only its own line; patterns single-sourced from `mb-import.py`.
- [ ] tests pass · shellcheck + ruff clean.

<!-- mb-task:7 -->
## Task 7: Archive gate (specs/done/ + --incomplete)

**Covers:** REQ-019, REQ-020
**Role:** backend

**What to do:**
- New `scripts/mb-spec-archive.sh archive <topic> [--incomplete "<reason>"]`: refuse archiving to `specs/done/` while unchecked `- [ ]` tasks remain, unless `--incomplete` with a non-empty reason (REQ-019).
- On `--incomplete`: move unchecked task lines to `backlog.md`, record the reason in the archived spec header AND a `progress.md` entry, then scoped `git mv specs/<topic>/ → specs/done/YYYY-MM-DD-<topic>/` (REQ-020).
- Wire it into the `/mb done` close-out path for spec-driven work.

**Testing (TDD — tests BEFORE implementation):**
- Spec with an unchecked task, no flag → refuses, exit non-zero, nothing moved (REQ-019).
- Same with `--incomplete "priorities changed"` → archived; unchecked tasks in `backlog.md`; reason in archive header + `progress.md` (REQ-020).
- All tasks checked → archives with no flag needed.
- `git mv` is scoped (never `-A`); dirty foreign hunks are not swept.

**DoD:**
- [ ] Unchecked tasks block archiving unless `--incomplete "<reason>"`; on override, tasks → backlog, reason → header + progress, spec → `specs/done/`.
- [ ] tests pass · shellcheck clean.

<!-- mb-task:8 -->
## Task 8: Native-only invariant guard

**Covers:** REQ-024
**Role:** qa

**What to do:**
- Add a test asserting the Phase-1 implementation introduces **no** OpenSpec runtime dependency: no network call, no `openspec` CLI invocation, no new runtime service — every new capability is pure shell/Python over local files.

**Testing (TDD — tests BEFORE implementation):**
- Grep/behavioral guard: the new/changed scripts contain no `openspec` binary call and no outbound network in the validate/sdd/archive paths (REQ-024).
- Offline run: full validate + sdd + archive succeed with no network available.

**DoD:**
- [ ] A committed test fails if any Phase-1 path gains an OpenSpec-runtime or network dependency.
- [ ] tests pass · shellcheck + ruff clean.

<!-- mb-task:9 -->
## Task 9: [DEFERRED — Phase 2] Living capability specs + change-spec deltas

**Covers:** REQ-021, REQ-022, REQ-023
**Role:** architect

**Status:** DEFERRED pending its own `/mb discuss` (design.md § Phase 2, decision D-10). Do NOT
implement inside Phase 1. This task exists so REQ-021/022/023 are tracked, not orphaned.

**Scope when unfrozen:**
- `specs/system/<capability>.md` as living truth (REQ-021).
- Change specs with ADDED/MODIFIED/REMOVED requirement sections validated as deltas against the living spec (REQ-022).
- `/mb done` merges deltas into living specs before archiving the change spec (REQ-023).

**Precondition:** run `/mb discuss sdd-openspec-parity-phase2` first; the delta format must stay
forward-compatible with the iceboxed donor `REQ-OSA-010`. Phase 1's archive gate (Task 7) and
`specs/done/` layout are the substrate this builds on.

**Testing (TDD — tests BEFORE implementation):**
- Deferred — the delta-merge and living-spec tests are authored during the Phase 2 `/mb discuss`, TDD-first like every other task, before any Phase 2 code.

**DoD:**
- [ ] (deferred) — no work until Phase 2 is unfrozen by an explicit `/mb discuss`.
