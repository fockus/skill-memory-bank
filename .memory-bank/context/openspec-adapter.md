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

- **D-01** *(superseded by AGR-101 — see § Round-trip (AGR-101))*: One-way import (OpenSpec → MB). No write-back to OpenSpec. — Rationale: fast release; user accepted that `/mb work` progress and requirement edits live only in MB. Rejected: batch bidirectional export (round-trip is lossy — synthesized IDs would have to be pushed into or stripped from foreign `spec.md`); live watcher (heavy, contradicts "ship fast").
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
- Must not modify the OpenSpec tree (D-01, NFR-002) — import/sync only; export is governed by § Round-trip (AGR-101) Q3.
- Must work without the `openspec` binary installed (D-08).
- Format skeleton must stay deterministic even under `--normalize` (D-04).

**Out of scope (v1)**
- Export / write-back MB → OpenSpec (any direction reversal) — brought into scope by AGR-101, see § Round-trip (AGR-101).
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

- **OQ-1** *(answered by § Round-trip (AGR-101) Q1/Q5, pending owner confirmation)*: Re-import overwrites local edits to `requirements.md`/`design.md` (task-state is preserved). Should sync warn/diff before clobbering local requirement edits? Deferred — add a guard later if it bites in practice.
- **OQ-2**: Topic slug on import — default to the change-id slug, overridable via `import <change-id> --as <topic>`? (Recommended default: change-id slug.)
- **OQ-3**: Should `list`/`status` filter out archived changes (`changes/archive/**`)? (Recommended: yes, show active by default, `--all` to include archived.)
- **OQ-4**: RENAMED handling depth — auto re-anchor by FROM/TO is assumed (REQ-018); confirm no manual approval step is wanted.

## Round-trip (AGR-101)

Draft 2026-11-18 (master-completion Stage 8, track B). AGR-101 supersedes D-01: Memory Bank reads
an OpenSpec change in place, imports it, and writes our changes back, with a three-way sync that
reports conflicts and never overwrites silently. Every recommendation below waits for the owner's
answers in § Decisions for the owner; once confirmed, they are recorded as one AGR and become R-01…R-07.

### What the code does today (evidence)

- Capability is lost: `_parse_delta_spec` (`scripts/mb_openspec_parse.py:135-148`) never reads
  `spec_file.parent.name`, all capabilities are flattened into one list (`:235-236`), and
  `OSRequirement` has no capability field (`scripts/mb_openspec_model.py:27-35`).
- Delta kind is lost in the output: ADDED and MODIFIED render the same way (`scripts/mb_openspec_convert.py:437-440`);
  REMOVED is skipped (`:358-360`) and becomes design prose (`:487-495`); RENAMED on a first import
  is not emitted at all (`:372-383`, listed at `:497-508`).
- Requirement text is flattened to one line (`_flatten`, `scripts/mb_openspec_convert.py:66-68`, used at `:363`);
  lists, code blocks and paragraph breaks in an OpenSpec body cannot be rebuilt from our copy.
- Task `Covers`/`Role` are hardcoded (`scripts/mb_openspec_convert.py:529-530`); on re-import every non-checkbox line comes
  from the fresh render (`:261-264`), so a hand-set `Covers`/`Role` is lost.
- OpenSpec check-state is read once: after the first import, a matched task keeps our state
  (`scripts/mb_openspec_convert.py:267-269`) and a new task always arrives unchecked (`:239-241`, `:271`), so a tick made on the
  OpenSpec side is never picked up.
- Task ids exist only as text: `1.2 …` stays in the item text (golden `tests/pytest/fixtures/openspec/golden/add-metadata-tracking/tasks.md:11-13`)
  and merge keys on normalized full text (`scripts/mb_openspec_convert.py:249-257`), so editing a task's wording orphans it.
- Re-import rewrites `design.md` and `requirements.md` whole (`scripts/mb-openspec.py:331-344`), so local edits are
  overwritten (OQ-1, line 155 above); only the OpenSpec-side hash is stored (`scripts/mb-openspec.py:177-180`) and `sync` compares
  only that hash (`scripts/mb-openspec.py:534-538`).
- `proposal.md` contributes only `## Why` and `## What Changes` (`scripts/mb_openspec_parse.py:224-225`); other proposal
  sections are not imported.
