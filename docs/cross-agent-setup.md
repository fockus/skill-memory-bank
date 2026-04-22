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
| 8 | Pi Code | Dual-mode (Skills API in dev) | `~/.pi/skills/memory-bank/` or `AGENTS.md` |

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
- `hooks.json` + `hooks/*.sh` — three hooks tagged `_mb_owned: true`:
  `sessionEnd` (autosave), `preCompact` (reminder), `beforeShellExecution` (block-dangerous)
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

**Optional project adapter:**

```bash
bash install.sh --clients cursor --project-root ~/my-project
# or: memory-bank install --clients cursor --project-root ~/my-project
# or directly: adapters/cursor.sh install ~/my-project
```

Creates:
- `.cursor/rules/memory-bank.mdc` — YAML frontmatter (`alwaysApply: true`) + RULES.md
- `.cursor/hooks.json` — CC-compat, events: `sessionEnd`, `preCompact`, `beforeShellExecution`
- `.cursor/hooks/*.sh` — self-contained copies of our hook scripts

**Limitation:** Cursor CLI only fires `beforeShellExecution`/`afterShellExecution`;
full event set works in IDE only.

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
- `opencode.json` — plugin reference added to `plugin` array
- `.opencode/commands/*.md` — project-local slash commands (works even without global install)
- `.opencode/plugins/memory-bank.js` — TS plugin with `session.idle`,
  `session.deleted`, `tool.execute.before`, and **`experimental.session.compacting`**
  (direct PreCompact equivalent)

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

**⚠️ Important:** Codex global support is broader than just the project adapter:
- bundled `commands/`, `agents/`, `hooks/`, `scripts/`, `references/` are available through `~/.codex/skills/memory-bank/`;
- `~/.codex/AGENTS.md` is the global entrypoint;
- actual hook/config execution remains primarily project-level via `.codex/`.

**⚠️ Experimental:** Codex hooks schema may change. Re-run `adapters/codex.sh install`
after upgrading Codex CLI.

### Pi Code

```bash
# Supported path: AGENTS.md + git-hooks-fallback
adapters/pi.sh install ~/my-project
```

`agents-md` is the supported path because Pi Skills API is still in active
development (2026-04-20 research). The native `skill` mode remains an explicit
compatibility probe only:

```bash
MB_PI_MODE=skill MB_EXPERIMENTAL_PI_SKILL=1 adapters/pi.sh install ~/my-project
```

Do not use that path in normal installs or CI unless you are validating an
upstream Pi API change.

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

## Hook matrix — our 4 hooks → client events

| Our hook | Cursor | Windsurf | Cline | Kilo | OpenCode | Pi | Codex |
|----------|--------|----------|-------|------|----------|-----|-------|
| SessionEnd auto-capture | `sessionEnd` | `model-response` | `afterToolExecution` | `post-commit` (git) | `session.idle`/`deleted` | git-fallback (supported), Skill (experimental) | project `.codex/hooks.json` only |
| PreCompact actualize | **`preCompact`** | — | — | — | **`experimental.session.compacting`** | — | guidance via `~/.codex/AGENTS.md`, project hook pending |
| PreToolUse block | `preToolUse`+`beforeShellExecution` | Cascade pre-hook (exit 2) | `beforeToolExecution` (exit 2) | rules guidance | `tool.execute.before` throw | native | project `userpromptsubmit` (exit 2) |
| Weekly compact reminder | `sessionEnd` check | `model-response` check | `onNotification` | git-fallback | `session.idle` check | fallback | guidance only |

## Resource availability matrix

| Resource | Claude global | Codex global | Cursor global | Native host surface in Codex |
|----------|---------------|--------------|---------------|-------------------------------|
| `SKILL.md` | `~/.claude/skills/memory-bank/` | `~/.codex/skills/memory-bank/` | `~/.cursor/skills/memory-bank/` | Yes, via skill discovery |
| `commands/` | bundled + Claude commands installed | bundled in Codex skill alias | bundled + mirrored to `~/.cursor/commands/` | No separate native slash-command install |
| `agents/` | bundled + Claude global agents installed | bundled in Codex skill alias | bundled in skill (`~/.cursor/skills/memory-bank/agents/`) | No separate global agent registry assumed |
| `hooks/` | bundled + Claude global hooks installed | bundled in Codex skill alias | bundled + three global bindings in `~/.cursor/hooks.json` (tagged `_mb_owned`) | Conservative/project-level only |
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

**Q: Cursor hooks fire in IDE but not CLI.**
A: Known Cursor CLI limitation (only `beforeShellExecution` / `afterShellExecution`
dispatched in CLI). Use the IDE for full lifecycle coverage.

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

**Q: `MB_PI_MODE=skill` produced a Skill folder but Pi doesn't pick it up.**
A: That path is experimental by design and is gated behind
`MB_EXPERIMENTAL_PI_SKILL=1`. The supported adapter path is `agents-md`. If you
are intentionally testing the native Pi API, check
[pi-mono](https://github.com/badlogic/pi-mono) for current manifest/schema
changes before relying on the generated `SKILL.md`.

**Q: Kilo adapter fails with "requires git repo".**
A: Kilo has no native hooks → git-hooks-fallback is mandatory. Run `git init`
before `adapters/kilo.sh install`, or use a different client.

**Q: Multiple adapters installed, uninstalling one breaks others.**
A: Should not happen — refcount design prevents it. If it does, file an issue with
`.mb-agents-owners.json` content attached.

## See also

- [Research notes (2026-04-20)](../.memory-bank/notes/2026-04-20_03-36_cross-agent-research.md)
- [Plan Stage 8](../.memory-bank/plans/2026-04-20_refactor_skill-v2.1.md)
- [ADR-010 (Codex)](../.memory-bank/backlog.md)
- [ADR-011 (Repo migration)](../.memory-bank/backlog.md)
