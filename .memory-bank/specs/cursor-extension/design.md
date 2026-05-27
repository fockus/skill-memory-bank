---
type: spec-design
topic: cursor-extension
status: ready
created: 2026-05-24
linked_requirements: requirements.md
linked_tasks: tasks.md
---

# Design: Cursor Extension (adapter + hook parity)

Closes the Cursor compatibility gap in `reports/2026-05-24_cursor-compatibility-audit.md`.
Cursor already has a Claude-Code-compatible hooks API — remediation is **wiring and
path resolution**, not a new runtime extension.

## 1. Architecture overview

```
~/.cursor/skills/memory-bank/          ← canonical skill bundle (symlink)
├── hooks/
│   ├── _skill_root.sh                 ← NEW: shared resolver
│   ├── mb-session-start-context.sh
│   ├── session-end-autosave.sh
│   ├── mb-compact-reminder.sh         ← renamed → mb-pre-compact.sh (handoff-v2)
│   ├── block-dangerous.sh
│   ├── mb-protected-paths-guard.sh
│   ├── mb-ears-pre-write.sh
│   ├── mb-context-slim-pre-agent.sh
│   ├── mb-sprint-context-guard.sh
│   ├── file-change-log.sh
│   └── mb-plan-sync-post-write.sh
├── scripts/                           ← hooks resolve HERE via _skill_root.sh
└── SKILL.md

~/.cursor/hooks.json                   ← global (install.sh)
<project>/.cursor/hooks.json           ← project adapter (optional)

# REMOVED pattern (legacy):
~/.cursor/hooks/*.sh                     ← copies break ../scripts resolution
<project>/.cursor/hooks/*.sh
```

## 2. `_skill_root.sh` resolver

### 2.1 Candidate order

1. `$MB_SKILL_ROOT` if set and directory exists
2. Parent of hook dir if it contains `SKILL.md` or `VERSION` (in-repo / dev checkout)
3. `$HOME/.cursor/skills/memory-bank`
4. `$HOME/.claude/skills/memory-bank` / `skill-memory-bank`
5. `$HOME/.codex/skills/memory-bank`

### 2.2 Public functions

| Function | Purpose |
|----------|---------|
| `mb_skill_root_resolve hook_dir` | Best skill root path |
| `mb_skill_scripts_dir hook_dir` | Absolute `scripts/` path |
| `mb_skill_script_path name hook_dir` | Absolute script path |
| `mb_hook_default_agent` | `cursor` when Cursor skill installed |
| `mb_hook_resolve_mb_path cwd` | MB_PATH → local → registry |

Registry lookup sources `_lib.sh` in a subshell (same pattern as pre-remediation session hooks).

## 3. Cursor adapter changes (`adapters/cursor.sh`)

### 3.1 Hook command format

```bash
# Example hooks.json entry (global or project):
{
  "command": "MB_AGENT=cursor MB_SKILLS_ROOT=/Users/me/.cursor/skills bash \"/Users/me/.cursor/skills/memory-bank/hooks/mb-plan-sync-post-write.sh\"",
  "matcher": "Write",
  "_mb_owned": true
}
```

Built by `cursor_build_hooks_json "$skill_hooks_dir"` where `skill_hooks_dir` comes from `cursor_resolve_skill_hooks_dir()`:

1. `$HOME/.cursor/skills/memory-bank/hooks` if present
2. Else `$SKILL_DIR/hooks` (repo-relative install)

### 3.2 Install flow (project)

1. Write `.cursor/rules/memory-bank.mdc`
2. Verify all `MB_HOOKS[]` exist in skill bundle
3. `cursor_remove_legacy_hook_copies` — delete stale `.cursor/hooks/*.sh`
4. Merge `hooks.json` with bundle-referenced commands
5. Manifest: rules + hooks.json + skill hooks dir path

### 3.3 Install flow (global)

Same hook wiring into `~/.cursor/hooks.json`. **Do not** copy hook scripts to `~/.cursor/hooks/`. Continue mirroring `commands/*.md` to `~/.cursor/commands/`.

### 3.4 AGENTS.md section update

Replace “Hooks: `~/.cursor/hooks/`” with “Hooks: bundled at `~/.cursor/skills/memory-bank/hooks/` wired via `~/.cursor/hooks.json`”.

## 4. Hook event map (10 bindings)

| Cursor event | Script | Matcher |
|--------------|--------|---------|
| `sessionStart` | `mb-session-start-context.sh` | — |
| `sessionEnd` | `session-end-autosave.sh` | — |
| `preCompact` | `mb-compact-reminder.sh` → `mb-pre-compact.sh` | — |
| `beforeShellExecution` | `block-dangerous.sh` | — |
| `preToolUse` | `mb-protected-paths-guard.sh` | Write\|Edit |
| `preToolUse` | `mb-ears-pre-write.sh` | Write |
| `preToolUse` | `mb-context-slim-pre-agent.sh` | Task |
| `preToolUse` | `mb-sprint-context-guard.sh` | Task |
| `postToolUse` | `file-change-log.sh` | Write\|Edit |
| `postToolUse` | `mb-plan-sync-post-write.sh` | Write |

## 5. Global storage path

```
/mb init --storage=global --agent=cursor
  → registry: ~/.cursor/skills/memory-bank/projects/<id>/.memory-bank/
  → hooks: MB_AGENT=cursor + mb_registry_lookup("cursor", MB_PROJECT_ROOT)
  → sessionStart injects context without local .memory-bank/
```

## 6. Parallel pipeline dispatch (W12)

Cursor orchestrator pattern mirrors Claude Code:

```
1. mb-run executor writes wave-*-dispatches.json
2. commands/run.md instructs main agent to read file
3. Main agent issues N Task() calls in one response
4. Each subagent writes expected_artifact
5. Executor resumes wait_for_artifacts loop
```

Document in `adapters/cursor/dispatch.md` (no bash loop required unless fallback).
Update `parallel-pipeline` matrix: Cursor = ✅ parallel via Task orchestrator.

## 7. Migration from legacy installs

On `install` / `install-global`:

1. Remove files in `MB_HOOKS[]` from `~/.cursor/hooks/` and `.cursor/hooks/`
2. Rewrite `_mb_owned` entries in hooks.json to bundle paths
3. Leave user-owned hook entries untouched

## 8. Testing strategy

| Layer | Files |
|-------|-------|
| Unit | `tests/bats/test_skill_root_resolver.bats` (new) |
| Adapter | `tests/bats/test_cursor_adapter.bats` — bundle paths, no copies |
| E2E global | `tests/e2e/test_cursor_global.bats` — hooks.json points to bundle |
| Contract | `tests/pytest/test_cursor_hooks_registration.py` |
| Integration | Hook smoke: plan-sync finds scripts when invoked from `/tmp` copy path |

## 9. Non-goals

- Cursor User Rules file API (platform limitation)
- Cursor CLI full hook parity (platform limitation)
- TypeScript plugin for hooks (unnecessary — native API sufficient)