- `/mb work` resolves only bank topics: Form 3 `specs/<topic>/tasks.md` (`scripts/mb-work-resolve.sh:242-252`),
  `declaration_candidates`/`resolve_spec_source` (`scripts/mb_work_source.py:16-18`, `:42-68`).
- `--normalize` cache lives under the git-ignored `.index/` (`scripts/mb_openspec_normalize.py:65-89`, `.gitignore:73-74`),
  so it is not shared between clones.

### Unit model (shared by Q1, Q4, Q5)

Sync and export work per **unit**, not per file. A unit is: a requirement `(cap, name)` with its
body, scenarios and kind; a removed or renamed delta entry; a task group `N` (title); a task item
`N.M` (text and checkbox as two separate fields); proposal `## Why`; proposal `## What Changes`; the
OpenSpec `design.md` as a whole. Bank-only content — `Covers`, `Role`, bank-added design sections,
task prose — is never exported and never overwritten by an import. For each unit the committed
sidecar `specs/<topic>/openspec-sync.json` stores `os` (hash of the raw OpenSpec unit) and `mb`
(hash of our rendering) as of the last sync. Requirements.md frontmatter keeps `openspec_source` and
`openspec_hash` as the discovery key and the fast no-op check.

### Q1. Conflict rule when both sides changed since the last sync

