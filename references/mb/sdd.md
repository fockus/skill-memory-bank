# /mb sdd — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `sdd <topic> [--force]` — Create Kiro-style spec triple `specs/<topic>/{requirements,design,tasks}.md`. If `context/<topic>.md` exists, EARS section copied verbatim into `requirements.md`. `--force` overwrites.

### sdd <topic> [--force]

Create the Kiro-style spec triple `specs/<topic>/{requirements,design,tasks}.md`. Each file owns one concern: requirements (EARS-only), design (architecture + interfaces + decisions), tasks (numbered checkboxes).

**Alias** for `/sdd` — dispatch to `commands/sdd.md` for the canonical workflow.

**Behavior:**

1. Resolve `<mb>`. Sanitize topic.
2. If `specs/<safe_topic>/` exists and no `--force` → exit 1.
3. If `<mb>/context/<safe_topic>.md` exists → copy its `## Functional Requirements (EARS)` block verbatim into `requirements.md` (REQ-IDs preserved).
4. Write `requirements.md` (EARS reference + REQ list), `design.md` (Architecture / Interfaces / Decisions / Risks scaffold), `tasks.md` (numbered tasks with `**Covers:** REQ-NNN` placeholders).

**Underlying:** `bash "$SKILL_DIR"/scripts/mb-sdd.sh <topic> [--force] [mb_path]`.

**Connection with `/mb plan`:** the spec triple is the *source of truth* for the topic. `/mb plan <type> <topic>` auto-detects `<mb>/context/<safe_topic>.md` (or accepts `--context <path>`) and adds a `## Linked context` section to the plan. `--sdd` flag in `/mb plan` enforces EARS validity before plan creation.

**Out of scope:**

- Does not run `/mb discuss`. If no context exists yet, `requirements.md` gets an EARS placeholder block.
- Does not validate REQ → task coverage (deferred to `/mb verify` and `/mb work` review-loop).
