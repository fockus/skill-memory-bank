# Migration guide: v1 → v2

This document explains how to migrate an existing skill install from version 1.x to 2.0.0.

---

## TL;DR

```bash
# 1. Update the skill source
cd ~/.claude/skills/skill-memory-bank
git fetch && git checkout v2.0.0

# 2. Reinstall (idempotent — existing user hooks are preserved)
./install.sh

# 3. After reinstall, these paths will be refreshed:
#    ~/.claude/skills/memory-bank
#    ~/.codex/skills/memory-bank
#    ~/.codex/AGENTS.md

# 4. In projects that already use .memory-bank/:
mv .planning/codebase .memory-bank/codebase 2>/dev/null || true
rm -f .memory-bank/index.json          # old index, will be regenerated
python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py .memory-bank
```

Done. Details below.

---

## Breaking changes

| # | What | v1 | v2 | Action |
|---|------|----|----|--------|
| 1 | Initialization command | `/mb:setup-project` | `/mb init --full` | Update habits / `.claude/commands/` — `install.sh` removes `setup-project.md` automatically |
| 2 | Mapping agent | `codebase-mapper` (orphan, GSD-style) | `mb-codebase-mapper` | `install.sh` removes the old agent. Update your own scripts accordingly |
| 3 | Codebase docs output path | `.planning/codebase/` | `.memory-bank/codebase/` | `mv .planning/codebase .memory-bank/codebase` |
| 4 | Subagent invocation from commands | `Task(prompt=..., subagent_type=...)` | `Agent(subagent_type=..., prompt=...)` | Automatic — `install.sh` updates it; custom commands must be updated manually |
| 5 | Python hardcode in `/mb update` | `.venv/bin/python -m pytest` | `bash mb-metrics.sh` | Automatic via `install.sh` |
| 6 | `SKILL.md` frontmatter | `user-invocable: false` (invalid) | `name: memory-bank` | Automatic |

---

## Step-by-step migration

### 1. Update the skill source

```bash
cd ~/.claude/skills/skill-memory-bank
git fetch origin
git log HEAD..origin/main --oneline   # inspect incoming changes
git checkout v2.0.0                   # or `main` for bleeding edge
```

If you modified the skill locally, run `git stash` first.

### 2. Reinstall

```bash
./install.sh
```

The script:
- Copies new commands/agents/hooks/scripts
- **Preserves your user hooks** in `settings.json` (covered by e2e tests)
- **Preserves your content above the** `[MEMORY-BANK-SKILL]` marker in `CLAUDE.md`
- Refreshes the install `manifest` for clean future uninstall

### 3. In every project with `.memory-bank/`

```bash
# (a) Move codebase docs if they came from the old codebase-mapper
if [ -d .planning/codebase ]; then
  mkdir -p .memory-bank/codebase
  mv .planning/codebase/*.md .memory-bank/codebase/ 2>/dev/null
fi

# (b) Remove the stale index.json (it will be rebuilt on next /mb done)
rm -f .memory-bank/index.json

# (c) Rebuild the index in v2 format
python3 ~/.claude/skills/memory-bank/scripts/mb-index-json.py .memory-bank
```

### 4. Verify

```bash
# Are all commands present?
ls ~/.claude/commands/ | wc -l        # expect 18

# Legacy command should be gone
ls ~/.claude/commands/setup-project.md 2>&1   # should print: No such file

# Agents
ls ~/.claude/agents/                  # mb-codebase-mapper.md, not codebase-mapper.md

# VERSION marker
cat ~/.claude/skills/memory-bank/VERSION   # 2.0.0
```

### 5. Optional: structural markers in existing plans

If you have active plans in `.memory-bank/plans/*.md` without `<!-- mb-stage:N -->` markers, `mb-plan-sync.sh` will still parse them through a fallback regex. New plans created by `scripts/mb-plan.sh` already include those markers automatically.

Manual marker example for older plans:

```markdown
<!-- mb-stage:1 -->
### Stage 1: Existing stage
```

---

## What did NOT break

- `.memory-bank/` structure (`STATUS`, `plan`, `checklist`, `RESEARCH`, `BACKLOG`, `progress`, `lessons`, `notes/`, `plans/`, `experiments/`, `reports/`) — 100% compatible
- Core file templates and semantics
- Numbering for H-NNN, EXP-NNN, ADR-NNN, L-NNN — unchanged
- MB Manager actions (`context`, `search`, `note`, `actualize`, `tasks`) — same API
- `mb-doctor` kept the same interface

---

## Rollback

If something went wrong, return to v1:

```bash
cd ~/.claude/skills/skill-memory-bank
./uninstall.sh               # removes the v2 install (preserves backups)
git checkout v1.0.0
./install.sh                 # installs v1

# Project-level `.memory-bank/` data stays untouched.
# If you moved `.planning/codebase/` → `.memory-bank/codebase/`, move it back manually.
```

Backups of your `CLAUDE.md` / `settings.json` use the suffix `.pre-mb-backup.<timestamp>`. Find them with:

```bash
ls ~/.claude/*.pre-mb-backup.*
```

---

## Known issues

| Problem | Workaround |
|---------|------------|
| `PyYAML` is not installed — `mb-index-json.py` uses a fallback parser. It understands `key: value` and `key: [a, b]`, but not nested structures. | Install `pip install pyyaml` for full support. The fallback is enough for simple frontmatter. |
| On macOS, `realpath -m` does not work (fixed in v2) | If you used v1 on macOS, just reinstall |
| `settings.json` may contain duplicated hooks from older versions | `./uninstall.sh && ./install.sh` — idempotent reinstall cleans it up |

---

## Support

- Issues: https://github.com/fockus/skill-memory-bank/issues
- CHANGELOG: [../CHANGELOG.md](../CHANGELOG.md)
- Version: `cat ~/.claude/skills/memory-bank/VERSION`
