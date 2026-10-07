# Host notes

Per-host details for Claude Code, Codex and Cursor. The supported-host summary stays in `SKILL.md`.

## Host-specific notes

### Claude Code and native memory

Claude Code has built-in `auto memory` (user-level cross-project memory in `~/.claude/projects/.../memory/`). This skill does **not replace** it — the two complement each other:

| Aspect | `.memory-bank/` | Native `auto memory` |
|--------|------------------|----------------------|
| Scope | Project | User, cross-project |
| Stores | Status, plans, checklists, research, ADRs, lessons | Preferences, role, feedback |
| Owner | Team (via git) | Individual user |

Rule of thumb: if it helps a teammate pick up the project tomorrow, store it in `.memory-bank/`. If it helps you in another project, store it in native memory. They can coexist without conflict.

### Codex

For native lifecycle/tool hooks, use the additive [Codex hooks adapter](references/codex-native-hooks.md). It reuses the existing MB checks, adapts `apply_patch`/`spawn_agent`, and documents the remaining Claude-only capture hooks. Installation and host trust are separate; verify runtime events before claiming hooks are active.

For Codex, this skill is positioned as a global skill bundle plus a guidance layer:
- discovery goes through `~/.codex/skills/memory-bank/`
- global entrypoint/guidance goes through `~/.codex/AGENTS.md`
- hook/config integration remains primarily project-level through `.codex/`

Codex therefore uses the same Memory Bank workflow, but it does not need to expose the same native command surface as Claude Code/OpenCode.

### Cursor

Cursor is a first-class global target. `install.sh` writes six artifacts to `~/.cursor/`:

| Artifact | Purpose |
|----------|---------|
| `~/.cursor/skills/memory-bank/` | Personal skill alias — Cursor auto-discovers it by description |
| `~/.cursor/hooks.json` | Global hooks (10 commands → skill bundle `hooks/`): `sessionStart` (auto-context), `sessionEnd`, `preCompact`, `beforeShellExecution`, four `preToolUse` matchers (`Write|Edit`, `Write`, `Task`×2), two `postToolUse` matchers. Each command runs `~/.cursor/skills/memory-bank/hooks/<script>.sh` with `MB_AGENT=cursor`. Tagged `_mb_owned: true` so user hooks are preserved |
| `~/.cursor/commands/*.md` | User-level slash commands mirrored from the skill `commands/` directory |
| `~/.cursor/agents/mb-*.md` | Native Cursor subagents ([docs](https://cursor.com/docs/agent/subagents)): every non-partial role rendered by `scripts/mb-agent-render.py --host cursor` — partials composed in, frontmatter cut to `name`/`description`, no `model` (= inherit the parent model; Claude aliases such as `haiku` are not Cursor ids). Cursor also reads `~/.claude/agents/`; on a name clash `.cursor/` wins, so this copy shadows the Claude one. Tracked in `~/.cursor/.mb-manifest.json`; `uninstall-global` removes only these files |
| `~/.cursor/AGENTS.md` | Marker section `memory-bank-cursor:start/end` — entrypoint for future Cursor versions that read global `AGENTS.md` |
| `~/.cursor/memory-bank-user-rules.md` | Paste-ready rules bundle for **Settings → Rules → User Rules** (Cursor exposes no file API for global User Rules, so this is a one-time manual step) |

Cursor User Rules paste flow:

```bash
# macOS
pbcopy < ~/.cursor/memory-bank-user-rules.md
# Linux
xclip -selection clipboard < ~/.cursor/memory-bank-user-rules.md
```

The project-level adapter (`.cursor/rules/memory-bank.mdc` + `.cursor/hooks.json`) remains available and is installed only when the user passes `--clients cursor`. Global and project-level installs coexist — Cursor merges hooks from both.

## Supported host model

Supported host model:
- **Claude Code / OpenCode** — native command surface + global install.
- **Cursor** — native full support: global skill alias (`~/.cursor/skills/memory-bank/`), global hooks (`~/.cursor/hooks.json`), global slash commands (`~/.cursor/commands/`), native subagents (`~/.cursor/agents/mb-*.md`), `~/.cursor/AGENTS.md` with managed section, plus a paste-ready file for Settings → Rules → User Rules. Project-level `.cursor/` adapter remains available as an add-on via `--clients cursor`.
- **Codex** — global skill discovery + `AGENTS.md` hints + project-level `.codex/` adapter; no separate native slash-command surface.
- **Other code agents** — via adapters, `AGENTS.md`, local hooks/configs, or direct CLI/script usage.
