# skill-memory-bank

[![test](https://github.com/fockus/skill-memory-bank/actions/workflows/test.yml/badge.svg)](https://github.com/fockus/skill-memory-bank/actions/workflows/test.yml)

Universal long-term project memory + dev toolkit for **8 AI coding clients**:
Claude Code, Cursor, Windsurf, Cline, Kilo, OpenCode, Codex, Pi Code.

Three-in-one skill:

1. **Long-term project memory** — `.memory-bank/` persists status, plans, checklists, lessons across sessions. Every session starts where the last one left off.
2. **Global development rules** — TDD, Clean Architecture (backend), Feature-Sliced Design (frontend), SOLID, Testing Trophy. Installed as `~/.claude/RULES.md` and referenced from every project.
3. **Dev toolkit** — 18 commands (`/mb`, `/commit`, `/review`, `/test`, `/plan`, `/pr`, `/adr`, `/contract`, `/security-review`, `/db-migration`, `/api-contract`, `/observability`, `/refactor`, `/doc`, `/changelog`, `/catchup`, `/start`, `/done`).

## Prerequisites

- Python 3.12+
- `jq` (used by hooks)

## Install

```bash
git clone https://github.com/fockus/skill-memory-bank.git ~/.claude/skills/skill-memory-bank
cd ~/.claude/skills/skill-memory-bank && chmod +x install.sh uninstall.sh && ./install.sh
```

## What Gets Installed

| Component | Count | Location |
|-----------|-------|----------|
| Global rules | 1 | `~/.claude/RULES.md` (TDD, SOLID, Clean Architecture, FSD for frontend) |
| CLAUDE.md section | 1 | Appended to `~/.claude/CLAUDE.md` |
| Commands | 18 | `~/.claude/commands/` |
| Agents | 4 | `~/.claude/agents/` |
| Hooks | 2 | `~/.claude/hooks/` |
| Settings hooks | 5 | Merged into `~/.claude/settings.json` |
| Skill data | — | `~/.claude/skills/memory-bank/` |

## Quick Start

```
# 1. Initialize memory bank in your project (auto-detects stack, generates CLAUDE.md)
/mb init

# or minimal (only .memory-bank/ structure)
/mb init --minimal

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
| `/mb init [--minimal\|--full]` | Init `.memory-bank/`. `--full` (default): + RULES + CLAUDE.md auto-gen. `--minimal`: structure only |
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
- **Clean Architecture (backend)** — Infrastructure → Application → Domain
- **FSD (frontend)** — Feature-Sliced Design: `app → pages → widgets → features → entities → shared`
- **Mobile (iOS/Android)** — UDF + Clean слои (View → ViewModel → UseCase → Repository → DataSource). iOS: SwiftUI + Observation + SwiftData. Android: Compose + StateFlow + Hilt + Room (Google Recommended Architecture)
- **SOLID** — SRP (≤300 lines), ISP (≤5 methods), DIP (constructor injection)
- **Testing Trophy** — integration > unit > e2e; mock only external services
- **Coverage** — 85%+ overall, 95%+ core, 70%+ infrastructure

## Coexistence with Native Claude Code Memory

Claude Code has its own built-in `auto memory` mechanism (cross-project user profile stored under `~/.claude/projects/.../memory/`). This skill does **not replace** it — they complement each other:

| Aspect | `.memory-bank/` (this skill) | Native `auto memory` |
|--------|------------------------------|----------------------|
| **Scope** | Project-specific | Cross-project, tied to user |
| **Content** | Status, plans, checklists, research, ADRs, lessons | User preferences, role, feedback patterns |
| **Stored in** | `.memory-bank/` in repo (commit it or gitignore) | `~/.claude/projects/.../memory/` (machine-local) |
| **Who owns it** | The project (team-shared via git) | The user (personal) |
| **When to use** | Anything about the project: goals, decisions, state, work-in-progress | Anything about how you like to work: style, tone, constraints |

**Rule of thumb**: if the information is useful to *a teammate picking up the project tomorrow* — it belongs in `.memory-bank/`. If it's useful for *you in a different project next week* — it belongs in native memory.

Both are loaded concurrently by Claude Code. Neither disables the other.

## Uninstall

```bash
cd ~/.claude/skills/skill-memory-bank && ./uninstall.sh
```

Removes all installed files, restores backups. Project `.memory-bank/` directories are not touched.

## License

MIT
