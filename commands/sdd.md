---
description: Create a Kiro-style spec triple — specs/<topic>/{requirements,design,tasks}.md
allowed-tools: [Bash, Read, Write]
---

# /mb sdd <topic>

Create a Kiro/Kilo-compatible spec triple under `.memory-bank/specs/<topic>/`. Each file has a single concern: **requirements** (EARS-only), **design** (architecture + interfaces + decisions), **tasks** (numbered checkbox work items).

## Why split into three?

- Parallel work — requirements / design / tasks evolve at different speeds.
- `requirements.md` stays self-contained and exportable to Kiro.
- `tasks.md` is checkbox-compatible with downstream tools.
- `mb-traceability-gen.sh` (Phase 1 Sprint 2) automatically picks up REQ-IDs from `specs/*/requirements.md` for the REQ → Plan → Test matrix.

## When to use

After `/mb discuss <topic>` produced an EARS-validated `context/<topic>.md`, when the work is large enough to need a dedicated spec triple (multi-sprint feature, cross-cutting refactor, new subsystem). For small fixes, `/mb plan` alone is enough.

## Arguments

- `<topic>` — short slug (kebab-case). Becomes the directory name `specs/<topic>/`.
- `--force` — overwrite existing spec triple. Without `--force`, the script refuses if `specs/<topic>/` already exists.

## Behavior

1. Resolve `<mb>` (skip if `.memory-bank/` is missing — suggest `/mb init`).
2. Sanitize topic to ASCII slug.
3. Refuse if `specs/<safe_topic>/` already exists and `--force` was not given.
4. Create `specs/<safe_topic>/` and write three files:
   - `requirements.md` — header + EARS reference + `## Requirements (EARS)` section. If `<mb>/context/<safe_topic>.md` exists, the `## Functional Requirements (EARS)` block is copied verbatim (REQ-IDs preserved).
   - `design.md` — Architecture / Interfaces / Decisions / Risks scaffold with a Protocol example.
   - `tasks.md` — numbered tasks with `**Covers:** REQ-NNN` placeholders and unchecked checkboxes.
5. Print the three created paths to stdout.

## Underlying script

```bash
bash scripts/mb-sdd.sh <topic> [--force] [mb_path]
```

## Typical flow

```
User: /mb discuss inventory-sync
→ produces context/inventory-sync.md (EARS-validated)

User: /mb sdd inventory-sync
→ writes:
  specs/inventory-sync/requirements.md   # EARS copied from context
  specs/inventory-sync/design.md         # blank design scaffold
  specs/inventory-sync/tasks.md          # numbered tasks scaffold

User: /mb plan feature inventory-sync --sdd
→ plan with `## Linked context` section pointing at context/inventory-sync.md
  (--sdd refuses to create plan unless EARS-valid context exists)

User: edits design.md / tasks.md by hand, then runs:
      /mb plan feature inventory-sync-stage-1 --sdd
→ next plan in the same Phase, also linked to the spec
```

## Out of scope

- Does not run `/mb discuss` — call that first if no context yet.
- Does not validate that every REQ in `requirements.md` has an implementing task — that's `/mb verify`'s job (or `/mb work` review-loop, Phase 3).
- Does not auto-generate `design.md` / `tasks.md` content — they start as scaffolds for the user to fill.

## Related

- `/mb discuss <topic>` — produces the EARS-validated context that feeds into `requirements.md`.
- `/mb plan <type> <topic> --context <path>` — create a plan that links to either the spec's requirements.md or directly to `context/<topic>.md`.
- `/mb plan <type> <topic> --sdd` — strict mode, refuses without an EARS-valid context.
- `/mb traceability-gen` — regenerate `traceability.md` after edits to `specs/*/requirements.md`.
- `bash scripts/mb-req-next-id.sh` — emit the next monotonic REQ-NNN.
- `bash scripts/mb-ears-validate.sh <file>|-` — verify REQ lines.
