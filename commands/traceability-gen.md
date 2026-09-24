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

## Skill bundle root

Every bundled helper below runs through the skill bundle root, never a bare `scripts/…` path (the
working directory is the user's project, where `scripts/` is absent or belongs to someone else):

```bash
SKILL_DIR="${MB_SKILLS_ROOT:-${SKILL_DIR:-$HOME/.claude/skills/memory-bank}}"
[ -f "$SKILL_DIR/scripts/_lib.sh" ] || { echo "mb: skill bundle not found at $SKILL_DIR — set MB_SKILLS_ROOT" >&2; exit 2; }
```

## Usage

Run after adding requirements, wiring `covers_requirements:` in a plan, or adding REQ-NNN markers to tests. Also runs automatically at the end of `/mb plan` and `/mb done`.

```bash
bash "$SKILL_DIR"/scripts/mb-traceability-gen.sh
```

## Exit codes

- `0` — success
- `1` — `.memory-bank/` not found
