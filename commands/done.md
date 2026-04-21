---
description: End session — actualize core MB files, create a note, append to progress
allowed-tools: [Bash, Read, Edit, Write, Task]
---

Canonical session-end command. `/mb done` is an alias that dispatches here.

## 0. If work followed a plan — verify first

If an active plan exists in `.memory-bank/plans/` (not in `done/`), run `/verify` (or `/mb verify`) before proceeding. Do not close out without verification when a plan was in use. Fix CRITICAL issues; surface WARNINGs to the user.

## 1. Actualize + note via MB Manager

Invoke the MB Manager subagent (prompt: `~/.claude/skills/memory-bank/agents/mb-manager.md`) with a combined flow of `action: actualize + action: note`. Pass the full description of the current session's work as context.

MB Manager must:

1. **Actualize `checklist.md`** — flip `⬜ → ✅` for completed tasks, add new `⬜` items for anything discovered during the session.
2. **Append to `progress.md`** (APPEND-ONLY — never edit old entries) — one block per session with a date header and 3-5 bullets on what was done, tests / coverage state, next step.
3. **Update `STATUS.md`** — only if a stage / milestone completed or key metrics shifted.
4. **Update `RESEARCH.md`** — only if an ML / experiment result landed.
5. **Update `lessons.md`** — only if an anti-pattern or repeated mistake was noticed this session.
6. **Update `BACKLOG.md`** — only if a new idea or ADR appeared.
7. **Create a note** in `notes/YYYY-MM-DD_HH-MM_<topic>.md` via `bash ~/.claude/skills/memory-bank/scripts/mb-note.sh "<topic>"`. Fill with YAML frontmatter (`type`, `tags`, `importance`, `created`) + "What was done" + "New knowledge" sections per `references/templates.md`. Notes are 5-15 lines, knowledge-focused, not chronology.
8. **Regenerate `index.json`**:
   ```bash
   python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py .memory-bank
   ```

## 2. If a plan completed — close it

```bash
bash ~/.claude/skills/memory-bank/scripts/mb-plan-done.sh .memory-bank/plans/<plan-file>.md
```

The script flips all `⬜ → ✅` in the plan's stage sections of `checklist.md`, moves the plan file to `plans/done/`, and clears the `<!-- mb-active-plan -->` block in `plan.md`.

## 3. Mark session lock

```bash
touch .memory-bank/.session-lock
```

This marks manual `/done` as completed so SessionEnd auto-capture hooks (`hooks/session-end-autosave.sh`, governed by `MB_AUTO_CAPTURE`) will skip writing a duplicate placeholder entry to `progress.md` for this session.

## 4. Report

Return a compact summary:

- Files updated (checklist / progress / STATUS / RESEARCH / lessons / BACKLOG as applicable)
- Note path + frontmatter summary (type, tags, importance)
- Plan closure (which plan moved to `done/`, if any)
- `index.json` regeneration confirmation
- `.session-lock` touched

## Lightweight mode (without MB Manager)

If the user wants a quick close without subagent overhead — for trivial sessions with no plan, no metrics changes, and no architectural output — a minimal flow is acceptable:

1. Update `checklist.md` directly — flip completed items
2. Append a short `progress.md` entry
3. `touch .memory-bank/.session-lock`

For anything non-trivial, default to the MB Manager flow above.
