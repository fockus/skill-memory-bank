# Spec-driven development (SDD)

For a fuzzy idea or a small fix, [`/mb plan`](../first-feature.md) is enough.
For a multi-sprint feature, a cross-cutting refactor, or a new subsystem,
Memory Bank offers a spec-driven path: a structured interview produces
EARS-validated requirements, requirements graduate into a Kiro-style spec
triple, and the spec's `tasks.md` becomes an executable work queue that
`/mb work` runs item by item.

```
/mb discuss <topic>     requirements interview → context/<topic>.md (EARS)
/mb sdd <topic>         spec triple → specs/<topic>/{requirements,design,tasks}.md
/mb work <topic>        execute tasks.md, one <!-- mb-task:N --> block at a time
/mb verify              audit code against the spec
/mb done                actualize + note + progress
```

## Step 1 — `/mb discuss <topic>`: the requirements interview

`/mb discuss` runs a 5-phase interview that turns a fuzzy idea into an
EARS-validated `context/<topic>.md`. Before asking anything, it gathers a
**research digest** — existing `roadmap.md`/`research.md`, a codebase
recon (code graph or semantic search) for exact `file:line` touchpoints, and
prior decisions via `/mb recall`. Every recommendation in the interview must
cite that digest or the code; a recommendation without a citation is flagged
as a guess.

The 5 phases are a coverage checklist, not a rigid script:

1. **Purpose & users** — who uses this, what problem it solves, what success
   looks like.
2. **Functional requirements (EARS-enforced)** — each requirement is written
   in one of five patterns and assigned the next `REQ-NNN` ID
   (`mb-req-next-id.sh`, per-spec-local numbering):

   | Pattern | Template |
   |---|---|
   | Ubiquitous | `The <system> shall <response>` |
   | Event-driven | `When <trigger>, the <system> shall <response>` |
   | State-driven | `While <state>, the <system> shall <response>` |
   | Optional | `Where <feature>, the <system> shall <response>` |
   | Unwanted | `If <trigger>, then the <system> shall <response>` |

   Drafts are validated with `mb-ears-validate.sh` before moving on.
3. **Non-functional requirements** — performance, security, scale,
   observability, captured as free-form `NFR-NNN` entries.
4. **Constraints + out-of-scope** — hard constraints and explicit exclusions,
   to keep planning from scope-creeping later.
5. **Edge cases & failure modes** — concrete boundary scenarios, not abstract
   "any edge cases?" questions.

Throughout, the interviewer keeps a running **Decision Log** (decision →
rationale → alternatives rejected) and an **Open Questions** list; nothing
gets dropped because a branch ran long. Before writing the file, it presents
a numbered summary of every decision and requires explicit confirmation.

The result: `context/<topic>.md`, EARS-valid, with the research digest,
decision log, and open questions all in one place — traceable input for
planning.

## Step 2 — `/mb sdd <topic>`: the spec triple

`/mb sdd <topic>` turns a discussed (or freshly started) topic into
`specs/<topic>/` with three files, each with one concern:

- **`requirements.md`** — hybrid format: a Kiro **User Story** per
  requirement (`As a <role>, I want <feature>, so that <benefit>`) with an
  `#### Acceptance Criteria` block of EARS `REQ-NNN` bullets underneath. If
  `context/<topic>.md` already exists, its EARS section is copied in
  verbatim — the author's job is just grouping bullets under user stories.
- **`design.md`** — Architecture (layering, data flow), Interfaces
  (Protocol/ABC definitions that anchor contract tests), Decisions
  (ADR-style: context → options → decision → rationale → consequences), and a
  Risks & mitigation table.
- **`tasks.md`** — numbered, checkbox-compatible work items, each covering one
  or more REQs.

Splitting into three lets requirements/design/tasks evolve at different
speeds, keeps `requirements.md` exportable to Kiro-compatible tooling as-is,
and lets `mb-traceability-gen.sh` pick up REQ-IDs automatically for the
REQ → Plan → Test matrix.

## `tasks.md` — executable, not a scaffold

Each task in `tasks.md` is wrapped in `<!-- mb-task:N -->` / `<!-- /mb-task:N -->`
HTML-comment markers:

```markdown
<!-- mb-task:1 -->
## 1. <task title>

**Covers:** REQ-NNN
**Role:** <implementer role>
**What:** <concrete actions>
**Testing:** <unit / integration tests>
**DoD:**
- [ ] concrete criterion
- [ ] tests pass
- [ ] lint clean
<!-- /mb-task:1 -->
```

`/mb work <topic>` parses these blocks as structured work items and executes
them in order — it is a first-class executable artifact, not scaffolding for
a human to retype into a plan. Run `mb-spec-validate.sh <topic>` after hand
edits to catch a malformed marker, a missing `Covers`/`DoD`/`Testing` field,
or an orphaned REQ-ID before `/mb work` runs.

## Step 3 — `/mb work <topic>` and beyond

`/mb work <topic>` resolves and runs `tasks.md` item by item through the
configured pipeline (implement → verify → done by default; review/judge are
opt-in). `/mb verify` then audits the resulting code against the spec's DoD
and REQ coverage, and `/mb done` closes the session — appending to
`progress.md`, actualizing `status.md`/`checklist.md`, and writing a note if
something worth remembering came out of it.

## When to reach for SDD instead of a plain plan

Use `/mb discuss` → `/mb sdd` when the work is large enough to need a
dedicated, reviewable requirements artifact — a multi-sprint feature, a
cross-cutting refactor, or a new subsystem. For a small fix, `/mb plan` alone
is enough; it can still read an existing `context/<topic>.md` via
`--context`, or refuse to proceed without one via `--sdd` strict mode.

See also: [Memory Bank Layout](memory-bank-layout.md) for what `specs/` and
`context/` are for in the wider bank, and [Your First Feature](../first-feature.md)
for the plain-plan equivalent of this same loop.
