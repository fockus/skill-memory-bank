---
type: spec-requirements
topic: cursor-extension
status: ready
created: 2026-05-24
linked_design: design.md
linked_tasks: tasks.md
linked_audit: reports/2026-05-24_cursor-compatibility-audit.md
---

# Requirements: Cursor Extension (adapter + hook parity)

EARS-validated functional requirements for first-class Cursor IDE integration.
Unlike Pi, Cursor exposes a **native CC-compatible hooks API** — no TypeScript
extension is required for hook guards and session lifecycle. This spec covers
hook infrastructure, adapter wiring, global storage, tests, docs, and optional
parallel-pipeline dispatch.

## Functional Requirements (EARS)

### Hook skill-root resolution

- **REQ-300** The skill shall provide `hooks/_skill_root.sh` that resolves the canonical skill bundle root from hook location, `MB_SKILL_ROOT`, or known install paths (`~/.cursor/skills/memory-bank`, `~/.claude/skills/memory-bank`, repo checkout).
- **REQ-301** When a hook needs a bundled script, the hook shall resolve it via `mb_skill_script_path()` rather than `$SCRIPT_DIR/../scripts/`.
- **REQ-302** When a hook needs Memory Bank path resolution, the hook shall use `mb_hook_resolve_mb_path()` supporting `MB_PATH`, local `.memory-bank/`, and registry lookup.
- **REQ-303** When `MB_AGENT` is unset and `~/.cursor/skills/memory-bank` exists, `mb_hook_default_agent()` shall return `cursor`.

### Cursor adapter (hooks.json wiring)

- **REQ-304** The Cursor adapter shall register all ten Memory Bank hooks in `hooks.json` with `_mb_owned: true`.
- **REQ-305** When the Cursor adapter builds hook commands, it shall prefix each command with `MB_AGENT=cursor` and `MB_SKILLS_ROOT=<resolved>` and invoke scripts from the **skill bundle** absolute path (not copied into `.cursor/hooks/`).
- **REQ-306** When the Cursor adapter installs or upgrades, it shall remove legacy hook script copies from `~/.cursor/hooks/` and `<project>/.cursor/hooks/` that match `MB_HOOKS[]`.
- **REQ-307** The Cursor adapter manifest shall track `hooks.json`, rules file, and skill hooks directory — not per-script copies under `.cursor/hooks/`.

### Session lifecycle hooks

- **REQ-308** On `sessionStart`, when a Memory Bank resolves, the hook shall return JSON with `additional_context` containing status, unfinished checklist items, and roadmap hints (cap 2500 chars).
- **REQ-309** On `sessionEnd`, when `MB_AUTO_CAPTURE=auto`, the hook shall append an idempotent placeholder to `progress.md` unless a fresh session lock exists.
- **REQ-310** On `preCompact`, when `.last-compact` is older than 7 days and dry-run reports candidates > 0, the hook shall print a compaction reminder to stderr.

### PreToolUse / postToolUse guards

- **REQ-311** On `preToolUse` for Write/Edit, the hook shall block paths matching `pipeline.yaml:protected_paths` unless `MB_ALLOW_PROTECTED=1`.
- **REQ-312** On `preToolUse` for Write, when the target is a spec requirements file, the hook shall run EARS validation before allowing the write.
- **REQ-313** On `preToolUse` for Task, when `MB_WORK_MODE=slim`, the hook shall emit trimmed stage context via `hookSpecificOutput.additionalContext`.
- **REQ-314** On `preToolUse` for Task, when sprint token budget exceeds configured threshold, the hook shall warn or block per `mb-session-spend.sh` policy.
- **REQ-315** On `postToolUse` for Write/Edit, the hook shall log changes and warn on placeholders/secrets in code files.
- **REQ-316** On `postToolUse` for Write to `.memory-bank/plans/*.md` or `specs/*.md`, the hook shall run plan-sync → roadmap-sync → traceability chain (best-effort).

### Agent-specific paths

- **REQ-317** When `MB_AGENT=cursor`, `file-change-log.sh` shall write to `~/.cursor/file-changes.log` instead of `~/.claude/file-changes.log`.
- **REQ-318** `mb-reviewer-resolve.sh` shall probe skill overrides in both `~/.cursor/skills` and `~/.claude/skills` when `MB_SKILLS_ROOT` is unset.

### Documentation accuracy

- **REQ-319** `docs/cross-agent-setup.md` shall document all ten Cursor hook bindings and skill-bundle hook paths (not `.cursor/hooks/` copies).
- **REQ-320** `SKILL.md` Cursor section shall state that hooks run from the skill bundle and require global or project `hooks.json` registration.

### Parallel pipeline dispatch (W12 follow-up)

- **REQ-321** The repository shall define `adapters/cursor/dispatch.md` describing how the orchestrator issues parallel `Task` tool calls from `dispatches.json` (Claude-Code-compatible pattern).
- **REQ-322** `specs/parallel-pipeline/design.md` capability matrix shall list Cursor as **parallel via Task orchestrator** (not TBD) once REQ-321 lands.
- **REQ-323** When the Cursor dispatch adapter is unavailable, `/mb run` shall fall back to sequential Task dispatch with stderr WARN.

### handoff-v2 compatibility

- **REQ-324** When `handoff-v2` renames `mb-compact-reminder.sh` to `mb-pre-compact.sh`, the Cursor adapter `EVENT_BINDINGS` shall register the new script name and remove the old binding.

## Constraints

- No new npm/TypeScript dependencies for Cursor hook parity.
- Cursor User Rules remain manual paste only (Cursor has no file API) — unchanged.
- Cursor CLI hook coverage remains limited to shell events — document IDE vs CLI in setup guide.
- Fail-open on missing jq or missing scripts must log to stderr when `MB_HOOK_DEBUG=1`.
