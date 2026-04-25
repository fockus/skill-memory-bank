---
type: pattern
tags: [docs, memory-bank, codebase, /mb-init, /mb-map, onboarding]
related_features: []
sprint: null
importance: medium
created: 2026-04-21
---

# docs-codebase-folder-surfaced
Date: 2026-04-21

## What was done
- Surfaced `.memory-bank/codebase/` in 6 structural/workflow documents + `/mb init` flow + CHANGELOG
- Made sure `rules/CLAUDE-GLOBAL.md` and `rules/RULES.md` carry byte-identical table rows (both install into ~/.claude/)
- Added optional Step 1.5 to `/mb init --full` (default=skip) offering to seed `codebase/` via `mb-codebase-mapper` subagent

## New knowledge
- **Gap-surfacing refactor pattern:** when an existing feature (here: `/mb map` + `mb-context.sh` integration with `codebase/`) is fully implemented in code but invisible in user-facing docs, the fix is purely documentation — 8 files, ~+90 lines, zero code churn. Use mb-drift.sh as the consistency gate, not unit tests.
- **Byte-identical wording across the two installed rule files is mandatory** — `rules/CLAUDE-GLOBAL.md` (appended to `~/.claude/CLAUDE.md`) and `rules/RULES.md` (installed as `~/.claude/RULES.md`) describe the same structure; drift between them confuses agents working in different host contexts. Always `diff` the extracted rows before committing.
- **Bootstrap prompts must default to skip, never auto-invoke subagents.** The empty-`codebase/` hint suggests `/mb map` but the user owns the decision. Same pattern applies to any future "seed this folder" additions.
