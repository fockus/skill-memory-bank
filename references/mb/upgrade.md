# /mb upgrade — reference

Loaded by `commands/mb.md` when the first word of `$ARGUMENTS` routes here. `$SKILL_DIR` and the bank setup are defined in `commands/mb.md`.

## Router entries

- `upgrade` — Update the skill from GitHub (`git pull + re-install`). Flags: `--check` (check only), `--force` (skip confirmation)

### upgrade

Update the skill to the latest version from GitHub. Requires a `git clone` installation.

Flags (the first word after `upgrade`):

- (no flags) — check and apply after confirmation
- `--check` — check only (exit 1 if an update is available, exit 0 if already up to date)
- `--force` — apply without interactive confirmation

**Session-start notice.** When the release cache confirms an update, the notice shows
`current -> latest` and the command for your installation. Run it yourself or ask the agent
to update Memory Bank for you. If the install method is unknown, the notice asks how you
installed Memory Bank instead of guessing a command. Current or unverified releases stay silent.
Codex and Pi pass the notice to both the root session UI and its next reply. Claude Code uses
SessionStart output; Cursor uses `sessionStart.additional_context`. On hosts without a release
hook, the root agent checks once with `MB_AUTO_UPDATE=off` and relays any notice.
Startup reads the local cache; a cache miss triggers a background refresh for a later session
(GitHub Releases, with PyPI as fallback).

- `MB_UPDATE_CHECK` (default `on`) — `off` disables the check entirely, no output, no network call.
- `MB_UPDATE_CHECK_TTL` (default `86400`, 24h) — cache TTL; at most one network call per window,
  an invalid value falls back to the default.
- `MB_AUTO_UPDATE` (default `off`) — `on` auto-applies the update (`mb-upgrade.sh --force`), but
  ONLY for a git-clone install with a clean working tree; pipx/pip/brew installs are never
  auto-run, and a dirty git tree refuses (notice-only). Fail-open: never blocks a session.

Run directly (no subagent — this is a systems-level operation, no LLM needed):

```bash
bash ${MB_SKILLS_ROOT:-$HOME/.claude/skills/memory-bank}/scripts/mb-upgrade.sh $ARGS_AFTER_UPGRADE
```

The script:

1. Pre-flight: checks that `~/.claude/skills/skill-memory-bank` is a git repo with a clean working tree
2. Reads the `VERSION` file and local commit hash
3. Runs `git fetch origin` and compares local vs remote (`ahead/behind`)
4. Shows pending commits (`git log HEAD..origin/main`)
5. If `--check` is used — exits with a status code
6. If updates exist and `--force` is not used — asks for confirmation
7. On confirmation: `git pull --ff-only` + re-run `install.sh` (idempotent merge of hooks/commands)
8. Prints `local → new` version

**Typical flow:**

```
User: /mb upgrade
→ script fetches, shows: "3 behind, 0 ahead"
→ shows the latest 3 commits
→ asks: "Apply 3 updates? (y/n)"
→ user: y
→ `git pull` + `bash install.sh` → manifest refreshed
→ "Skill updated: 2.0.0-dev (cd65d0a) → 2.1.0 (abc1234)"
```

**Errors:**

- Skill is not a git clone → suggest reinstalling via clone
- Dirty working tree → suggest `git stash` / `git checkout --`
- Divergent branches → suggest manual pull
- Non-interactive mode without `--force` → error

**IMPORTANT:** The skill repo (`~/.claude/skills/skill-memory-bank`) is the canonical source. After `git pull`, `install.sh` must be rerun to refresh host-specific globals, symlink aliases `~/.claude/skills/memory-bank` and `~/.codex/skills/memory-bank`, and the managed block in `~/.codex/AGENTS.md`. The script does this automatically.
