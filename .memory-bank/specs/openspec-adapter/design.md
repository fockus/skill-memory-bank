# Design: openspec-adapter

> Architecture, interfaces, and decisions backing requirements.md.
> Source of decisions: `context/openspec-adapter.md` (discuss of 2026-07-15, AGR-016).

## Architecture

Two new files, everything else reuses existing MB tooling (NFR-004/005):

- `scripts/mb-openspec.py` — the adapter core. Pure functions: **parse** an OpenSpec
  change dir → structured dict → **convert** → MB spec-triple strings. Also `list`/`status`/
  `sync` logic. Text-only, stdlib (mirrors `mb-import.py` / `mb-codegraph.py`).
- `scripts/mb-openspec.sh` — thin dispatcher (`import|sync|list|status`), like other `mb-*.sh`.
  Wired into the `commands/mb.md` router as `/mb openspec <sub>`.

Data flow (one-way, D-01):

```
openspec/changes/<id>/           mb-openspec.py                 .memory-bank/specs/<topic>/
  proposal.md      ─┐            ┌ parse_change() → dict ┐      ├ requirements.md  (REQ-NNN + anchors)
  design.md         ├─ read ──── │ convert() (skeleton)  │ ──── ├ design.md        (Why/Changes/REMOVED)
  tasks.md          │            │   + fill_slots()      │      └ tasks.md         (mb-task groups)
  specs/*/spec.md  ─┘            └ (opt) normalize()  ───┘        frontmatter: openspec_source+hash
```

The OpenSpec tree is **read-only** — the converter returns strings, only the MB writer touches disk,
and only under `.memory-bank/` (REQ-003, NFR-002). No `openspec` CLI dependency — files parsed
directly (D-08).

**Deterministic skeleton vs LLM slots (D-04):** `convert()` produces the full format skeleton
(headers, `- **REQ-NNN**`, `<!-- openspec-req: X -->`, `<!-- mb-task:N -->`, `**Covers:**`) with
deterministic slot fallbacks. `--normalize` swaps specific slots for LLM output, each cached by the
source-requirement hash so re-import stays stable.

## Interfaces

```python
# mb-openspec.py — core shapes (stdlib only)

@dataclass
class OSScenario:
    name: str
    steps: list[tuple[str, str]]   # [("WHEN", "..."), ("THEN", "...")]

@dataclass
class OSRequirement:
    name: str            # from "### Requirement: <name>" — the stable anchor key (D-06)
    text: str            # full prose-SHALL body
    change_kind: str     # "added" | "modified" | "removed"
    reason: str | None   # REMOVED only
    scenarios: list[OSScenario]

@dataclass
class OSTaskGroup:
    number: str          # "1", "2" from "## N. <Group>"
    title: str
    items: list[tuple[bool, str]]  # [(checked, "task text")]

@dataclass
class OSChange:
    change_id: str
    why: str             # proposal.md ## Why
    what_changes: str    # proposal.md ## What Changes
    design_md: str | None
    requirements: list[OSRequirement]
    task_groups: list[OSTaskGroup]
    source_hash: str     # sha256 over the change's source files (drift key, REQ-014)

def parse_change(change_dir: Path) -> OSChange: ...            # read-only
def convert(ch: OSChange, prior_triple, normalize: bool): ... # returns strings, no disk writes
def anchor_map(prior_requirements_md: str) -> dict[str, str]:  # name -> REQ-NNN (D-06)
def merge_task_state(new_tasks: str, prior_tasks: str):        # -> (merged_str, orphaned_task_lines)
```

Reused as-is (NFR-005): `mb-req-next-id.sh --spec` (REQ-ID allocation), `mb-ears-validate.sh`
(warn-mode, REQ-020), `mb-scenario-extract.py` (scenario format is already compatible — see the
research digest), `mb-sdd.sh` triple layout, `backlog.md` writer conventions.

## Decisions

See `context/openspec-adapter.md` § Decision Log (D-01…D-09) — the authoritative record. Design-level
consequences:

- **D-06 anchor** → `convert()` never trusts positional order; it reads `anchor_map()` from the prior
  requirements.md and reuses REQ-NNN by OpenSpec requirement name. New name → `mb-req-next-id.sh
  --spec openspec-adapter`. This single mechanism powers both drift detection and task-state
  preservation.
