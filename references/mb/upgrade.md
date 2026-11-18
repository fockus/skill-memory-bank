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

**Automatic release check (SessionStart notice).** Independent of the `upgrade` command above,
`scripts/mb-version-check.sh` answers "is a newer release out?" (GitHub Release, PyPI JSON
fallback, TTL-cached) and `hooks/mb-update-notify.sh` renders its answer at SessionStart: an
up-to-date session sees nothing; an out-of-date one sees a ≤3-line notice naming `current ->
latest` and the exact upgrade command for the detected install flavor (`git pull` for a clone,
the matching `pipx`/`pip`/`brew` command otherwise — a package manager is only ever *named*, never
run on your behalf). Controlled by three env vars:

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
