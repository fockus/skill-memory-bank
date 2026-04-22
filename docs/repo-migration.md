# Repository migration guide — v2.2 → v3.0

The skill has moved to a new public repository:

- **Old:** `github.com/fockus/claude-skill-memory-bank`
- **New:** `github.com/fockus/skill-memory-bank` ← canonical going forward

The old repository stays online in read-only state (historical tags remain
accessible). All new releases, issues, and PRs happen in the new repo.

**Why the move:** after Stage 8 (Cross-agent adapters) the skill supports
8 AI coding clients beyond Claude Code — the `claude-` prefix became misleading.
See [ADR-011](../.memory-bank/backlog.md) for full rationale.

---

## Upgrade for existing users

### 1. Update git remote

```bash
cd ~/.claude/skills/claude-skill-memory-bank   # old path
git remote set-url origin https://github.com/fockus/skill-memory-bank.git
git fetch origin
git pull origin main
```

### 2. Rename the install directory (recommended)

`mb-upgrade.sh` now expects `~/.claude/skills/skill-memory-bank/` as the default
install location.

```bash
mv ~/.claude/skills/claude-skill-memory-bank ~/.claude/skills/skill-memory-bank
```

If you keep the old path, override via environment variable:

```bash
export MB_SKILL_DIR="$HOME/.claude/skills/claude-skill-memory-bank"
```

(add to your `.zshrc` / `.bashrc` if you want it permanent).

### 3. Re-run install.sh

```bash
cd ~/.claude/skills/skill-memory-bank
bash install.sh
```

This refreshes `~/.claude/{RULES.md,commands/,agents/,hooks/}` and registers the
new skill directory. It also refreshes the managed aliases:
- `~/.claude/skills/memory-bank`
- `~/.codex/skills/memory-bank`
- `~/.codex/AGENTS.md`

Safe to run on top of existing state.

### 4. (Optional) Enable cross-agent adapters

New in v3.0 — install into any project:

```bash
# Global + project-level adapters
bash install.sh --clients claude-code,cursor,windsurf --project-root ~/my-project

# Full list of supported clients:
# claude-code, cursor, windsurf, cline, kilo, opencode, pi, codex
```

See [cross-agent-setup.md](cross-agent-setup.md) for per-client details.

---

## Troubleshooting

### `git fetch` shows "repository moved" or 301 redirect

GitHub auto-redirects HTTPS clones from old URLs, but the redirect is transparent
only for cloning. For ongoing operations update the remote as shown above.

### `mb-upgrade.sh` still points at the old repo

Re-install: `bash install.sh` — the upgrade script is overwritten with the new URL.

### My existing `.memory-bank/` changes are safe?

Yes. Migration only touches global install (`~/.claude/`) and the skill source
directory. Project-local `.memory-bank/` directories are untouched.

### Tag `v2.2.0` release notes show old repo

Historical tags resolve against the repo where they were originally pushed.
`v2.0.0` / `v2.1.0` / `v2.2.0` remain in the old repo; `v3.0.0` and forward live
in the new repo.

### Issues / PRs

New issues and PRs: [github.com/fockus/skill-memory-bank/issues](https://github.com/fockus/skill-memory-bank/issues).
Old issues remain linkable (read-only) but won't be actively triaged.

---

## What changed besides the URL

Stage 8 + rename batch (v3.0.0-rc1):

- 7 cross-agent adapters (`adapters/cursor.sh`, `windsurf.sh`, `cline.sh`,
  `kilo.sh`, `opencode.sh`, `codex.sh`, `pi.sh`) + `git-hooks-fallback.sh`
- `install.sh --clients <list>` non-interactive flag
- Shared `AGENTS.md` refcount library (`adapters/_lib_agents_md.sh`)
- `docs/cross-agent-setup.md` — complete per-client reference
- **340+/340+ bats+e2e green** (previous v2.2.0: 257/257)

No breaking changes to `.memory-bank/` contents, Memory Bank workflow,
`/mb` commands, or rules. Backward-compatible upgrade.

---

## Skipped the rename, stay on old repo?

Possible but not recommended: no new features or fixes will land there.
Install script reinstallation is still required for Stage 8 features
(adapter invocation via `--clients`).
