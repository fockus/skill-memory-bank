---
description: Regenerate traceability.md from specs + plans + tests
allowed-tools: [Bash, Read]
---

# /mb traceability-gen

Regenerate `.memory-bank/traceability.md` — the REQ → Plan → Test coverage matrix.

## What it does

Scans:
- `.memory-bank/specs/*/requirements.md` for `REQ-NNN` definitions
- `.memory-bank/plans/*.md` + `plans/done/*.md` for:
  - `covers_requirements: [REQ-NNN, ...]` frontmatter field
  - `<!-- covers: REQ-NNN -->` inline markers
- `tests/` (repo root) and `.memory-bank/tests/` for `REQ_NNN` / `REQ-NNN` substrings

Produces a full-overwrite `traceability.md` with:
- Coverage summary (Total / Planned / Tested)
- Matrix table
- Orphans section (REQs in spec but no covering plan)

## Zero-spec fallback

If no `specs/*/requirements.md` exists, produces a minimal `traceability.md` saying
"No specs yet — run `/mb sdd <topic>` to create requirements." and exits 0.

## Usage

Run after adding requirements, wiring `covers_requirements:` in a plan, or adding REQ-NNN markers to tests. Also runs automatically at the end of `/mb plan` and `/mb done`.

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-traceability-gen.sh
```

## Exit codes

- `0` — success
- `1` — `.memory-bank/` not found
