# Tasks: openspec-adapter

> Numbered, checkbox-tracked work items. Each task references the REQ-IDs it
> satisfies via the Covers field. Source: `context/openspec-adapter.md` (AGR-016).
>
> Dependency order: T1 (parser) gates T2 (converter); T2 gates T3 (write+safety);
> T3 gates T4 (CLI) and T5 (re-import); T6 (--normalize) needs T2's slot structure.
> Ship order = value order: T1–T3 = deterministic import MVP; T4 usability; T5
> re-import correctness; T6 opt-in LLM layer.
> Global invariant (NFR-001/002): the deterministic path is byte-stable for identical
> input and never writes outside `.memory-bank/` — T2 authors the golden fixture, T3
> the no-write guard; every later task keeps both green.

<!-- mb-task:1 -->
## Task 1: OpenSpec change parser (read-only)

**Covers:** REQ-004, REQ-011, REQ-012
**Role:** backend

**What to do:**
- Add `scripts/mb-openspec.py` with `parse_change(change_dir) -> OSChange` (dataclasses per design.md).
- Parse `proposal.md` (`## Why`, `## What Changes`), optional `design.md`, delta specs
  `specs/*/spec.md` (`## ADDED/MODIFIED/REMOVED/RENAMED Requirements` → `OSRequirement` with
  `change_kind`, `reason` for REMOVED, `#### Scenario` WHEN/THEN → `OSScenario`), and `tasks.md`
  (`## N. Group` + `- [ ] N.M` → `OSTaskGroup`).
- Compute `source_hash` = sha256 over the change's source files (stable ordering).
- Defensive: unknown/malformed markers → warn to stderr + skip, never crash.

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_openspec_parse.py`: a fixture OpenSpec change (real markers from the research
  digest) → asserts requirement names, change_kind per delta section, scenario steps, task groups
  with checkbox state, and a stable source_hash. Malformed spec → parsed with a warning, no exception.

**DoD:**
- [x] `parse_change` returns the full `OSChange` for the fixture; ADDED/MODIFIED/REMOVED/RENAMED all mapped.
- [x] Reads only — no writes anywhere (asserted).
- [x] tests pass
- [x] lint clean (ruff)

<!-- mb-task:2 -->
## Task 2: Deterministic converter (parsed → MB triple strings)

**Covers:** REQ-002, REQ-005, REQ-006, REQ-009, REQ-013, REQ-020
**Role:** backend

**What to do:**
- Add `convert(ch, prior_triple=None, normalize=False) -> (requirements_md, design_md, tasks_md)`.
- Requirements: fixed skeleton `### Requirement N: <name>` + `- **REQ-NNN** (pattern): <verbatim text>`
  with a `<!-- openspec-req: <name> -->` anchor. Auto-classify EARS pattern (default `ubiquitous`).
  Deterministic slot fallbacks when `normalize=False` (verbatim prose; empty scenario stub).
- Design: `## Why` (proposal Why), `## What Changes`, OpenSpec design.md sections, and a
  `## Removed scope` note per REMOVED requirement with its reason (D-07).
- Tasks: each `OSTaskGroup` → one `<!-- mb-task:N -->` + `## Task N:` with its `- [ ]` items as the
  checklist; `**Covers:**`/`**Role:**` deterministic defaults. Non-checkbox lines → plain text + warn
  (REQ-013).
- Run `mb-ears-validate.sh` in **warn mode** over the emitted requirements — record warnings, never
  abort (REQ-020).

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_openspec_convert.py`: fixture change → **golden** triple (committed expected
  output). Assert byte-identical (NFR-001) and idempotent on a second `convert` call. Anchor markers
  present per requirement. REMOVED → design note. Non-checkbox task → warning + plain text.

**DoD:**
- [x] Golden fixture matches byte-for-byte; second run identical (NFR-001).
- [x] Every REQ carries an `<!-- openspec-req: -->` anchor (REQ-005).
- [x] tests pass
- [x] lint clean

<!-- mb-task:3 -->
## Task 3: One-way writer + safety guard + drift frontmatter

**Covers:** REQ-001, REQ-003, REQ-014
**Role:** backend

**What to do:**
- Add the writer path: `import <change-id> [--as <topic>]` writes the triple under
  `specs/<topic>/` (topic default = change-id slug, OQ-2).
- Write frontmatter `openspec_source: <path to changes/<id>>` + `openspec_hash: <source_hash>`
  into requirements.md (REQ-014).
- Hard guard: assert every write path is under `.memory-bank/`; the OpenSpec tree is never opened
  for writing (REQ-003, NFR-002).

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_openspec_write.py`: `import` on the fixture creates the triple with the two
  frontmatter fields; a spy/guard asserts zero writes outside `.memory-bank/` (NFR-002); rerunning
  `import` on unchanged source is a no-op diff.

