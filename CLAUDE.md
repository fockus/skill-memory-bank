# Memory Bank Skill

Long-term project memory via `.memory-bank/`. Rules enforcement, session lifecycle, codebase mapping.

## Rules

Before ANY work: read `~/.claude/RULES.md` + `.memory-bank/RULES.md`.
**RULES.md — hard requirement.**

## Workflow

**Start**: `/mb start` → read STATUS, checklist, plan, RESEARCH.
**Work**: update checklist immediately (⬜→✅). STATUS at milestones.
**End**: `/mb verify` (if plan) → `/mb done`.

## Commands

| Command | Description |
|---------|-------------|
| `/mb start` | Load project context |
| `/mb done` | Save progress, close session |
| `/mb verify` | Check plan vs implementation |
| `/mb init [--minimal\|--full]` | Init `.memory-bank/`. `--full` (default): + RULES + CLAUDE.md auto-gen |
| `/commit` | Smart commit |
| `/review` | Full code review |
| `/test` | Run tests + analysis |
| `/plan` | Create plan with DoD |
| `/contract` | Contract-First workflow |
