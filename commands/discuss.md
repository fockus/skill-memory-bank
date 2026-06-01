---
description: 5-phase requirements-elicitation interview that produces an EARS-validated context/<topic>.md
allowed-tools: [Bash, Read, Write, AskUserQuestion]
---

# /mb discuss <topic>

Run a structured 5-phase interview that turns a fuzzy idea into an EARS-validated `context/<topic>.md`. The output feeds `mb-traceability-gen.sh` REQ → Plan → Test matrix and is read by `/mb plan` to link stages to requirements.

## When to use

Before creating a non-trivial plan (`/mb plan feature/refactor/...`). Skip for trivial fixes — the overhead isn't justified.

## Arguments

- `<topic>` — short slug (kebab-case). Becomes the filename: `.memory-bank/context/<topic>.md`.

## Workflow

### Pre-flight

1. Resolve `MB_PATH = .memory-bank/`. Refuse if missing (suggest `/mb init`).
2. Compute `CONTEXT_FILE = $MB_PATH/context/<topic>.md`.
3. If `CONTEXT_FILE` exists → ask `AskUserQuestion`: continue editing / overwrite / cancel.
4. Warm context — read these (best-effort, skip if missing):
   - `roadmap.md` (current direction)
   - `research.md` (active hypotheses)
   - `codebase/STACK.md`, `codebase/ARCHITECTURE.md` (technical reality)

### 5 phases — one question at a time

After each phase, restate what was captured and ask the user to confirm before moving on.

#### Phase 1 — Purpose & Users

- Who uses this?
- What problem does it solve for them?
- How will we know it's a success (qualitatively)?

#### Phase 2 — Functional Requirements (EARS-enforced)

For each requirement, pick one of the 5 patterns and assign the next ID via `bash $SKILL_DIR/scripts/mb-req-next-id.sh --spec <topic> "$MB_PATH"` (per-spec-local: the topic owns its REQ namespace, so a brand-new topic starts at `REQ-001` regardless of other specs):

| Pattern | Template |
|---|---|
| Ubiquitous | `The <system> shall <response>` |
| Event-driven | `When <trigger>, the <system> shall <response>` |
| State-driven | `While <state>, the <system> shall <response>` |
| Optional | `Where <feature>, the <system> shall <response>` |
| Unwanted | `If <trigger>, then the <system> shall <response>` |

After all REQs are drafted, run the validator on the in-memory draft:

```bash
echo "$DRAFT_REQ_BLOCK" | bash $SKILL_DIR/scripts/mb-ears-validate.sh -
```

If exit ≠ 0, surface every violation back to the user and re-prompt for that specific REQ.

#### Phase 3 — Non-Functional Requirements

Performance, security, scale, observability. Capture as `**NFR-NNN**: <description>` (free-form, no EARS enforcement).

#### Phase 4 — Constraints + Out-of-Scope

- Hard constraints (regulatory, technical, organizational).
- Explicit exclusions — prevents scope creep at planning time.

#### Phase 5 — Edge Cases & Failure Modes

What breaks at boundaries? What happens when dependencies fail? What's the worst-case input?

### Write & finalize

1. Render `context/<topic>.md` using the template in `references/templates.md` (`## Context (context/<topic>.md)` section).
2. Run `bash scripts/mb-ears-validate.sh "$CONTEXT_FILE"`. If it fails, fix in place and retry — do not commit invalid state.
3. Run `bash scripts/mb-traceability-gen.sh "$MB_PATH"` so the matrix picks up new REQs.
4. Update frontmatter `status: ready`.

### Out of scope for this command

- Does not create a plan (`/mb plan` does that, optionally reading `context/<topic>.md`).
- Does not edit `roadmap.md` / `status.md` directly — those flip at `/mb plan` and `/mb done` time.

## Exit conditions

- Success: `context/<topic>.md` exists, EARS-valid, traceability regenerated.
- Cancel mid-interview: leave `status: draft` so `/mb discuss` can resume later.
- Validation failure that user can't fix: keep the file as `status: draft` and surface the violation list.

## Related

- `/mb plan <type> <topic>` — read `context/<topic>.md` to link stages to REQs.
- `/mb traceability-gen` — regenerate `traceability.md` after edits.
- `bash scripts/mb-req-next-id.sh --spec <topic>` — next per-spec-local REQ-NNN for this topic (omit `--spec` for a project-wide max+1).
- `bash scripts/mb-ears-validate.sh <file>|-` — validate REQ lines against the 5 EARS patterns.