**DoD:**
- [x] Triple written under `specs/<topic>/`, frontmatter carries source + hash.
- [x] Zero writes outside `.memory-bank/` (asserted).
- [x] tests pass
- [x] lint clean

<!-- mb-task:4 -->
## Task 4: CLI dispatcher + list/status + router wiring

**Covers:** REQ-001, REQ-015, REQ-019
**Role:** backend

**What to do:**
- Add `scripts/mb-openspec.sh` dispatching `import | sync | list | status` to `mb-openspec.py`.
- `list`: detect an `openspec/` project, enumerate `changes/*` (skip `changes/archive/**` unless
  `--all`, OQ-3) with import status (imported / drifted / not-imported). `status`: same for one topic.
- `sync [<topic>]`: recompute source_hash, re-import only when it differs from `openspec_hash` (REQ-015).
- Wire `/mb openspec <sub>` into the `commands/mb.md` router table + a `### openspec` section.

**Testing (TDD — tests BEFORE implementation):**
- `tests/bats/test_mb_openspec.bats`: `list` on a fixture repo shows changes + status; `sync` is a
  no-op when the hash matches and re-imports when the source file changed; unknown subcommand → usage
  error, exit ≠ 0.

**DoD:**
- [~] `import`/`sync`/`list`/`status` reachable via `scripts/mb-openspec.sh`; `/mb openspec` router entry DEFERRED (commands/mb.md under adapter-parity FREEZE — lands when freeze lifts).
- [x] `sync` re-imports only on hash drift (REQ-015).
- [x] tests pass
- [x] shellcheck clean

<!-- mb-task:5 -->
## Task 5: Re-import — anchor matching + progress preservation

**Covers:** REQ-016, REQ-017, REQ-018
**Role:** backend

**What to do:**
- `anchor_map(prior_requirements_md)` → `{openspec-name: REQ-NNN}`; reuse the ID for the same name,
  allocate the next via `mb-req-next-id.sh --spec` for a new name (D-06).
- On re-import: regenerate requirements.md/design.md from source; run `merge_task_state()` to keep
  check-state by normalized task text; new source tasks arrive unchecked; tasks absent from source
  but previously imported → appended to `backlog.md` with a note (REQ-017), never silently dropped.
- RENAMED delta (FROM/TO): move the anchor FROM→TO, preserving REQ-NNN and its task galki (REQ-018).

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_openspec_reimport.py`: import → check a task → edit source requirement text →
  re-import → the checked task stays checked and the REQ keeps its ID (matched by anchor). A source
  task removed on re-import lands in backlog. A RENAMED delta moves the anchor and keeps the galka.

**DoD:**
- [x] Task check-state survives re-import (REQ-016); orphans → backlog (REQ-017); RENAMED re-anchors (REQ-018).
- [x] tests pass
- [x] lint clean

<!-- mb-task:6 -->
## Task 6: --normalize opt-in LLM slot layer + source-hash cache

**Covers:** REQ-007, REQ-008, REQ-010
**Role:** backend

**What to do:**
- Add `--normalize` to `import`/`sync`: dispatch a subagent that fills LLM slots (rewrite prose-SHALL
  into a strict EARS pattern, generate a missing `#### Scenario`, propose `Covers` links).
- Cache each slot output keyed by the source-requirement hash under `.memory-bank/.index/openspec/`;
  unchanged source → reuse cache, changed source → regenerate only that slot (D-04, REQ-008).
- Fail-open: if the LLM is unavailable, fall back to the deterministic slots + warn, import still
  succeeds (REQ-010).

**Testing (TDD — tests BEFORE implementation):**
- `tests/pytest/test_openspec_normalize.py` (LLM mocked): first run populates the cache; second run
  with identical source reuses it (no second call); a changed requirement regenerates only its slot;
  a simulated LLM-unavailable path falls back to deterministic slots + warning, exit 0.

**DoD:**
- [x] `--normalize` fills slots and caches by source-hash; unchanged reqs never regenerate (REQ-008).
- [x] LLM-unavailable falls back deterministically without failing the import (REQ-010).
- [x] tests pass
- [x] lint clean
