# Installation

Three paths. Pick the one that fits.

## Path A — pipx (recommended)

**Requires:** Python 3.11+, `pipx` ([install guide](https://pipx.pypa.io/)).

```bash
pipx install memory-bank-skill
memory-bank install --clients claude-code,cursor    # global + per-project adapters
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
```

Upgrades: `brew upgrade memory-bank`.

## Path C — git clone (developers / contributors)

```bash
git clone https://github.com/fockus/skill-memory-bank.git ~/.claude/skills/skill-memory-bank
cd ~/.claude/skills/skill-memory-bank
./install.sh
```

Upgrade via `scripts/mb-upgrade.sh` (reads `git fetch origin`).

## CLI reference (pipx / Homebrew)

| Command | Purpose |
|---------|---------|
| `memory-bank install [--clients <list>] [--project-root <path>]` | Run global install + optional cross-agent adapters |
| `memory-bank uninstall` | Remove global install |
| `memory-bank init` | Print `/mb init` hint (Claude Code command) |
| `memory-bank version` | Print version |
| `memory-bank self-update` | Show upgrade command |
| `memory-bank doctor` | Resolve bundle path + platform info |
| `memory-bank --help` | Full usage |

`--clients` accepts: `claude-code, cursor, windsurf, cline, kilo, opencode, pi, codex`.

`memory-bank install` now performs a native OpenCode global install too:
- `~/.config/opencode/AGENTS.md`
- `~/.config/opencode/commands/*.md`

If you also pass `--clients opencode`, project-level OpenCode files are added under:
- `<project>/AGENTS.md`
- `<project>/opencode.json`
- `<project>/.opencode/plugins/memory-bank.js`
- `<project>/.opencode/commands/*.md`

See [cross-agent-setup.md](cross-agent-setup.md) for per-client details.

## Platform support

| Platform | Status |
|----------|--------|
| macOS | ✅ Full |
| Linux | ✅ Full |
| Windows | ⚠️ WSL only (bash required) |

Running `memory-bank install` on native Windows exits with a WSL hint.

## Troubleshooting

**`memory-bank: command not found`** — Ensure `~/.local/bin` (pipx) or
`/opt/homebrew/bin` (Homebrew) is on your `$PATH`.

**`memory-bank doctor` reports "Bundle: NOT FOUND"** — Something corrupted the
venv shared-data. Reinstall: `pipx reinstall memory-bank-skill`.

**`jq required` errors** — Install jq: `brew install jq` or `sudo apt install jq`.

**Upgrade didn't pick up new version** — `pipx reinstall memory-bank-skill`
(more aggressive than `pipx upgrade`).
