---
description: End session — actualize core MB files, create a note, append to progress
allowed-tools: [Bash, Read, Edit, Write, Task]
---

Canonical session-end command. `/mb done` is an alias that dispatches here.

## 0. If work followed a plan — verify first

If an active plan exists in `.memory-bank/plans/` (not in `done/`), run `/verify` (or `/mb verify`) before proceeding. Do not close out without verification when a plan was in use. Fix CRITICAL issues; surface WARNINGs to the user.

## 1. Run MB Manager `action: done`

Invoke the MB Manager subagent (prompt: `~/.claude/skills/memory-bank/agents/mb-manager.md`) with `action: done`. Pass the full description of the current session's work as context.

`action: done` is a first-class 6-step flow (documented in the prompt). The subagent runs them in order:

1. **Actualize core files** — `checklist.md` (⬜→✅ + new items), `progress.md` (APPEND-ONLY entry), plus `status.md` / `research.md` / `lessons.md` / `backlog.md` / `roadmap.md` when the session genuinely changed them.
2. **Create a note** via `bash ~/.claude/skills/memory-bank/scripts/mb-note.sh "<topic>"` with YAML frontmatter (`type`, `tags`, `importance`, `created`) + "What was done" + "New knowledge" sections.
3. **Close a plan** (if the session ended one) via `bash ~/.claude/skills/memory-bank/scripts/mb-plan-done.sh .memory-bank/plans/<plan-file>.md` — flips `⬜→✅` in checklist, moves the file to `plans/done/`, clears the active-plan block.
4. **Prune checklist** — `bash ~/.claude/skills/memory-bank/scripts/mb-checklist-prune.sh --apply --mb .memory-bank` — collapses fully-✅ sections that link to `plans/done/` into one-liners. Enforces the ≤120-line hard cap declared in `checklist.md` header. Idempotent — safe to call when there is nothing to collapse.
5. **Touch `.memory-bank/.session-lock`** — signals the SessionEnd auto-capture hook that manual close happened.
6. **Regenerate `index.json`** via `python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py .memory-bank`.
7. **Report** — list which files changed, note path, plan closure, prune verdict, index regen, session-lock touch.

Conflict resolution (also in the prompt): trust `mb-metrics.sh --run` over `status.md` metrics; trust `checklist.md` over closed plans in `plans/done/`; `progress.md` is APPEND-ONLY; trust active plan file over `roadmap.md` focus line; trust `experiments/EXP-NNN.md` over `research.md` status.

## 2. Report

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
