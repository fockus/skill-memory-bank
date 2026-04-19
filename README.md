# claude-skill-memory-bank

Long-term project memory for Claude Code. Persists knowledge, rules, and development state across sessions. Gives Claude structured context about your project — status, plans, checklists, lessons learned — so every session starts where the last one left off.

## Prerequisites

- Python 3.12+
- `jq` (used by hooks)

## Install

```bash
git clone https://github.com/fockus/claude-skill-memory-bank.git ~/.claude/skills/claude-skill-memory-bank
cd ~/.claude/skills/claude-skill-memory-bank && chmod +x install.sh uninstall.sh && ./install.sh
```

## What Gets Installed

| Component | Count | Location |
|-----------|-------|----------|
| Global rules | 1 | `~/.claude/RULES.md` (TDD, SOLID, Clean Architecture) |
| CLAUDE.md section | 1 | Appended to `~/.claude/CLAUDE.md` |
| Commands | 19 | `~/.claude/commands/` |
| Agents | 4 | `~/.claude/agents/` |
| Hooks | 2 | `~/.claude/hooks/` |
| Settings hooks | 5 | Merged into `~/.claude/settings.json` |
| Skill data | — | `~/.claude/skills/memory-bank/` |

## Quick Start

```
# 1. Initialize memory bank in your project
/mb:setup-project

# 2. Start each session (loads context)
/mb start

# 3. End each session (saves progress)
/mb done
```

## Commands

| Command | Description |
|---------|-------------|
| `/mb` or `/mb context` | Load project context (status, checklist, plan) |
| `/mb start` | Extended session start (context + active plan) |
| `/mb done` | End session (update checklist, append progress, write note) |
| `/mb update` | Refresh core files (checklist, plan, status) |
| `/mb tasks` | Show incomplete tasks |
| `/mb search <query>` | Search memory bank by keywords |
| `/mb note <topic>` | Create a knowledge note |
| `/mb plan <type> <topic>` | Create plan (feature, fix, refactor, experiment) |
| `/mb verify` | Verify plan vs implementation (required before `/mb done` if working from a plan) |
| `/mb index` | Registry of all entries |
| `/mb init` | Initialize memory bank in a new project |
| `/commit` | Smart commit with conventional message |
| `/review` | Code review |
| `/test` | Run tests with coverage |
| `/plan` | Create implementation plan |
| `/doc` | Generate documentation |
| `/pr` | Create pull request |
| `/refactor` | Guided refactoring |
| `/security-review` | Security audit |
| `/catchup` | Catch up on recent changes |

## Memory Bank Structure

When initialized in a project (`.memory-bank/`):

| File | Purpose | Update frequency |
|------|---------|-----------------|
| `STATUS.md` | Where we are, roadmap, key metrics | On milestone completion |
| `checklist.md` | Current tasks (✅/⬜) | Every session |
| `plan.md` | Priorities, direction | When focus changes |
| `RESEARCH.md` | Hypotheses, findings, experiments | On hypothesis changes |
| `BACKLOG.md` | Ideas, ADRs, deferred items | When ideas arise |
| `progress.md` | Work done by date (append-only) | End of session |
| `lessons.md` | Recurring mistakes, anti-patterns | When patterns noticed |
| `notes/` | Knowledge notes (not chronology) | After completing tasks |
| `plans/` | Detailed implementation plans | Before complex work |
| `reports/` | Analysis reports | When useful for future |

## Agents

| Agent | Purpose |
|-------|---------|
| `mb-doctor` | Diagnose and repair memory bank issues |
| `mb-manager` | Automated memory bank updates (sonnet) |
| `plan-verifier` | Verify plan completion vs code |
| `mb-codebase-mapper` | Scan codebase, write structured MDs (STACK/ARCHITECTURE/CONVENTIONS/CONCERNS) to `.memory-bank/codebase/` — integrated with `/mb context` |

## Hooks

| Hook | Trigger | Purpose |
|------|---------|---------|
| `block-dangerous.sh` | PreToolUse (Bash) | Blocks `rm -rf /`, `DROP TABLE`, force push to main |
| `file-change-log.sh` | PostToolUse (Write/Edit) | Logs file changes, warns on secrets |

## Global Rules

The installed `RULES.md` enforces across all projects:
- **TDD** — tests first, then implementation
- **Clean Architecture** — Infrastructure → Application → Domain
- **SOLID** — SRP (≤300 lines), ISP (≤5 methods), DIP (constructor injection)
- **Testing Trophy** — integration > unit > e2e; mock only external services
- **Coverage** — 85%+ overall, 95%+ core, 70%+ infrastructure

## Uninstall

```bash
cd ~/.claude/skills/claude-skill-memory-bank && ./uninstall.sh
```

Removes all installed files, restores backups. Project `.memory-bank/` directories are not touched.

## License

MIT
