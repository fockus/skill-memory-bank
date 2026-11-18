# /mb discuss — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `discuss <topic>` — 5-phase requirements-elicitation interview → EARS-validated `context/<topic>.md` (Phase 1 Purpose & Users / Phase 2 Functional EARS / Phase 3 Non-Functional / Phase 4 Constraints / Phase 5 Edge Cases). Feeds traceability matrix.
- `askme <topic>`, `ask_me <topic>` — **Alias for `discuss`** — same interview, easier to remember. Dispatch identically.

### discuss <topic>

Run a 5-phase requirements-elicitation interview that produces an EARS-validated `context/<topic>.md`. Feeds `mb-traceability-gen.sh` (REQ → Plan → Test matrix) and is read by `/mb plan` to link stages to requirements.

**Alias** for `/discuss` — dispatch to `commands/discuss.md` for the canonical workflow.

**Phases:**

1. **Purpose & Users** — who uses this, what problem, success criteria.
2. **Functional Requirements (EARS-enforced)** — assigns IDs via `mb-req-next-id.sh`; validates via `mb-ears-validate.sh`. Five EARS patterns: Ubiquitous (`The ... shall ...`), Event-driven (`When ..., the ... shall ...`), State-driven (`While ..., the ... shall ...`), Optional (`Where ..., the ... shall ...`), Unwanted (`If ..., then the ... shall ...`).
3. **Non-Functional Requirements** — performance, security, scale, observability (NFR-NNN, free-form).
4. **Constraints + Out-of-Scope** — hard limits + explicit exclusions.
5. **Edge Cases & Failure Modes** — boundary conditions, dependency failures.

**Pre-flight:**

- If `<mb>/context/<topic>.md` exists → ask `AskUserQuestion`: continue editing / overwrite / cancel.
- Warm context — read `roadmap.md`, `research.md`, `codebase/STACK.md`, `codebase/ARCHITECTURE.md` (best-effort, skip missing).

**Finalize:**

- Render `context/<topic>.md` per the template in `references/templates.md` ("Context (`context/<topic>.md`)" section).
- `bash "$SKILL_DIR"/scripts/mb-ears-validate.sh "$CONTEXT_FILE"` — must exit 0 before commit. On violations, fix in place and retry.
- `bash "$SKILL_DIR"/scripts/mb-traceability-gen.sh "$MB_PATH"` — regenerate matrix.
- Set frontmatter `status: ready`.

**Exit conditions:**

- Success — file exists, EARS-valid, traceability regenerated.
- Cancel mid-interview — leave `status: draft` so `/mb discuss` resumes later.
- Validation failure user can't fix — keep `status: draft` + surface violation list.

**Out of scope:**

- Does not create a plan (`/mb plan` does that, optionally reading `context/<topic>.md`).
- Does not edit `roadmap.md` / `status.md` directly.

**Related scripts:**

- `bash "$SKILL_DIR"/scripts/mb-req-next-id.sh [--spec <name>] [mb_path]` — emits the next `REQ-NNN`. Default: project-wide max+1 across `specs/*/requirements.md`, `specs/*/design.md`, `context/*.md`. With `--spec <name>`: per-spec-local max+1 scoped to `specs/<name>/{requirements,design}.md` + `context/<name>.md` (a brand-new spec starts at `REQ-001`).
- `bash "$SKILL_DIR"/scripts/mb-ears-validate.sh <file>|-` — exit 0 if every `- **REQ-NNN** ...` bullet matches an EARS pattern; exit 1 with violation list on stderr otherwise; exit 2 on usage error.

### askme <topic> (also ask_me)

**Alias** for `discuss` — dispatch to `### discuss` above / `commands/discuss.md`. Same interview, same artifacts; the name exists only to be easier to remember.