| Option | How it works | Data-loss risk |
|---|---|---|
| A. Whole-change hashes | Store `openspec_hash` + `mb_hash` per topic; one side moved → apply it; both moved → conflict | None, but a tick in `/mb work` plus any OpenSpec edit is a conflict, which will happen most of the time |
| **B. Per-unit three-way** | Per unit: only OpenSpec moved → take it; only ours → export candidate; both moved to the same value → converged; both moved differently → conflict. A checkbox is a boolean, so a three-way on it never conflicts | None while the sidecar is intact; a missing sidecar falls back to Q5 migration (reports conflicts) |
| C. Fixed winner (today's D-05) | OpenSpec wins text, bank wins check-state | Loses bank edits to requirements and design; breaks AGR-101 |

**Recommendation: B.** Any conflict makes the whole sync write nothing and exit 1 (all-or-nothing, as Stage 9 asks).
The report lists each conflicting unit with both texts. The user resolves by editing one side until
the units converge, or with an explicit `sync <topic> --take openspec|bank`. `sync` itself writes
only the bank; when our side is ahead it prints "run export". Reason: per-unit is the only rule that
lets everyday work (ticks here, prose there) merge without conflicts, and keeping `sync` bank-only
preserves the NFR-002 guarantee for the command `/mb work` runs automatically.

### Q2. REQ-IDs inside OpenSpec files

| Option | How it works | Data-loss risk |
|---|---|---|
| A. HTML comments | `<!-- mb: REQ-003 -->` under each `### Requirement:` | None, and an OpenSpec-side rename without a RENAMED delta keeps the ID. But `openspec archive` copies delta bodies into the living `openspec/specs/`, so our comments spread into their source of truth |
| **B. Strip** | Never write IDs; the requirement name stays the key; the map lives only in our anchors (`<!-- openspec-req: … -->`, `scripts/mb_openspec_convert.py:439`, D-06) | A rename made in OpenSpec without a RENAMED delta looks like remove plus add: the old REQ retires and a new ID is allocated. Text is kept; traceability links to the old ID break. Sync reports the pair as "anchor lost / new" |
| C. Map file in the change | `openspec/changes/<id>/.mb-map.json` | None; but it adds a foreign file to their tree, and archive carries it along |

**Recommendation: B.** The name is already OpenSpec's own stable key and our anchor. Their files stay
exactly what OpenSpec tools and teammates expect.

### Q3. Export scope and write guard

| Option | Scope | Data-loss risk |
|---|---|---|
| **A. One change dir, surgical** | Only `openspec/changes/<id>/` recorded in `openspec_source`; only `proposal.md`, `design.md`, `tasks.md`, `specs/<cap>/spec.md`; only changed units are spliced in, every other byte is kept | Lowest; unknown proposal sections and RENAMED blocks are never touched |
| B. One change dir, whole-file render | Same files, but re-rendered from the bank | High: drops sections we never imported, loses formatting through flattening, can't be byte-identical |
| C. Also update `openspec/specs/` | Writes the living spec | High; that is what `openspec archive` does; breaks D-02 |

**Recommendation: A.** Guard, in order:
1. The resolved change dir has parent `changes` and grandparent `openspec`, and no path component is `archive`.
2. Neither the change dir nor any target file is a symlink, and each target's realpath is inside the
   change dir (same checks as `_assert_within`/`_assert_topic_dir_not_symlink_escape`, `scripts/mb-openspec.py:108-138`).
3. Only the four relative paths above are written; `<cap>` passes the topic-slug validator.
4. No file deletes and no `.openspec.yaml`/`config.yaml` writes.
5. Default is a dry-run unified diff; `--write` applies through `atomic_write`.
6. If the OpenSpec hash moved since the last sync, export refuses and says "run sync first". No `--force` (see owner question 4).

Import and sync keep the rule that they write nothing outside `.memory-bank/`.

### Q4. What text goes back: raw or normalized

| Option | What is written | Data-loss risk |
|---|---|---|
| A. Raw only | Always the original OpenSpec text | Our requirement edits never go back; breaks AGR-101 |
| B. Bank text for every unit | Re-render everything from the bank | Flattened bodies and `--normalize` rewrites overwrite their wording; no byte identity |
| **C. Per unit** | An unchanged unit keeps OpenSpec's bytes untouched. A unit changed on our side goes back as the bank text the user wrote, scenarios rendered as `#### Scenario:` + `- **WHEN**/**THEN**`. The `mb` baseline is recorded after normalization, so an LLM rewrite never goes back unless the user then edits it | An edited requirement whose source body had several paragraphs or a list goes back as one paragraph (flatten, `scripts/mb_openspec_convert.py:66`). The dry-run diff shows it; nothing is written silently |

**Recommendation: C.** Raw text never has to be stored in the bank: when the OpenSpec unit has not
moved, the current OpenSpec file *is* the base. Import → export with no edits writes nothing, which
gives the Stage 9 byte-identical round-trip for free. A dry-run warning marks an edited requirement that came from
`--normalize`. Export uppercases nothing: a requirement without `SHALL`/`MUST` gets a warning, because OpenSpec's validator rejects
it (research digest, line 38).

### Q5. How import keeps capability, kind, raw body and task ids; migration

Marker format:

| Option | Format | Data-loss risk |
|---|---|---|
| A. Extend the anchor | `<!-- openspec-req: cap=…; kind=…; name=… -->` | Old anchors no longer match `_ANCHOR_AND_BULLET_RE` (`scripts/mb_openspec_convert.py:129-133`), so a re-import of an old topic would hand out new REQ-IDs |
| **B. Meta line before the anchor** | `<!-- openspec: cap=<cap>; kind=added\|modified\|removed\|renamed[; from=<name>] -->`, then the existing anchor, then the bullet (anchor→bullet adjacency unchanged) | None; old files still parse |
| C. Sidecar only | cap/kind only in `openspec-sync.json` | None, but invisible: a requirement added in the bank cannot declare its capability where it is written |

**Recommendation: B, plus the sidecar for hashes.**
- Parser: `OSRequirement` gains `capability`.
- Kind: kept as the source wrote it, even for a MODIFIED whose name is new locally.
- REMOVED: stays a "Removed scope" entry in our `design.md` with the same meta line before its `### <name>`.
- RENAMED: a unit our side never edits.
- Raw body: not stored (see Q4); `os` hashes in the sidecar detect changes.
- Task ids: taken from the `N.M` prefix already in the item text. Merge keys on the id, falling back to text for lines without an id, so rewording a task no longer orphans it.
- `Covers`/`Role`: keep today's defaults on first import; after that they are bank-only and keep their bank value.

Migration of existing imports:

| Option | How | Data-loss risk |
|---|---|---|
| A. Plain re-import (plan text) | First sync with new code regenerates everything | Overwrites local edits once (exactly OQ-1) |
| **B. Adopt baseline** | No sidecar → render the current OpenSpec change and compare per unit with the bank. Equal → baseline. Different and stored `openspec_hash` equals current → our edit (kept, export candidate). Different and the hash moved → conflict (who changed it can't be known). Write meta lines and sidecar only when there is no conflict | None |
| C. Explicit `migrate` command | User runs it once | None, but another verb, and an old topic stays half-supported until someone runs it |

**Recommendation: B.** It runs inside `sync`/`import` with no new verb and never guesses a winner.

### Q6. `/mb work` over an OpenSpec change id

| Option | Flow | Data-loss risk |
|---|---|---|
| **A. Sync, work on the triple, dry-run export at the end** | `mb-openspec.sh resolve <id\|openspec/changes/<id>> --mb <bank>` imports when new and syncs otherwise, then prints the bank `tasks.md`. `mb-work-resolve.sh` calls it for that target form. A sync conflict stops `/mb work` with the report. At the end of the run, `/mb work` shows `export <topic>` as a dry-run diff and asks before `--write` | None; the work never runs on a stale triple, and OpenSpec is written only after the user says yes |
| B. Require an explicit import first | Resolver fails with "run `/mb openspec import`" | None; one extra step every time |
| C. Run in place on OpenSpec files | Teach `/mb work` the OpenSpec format | None, but a second task format in the loop; `mb-task` markers, `Covers` and `Role` don't exist there |

**Recommendation: A.**
- The import/sync side effect lives in the OpenSpec module, not in the resolver's parsing.
- `mb_work_source.py` needs no change, because the target becomes a normal bank topic.
- Name clash: if `specs/<id>/` exists and its `openspec_source` points elsewhere, or it has none, the resolver exits 1 and asks for `--as`/a path.
- The OpenSpec root is the project root, the bank's parent for a local bank. Today `list` uses cwd (`--openspec .`, `scripts/mb-openspec.py:566-568`).

### Q7. `export --new` for a spec written in the bank

| Option | Result | Data-loss risk |
|---|---|---|
| **A. Project into a new change** | `export --new <topic> [--id <id>] [--cap <cap>]` creates `openspec/changes/<id>/`. `proposal.md` gets Why and What Changes from our `design.md`. `specs/<cap>/spec.md` gets every REQ as ADDED: name = the group title, with ` <k>` added when the group has more than one REQ. `tasks.md` gets one `## N.` group per `mb-task` and its checkboxes as `N.M`. Then it writes `openspec_source`, meta lines and the sidecar, so the topic round-trips from then on | None in the bank (it stays the full source); OpenSpec gets a projection without `Covers`/`Role`/`Files`/prose |
| B. Defer | No `--new` until a user asks | None |
| C. Write a living spec | `openspec/specs/<cap>/` | Bypasses OpenSpec's change/archive flow; breaks D-02 |

**Recommendation: A, with guards.** It refuses when `openspec/changes/<id>` exists, and when `openspec/` is
missing (no `openspec init` emulation). It is a dry-run unless `--write`, and the default `--cap` is the topic.
It is in plan Stage 9 and costs little once the per-unit renderer exists.

### Decisions for the owner

1. Conflict rule: per-unit three-way (B), all-or-nothing write on any conflict, resolved by converging edits or `sync --take openspec|bank`? **Recommended: yes.** Alternative: whole-change hashes (A).
2. `sync` writes only the bank and only prints "run export" when our side is ahead; only `export --write` touches OpenSpec? **Recommended: yes.**
3. REQ-IDs in OpenSpec files: strip (B) / HTML comments (A) / map file (C)? **Recommended: strip.**
4. Drop `--force` on export (refuse on OpenSpec drift and point to `sync`)? **Recommended: yes**; the plan text lists `--force`.
5. Text going back: per unit; unchanged units keep OpenSpec bytes, edited units send the bank text, and `--normalize` text goes back only after a user edit (C)? **Recommended: yes.**
6. Import markers: meta line `<!-- openspec: cap=…; kind=… -->` before the existing anchor, plus committed `specs/<topic>/openspec-sync.json` for per-unit hashes? **Recommended: yes.** Alternative: git-ignored sidecar under `.index/`, which gives false conflicts on a fresh clone.
7. Task identity keyed on the `N.M` id, with a text fallback, and `Covers`/`Role` treated as bank-only after first import? **Recommended: yes.**
8. Migration of existing imports: adopt baseline inside `sync` (B) / plain re-import (A) / explicit `migrate` (C)? **Recommended: adopt baseline.**
9. A bank-side deletion of an imported requirement or task: show it in the dry-run, but write it to OpenSpec only with `export --allow-delete`? **Recommended: yes.**
10. `/mb work <change-id>`: import-or-sync first, stop on conflict, dry-run export at the end and ask before `--write` (A)? **Recommended: yes.**
11. `export --new` in Stage 9 with the guards above (A), or defer (B)? **Recommended: A.**
