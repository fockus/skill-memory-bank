# Installation

Three paths. Pick the one that fits.

## Path A — pipx (recommended)

**Requires:** Python 3.11+, `pipx` ([install guide](https://pipx.pypa.io/)).

```bash
pipx install memory-bank-skill
memory-bank install --clients claude-code,cursor    # global + per-project adapters
memory-bank install --language ru                   # install Russian rule wording
```

Upgrades:

```bash
pipx upgrade memory-bank-skill
```

Verify:

```bash
memory-bank doctor
memory-bank version
```

## Path B — Homebrew (macOS / Linuxbrew)

**Requires:** Homebrew.

```bash
brew tap fockus/tap
brew install memory-bank
memory-bank install --clients claude-code,cursor
memory-bank install --language en
```

Upgrades: `brew upgrade memory-bank`.

## Path C — git clone (developers / contributors)

```bash
git clone https://github.com/fockus/skill-memory-bank.git ~/.claude/skills/skill-memory-bank
cd ~/.claude/skills/skill-memory-bank
./install.sh
./install.sh --language ru
```

Upgrade via `scripts/mb-upgrade.sh` (reads `git fetch origin`).

## CLI reference (pipx / Homebrew)


| Command                                                                               | Purpose                                            |
| ------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `memory-bank install [--clients <list>] [--language <en|ru>] [--project-root <path>]` | Run global install + optional cross-agent adapters |
| `memory-bank uninstall [-y|--non-interactive]`                                        | Remove global install                              |
| `memory-bank init`                                                                    | Print `/mb init` hint (Claude Code command)        |
| `memory-bank version`                                                                 | Print version                                      |
| `memory-bank self-update`                                                             | Show upgrade command                               |
| `memory-bank doctor`                                                                  | Resolve bundle path + platform info                |
| `memory-bank --help`                                                                  | Full usage                                         |


`--clients` accepts: `claude-code, cursor, windsurf, cline, kilo, opencode, pi, codex`.

`--language` accepts: `en`, `ru`.

- TTY install without `--language` → interactive language prompt
- non-interactive install without `--language` → default `en`
- env override also works: `MB_LANGUAGE=ru memory-bank install`
- uninstall can also be non-interactive: `memory-bank uninstall -y`

`memory-bank install` now performs these global registrations:

- Canonical skill path: `~/.claude/skills/skill-memory-bank`
- Claude runtime alias: `~/.claude/skills/memory-bank`
- Codex runtime alias: `~/.codex/skills/memory-bank`
- Codex global hints: `~/.codex/AGENTS.md`

It also performs a native OpenCode global install:

- `~/.config/opencode/AGENTS.md`
- `~/.config/opencode/commands/*.md`

For Codex this is intentionally conservative:

- the skill, bundled commands, bundled agents, and bundled hooks are discoverable globally;
- project-level Codex config/hooks still live under `<project>/.codex/`;
- there is no native Codex `/mb install` command surface.

If you also pass `--clients opencode`, project-level OpenCode files are added under:

- `<project>/AGENTS.md`
- `<project>/opencode.json`
- `<project>/.opencode/plugins/memory-bank.js`
- `<project>/.opencode/commands/*.md`

See [cross-agent-setup.md](cross-agent-setup.md) for per-client details.

## Security-sensitive toggles

- Project-local `.memory-bank/metrics.sh` overrides are **disabled by default**. To run one intentionally, use `MB_ALLOW_METRICS_OVERRIDE=1`.
- Pi's native skill mode is **not** part of the supported default surface. The supported path is `agents-md`. If you need to probe the native API, gate it explicitly: `MB_PI_MODE=skill MB_EXPERIMENTAL_PI_SKILL=1 adapters/pi.sh install <project>`.

## Platform support


| Platform | Status                      |
| -------- | --------------------------- |
| macOS    | ✅ Full                      |
| Linux    | ✅ Full                      |
| Windows  | ⚠️ WSL only (bash required) |


Running `memory-bank install` on native Windows exits with a WSL hint.

## Troubleshooting

`**memory-bank: command not found**` — Ensure `~/.local/bin` (pipx) or
`/opt/homebrew/bin` (Homebrew) is on your `$PATH`.

`**memory-bank doctor` reports "Bundle: NOT FOUND"** — Something corrupted the
venv shared-data. Reinstall: `pipx reinstall memory-bank-skill`.

`**jq required` errors** — Install jq: `brew install jq` or `sudo apt install jq`.

**Upgrade didn't pick up new version** — `pipx reinstall memory-bank-skill`
(more aggressive than `pipx upgrade`).

`memory-bank uninstall` hangs in CI — pass `-y` / `--non-interactive`.
