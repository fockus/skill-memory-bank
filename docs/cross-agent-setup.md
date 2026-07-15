# Cross-agent setup (Stage 8, v3.0)

Memory Bank works across 7+ AI coding clients. Canonical global skill lives under
`~/.claude/skills/skill-memory-bank`; Claude, Codex, and Cursor consume it through
managed aliases (`~/.claude/skills/memory-bank`, `~/.codex/skills/memory-bank`,
`~/.cursor/skills/memory-bank`). OpenCode also gets native global files under
`~/.config/opencode/`. Cursor additionally receives global hooks, slash commands,
an `AGENTS.md` marker section, and a paste-ready rules file at the user level.
Per-project adapters write client-specific configs + hooks.

## Supported clients

| # | Client | Native hooks | Config format |
|---|--------|--------------|---------------|
| 1 | Claude Code | Full (SessionEnd/PreCompact/PreToolUse) | `~/.claude/settings.json` |
| 2 | **Cursor** (1.7+) | **Full global + project, CC-compat** `hooks.json` | **Global:** `~/.cursor/{skills,hooks,commands,AGENTS.md,memory-bank-user-rules.md,hooks.json}` · **Project:** `.cursor/rules/*.mdc` + `.cursor/hooks.json` |
| 3 | Windsurf | Cascade Hooks (JSON+shell) | `.windsurf/rules/*.md` + `.windsurf/hooks.json` |
| 4 | Cline | `.clinerules/hooks/*.sh` | `.clinerules/*.md` + `hooks/` |
| 5 | Kilo | ❌ (FR #5827 open) — git-hooks fallback | `.kilocode/rules/*.md` |
| 6 | OpenCode | TypeScript plugins (`session.*`, `tool.execute.*`, `experimental.session.compacting`) + native slash commands | `~/.config/opencode/{AGENTS.md,commands/}` + `AGENTS.md` + `opencode.json` |
| 7 | Codex | Conservative global support + experimental project hooks | `~/.codex/skills/memory-bank` + `~/.codex/AGENTS.md` + `AGENTS.md` + `.codex/config.toml` + `.codex/hooks.json` |
| 8 | Pi Code | Global skill + prompt templates + `AGENTS.md` | `~/.pi/agent/skills/memory-bank`, `~/.pi/agent/prompts/*.md`, `~/.pi/agent/AGENTS.md` + optional project `AGENTS.md` |

## Storage modes per agent

Memory Bank supports **local**, **global**, and **rules-only** storage modes. The table below shows per-agent support and global bank locations.

| Agent | Global config dir | Local mode | Global mode | Rules-only |
|-------|-------------------|------------|-------------|------------|
| Claude Code | `~/.claude` | `/mb init --storage=local` | `/mb init --storage=global --agent=claude-code` | ✅ `[MEMORY BANK: ABSENT]` |
| Cursor | `~/.cursor` | `/mb init --storage=local` | `/mb init --storage=global --agent=cursor` | ✅ `[MEMORY BANK: ABSENT]` |
| Codex | `~/.codex` | `/mb init --storage=local` | `/mb init --storage=global --agent=codex` | ✅ `[MEMORY BANK: ABSENT]` |
| OpenCode | `~/.config/opencode` | `/mb init --storage=local` | `/mb init --storage=global --agent=opencode` | ✅ `[MEMORY BANK: ABSENT]` |
| Pi Code | `~/.pi/agent` | `/mb init --storage=local` | `/mb init --storage=global --agent=pi` | ✅ `[MEMORY BANK: ABSENT]` |
| Windsurf | `~/.windsurf` | `/mb init --storage=local` | via `MB_AGENT=windsurf` (adapter-only) | ✅ rules via adapter |
| Cline | `~/.cline` | `/mb init --storage=local` | via `MB_AGENT=cline` (adapter-only) | ✅ rules via adapter |
| Kilo | `~/.kilocode` | `/mb init --storage=local` | via `MB_AGENT=kilo` (adapter-only) | ✅ rules via adapter |

**Notes:**
- **Local mode** — bank lives in the repo (`.memory-bank/`), committable, team-shared. Default of `/mb init`.
- **Global mode** — bank lives under `~/.<agent>/memory-bank/projects/<id>/.memory-bank`, personal storage, **do not commit to the repo**. Requires `--storage=global --agent=<agent>` on init.
- **Rules-only mode** — no `/mb init` at all; engineering rules (TDD, SOLID, Clean Architecture, DRY/KISS/YAGNI) are always-on via globally installed rules files; Memory Bank lifecycle commands stay inactive. Valid steady state for projects that want rules without bank overhead.
- Native-skill agents (Claude Code, Cursor, Codex, OpenCode, Pi) support all three modes directly. Adapter-only agents (Windsurf, Cline, Kilo) support local and rules-only; global mode is available via `MB_AGENT` env override.

## Install

```bash
# Global install + cross-agent adapters in one command
bash install.sh --clients claude-code,cursor,windsurf --project-root .

# All supported clients
bash install.sh --clients claude-code,cursor,windsurf,cline,kilo,opencode,codex,pi --project-root .

# Only cross-agent adapters (no Claude Code)
bash install.sh --clients cursor,opencode --project-root ~/my-project
```

**Flags:**
- `--clients <list>` — comma-separated. Default: `claude-code` only.
- `--project-root <path>` — where to place adapters. Default: `$PWD`.
- `--help` — full usage.

### Global agent resources always install (A25 / CDX-I13)

`install.sh` calls `install_opencode_global_agents`, `install_codex_global_agents`, and
`install_pi_global_agents` unconditionally on every run, **independently of `--clients`**.
That means the global skill alias, global `AGENTS.md` entrypoint, and prompt templates for
OpenCode, Codex, and Pi are installed even when `--clients` doesn't include them — so those
hosts are ready to use the moment you open them, without a separate install step. Only the
**project-local** adapter (`.codex/config.toml`, `.opencode/plugins/…`, project `AGENTS.md`,
etc.) is actually gated by `--clients`.

**Open question:** gating the global-resource install itself by the selected `--clients`
is a deliberate, separate product decision — not implemented here. If you want that
gating, track it as a follow-up rather than assuming today's behavior will change.

## Per-client cheatsheet

### Cursor (full global parity + project adapter)

Cursor is a first-class **global** target: `install.sh` writes all five artifacts
automatically with **no `--clients cursor` flag required**. The project-level
adapter (`.cursor/rules/*.mdc` + `.cursor/hooks.json`) is an optional add-on.

**Global install (always):**

```bash
bash install.sh --non-interactive
# or: memory-bank install
```

Creates under `~/.cursor/`:
- `skills/memory-bank/` — symlink on canonical skill bundle (auto-discovered by Cursor)
- `hooks.json` — ten hook commands tagged `_mb_owned: true` (scripts run from skill bundle `~/.cursor/skills/memory-bank/hooks/`, not copied to `~/.cursor/hooks/`):
  `sessionStart` (auto-context), `sessionEnd` (autosave), `preCompact` (reminder),
  `beforeShellExecution` (block-dangerous), four `preToolUse` entries (protected paths, EARS, context-slim, sprint-guard),
  two `postToolUse` entries (file-change-log, plan-sync)
- `commands/*.md` — user-level slash commands mirrored from the skill
- `AGENTS.md` — marker section `memory-bank-cursor:start/end` (managed block,
  user content above/below is preserved)
- `memory-bank-user-rules.md` — paste-ready bundle for **Settings → Rules → User Rules**
  (Cursor has no file API for global User Rules; this is a one-time manual copy-paste)

**Cursor User Rules paste flow:**

```bash
# macOS
pbcopy < ~/.cursor/memory-bank-user-rules.md
# Linux
xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md
```

Then in Cursor: Settings → Rules → User Rules → paste.

The paste file includes version markers `<!-- memory-bank:start vX.Y.Z -->` … `<!-- memory-bank:end -->`.
Cursor cannot write User Rules via file API — manual paste only.

**Optional project adapter:**

```bash
bash install.sh --clients cursor --project-root ~/my-project
# or: memory-bank install --clients cursor --project-root ~/my-project
# or directly: adapters/cursor.sh install ~/my-project
```

Creates:
- `.cursor/rules/memory-bank.mdc` — YAML frontmatter (`alwaysApply: true`) + RULES.md
- `.cursor/hooks.json` — CC-compat, all ten events wired to skill-bundle hook scripts + `MB_AGENT=cursor`
- No `.cursor/hooks/*.sh` copies — hooks execute from `~/.cursor/skills/memory-bank/hooks/` or repo skill bundle

**Limitation (IDE vs CLI hook firing):** The Cursor *agent CLI* fires the full CC-compatible hook
set. The Cursor *IDE* does not guarantee every hook event (notably `sessionEnd`) fires on every
interaction — treat IDE auto-capture as best-effort and rely on explicit `/mb done` for durable
session closure. See [docs/cursor-extension.md](cursor-extension.md#limitations) for the
architecture-level detail.

### Windsurf

```bash
adapters/windsurf.sh install ~/my-project
```

Creates:
- `.windsurf/rules/memory-bank.md` (`trigger: always_on` frontmatter)
- `.windsurf/hooks.json` (Cascade, events: `user-prompt-submit`, `model-response`)
- Pre-hooks exit with code `2` to block.

### Cline

```bash
adapters/cline.sh install ~/my-project
```

Creates:
- `.clinerules/memory-bank.md` (`paths: ["**"]` frontmatter)
- `.clinerules/hooks/before-tool.sh` — blocks `rm -rf /` family (exit 2)
- `.clinerules/hooks/after-tool.sh` — auto-capture (idempotent per `sessionId`)
- `.clinerules/hooks/on-notification.sh` — weekly compact reminder (opt-in)

### Kilo (git-hooks fallback mandatory)

```bash
adapters/kilo.sh install ~/my-project   # must be a git repo
```

Creates:
- `.kilocode/rules/memory-bank.md` — rules
- `.git/hooks/post-commit` + `.git/hooks/pre-commit` (via `git-hooks-fallback.sh`)

Post-commit auto-captures to `progress.md` (respects `.session-lock`,
`MB_AUTO_CAPTURE=off|strict|auto`). Pre-commit warns on staged `<private>` blocks.

**Why git-hooks:** Kilo has no native lifecycle hooks — FR
[Kilo-Org/kilocode#5827](https://github.com/Kilo-Org/kilocode/issues/5827).

### OpenCode

```bash
adapters/opencode.sh install ~/my-project
```

Creates:
- `~/.config/opencode/AGENTS.md` — global OpenCode rules for prompt injection
- `~/.config/opencode/commands/*.md` — native slash commands in OpenCode menu
- `AGENTS.md` — shared format, refcount-tracked via `.mb-agents-owners.json`
- `.opencode/commands/*.md` — project-local slash commands (works even without global install)
- `.opencode/plugins/memory-bank.js` — TS plugin with `session.idle`,
  `session.deleted`, `tool.execute.before`, and **`experimental.session.compacting`**
  (direct PreCompact equivalent). Registration contract is **auto-discovery**:
  OpenCode loads any module under `.opencode/plugins/` on its own, so no
  `opencode.json` entry is required or written. If a project's `opencode.json`
  carries a *stale legacy* reference to `./.opencode/plugins/memory-bank.js`
  from an older skill version, install removes just that entry (atomic
  rewrite via `jq`) and preserves every other user key untouched.

On `session.idle`/`session.deleted`, the plugin also invokes the same
CC-compatible summarize capture Cursor wires (`mb-session-end.sh`, resolved
via the OpenCode skill alias `~/.config/opencode/skills/memory-bank/hooks/`,
overridable via `MB_SUMMARIZE_BIN`) — fail-open if that script is absent (B4).

### Codex (OpenAI)

```bash
adapters/codex.sh install ~/my-project
```

Creates:
- `~/.codex/skills/memory-bank` — global skill alias to the canonical bundle
- `~/.codex/AGENTS.md` — global Memory Bank entrypoint and conservative hook guidance
- `AGENTS.md` — shared format
- `.codex/config.toml` — project settings (`project_doc_max_bytes=65536`,
  `approval_policy="on-request"`)
- `.codex/hooks.json` — experimental hooks (warning included in `_mb_warning` field)
- `.git/hooks/post-commit` + `.git/hooks/pre-commit` (via `git-hooks-fallback.sh`,
  when the project is a git repo — B5) — the same session-capture fallback Kilo/Pi
  get, since Codex's own lifecycle hooks are still experimental/limited (above).
  Skipped (not an error) outside a git repo.

**⚠️ Important:** Codex global support is broader than just the project adapter:
- bundled `commands/`, `agents/`, `hooks/`, `scripts/`, `references/` are available through `~/.codex/skills/memory-bank/`;
- `~/.codex/AGENTS.md` is the global entrypoint;
- actual hook/config execution remains primarily project-level via `.codex/`.

**⚠️ Experimental:** Codex hooks schema may change. Re-run `adapters/codex.sh install`
after upgrading Codex CLI.

### Pi Code

Global Pi support is installed automatically by `memory-bank install`:

- `~/.pi/agent/skills/memory-bank` — global Pi skill alias
- `~/.pi/agent/prompts/*.md` — Pi slash prompt templates (`/mb`, `/start`, `/done`, `/plan`, etc.)
- `~/.pi/agent/AGENTS.md` — always-loaded Memory Bank entrypoint + core rules

After installing in a running Pi session, run `/reload`.

Optional project adapter:

```bash
adapters/pi.sh install ~/my-project
# or: memory-bank install --clients pi --project-root ~/my-project
```

The project adapter writes shared `AGENTS.md`. If the project is a git repo it
also installs the git-hooks fallback; otherwise it safely installs only
`AGENTS.md`. `MB_PI_MODE=skill` is supported for compatibility, but it leaves an
existing global Pi skill symlink unchanged so it cannot overwrite the bundled
`SKILL.md` installed by `memory-bank install`.

## Shared AGENTS.md coexistence

OpenCode, Codex, and Pi (agents-md mode) all use `AGENTS.md`. Cline also reads it
automatically. Multiple MB adapters installing at once share a single marker section:

```markdown
<!-- memory-bank:start -->

# Memory Bank — Project Rules
...

<!-- memory-bank:end -->
```

Ownership is refcounted in `.mb-agents-owners.json`:

```json
{
  "owners": ["opencode", "codex", "pi"],
  "initial_had_user_content": false
}
```

**Uninstall rules:**
- Remove one client → refcount decremented, section kept
- Remove last client → section removed (file deleted if `initial_had_user_content: false`)

## Hook matrix — our hook categories → client events

Our own lifecycle set is broader than 4 events (see `settings/hooks.json`: `Setup`,
`PreToolUse`, `PostToolUse`, `Notification`, `PreCompact`, `Stop`, `UserPromptSubmit`,
`SessionStart`, `SessionEnd`) — the table below groups them into the cross-client-relevant
categories; not every category has an equivalent on every host.

| Our hook | Cursor | Windsurf | Cline | Kilo | OpenCode | Pi | Codex |
|----------|--------|----------|-------|------|----------|-----|-------|
| SessionStart context injection | `sessionStart` (`mb-session-start-context.sh`) | — | — | — | — | — | — |
| SessionEnd auto-capture | `sessionEnd` (`mb-session-end.sh`, CC-compatible) | `model-response` | `afterToolExecution` | `post-commit` (git) | `session.idle`/`deleted` (+ summarize hook wired, B4) | `post-commit` (git-hooks-fallback, same mechanism as Kilo/Codex) | `post-commit` (git-hooks-fallback, B5) |
| PreCompact actualize | **`preCompact`** | — | — | — | **`experimental.session.compacting`** | — (no installed fallback; git hooks only fire on commit) | guidance via `~/.codex/AGENTS.md`, project hook pending |
| PreToolUse block | `preToolUse`+`beforeShellExecution` | Cascade pre-hook (exit 2) | `beforeToolExecution` (exit 2) | rules guidance | `tool.execute.before` throw | — (no installed fallback) | project `userpromptsubmit` (exit 2) |
| Weekly compact reminder | `sessionEnd` check | `model-response` check | `onNotification` | git-fallback | `session.idle` check | git-fallback (`post-commit` staleness check) | guidance only |

**Pi native extension status:** `adapters/pi_session_memory_extension.ts` (a TypeScript extension listening
to `session_start`/`session_before_compact`/`session_shutdown`/`tool_call` events) ships in the bundle as
source, but no adapter currently copies it to `~/.pi/agent/extensions/`. Until an install path wires it up,
Pi's actual lifecycle coverage is the git-hooks-fallback (post-commit) row above, not the native-extension
events — treat the extension as a template, not an installed artifact.

## Resource availability matrix

| Resource | Claude global | Codex global | Cursor global | Native host surface in Codex |
|----------|---------------|--------------|---------------|-------------------------------|
| `SKILL.md` | `~/.claude/skills/memory-bank/` | `~/.codex/skills/memory-bank/` | `~/.cursor/skills/memory-bank/` | Yes, via skill discovery |
| `commands/` | bundled + Claude commands installed | bundled in Codex skill alias | bundled + mirrored to `~/.cursor/commands/` | No separate native slash-command install |
| `agents/` | bundled + Claude global agents installed | bundled in Codex skill alias | bundled in skill (`~/.cursor/skills/memory-bank/agents/`) | No separate global agent registry assumed |
| `hooks/` | bundled + Claude global hooks installed | bundled in Codex skill alias | bundled at `~/.cursor/skills/memory-bank/hooks/` + ten `_mb_owned` entries in `~/.cursor/hooks.json` | Conservative/project-level only |
| Global rules | `~/.claude/CLAUDE.md` managed section | `~/.codex/AGENTS.md` managed section | `~/.cursor/AGENTS.md` managed section **+** paste-file for Settings → Rules → User Rules | n/a |

## Uninstall

Every adapter has idempotent `uninstall`:

```bash
adapters/cursor.sh uninstall ~/my-project
adapters/kilo.sh uninstall ~/my-project
# ...
```

Adapters preserve user content:
- User hooks in `.cursor/hooks.json` / `.windsurf/hooks.json` — only `_mb_owned: true`
  entries are removed.
- User rules in `.clinerules/` / `.kilocode/rules/` — only our `memory-bank.md` removed.
- User `AGENTS.md` content — preserved via refcount + marker section removal.
- User `.git/hooks/*` — restored from `.pre-mb-backup` backups.

## Troubleshooting

**Q: My `AGENTS.md` lost its custom sections after uninstall.**
A: Only our marker section (between `<!-- memory-bank:start/end -->`) is removed.
If your custom content was outside that marker, it's preserved. If not — recovery via
git: `git checkout HEAD -- AGENTS.md`.

**Q: Cursor hooks don't fire reliably (e.g. `sessionEnd` auto-capture missing).**
A: This is an IDE limitation, not a CLI one — the Cursor *agent CLI* fires the full
CC-compatible hook set, but the Cursor *IDE* does not guarantee every hook event fires on
every interaction. Rely on explicit `/mb done` for durable session closure in the IDE; see
[docs/cursor-extension.md](cursor-extension.md#limitations).

**Q: I installed Memory Bank but Cursor's User Rules panel is empty.**
A: Cursor exposes **no file API for global User Rules** — they are only editable
via Settings → Rules → User Rules. `install.sh` writes a paste-ready file to
`~/.cursor/memory-bank-user-rules.md`. Run:
```bash
# macOS
pbcopy < ~/.cursor/memory-bank-user-rules.md
# Linux
xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md
```
Then paste once into Settings → Rules → User Rules. This is a one-time manual
step per machine.

**Q: Does Cursor need `--clients cursor` for the global install?**
A: No. Global Cursor artifacts (`~/.cursor/skills/`, `~/.cursor/hooks.json`,
`~/.cursor/commands/`, `~/.cursor/AGENTS.md`, `~/.cursor/memory-bank-user-rules.md`)
are written by `install.sh` unconditionally. Pass `--clients cursor` only when
you also want the project-level adapter (`.cursor/rules/*.mdc` + `.cursor/hooks.json`)
in your current project.

**Q: Codex CLI ignores `.codex/hooks.json`.**
A: The hooks API is experimental and **off by default**. Enable it in Codex CLI config
per OpenAI docs, or wait for GA. The `_mb_warning` field in the generated file
documents this.

**Q: Pi doesn't show `/mb` after install.**
A: Run `/reload` in the current Pi session. Pi prompt templates are installed to
`~/.pi/agent/prompts/*.md`; new sessions pick them up automatically. If you had
an older local Pi skill directory, its backup is stored under
`~/.pi/agent/.memory-bank-backups/` so Pi does not discover it as a duplicate
skill.

**Q: Kilo adapter fails with "requires git repo".**
A: Kilo has no native hooks → git-hooks-fallback is mandatory. Run `git init`
before `adapters/kilo.sh install`, or use a different client.

**Q: Multiple adapters installed, uninstalling one breaks others.**
A: Should not happen — refcount design prevents it. If it does, file an issue with
`.mb-agents-owners.json` content attached.

## See also

- [Research notes (2026-04-20)](../.memory-bank/notes/2026-04-20_03-36_cross-agent-research.md)
- [Plan Stage 8](https://github.com/fockus/skill-memory-bank/blob/main/.memory-bank/plans/done/2026-04-20_refactor_skill-v2.1.md)
- [ADR-010 (Codex)](../.memory-bank/backlog.md)
- [ADR-011 (Repo migration)](../.memory-bank/backlog.md)
