# memory-bank-skill

[![test](https://github.com/fockus/skill-memory-bank/actions/workflows/test.yml/badge.svg)](https://github.com/fockus/skill-memory-bank/actions/workflows/test.yml)
[![PyPI](https://img.shields.io/pypi/v/memory-bank-skill?color=blue)](https://pypi.org/project/memory-bank-skill/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Long-term project memory + dev toolkit for 8 AI coding agents.** Your AI remembers the project between sessions, follows the same engineering rules, and picks up exactly where you left off.

Works with: **Claude Code · Cursor · Windsurf · Cline · Kilo · OpenCode · Codex · Pi Code**.

---

## The problem it solves

Every new AI coding session is amnesia. You re-explain the project, re-state the plan, re-list what's done. Rules get forgotten. Architecture drifts. Context compaction erases whatever the agent finally learned.

**memory-bank-skill** fixes this by making AI memory a first-class citizen — a simple `.memory-bank/` directory inside your project that the agent reads at the start of every session and updates as it works.

```
.memory-bank/
├── STATUS.md          ← where we are, what's next
├── checklist.md       ← current tasks (✅ / ⬜)
├── plan.md            ← priorities, direction
├── RESEARCH.md        ← hypotheses, experiments
├── progress.md        ← work log (append-only)
├── lessons.md         ← mistakes not to repeat
├── notes/             ← knowledge (5-15 line snippets)
├── plans/             ← detailed plans per feature/fix
└── reports/           ← analysis, post-mortems
```

This directory lives alongside your code (commit it, share it with your team, or `.gitignore` it — your call).

---

## Install

Pick one:

### Option 1: pipx (recommended, cross-platform)

```bash
pipx install memory-bank-skill           # stable
# or, for the latest release candidate:
pipx install --pip-args='--pre' memory-bank-skill

memory-bank install                      # global install for Claude Code
```

**Requires:** Python 3.11+, `pipx`, `jq`.

### Option 2: Homebrew (macOS / Linuxbrew)

```bash
brew tap fockus/tap
brew install memory-bank
memory-bank install
```

### Option 3: git clone (developers)

```bash
git clone https://github.com/fockus/skill-memory-bank.git ~/.claude/skills/skill-memory-bank
cd ~/.claude/skills/skill-memory-bank
./install.sh
```

### Add cross-agent support (Cursor, Windsurf, OpenCode, etc.)

```bash
# From inside your project directory:
memory-bank install --clients claude-code,cursor,windsurf
```

Supported client names: `claude-code`, `cursor`, `windsurf`, `cline`, `kilo`, `opencode`, `pi`, `codex`.

Full per-client details: [docs/cross-agent-setup.md](docs/cross-agent-setup.md).

---

## 5-minute quick start

1. **Install** (see above).

2. **Open your project** in your AI agent (Claude Code, Cursor, etc.) and run:

   ```
   /mb init
   ```

   This creates `.memory-bank/` with all the files above, detects your stack, and generates a `CLAUDE.md` (or equivalent) pointing the agent at the memory bank.

3. **Every session starts with:**

   ```
   /mb start
   ```

   The agent loads `STATUS.md`, `checklist.md`, `plan.md`, `RESEARCH.md` — it knows exactly what you were working on and what comes next.

4. **As you work:** the agent updates `checklist.md` (⬜ → ✅) whenever tasks finish.

5. **Every session ends with:**

   ```
   /mb done
   ```

   This appends a session entry to `progress.md`, updates `STATUS.md` if needed, writes a knowledge note if something interesting was learned.

That's it. Rinse and repeat.

---

## What you get

### 1. Persistent project memory

Across sessions, compaction events, and even across AI agents — the project state survives. Switch from Claude Code to Cursor mid-project and the new agent catches up by reading `.memory-bank/`.

### 2. Engineering rules applied automatically

Installs `~/.claude/RULES.md` (or equivalent per client) with:

- **TDD** — tests before implementation
- **Clean Architecture** (backend) — Infrastructure → Application → Domain, never the reverse
- **Feature-Sliced Design** (frontend) — `app → pages → widgets → features → entities → shared`
- **Mobile** (iOS/Android) — UDF + Clean layers, SwiftUI+Observation / Compose+StateFlow
- **SOLID** — SRP (≤300 LOC / class), ISP (≤5 methods / interface), DIP (constructor injection)
- **Testing Trophy** — integration > unit > e2e; mock only external services
- **Coverage** targets — 85% overall, 95% core, 70% infrastructure

The agent reads these rules at session start and follows them without you having to remind it.

### 3. 18 dev-workflow commands

| Command | Purpose |
|---------|---------|
| `/mb start` | Load full project context |
| `/mb done` | End-of-session actualize + progress note |
| `/mb verify` | Check that implementation matches the plan |
| `/mb plan <type> <topic>` | Create a detailed plan (feature / fix / refactor / experiment) with DoD criteria |
| `/mb search <query>` | Search across the memory bank |
| `/mb note <topic>` | Quick knowledge note |
| `/mb tasks` | Show pending work |
| `/mb update` | Refresh core files without closing the session |
| `/commit` | Conventional-commit message with context |
| `/review` | Full code review (security + perf + quality) |
| `/test` | Run tests with coverage analysis |
| `/plan` | Implementation plan generator |
| `/refactor` | Guided refactoring |
| `/pr` | Create pull request with description |
| `/adr` | Architecture Decision Record template |
| `/contract` | Contract-first workflow (Protocol/ABC → tests → impl) |
| `/security-review` | Security audit pass |
| `/api-contract` | API contract validation |
| `/db-migration` | Safe migration planning |
| `/observability` | Logging/metrics/tracing review |
| `/doc` | Generate documentation |
| `/changelog` | CHANGELOG update |
| `/catchup` | Summarize recent changes |

### 4. Cross-agent portability

One `.memory-bank/` directory, 8 AI clients:

| Client | Native hooks | Adapter output |
|--------|--------------|----------------|
| **Claude Code** | Full lifecycle | `~/.claude/settings.json` + `hooks/` |
| **Cursor 1.7+** | ✅ (Claude-Code-compatible format) | `.cursor/rules/*.mdc` + `.cursor/hooks.json` |
| **Windsurf** | ✅ Cascade Hooks | `.windsurf/rules/*.md` + `.windsurf/hooks.json` |
| **Cline** | ✅ `.clinerules/hooks/*.sh` | `.clinerules/memory-bank.md` + `hooks/` |
| **Kilo** | ❌ (fallback to git hooks) | `.kilocode/rules/` + `.git/hooks/` |
| **OpenCode** | ✅ TypeScript plugins | `AGENTS.md` + `opencode.json` + TS plugin |
| **Codex** (OpenAI) | ✅ Experimental | `AGENTS.md` + `.codex/config.toml` + `hooks.json` |
| **Pi Code** | Dual-mode (skill / AGENTS.md) | `~/.pi/skills/memory-bank/` or `AGENTS.md` |

`AGENTS.md` is shared across OpenCode, Codex, Pi — ownership is refcount-tracked, so uninstalling one client doesn't break the others.

---

## Usage examples

### Starting a new feature

```
You: /mb plan feature user-auth

Agent: [creates .memory-bank/plans/2026-04-20_feature_user-auth.md with DoD,
        test plan, stage breakdown, dependencies]

You: Now implement stage 1.

Agent: [reads plan, writes failing tests first (TDD), then implementation,
        runs tests, updates checklist ⬜ → ✅]

You: /mb verify

Agent: [plan-verifier agent checks that implementation matches plan DoD]

You: /mb done

Agent: [appends session summary to progress.md, updates STATUS.md if needed]
```

### Jumping into an existing project

```bash
cd some-legacy-project/
memory-bank install --clients cursor   # adds .cursor/ adapter

# In Cursor:
/mb init --full                         # auto-detect stack, generate CLAUDE.md
/mb start                               # load everything
```

### Sharing state with your team

`.memory-bank/` is just markdown. Commit it. Your colleague clones the repo, runs `/mb start`, and has the full project context without asking you a single question.

---

## CLI reference

After `pipx install memory-bank-skill`:

```bash
memory-bank install [--clients <list>] [--project-root <path>]
memory-bank uninstall
memory-bank init                    # prints /mb init hint
memory-bank version
memory-bank self-update             # prints `pipx upgrade ...`
memory-bank doctor                  # resolves bundle, platform info
memory-bank --help
```

Flags:
- `--clients <list>` — comma-separated. Valid: `claude-code, cursor, windsurf, cline, kilo, opencode, pi, codex`. Default: `claude-code` only.
- `--project-root <path>` — where to place client-specific adapters. Default: current directory.

---

## Environment variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `MB_AUTO_CAPTURE` | SessionEnd auto-capture mode: `auto` / `strict` / `off` | `auto` |
| `MB_COMPACT_REMIND` | Weekly `/mb compact` reminder: `auto` / `off` | `auto` |
| `MB_PI_MODE` | Pi adapter mode: `agents-md` / `skill` | `agents-md` |
| `MB_SKILL_BUNDLE` | Override bundle path (dev / testing) | auto-detected |
| `MB_SKIP_DEPS_CHECK` | Skip preflight dep check in `install.sh` | `0` |

---

## Platform support

| OS | Status |
|----|--------|
| macOS | ✅ Full |
| Linux | ✅ Full |
| Windows | ⚠️ WSL only (bash required) |

Running native Windows prints a WSL hint and exits. Use WSL: `wsl --install`, then install from inside WSL.

---

## FAQ

**Q: Do I need to commit `.memory-bank/` to git?**
A: Recommended if working in a team — that's how state is shared. Solo project: optional. Either way works.

**Q: Does this replace Claude Code's built-in memory?**
A: No — complementary. Native memory is per-user, cross-project (preferences, style). `.memory-bank/` is per-project, team-shared (status, plans, decisions). Both load simultaneously.

**Q: Will it work on private repositories?**
A: Yes. Everything is local. No data sent anywhere unless your AI agent itself calls external APIs (that's unchanged).

**Q: What if my team uses different AI agents?**
A: That's the whole point. Install per-client: `memory-bank install --clients cursor,windsurf,claude-code`. One memory bank, everyone reads it.

**Q: Cursor hooks are experimental / Codex hooks are experimental — is that a problem?**
A: Partial — where native hooks don't exist or aren't stable, we ship graceful fallbacks (git hooks for Kilo; `AGENTS.md` fallback for Pi). See [docs/cross-agent-setup.md](docs/cross-agent-setup.md) for specifics.

**Q: My existing `AGENTS.md` / `.cursor/hooks.json` — will this overwrite them?**
A: No. Adapters use a marker pattern (`<!-- memory-bank:start/end -->` for MD files, `_mb_owned: true` for JSON hooks) and merge idempotently. User content is preserved; uninstall only removes MB-owned sections.

**Q: How do I upgrade?**
A: `pipx upgrade memory-bank-skill` or `brew upgrade memory-bank`. Git-clone install: `cd ~/.claude/skills/skill-memory-bank && git pull && ./install.sh`.

**Q: I want to remove everything.**
A: `memory-bank uninstall` removes global install. Per-project adapters: `adapters/<client>.sh uninstall <project-dir>` (or drop the `.memory-bank/`, `.cursor/`, etc. directories manually).

**Q: Is this production-ready?**
A: Current version is a release candidate (`3.0.0-rc1`). Daily used on real projects. 461 automated tests green (bats + pytest). Stable API; rc only because we want 1-2 weeks of real-world usage before the stable tag.

---

## Documentation

- **[Cross-agent setup](docs/cross-agent-setup.md)** — per-client cheatsheet + hook capability matrix
- **[Install guide](docs/install.md)** — pipx / Homebrew / git-clone with troubleshooting
- **[Repository migration](docs/repo-migration.md)** — for users upgrading from `claude-skill-memory-bank`
- **[Release process](docs/release-process.md)** — PyPI OIDC setup + tag workflow
- **[CHANGELOG](CHANGELOG.md)** — version history

---

## Contributing

1. Fork & clone.
2. `./install.sh && /mb init` in the repo itself (this skill uses itself — meta but works).
3. Write tests first (TDD). `bats tests/bats/ tests/e2e/` + `python3 -m pytest tests/pytest/`.
4. Follow the rules in `rules/RULES.md` (the same ones the skill enforces on users).
5. Open a PR. CI runs on Python 3.11 + 3.12 × ubuntu + macos.

## License

MIT. See [LICENSE](LICENSE).

## Links

- **Repo:** https://github.com/fockus/skill-memory-bank
- **PyPI:** https://pypi.org/project/memory-bank-skill/
- **Homebrew tap:** https://github.com/fockus/homebrew-tap
- **Issues:** https://github.com/fockus/skill-memory-bank/issues
