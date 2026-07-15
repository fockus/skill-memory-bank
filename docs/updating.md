# Staying up to date

Memory Bank has three install paths (pipx, Homebrew, git clone), each with its own upgrade
command. This page covers only the released, on-demand upgrade paths — pick the one that matches
how you installed in the first place.

## pipx (recommended path)

```bash
pipx upgrade memory-bank-skill
```

If an upgrade doesn't seem to pick up the new version (stale cached wheel, partial venv state),
force a clean reinstall instead:

```bash
pipx reinstall memory-bank-skill
```

After upgrading, re-run the global install so any new hooks/commands/agents get wired in:

```bash
memory-bank install
```

Verify the result:

```bash
memory-bank doctor
memory-bank version
```

## Homebrew (macOS / Linuxbrew)

```bash
brew upgrade memory-bank
memory-bank install
```

`brew upgrade` only updates the CLI package itself; `memory-bank install` is what actually
refreshes the hooks, commands, and agent files under your host's config directory
(`~/.claude/`, `~/.codex/`, `~/.cursor/`, etc.) to match the new version.

## git clone (developers / contributors)

For a `git clone` install, the canonical way to check for and apply an update is the skill's own
`/mb upgrade` command, backed by `scripts/mb-upgrade.sh`:

```bash
/mb upgrade            # check, show pending commits, ask for confirmation, then apply
/mb upgrade --check    # check only — exit 1 if an update is available, exit 0 if current
/mb upgrade --force    # apply without an interactive confirmation prompt
```

What it does under the hood:

1. Pre-flight: confirms `~/.claude/skills/skill-memory-bank` is a git repository with a clean
   working tree.
2. Reads the local `VERSION` file and current commit hash.
3. Runs `git fetch origin` and compares local vs. remote (`ahead`/`behind`).
4. Shows the pending commits (`git log HEAD..origin/main`).
5. With `--check`, still prints the local/remote version+commit, ahead/behind status, and the
   pending commit log, then exits `1` if an update is available or `0` if already current (no
   pull, no prompt).
6. Without `--check` or `--force`, asks for confirmation before applying.
7. On confirmation (or with `--force`): `git pull --ff-only`, then re-runs `install.sh` — an
   idempotent merge of hooks/commands into your host config.
8. Prints the version transition, e.g. `2.0.0-dev (cd65d0a) → 2.1.0 (abc1234)`.

You can also drive the same script directly without going through the slash command:

```bash
git -C ~/.claude/skills/skill-memory-bank fetch origin
bash ~/.claude/skills/skill-memory-bank/scripts/mb-upgrade.sh --check
bash ~/.claude/skills/skill-memory-bank/scripts/mb-upgrade.sh --force
```

### Common failure modes

- **Skill is not a git clone** — you likely installed via pipx or Homebrew instead; use the
  matching section above rather than `/mb upgrade`.
- **Dirty working tree** — `/mb upgrade` refuses to pull over local edits. Stash or discard them
  first (`git stash` or `git checkout --`), then retry.
- **Divergent branches** — `git fetch` shows both ahead and behind commits; resolve manually
  (`git log`, `git merge`/`git rebase` as appropriate) rather than forcing a fast-forward pull.
- **Non-interactive mode without `--force`** — automated/CI contexts should always pass
  `--force` explicitly rather than relying on a prompt that can't be answered.

**Important:** the skill repo (`~/.claude/skills/skill-memory-bank`) is the canonical source.
After `git pull`, `install.sh` must be re-run to refresh host-specific globals — the runtime
aliases (`~/.claude/skills/memory-bank`, `~/.codex/skills/memory-bank`), and the managed block in
`~/.codex/AGENTS.md`. `/mb upgrade`/`mb-upgrade.sh` does this automatically as its last step; if
you ever pull manually outside the script, re-run `./install.sh` yourself afterward.

## Troubleshooting an install, generally

If the upgrade itself succeeds but something still looks wrong afterward, `install.md`'s
troubleshooting section covers the general cases: `memory-bank: command not found` (check
`~/.local/bin` for pipx or `/opt/homebrew/bin` for Homebrew is on `$PATH`), `memory-bank doctor`
reporting `Bundle: NOT FOUND` (reinstall via `pipx reinstall memory-bank-skill`), missing `jq`
(`brew install jq` / `sudo apt install jq`), and `memory-bank uninstall` hanging in CI (pass
`-y`/`--non-interactive`).

## Related

- [Installation](install.md) — the three install paths from scratch, plus the full CLI reference.
- `/mb upgrade` — the router entry for the git-clone upgrade command (`commands/mb.md`).
