# Cursor × Memory Bank — compatibility audit

**Date:** 2026-05-24  
**Scope:** `adapters/cursor.sh`, global `install.sh` Cursor path, all 10 hooks, docs vs implementation, parallel-pipeline S5 readiness  
**Linked spec:** `specs/cursor-extension/`  
**Linked plan:** `plans/2026-05-24_fix_cursor-compatibility-remediation.md`

---

## Executive summary

| Level | Count |
|-------|-------|
| 🔴 Blocker (hooks silently broken — user thinks MB works but scripts never run) | 1 |
| 🟠 Critical gap (feature degraded vs Claude Code) | 3 |
| 🟡 Warning (docs drift, legacy migration) | 4 |
| 🟢 Works correctly today | 6 |

**Verdict:** Cursor is documented as **“full global + project, CC-compat”**, but the project adapter **copied hook scripts into `~/.cursor/hooks/` or `.cursor/hooks/`**, breaking `$SCRIPT_DIR/../scripts/` resolution. Five hooks fail open with no user-visible error. Global storage (`/mb init --storage=global --agent=cursor`) is not wired because `MB_AGENT=cursor` was missing from hook commands. Remediation is **bash-only** (no TypeScript extension like Pi) — see `specs/cursor-extension/`.

---

## 1. What works today (🟢)

### 1.1 Global skill install
- `install.sh` creates `~/.cursor/skills/memory-bank` → canonical bundle symlink
- Cursor discovers `SKILL.md` from global skills path
- **Test:** `tests/e2e/test_cursor_global.bats` — symlink parity PASS

### 1.2 Rules + AGENTS.md + User Rules paste-file
- `~/.cursor/AGENTS.md` managed section with marker `memory-bank-cursor:start/end`
- `~/.cursor/memory-bank-user-rules.md` for Settings → Rules → User Rules paste
- Project adapter writes `.cursor/rules/memory-bank.mdc` with `alwaysApply: true`

### 1.3 Slash commands mirror
- `commands/*.md` copied to `~/.cursor/commands/` on global install

### 1.4 CC-compat hooks.json registration (structure)
- Ten events registered with `_mb_owned: true`
- Merge preserves user hooks in existing `hooks.json`

### 1.5 Hooks that worked even with broken copy layout
- `block-dangerous.sh` — self-contained
- Session hooks when **local** `.memory-bank/` exists

### 1.6 Cursor native hook surface
- Cursor 1.7+ supports CC-compat events including `preToolUse` / `postToolUse` / `sessionStart` (IDE)

---

## 2. Blocker (🔴)

### 🔴 B1: Copied hooks break bundled `scripts/` resolution

Adapter copied hooks to `.cursor/hooks/`; `$SCRIPT_DIR/../scripts/` resolved to non-existent `~/.cursor/scripts/`. Five hooks fail open silently.

**Fix:** Skill-bundle hook paths + `hooks/_skill_root.sh` (REQ-300..REQ-303).

---

## 3. Critical gaps (🟠)

- **C1:** Global storage — missing `MB_AGENT=cursor` on hook commands (REQ-304, REQ-305)
- **C2:** Hardcoded `~/.claude/` paths in compact reminder + file-change-log (REQ-306, REQ-307)
- **C3:** `mb-reviewer-resolve.sh` ignores `~/.cursor/skills` (REQ-308)

---

## 4. Warnings (🟡)

- **W1:** Docs list 3 hooks; implementation has 10
- **W2:** Legacy `~/.cursor/hooks/*.sh` copies need cleanup on upgrade
- **W3:** `handoff-v2` hook rename must sync to Cursor adapter
- **W4:** Parallel pipeline marks Cursor TBD — Cursor can use Task dispatch like Claude Code

---

## 5. Recommended sequence

See `plans/2026-05-24_fix_cursor-compatibility-remediation.md` and `specs/cursor-extension/tasks.md`.