- **D-05 re-import** → requirements.md/design.md are regenerated from source; tasks.md goes through
  `merge_task_state()` (check-state by task text; orphans → backlog). Local req edits are overwritten
  (accepted one-way cost, OQ-1).
- **D-07 deltas** → ADDED+MODIFIED become REQ bullets; REMOVED becomes a design.md "Removed scope"
  note with its reason. Living `specs/` never read for execution (D-02).
- **AGR-105 round-trip groundwork** (master-completion Stage 8; full design in
  `context/openspec-adapter.md` § Round-trip): a `<!-- openspec: cap=…; kind=…[; from=…] -->` meta
  line precedes each anchor and each Removed-scope heading; RENAMED is emitted on the first import;
  tasks merge on the `N.M` id, then text; Covers/Role are bank-only after the first import.
  `mb_openspec_sync.py` keeps the committed `specs/<topic>/openspec-sync.json` sidecar: per unit
  (`req:<anchor>`, `removed:<name>`, `group:N`, `task:N.M` or `task:N:<text>`, `proposal:why`,
  `proposal:what-changes`, `design`) it stores `os`/`mb` SHA-256 hashes plus location fields
  (`cap`, `kind`, `name`, `from`) and task check-states, written before requirements.md. `sync`
  adopts a baseline when the sidecar is missing or unreadable and refuses a re-import that would
  overwrite bank units edited since the last sync. Export and three-way sync build on this (Stage 9).
- **AGR-105 export and three-way sync** (master-completion Stage 9; supersedes the D-05 bullet for
  requirements.md/design.md): every bank write after the first import is a per-unit three-way merge
  (`mb_openspec_merge.plan_sync`) against the sidecar baseline, applied by a per-unit splice
  (`mb_openspec_splice`) over shared unit spans (`mb_openspec_spans`), so bank-added sections, task
  prose and Covers/Role keep their bytes. Only-OpenSpec-moved units are taken, only-bank-moved units
  are export candidates, a differing double move is a conflict (nothing written, exit 1) unless
  `sync <topic> --take openspec|bank`; checkboxes merge as booleans. A re-`import` is the same merge
  (no `take`), allowed only for the change the topic is linked to; a missing or mismatched sidecar is replaced by a synthetic baseline
  (adoption). `export <topic>` (`mb_openspec_export`, text splicers in `mb_openspec_osfmt`) prints a
  diff of the bank's changed units and, with `--write`, splices only those into the change — after
  refusing an OpenSpec change that moved since the last sync, guarding every read and write to the
  four change files (no symlinks, no `archive/`, no `openspec/specs/`), and deleting only with
  `--allow-delete`. `export <topic> --new` (`mb_openspec_export_new`) projects a bank spec into a new
  change (built in a sibling temp dir, renamed into place, resumable) and links the topic. A batch
  `sync` writes nothing when any topic conflicts or errors; export re-checks OpenSpec and the bank
  right before writing (compare-and-swap). Every `import`/`sync`/`export` holds one
  bank lock (`flock` on `<bank>/specs`, reusing `mb_fs_atomic._dir_lock`) for the whole operation;
  a batch `sync` stages every file before renaming any (`mb_openspec_publish`). A requirement unit
  includes the shared `mb-scenario` blocks that cover it (sidecar format 2; a format-1 sidecar is
  re-adopted), and taking it from OpenSpec moves its scenarios inline. The CLI `mb-openspec.py` only parses arguments and owns the
  `atomic_write` seam; bank helpers live in `mb_openspec_bank`, import/sync in `mb_openspec_ops`.

## Risks & mitigation

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| OpenSpec format drift breaks the parser | M | M | Parse defensively; unknown markers → warn+skip, never crash; pin fixtures from the real repo |
| Non-deterministic `--normalize` corrupts re-import diffs | M | H | Slots frozen by source-hash cache (D-04); core path never calls the LLM |
| Accidental write into the OpenSpec tree | L | H | Converter returns strings only; NFR-002 test asserts zero writes outside `.memory-bank/` |
| Task-text drift loses check-state on re-import | M | M | Match on normalized task text; unmatched checked tasks → backlog (never silent drop, REQ-017) |
| Duplicate requirement names collide on the anchor | L | M | Append an index to the anchor marker + warn |
