---
topic: openspec-adapter
created: 2026-07-15
status: ready
---

# Context: openspec-adapter

## Purpose & Users

Let Memory Bank consume specs authored with the **OpenSpec** tool
(<https://github.com/Fission-AI/OpenSpec/>) without asking the team to abandon it.
A thin **import adapter** reads an OpenSpec `change` from disk, converts it into our
spec triple (`specs/<topic>/{requirements,design,tasks}.md`), and runs `/mb work` over
it. When the OpenSpec side changes, a re-import refreshes our copy while preserving
`/mb work` progress.

- **Users:** teams whose specs live in `openspec/` but who want the Memory Bank
  pipeline (`/mb work`, verify, review, traceability, session memory) on top.
- **Success (qualitative):** point the adapter at an existing OpenSpec repo, `import`
  a change, and `/mb work` executes it as if it had been authored natively — with a
  deterministic, byte-stable conversion and no writes back into the OpenSpec tree.

This is **not** `sdd-openspec-parity` (which natively re-implements OpenSpec's quality
features). This topic is a **format adapter** over the real OpenSpec files. It is also
distinct from the iceboxed donor v6.7.0 "OpenSpec runtime integration" (AGR-004).

## Sources

- S-01: OpenSpec repo — <https://github.com/Fission-AI/OpenSpec/> (on-disk format, CLI, validator).
- S-02: `.memory-bank/context/sdd-openspec-parity.md` — sibling native-parity topic (boundary).

## Research Digest

Each line = one fact + citation. Gathered Phase 0 (2026-07-15).

- OpenSpec two-tier: `openspec/specs/<capability>/spec.md` = living truth; `openspec/changes/<id>/` = delta proposals; `changes/archive/YYYY-MM-DD-<name>/` = archived — OpenSpec `docs/concepts.md`, `docs/cli.md`.
- Living spec.md: mandatory `## Purpose` + `## Requirements`; `### Requirement: <name>` body must contain SHALL/MUST; `#### Scenario: <name>` with `**WHEN**`/`**THEN**` bullets — `src/core/validation/constants.ts`, `schemas/spec-driven/schema.yaml`.
- OpenSpec requirements have **no IDs** — the `### Requirement:` name is the only stable key; RENAMED deltas carry FROM:/TO: — real archived `spec.md`.
- Change dir: `proposal.md` (`## Why`, `## What Changes`), `tasks.md`, optional `design.md`, delta specs `specs/<cap>/spec.md` with `## ADDED / MODIFIED / REMOVED / RENAMED Requirements` — `schemas/spec-driven/schema.yaml`.
- Deltas carry full text: ADDED = full new requirement; MODIFIED = full replacement text; REMOVED = name + `**Reason**` (+ `**Migration**`) — `schemas/spec-driven/schema.yaml`.
- tasks.md = checkboxes only: `- [ ] N.M <task>` under `## N. <Group>` numbered headings — `schemas/spec-driven/templates/tasks.md`.
- No repo-wide JSON index/manifest; state derived by scanning files. Root `openspec/config.yaml` — `docs/cli.md`, `src/core/config.ts`.
- `openspec validate [--strict --json]`; hard errors = missing SHALL, missing scenarios, empty `## Why` — `src/core/validation/constants.ts`.
- **Our** scenario parser `scripts/mb-scenario-extract.py:52-56` matches `^#{1,6}\s*Scenario:` and `**WHEN**`/`**THEN**` bullets (optional `**`, GIVEN optional) → OpenSpec scenarios import ≈ verbatim.
- **Our** tasks format = `<!-- mb-task:N -->` + `## Task N:` + `**Covers:** REQ-…` + `**Role:**` — `.memory-bank/specs/adapter-parity/tasks.md`.
- **Our** requirements = `- **REQ-NNN** (pattern): …` bullets with per-spec-local IDs — `scripts/mb-req-id.py`, `scripts/mb-req-next-id.sh`.
- Reusable deterministic tooling already present: `mb-scenario-extract.py`, `mb-req-next-id.sh`, `mb-ears-validate.sh`, `mb-spec-validate.sh`, `mb-traceability-gen.sh`.

## Decision Log

- **D-01**: One-way import (OpenSpec → MB). No write-back to OpenSpec. — Rationale: fast release; user accepted that `/mb work` progress and requirement edits live only in MB. Rejected: batch bidirectional export (round-trip is lossy — synthesized IDs would have to be pushed into or stripped from foreign `spec.md`); live watcher (heavy, contradicts "ship fast").
- **D-02**: Sync unit = one OpenSpec `change` → one MB spec triple. Living `specs/` are read-only context only. — Rationale: a change (proposal + deltas + tasks) maps 1:1 onto our triple and *is* executable work; a living capability spec has no tasks — nothing for `/mb work` to run. Rejected: living-spec-as-unit (no tasks); support both (double the conversion + sync code in v1).
- **D-03**: Deterministic core converter runs always; optional `--normalize` adds an LLM pass, cached by source-hash, that (a) rewrites prose-SHALL into strict EARS and (b) fills gaps (missing scenario, pattern classification, `Covers` links). — Rationale: core ships the MVP immediately; LLM is a quality booster, not a dependency. Rejected: LLM-always (tokens + slow + unstable re-import); LLM as a later slice (user wants the option from release one).
- **D-04**: The output format is a rigid deterministic **skeleton**; the LLM only fills **text slots** inside it, and each slot is frozen by the hash of its source requirement. Same source ⇒ same slot (from cache); changed source ⇒ only that slot regenerates. — Rationale: "deterministic по формату" — structure (headers, `- **REQ-NNN**`, `<!-- mb-task:N -->`, section order) is 100% template-driven and never LLM-generated, so re-import stays stable even with `--normalize`. Rejected: LLM generating structure (non-deterministic format, unstable re-import).
- **D-05**: Re-import refreshes `requirements.md`/`design.md` from source; `tasks.md` keeps check-state matched by task text; new source tasks arrive unchecked; tasks that vanished from source move to `backlog.md`. — Rationale: preserves `/mb work` progress across upstream edits. Rejected: refuse-if-dirty (manual conflict every time); hard overwrite (loses progress mid-work).
- **D-06**: Each generated `REQ-NNN` is anchored to its OpenSpec requirement **name** via a hidden `<!-- openspec-req: <name> -->` marker. Re-import: same name → same ID; new name → next ID; missing name → REQ retired. — Rationale: the name is OpenSpec's own stable key (RENAMED deltas exist); enables both drift detection and task/galka preservation. Rejected: positional IDs (any insert/delete shifts everything → false diffs); body-hash anchor (any wording tweak looks like remove+add, breaks linkage).
- **D-07**: Delta import — `## ADDED` and `## MODIFIED` requirements (both carry full text) become `REQ-NNN` bullets; `## REMOVED` becomes an "Out of scope / removed" note in `design.md` with its reason. — Rationale: ADDED+MODIFIED are self-contained, so the change is executable without reading the living spec. Rejected: merge with living spec (drags in requirements the change doesn't touch — `/mb work` would "execute" already-done work); ADDED-only (drops MODIFIED work).
- **D-08** *(default, not grilled)*: Command surface `/mb openspec <import|sync|list|status>`; drift tracked via spec frontmatter `openspec_source: changes/<id>` + `openspec_hash: <sha>`; the adapter parses OpenSpec files directly and does **not** require the `openspec` CLI installed. — Rationale: no external binary dependency; deterministic file parsing. Rejected: shell out to `openspec` (adds an install requirement).
- **D-09** *(default, not grilled)*: `proposal.md ## Why` → our `## Why`; `## What Changes` + OpenSpec `design.md` sections (`## Context`, `## Decisions`, `## Risks`) → our `design.md`. — Rationale: preserves rationale/provenance in the natural target section. Rejected: drop proposal (loses "why").

## Functional Requirements (EARS)

### Requirement 1: Import an OpenSpec change

**User Story:** As a team using OpenSpec, I want to import a change into Memory Bank, so that `/mb work` can execute it natively.

#### Acceptance Criteria

- **REQ-001** (event-driven): When the user runs the OpenSpec import command for a change id, the system shall create a Memory Bank spec triple under `specs/<topic>/` from that change.
- **REQ-002** (ubiquitous): The system shall convert OpenSpec change artifacts into the Memory Bank format deterministically, producing a byte-stable skeleton for identical input.
- **REQ-003** (ubiquitous): The system shall not write to any file under the OpenSpec project directory.
- **REQ-004** (event-driven): When importing requirement deltas, the system shall map ADDED and MODIFIED requirements to REQ-NNN bullets and record REMOVED requirements as removed-scope notes with their reason.
- **REQ-005** (ubiquitous): The system shall anchor each generated REQ-NNN to its source OpenSpec requirement name via a hidden marker.

### Requirement 2: Deterministic format with optional LLM normalization

**User Story:** As a maintainer, I want the converted format to be stable regardless of the LLM, so that re-imports produce clean diffs.

#### Acceptance Criteria

- **REQ-006** (ubiquitous): The system shall generate the target format skeleton from a fixed template without LLM involvement.
- **REQ-007** (optional): Where the normalize flag is passed, the system shall run an LLM pass that rewrites requirement text into EARS patterns and fills missing scenarios and Covers links.
- **REQ-008** (event-driven): When the normalize pass produces a slot output, the system shall cache it keyed by the source requirement hash and reuse it while that source is unchanged.
- **REQ-009** (state-driven): While the normalize flag is not passed, the system shall fill LLM slots with deterministic fallbacks.
- **REQ-010** (unwanted): If the normalize pass is requested but the language model is unavailable, then the system shall fall back to deterministic slots and record a warning without aborting the import.

### Requirement 3: Scenario and task mapping

**User Story:** As a spec author, I want scenarios and tasks to carry over, so that acceptance and progress tracking work.

#### Acceptance Criteria

- **REQ-011** (event-driven): When importing OpenSpec scenarios, the system shall map each `#### Scenario` WHEN/THEN block to the Memory Bank scenario format.
- **REQ-012** (event-driven): When importing OpenSpec tasks, the system shall map each numbered task group to one mb-task carrying its checkbox items as the task checklist.
- **REQ-013** (unwanted): If an OpenSpec task line is not in checkbox form, then the system shall import it as plain checklist text under its group and record a warning.

### Requirement 4: Re-import and drift

**User Story:** As a user, I want to re-import when the OpenSpec side changes without losing my `/mb work` progress.

#### Acceptance Criteria

- **REQ-014** (ubiquitous): The system shall record the source change path and a content hash in the spec frontmatter.
- **REQ-015** (event-driven): When the user runs the OpenSpec sync command, the system shall re-import only specs whose stored source hash differs from the current source.
- **REQ-016** (event-driven): When re-importing a change, the system shall refresh requirements and design from source while preserving existing task check-state matched by task text.
- **REQ-017** (event-driven): When re-import finds tasks absent from source that were previously imported, the system shall move them to the backlog rather than deleting them silently.
- **REQ-018** (event-driven): When an OpenSpec RENAMED delta is imported, the system shall move the REQ anchor from the old name to the new name and preserve the existing REQ-NNN and its task progress.

### Requirement 5: Discovery and validation

**User Story:** As a user, I want to see what OpenSpec changes exist and whether they imported cleanly.

#### Acceptance Criteria

- **REQ-019** (optional): Where an OpenSpec project is detected, the system shall list available changes and their import status.
- **REQ-020** (unwanted): If EARS validation of an imported requirement fails, then the system shall record a warning and continue rather than aborting the import.

## Non-Functional Requirements

- **NFR-001**: Deterministic core — identical OpenSpec input without `--normalize` yields byte-identical MB output. A regression fixture (sample OpenSpec change → expected triple) guards this.
- **NFR-002**: One-way safety — no file outside `.memory-bank/` is written by import/sync; enforced by a test asserting zero writes to the OpenSpec tree.
- **NFR-003**: `--normalize` LLM outputs are cached by source-requirement hash; unchanged requirements never regenerate.
- **NFR-004**: No new runtime dependency and no requirement to install the `openspec` CLI — parse files directly with the bash/python/jq the skill already ships.
- **NFR-005**: Reuse existing deterministic tooling (`mb-scenario-extract.py`, `mb-req-next-id.sh`, `mb-ears-validate.sh`, `mb-spec-validate.sh`, `mb-traceability-gen.sh`) rather than reimplementing.

## Constraints & Out of Scope

**Hard constraints**
- Must not modify the OpenSpec tree (D-01, NFR-002).
- Must work without the `openspec` binary installed (D-08).
- Format skeleton must stay deterministic even under `--normalize` (D-04).

**Out of scope (v1)**
- Export / write-back MB → OpenSpec (any direction reversal).
- Living capability spec (`openspec/specs/<cap>/spec.md`) as an executable unit — read-only context only.
- OpenSpec `config.yaml`, custom `schemas/`, and `openspec archive` write semantics.
- Background watcher / live continuous sync.
- Automatic conflict merge (re-import conflicts on requirement text are resolved by D-05: source wins for req/design, local wins for task-state).

## Edge Cases & Failure Modes

- **Requirement with zero scenarios** → import succeeds; deterministic empty scenario stub + warn; `--normalize` generates a scenario.
- **MODIFIED requirement with a name not present locally (first import)** → treated as ADDED (fresh REQ-NNN).
- **RENAMED delta (FROM/TO)** → re-anchor marker FROM→TO; REQ-NNN and task check-state preserved (REQ-018).
- **Two OpenSpec requirements with identical names** → disambiguate by appending an index to the anchor marker; warn.
- **A checked-done local task disappears from source on re-import** → moved to backlog with a note, never silently dropped (REQ-017).
- **OpenSpec requirement body has no SHALL/MUST (malformed vs their own validator)** → import verbatim, pattern = unknown, warn (REQ-020).
- **`--normalize` offline / LLM unavailable** → deterministic fallback slots + warn, import still succeeds (REQ-010).
- **Task line not in `- [ ]` form** → plain checklist text under the group, not tracked as mb-task checkbox; warn (REQ-013).
- **Local manual edits to imported requirements.md on re-import** → overwritten from source (task-state preserved) — accepted cost of the one-way contract; see OQ-1.

## Open Questions

- **OQ-1**: Re-import overwrites local edits to `requirements.md`/`design.md` (task-state is preserved). Should sync warn/diff before clobbering local requirement edits? Deferred — add a guard later if it bites in practice.
- **OQ-2**: Topic slug on import — default to the change-id slug, overridable via `import <change-id> --as <topic>`? (Recommended default: change-id slug.)
- **OQ-3**: Should `list`/`status` filter out archived changes (`changes/archive/**`)? (Recommended: yes, show active by default, `--all` to include archived.)
- **OQ-4**: RENAMED handling depth — auto re-anchor by FROM/TO is assumed (REQ-018); confirm no manual approval step is wanted.
