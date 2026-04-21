# memory-bank-skill

[![CI](https://img.shields.io/github/actions/workflow/status/fockus/skill-memory-bank/test.yml?branch=main&label=tests&style=flat-square&color=brightgreen&v=300)](https://github.com/fockus/skill-memory-bank/actions/workflows/test.yml)
[![PyPI version](https://img.shields.io/pypi/v/memory-bank-skill?style=flat-square&color=brightgreen&label=pypi&v=300)](https://pypi.org/project/memory-bank-skill/)
[![GitHub release](https://img.shields.io/github/v/release/fockus/skill-memory-bank?style=flat-square&color=brightgreen&label=release&v=300)](https://github.com/fockus/skill-memory-bank/releases/latest)
[![Python versions](https://img.shields.io/pypi/pyversions/memory-bank-skill?style=flat-square&color=brightgreen&v=300)](https://pypi.org/project/memory-bank-skill/)
[![Homebrew tap](https://img.shields.io/badge/homebrew-fockus%2Ftap-brightgreen?style=flat-square&v=300)](https://github.com/fockus/homebrew-tap)
[![Downloads](https://img.shields.io/pypi/dm/memory-bank-skill?style=flat-square&color=brightgreen&v=300)](https://pypi.org/project/memory-bank-skill/)
[![Last commit](https://img.shields.io/github/last-commit/fockus/skill-memory-bank?style=flat-square&color=brightgreen&v=300)](https://github.com/fockus/skill-memory-bank/commits/main)
[![License: MIT](https://img.shields.io/badge/license-MIT-brightgreen?style=flat-square&v=300)](LICENSE)

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
├── RESEARCH.md        ← hypotheses log (H-NNN) + current experiment
├── BACKLOG.md         ← parking lot for ideas + ADRs
├── progress.md        ← work log (append-only)
├── lessons.md         ← mistakes not to repeat
├── notes/             ← knowledge (5-15 line snippets)
├── plans/             ← detailed plans per feature/fix
├── reports/           ← analysis, post-mortems
├── experiments/       ← EXP-NNN experiment artifacts
└── codebase/          ← stack / architecture / conventions map (`/mb map`)
```

This directory lives alongside your code (commit it, share it with your team, or `.gitignore` it — your call).

---

## Install

Pick one:

### Option 0: skills.sh CLI (fastest one-shot install)

```bash
npx skills add fockus/skill-memory-bank
```

Copies the skill bundle (SKILL.md + scripts + commands + agents) into your local skills directory. Use this for a quick single-host try-out (Claude Code, Cursor, or any host that reads `~/.claude/skills/` or `~/.cursor/skills/`). For cross-agent setup (Codex / Windsurf / OpenCode hooks, managed blocks in `AGENTS.md`, `memory-bank` CLI, hooks, slash commands globally installed), use Option 1 or 2 below.

### Option 1: pipx (recommended, cross-platform)

```bash
pipx install memory-bank-skill           # stable
# or, for the latest release candidate:
pipx install --pip-args='--pre' memory-bank-skill

memory-bank install                      # global install for Claude Code + Cursor + Codex hints + OpenCode
# optional: pick installed rule language explicitly
memory-bank install --language ru
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

Three ways — pick whichever matches your workflow:

**A. Interactive menu** (from any terminal — recommended if you're unsure which clients you want):

```bash
cd your-project/
memory-bank install                     # multi-select prompt for all 8 clients
# in TTY mode it will also ask which language to use for installed rules
```

**B. CLI flags** (scripts / CI / one-liner):

```bash
cd your-project/
memory-bank install --clients claude-code,cursor,windsurf
memory-bank install --clients claude-code,cursor --language en
```

**C. From inside an agent with command surface** (Claude Code / OpenCode):

```
/mb install                                 # interactive picker
/mb install cursor,windsurf                 # direct
/mb install all                             # every client
```

Claude Code/OpenCode can front this through `/mb install`, then run `memory-bank install --clients <selected>` for the current project. In Codex use the CLI directly; Codex gets global skill discovery plus `~/.codex/AGENTS.md` hints, not a native `/mb` command surface.

Supported client names: `claude-code`, `cursor`, `windsurf`, `cline`, `kilo`, `opencode`, `pi`, `codex`.
Supported rule languages: `en` (default), `ru` (full translation), `es`/`zh` (scaffolds — community PRs welcome, see [docs/i18n.md](docs/i18n.md)). You can also set `MB_LANGUAGE=en|ru|es|zh`.

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

Installs `~/.claude/RULES.md`, `~/.claude/CLAUDE.md`, canonical skill registration in
`~/.claude/skills/skill-memory-bank`, compatibility aliases in `~/.claude/skills/memory-bank`,
`~/.codex/skills/memory-bank`, and `~/.cursor/skills/memory-bank`, plus full Cursor global
surface (`~/.cursor/hooks.json` + `~/.cursor/hooks/*.sh` + `~/.cursor/commands/*.md`
+ `~/.cursor/AGENTS.md` managed section + `~/.cursor/memory-bank-user-rules.md`
paste-file for Settings → Rules → User Rules), plus native OpenCode global files
(`~/.config/opencode/AGENTS.md` + `~/.config/opencode/commands/`) with:

- **TDD** — tests before implementation
- **Clean Architecture** (backend) — Infrastructure → Application → Domain, never the reverse
- **Feature-Sliced Design** (frontend) — `app → pages → widgets → features → entities → shared`
- **Mobile** (iOS/Android) — UDF + Clean layers, SwiftUI+Observation / Compose+StateFlow
- **SOLID** — SRP (≤300 LOC / class), ISP (≤5 methods / interface), DIP (constructor injection)
- **Testing Trophy** — integration > unit > e2e; mock only external services
- **Coverage** targets — 85% overall, 95% core, 70% infrastructure

The agent reads these rules at session start and follows them without you having to remind it.

### 3. Dev-workflow commands

**18 top-level slash-commands** (live in `commands/`):

| Command | Purpose |
|---------|---------|
| `/mb <sub>` | Memory Bank hub (20 sub-commands — see table below) |
| `/start` | Lightweight session start (loads STATUS/checklist only) |
| `/done` | Lightweight session close (no full actualize) |
| `/plan` | Implementation plan generator with DoD/TDD scaffolding |
| `/commit` | Conventional-commit message with MB context |
| `/pr` | Create pull request with structured description |
| `/review` | Full code review (correctness + security + perf + style) |
| `/test` | Run tests + coverage analysis + gap report |
| `/refactor` | Guided refactoring (Strangler Fig, staged diffs) |
| `/doc` | Generate / refresh documentation from code |
| `/changelog` | Update CHANGELOG.md from recent commits |
| `/catchup` | Summarize recent changes since last session |
| `/adr` | Architecture Decision Record template writer |
| `/contract` | Contract-first workflow (Protocol/ABC → tests → impl) |
| `/security-review` | OWASP-focused security audit pass |
| `/api-contract` | API contract validation + breaking-change detection |
| `/db-migration` | Safe DB migration planning (rollback, backfill) |
| `/observability` | Logging / metrics / tracing audit for a module |

**21 `/mb` sub-commands** (live in `commands/mb.md`):

| Sub-command | Purpose |
|-------------|---------|
| `/mb` / `/mb context` | Collect project context (status, checklist, active plan) |
| `/mb start` | Extended session start — full context + active plan body |
| `/mb done` | Close session — actualize + note + progress |
| `/mb update` | Refresh core files with live metrics (no note) |
| `/mb verify` | Verify implementation matches the active plan (CRITICAL before `/mb done`) |
| `/mb doctor` | Find & fix inconsistencies inside the memory bank |
| `/mb plan <type> <topic>` | Create detailed plan (feature / fix / refactor / experiment) |
| `/mb search <query>` | Keyword search across the memory bank |
| `/mb note <topic>` | Quick knowledge note (5-15 lines) |
| `/mb tasks` | Show pending tasks from checklist |
| `/mb index` | Registry of all entries (core + notes/plans/experiments/reports) |
| `/mb map [focus]` | Scan codebase, write MD docs to `.memory-bank/codebase/` (stack/arch/quality/concerns/all) |
| `/mb graph [--apply]` | Multi-language code graph: Python (stdlib `ast`) + Go/JS/TS/Rust/Java (tree-sitter, opt-in) |
| `/mb compact [--apply]` | Status-based decay — archive old done plans + low-importance notes |
| `/mb import --project <path>` | Bootstrap MB from Claude Code JSONL transcripts |
| `/mb tags [--apply]` | Normalize frontmatter tags (Levenshtein-based synonym merge) |
| `/mb upgrade` | Update skill from GitHub (git pull + re-install) |
| `/mb init [--minimal\|--full]` | Initialize `.memory-bank/` in a new project |
| `/mb install [<clients>]` | Install Memory Bank + cross-agent adapters interactively or via client list |
| `/mb deps [--install-hints]` | Dependency check (python3, jq, git + optional tree-sitter) |
| `/mb help [subcommand]` | Show sub-command reference inline |

**Run `/mb help` inside any agent** to see this table live; `/mb help <sub>` for full detail of one sub-command.

### 4. Cross-agent portability

One `.memory-bank/` directory, 8 AI clients:

| Client | Native hooks | Adapter output |
|--------|--------------|----------------|
| **Claude Code** | Full lifecycle | `~/.claude/settings.json` + `hooks/` |
| **Cursor 1.7+** | ✅ (Claude-Code-compatible format) | **Global (auto):** `~/.cursor/{skills,hooks,commands,AGENTS.md,hooks.json,memory-bank-user-rules.md}` · **Project (optional `--clients cursor`):** `.cursor/rules/*.mdc` + `.cursor/hooks.json` |
| **Windsurf** | ✅ Cascade Hooks | `.windsurf/rules/*.md` + `.windsurf/hooks.json` |
| **Cline** | ✅ `.clinerules/hooks/*.sh` | `.clinerules/memory-bank.md` + `hooks/` |
| **Kilo** | ❌ (fallback to git hooks) | `.kilocode/rules/` + `.git/hooks/` |
| **OpenCode** | ✅ TypeScript plugins + native commands | `~/.config/opencode/{AGENTS.md,commands/}` + project `AGENTS.md` + `opencode.json` + TS plugin |
| **Codex** (OpenAI) | ✅ Conservative global support + experimental project hooks | `~/.codex/skills/memory-bank` + `~/.codex/AGENTS.md` + project `AGENTS.md` + `.codex/config.toml` + `.codex/hooks.json` |
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
memory-bank install                     # global install for all supported clients
#                                       # (Claude + Cursor + Codex + OpenCode, auto)
memory-bank install --clients cursor    # OPTIONAL: also wire .cursor/ project adapter
#                                       # — global parity already active without this flag

# In Cursor:
/mb init --full                         # auto-detect stack, generate CLAUDE.md
/mb start                               # load everything
```

### Cursor-only quick start

```bash
# Step 1. Install (no --clients flag needed for Cursor global parity)
memory-bank install

# Step 2 (one-time, per machine). Cursor User Rules panel is UI-only —
# paste the generated bundle into Settings → Rules → User Rules:
pbcopy < ~/.cursor/memory-bank-user-rules.md           # macOS
xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md   # Linux

# Step 3. Open any project in Cursor and run:
/mb init                                # one-time per project
/mb start                               # every session
```

### Sharing state with your team

`.memory-bank/` is just markdown. Commit it. Your colleague clones the repo, runs `/mb start`, and has the full project context without asking you a single question.

---

## CLI reference

After `pipx install memory-bank-skill`:

```bash
memory-bank install [--clients <list>] [--language <en|ru|es|zh>] [--project-root <path>] [--non-interactive]
memory-bank uninstall [-y|--non-interactive]
memory-bank init                    # prints /mb init hint
memory-bank version
memory-bank self-update             # prints `pipx upgrade ...`
memory-bank doctor                  # resolves bundle, platform info, checks bash
memory-bank --help
```

Flags:
- `--clients <list>` — comma-separated. Valid: `claude-code, cursor, windsurf, cline, kilo, opencode, pi, codex`. If omitted and running in a TTY → interactive menu. Non-TTY default: `claude-code` only.
- `--project-root <path>` — where to place client-specific adapters. Default: current directory.
- `--non-interactive` — never prompt; use defaults when `--clients` not specified. Use in CI / scripted installs.
- `-y` / `--non-interactive` on `uninstall` — skip the confirmation prompt. Use in CI / scripted cleanup.

---

## Environment variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `MB_AUTO_CAPTURE` | SessionEnd auto-capture mode: `auto` / `strict` / `off` | `auto` |
| `MB_COMPACT_REMIND` | Weekly `/mb compact` reminder: `auto` / `off` | `auto` |
| `MB_ALLOW_METRICS_OVERRIDE` | Allow executing project-local `.memory-bank/metrics.sh` overrides | `0` |
| `MB_PI_MODE` | Pi adapter mode. Supported: `agents-md`; `skill` is experimental | `agents-md` |
| `MB_EXPERIMENTAL_PI_SKILL` | Explicit gate for `MB_PI_MODE=skill` compatibility testing | `0` |
| `MB_SKILL_BUNDLE` | Override bundle path (dev / testing) | auto-detected |
| `MB_SKIP_DEPS_CHECK` | Skip preflight dep check in `install.sh` | `0` |

---

## Platform support

| OS | Status |
|----|--------|
| macOS | ✅ Native |
| Linux | ✅ Native |
| Windows (Git Bash) | ✅ Via Git for Windows — install works, CLI auto-detects `bash.exe` |
| Windows (WSL) | ✅ Full native POSIX path |
| Windows (native PowerShell, no bash) | ⚠️ Fails with install hint |

**Windows quick start:**

```powershell
# Either:
winget install Git.Git            # → supplies bash.exe at C:\Program Files\Git\bin\bash.exe
# or:
wsl --install                     # → full Linux env
pip install memory-bank-skill     # inside WSL or with Git Bash on PATH
memory-bank doctor                # verifies bash discovery
memory-bank install               # works once bash is resolvable
```

`memory-bank doctor` on Windows reports the detected bash path (or an install hint if none found).

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
A: Partial — where native hooks don't exist or aren't stable, we ship graceful fallbacks or conservative integration. For Codex, global support means skill discovery + `~/.codex/AGENTS.md` hints; hook/config integration is still primarily project-level via `.codex/`. See [docs/cross-agent-setup.md](docs/cross-agent-setup.md) for specifics.

**Q: My existing `AGENTS.md` / `.cursor/hooks.json` — will this overwrite them?**
A: No. Adapters use a marker pattern (`<!-- memory-bank:start/end -->` for MD files, `_mb_owned: true` for JSON hooks) and merge idempotently. User content is preserved; uninstall only removes MB-owned sections.

**Q: How do I upgrade?**
A: `pipx upgrade memory-bank-skill` or `brew upgrade memory-bank`. Git-clone install: `cd ~/.claude/skills/skill-memory-bank && git pull && ./install.sh`.

**Q: Does reinstalling create `.pre-mb-backup.*` files every time?**
A: No. Since `3.0.0`, `install.sh` is byte-level idempotent: each target is compared via `cmp -s` to the expected post-install content (including localization) and backup is created only if content actually differs. Repeat installs on an up-to-date tree produce zero backups. Language swap (`--language en` → `--language ru`) backs up exactly the localize-target files (`RULES.md`, `memory-bank-user-rules.md`) and nothing else.

**Q: I want to remove everything.**
A: `memory-bank uninstall -y` removes global install without a prompt. Per-project adapters: `adapters/<client>.sh uninstall <project-dir>`.

**Q: Can a project-local `.memory-bank/metrics.sh` run arbitrary commands during install or doctor flows?**
A: Not by default. Project-local metrics overrides are disabled unless you explicitly opt in with `MB_ALLOW_METRICS_OVERRIDE=1`. Without that env var, the shipped stack detection stays on the safe built-in path.

**Q: Does Pi still support `MB_PI_MODE=skill`?**
A: Only as an explicit compatibility experiment. The supported path is `agents-md`. If you need to probe the native Pi Skills surface, gate it intentionally with `MB_PI_MODE=skill MB_EXPERIMENTAL_PI_SKILL=1` and expect breakage while the upstream API is still moving.

**Q: Is this production-ready?**
A: Yes. `3.0.0` is the first stable 3.x release. Daily used on real projects. Full test envelope green (bats + pytest). Stable API. Prior pre-release tags (`3.0.0-rc1`/`rc2`/`rc3`) are still published on PyPI as pre-releases for reference.

---

## Documentation

- **[Cross-agent setup](docs/cross-agent-setup.md)** — per-client cheatsheet + hook capability matrix
- **[Install guide](docs/install.md)** — pipx / Homebrew / git-clone with troubleshooting
- **[v3.0 → v3.1 migration](docs/MIGRATION-v3-v3.1.md)** — automatic structural upgrade (multi-active plans, `I-NNN` ideas, `ADR-NNN`)
- **[v1 → v2 migration](docs/MIGRATION-v1-v2.md)** — older structural migration
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
