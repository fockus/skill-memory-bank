# Memory Bank Hooks — Installation & Reference

## Contents

- [1. `hooks/mb-protected-paths-guard.sh` — block writes to protected paths](#1-hooksmb-protected-paths-guardsh--block-writes-to-protected-paths)
- [2. `hooks/mb-plan-sync-post-write.sh` — keep bank consistent after Markdown edits](#2-hooksmb-plan-sync-post-writesh--keep-bank-consistent-after-markdown-edits)
- [3. `hooks/mb-ears-pre-write.sh` — block invalid EARS requirements before they land](#3-hooksmb-ears-pre-writesh--block-invalid-ears-requirements-before-they-land)
- [4. `hooks/mb-context-slim-pre-agent.sh` — emit slim-context advisory on Task dispatch](#4-hooksmb-context-slim-pre-agentsh--emit-slim-context-advisory-on-task-dispatch)
- [5. `hooks/mb-sprint-context-guard.sh` — runtime token-spend watcher](#5-hooksmb-sprint-context-guardsh--runtime-token-spend-watcher)
- [Combined snippet](#combined-snippet)
- [Operational notes](#operational-notes)
- [Related](#related)
- [Session-memory lifecycle hooks](#session-memory-lifecycle-hooks)
  - [Claude Code hooks](#claude-code-hooks)
  - [Pi adapter hooks](#pi-adapter-hooks)
  - [Doctor diagnostics](#doctor-diagnostics)
- [Cursor adapter wiring](#cursor-adapter-wiring)
- [Hook inventory](#hook-inventory)

This document covers the Memory Bank lifecycle hooks. The first five entries are Claude Code tool hooks that run around writes and subagent dispatches; the Cursor section at the end documents the 10-hook Cursor adapter contract. Hooks are installed automatically by `install.sh`; the JSON snippets below remain useful for manual debugging or custom hosts.

---

## 1. `hooks/mb-protected-paths-guard.sh` — block writes to protected paths

**Event:** `PreToolUse`
**Matchers:** `tool_name ∈ {Write, Edit}` and `tool_input.file_path` matches a glob in `pipeline.yaml:protected_paths` (default: `.env*`, `ci/**`, `.github/workflows/**`, `Dockerfile*`, `k8s/**`, `terraform/**`).

**Behavior:**

- Reads JSON from stdin via `jq`.
- Skips if the tool is anything other than `Write` / `Edit`.
- Skips if `MB_ALLOW_PROTECTED=1` (mirrors the `--allow-protected` flag of `/mb work`).
- Delegates to `scripts/mb-work-protected-check.sh` for the actual glob match (so the rule definition lives in one place).
- Exit `2` blocks the tool call with a clear stderr message explaining the override.

**`~/.claude/settings.json` snippet:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-protected-paths-guard.sh" }
        ]
      }
    ]
  }
}
```

Override per-session: `MB_ALLOW_PROTECTED=1 claude` (or run `/mb work --allow-protected`, which sets the variable for the loop).

---

## 2. `hooks/mb-plan-sync-post-write.sh` — keep bank consistent after Markdown edits

**Event:** `PostToolUse`
**Matchers:** `tool_name == "Write"` and `tool_input.file_path` matches `*plans/*.md` or `*specs/*/*.md`.

**Behavior:**

- Triggers the deterministic chain that keeps `roadmap.md` / `traceability.md` / active-plans block in sync with the latest plan or spec edit:

  ```
  scripts/mb-plan-sync.sh
    → scripts/mb-roadmap-sync.sh
      → scripts/mb-traceability-gen.sh
  ```

- Each step is best-effort: if a script is missing it is skipped silently; if a script exits non-zero, a warning is logged but the hook still exits `0` (PostToolUse should never block downstream behavior).

**`~/.claude/settings.json` snippet:**

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-plan-sync-post-write.sh" }
        ]
      }
    ]
  }
}
```

---

## 3. `hooks/mb-ears-pre-write.sh` — block invalid EARS requirements before they land

**Event:** `PreToolUse`
**Matchers:** `tool_name == "Write"` and `tool_input.file_path` matches `*specs/*/requirements.md` or `*context/*.md`.

**Behavior:**

- Pulls `tool_input.content` from the JSON.
- Pipes it through `scripts/mb-ears-validate.sh -` (stdin form).
- Exit `2` if any REQ line fails the EARS regex; the validator's stderr is forwarded to the user with each line prefixed `[ears-pre-write]`.
- Exit `0` for unrelated paths, missing content, or valid REQ lines.

This complements `/mb plan --sdd` (strict) and `/mb sdd` (hard EARS requirement). Manual edits to `specs/*/requirements.md` are caught even when the user bypasses the slash command.

**`~/.claude/settings.json` snippet:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-ears-pre-write.sh" }
        ]
      }
    ]
  }
}
```

---

## 4. `hooks/mb-context-slim-pre-agent.sh` — emit slim-context advisory on Task dispatch

**Event:** `PreToolUse`
**Matchers:** `tool_name` is `Agent` (Claude Code 2.1+) or `Task` (earlier versions) and `MB_WORK_MODE=slim` is set in the environment.

**Behavior (Sprint 2):**

- When `MB_WORK_MODE=slim` and the prompt advertises `Plan: <path.md>` and `Stage: <N>` markers, the hook delegates to `scripts/mb-context-slim.py` to produce a trimmed view containing the active stage block + DoD bullets + `covers_requirements` REQ list + `git diff --staged`.
- The trimmed text is emitted via JSON `hookSpecificOutput.additionalContext` so Claude Code can surface it to the orchestrator without mutating the original `tool_input`.
- No-op (advisory only) when `MB_WORK_MODE` is unset, `full`, or anything else; or when the prompt has no `Plan:` / `Stage:` markers; or when the trimmer / plan file is missing.
- Always exits `0` (the hook is informational; it never blocks the dispatch).

**`~/.claude/settings.json` snippet:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Task|Agent",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-context-slim-pre-agent.sh" }
        ]
      }
    ]
  }
}
```

To opt in for a session: `MB_WORK_MODE=slim claude` (or `/mb work --slim`, which sets the env for the loop subshell).

---

## 5. `hooks/mb-sprint-context-guard.sh` — runtime token-spend watcher

**Event:** `PreToolUse`
**Matchers:** `tool_name` is `Agent` (Claude Code 2.1+) or `Task` (earlier versions).

**Behavior:**

- Estimates running session token spend by accumulating the character length of every dispatched Task prompt (rule of thumb: 1 token ≈ 4 chars). State is persisted to `<bank>/.session-spend.json` via `scripts/mb-session-spend.sh`.
- Bank discovery: `MB_SESSION_BANK` env var (when set), else `${PWD}/.memory-bank` if present. Otherwise the hook is a no-op.
- Lazy-initialises `mb-session-spend.sh` with the soft / hard thresholds from `pipeline.yaml:sprint_context_guard.{soft_warn_tokens, hard_stop_tokens}` (defaults 150 000 / 190 000) on the first invocation.
- Exit codes:
  - `0` below soft, or in the soft warn band (warning to stderr only, dispatch proceeds).
  - `2` at or above the hard stop — the dispatch is blocked with a message recommending `/mb done` + `/compact` + `/mb start`.

**`~/.claude/settings.json` snippet:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Task|Agent",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-sprint-context-guard.sh" }
        ]
      }
    ]
  }
}
```

Pair with `hooks/mb-context-slim-pre-agent.sh` on the same `Task` matcher; both fire on each dispatch and complement each other (slim trims the prompt, guard keeps cumulative spend in check).

Companion CLI for ad-hoc inspection:

```bash
bash scripts/mb-session-spend.sh status --mb .memory-bank
bash scripts/mb-session-spend.sh check --mb .memory-bank   # exit 0/1/2
bash scripts/mb-session-spend.sh clear --mb .memory-bank
```

---

## Combined snippet

To register all five at once, merge the array entries above. Order does not matter — Claude Code runs each matching hook for an event.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-protected-paths-guard.sh" }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-ears-pre-write.sh" }
        ]
      },
      {
        "matcher": "Task|Agent",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-context-slim-pre-agent.sh" },
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-sprint-context-guard.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": "bash $CLAUDE_PROJECT_DIR/hooks/mb-plan-sync-post-write.sh" }
        ]
      }
    ]
  }
}
```

---

## Operational notes

- All five hooks require `jq` on the `PATH`; if it is missing, they fail-open (exit 0) so your session never breaks because of the hook.
- The `protected-paths-guard` and `ears-pre-write` hooks fail-open if their underlying validators are missing — they never block on infrastructure errors.
- `plan-sync-post-write` skips chain steps whose scripts are not installed; older bank layouts continue working.
- `context-slim-pre-agent` and `sprint-context-guard` both fire on `Task` invocations: the first emits a trimmed prompt as `additionalContext` (advisory if it cannot detect plan/stage), the second tracks cumulative session spend and hard-stops at `pipeline.yaml:sprint_context_guard.hard_stop_tokens`.
- The hooks log to stderr with a `[<hook-name>]` prefix so the source of every diagnostic is obvious.

## Related

- `references/pipeline.default.yaml` — declares `protected_paths` and the rest of the engine config the hooks consume.
- `references/session-memory.md` — session-memory contract v2, lifecycle, adapter contracts, recall, doctor checks, environment variables.
- `commands/work.md` — `/mb work` workflow that complements these hooks (the loop runs the same checks deterministically).
- `scripts/mb-work-protected-check.sh`, `scripts/mb-ears-validate.sh`, `scripts/mb-context-slim.py`, `scripts/mb-session-spend.sh` — underlying helpers.

---

## Session-memory lifecycle hooks

Memory Bank records every agent session to `.memory-bank/session/*.md`. The core hooks below implement the session-memory contract v2 (defined in `references/session-memory.md`).

### Claude Code hooks

| Hook script | Event | Purpose |
|-------------|-------|---------|
| `mb-session-start.sh` | `SessionStart` | Inject `_recent.md` context + dispatch catchup |
| `mb-session-turn.sh` | `Stop` | Append turn entry to Live log |
| `mb-session-end.sh` | `SessionEnd` | Finalize log + summarize + rebuild `_recent.md` |
| `mb-session-catchup.sh` | `SessionStart` (before start) | Summarize stale `summarized:false` sessions in background |
| `mb-session-summarize.sh` | sourced by end/catchup | Generate Haiku/CLI summary for one session file |
| `mb-pre-compact.sh` | `PreCompact` | Write handoff capsule before context compaction |
| `mb-semantic-recall.sh` | `UserPromptSubmit` | Semantic recall with lexical fallback |
| `session-end-autosave.sh` | `SessionEnd` (legacy) | Writes progress.md auto-capture stub; disabled in modern setup via `MB_AUTO_CAPTURE=off` |

### Pi adapter hooks

The Pi adapter is a TypeScript extension (`adapters/pi_session_memory_extension.ts`) that listens to Pi lifecycle events and calls the same core scripts:

| Pi event | Session-memory action |
|----------|----------------------|
| `session_start` | Resolve bank, run catchup, rebuild `_recent.md`, inject into context |
| `input` | Append user prompt to Live log |
| `tool_execution_end` | Append tool name, files, outcome to Live log |
| `agent_end` / `turn_end` | Finalize turn entry |
| `session_before_compact` | Write handoff capsule via `mb-pre-compact.sh` |
| `session_shutdown` | Finalize session, summarize, rebuild `_recent.md`, background reindex |

### Doctor diagnostics

`mb-session-doctor.sh` (called by `/mb doctor`) inspects:
- Unsummarized sessions (`summarized:false`)
- Missing/stale `_recent.md`
- Empty semantic index
- Missing adapter files (catchup, precompact, Pi extension)
- Legacy auto-capture stubs in `progress.md`

---

## Cursor adapter wiring

Cursor 1.7+ uses Claude-Code-compatible `hooks.json`. The `adapters/cursor.sh` installer registers **ten** Memory Bank hooks globally (`~/.cursor/hooks.json`) and in project `.cursor/hooks.json`:

| Cursor event | Script | Matcher |
|--------------|--------|---------|
| `sessionStart` | `mb-session-start-context.sh` | — |
| `sessionEnd` | `session-end-autosave.sh` | — |
| `preCompact` | `mb-pre-compact.sh` | — |
| `beforeShellExecution` | `block-dangerous.sh` | — |
| `preToolUse` | `mb-protected-paths-guard.sh` | `Write|Edit` |
| `preToolUse` | `mb-ears-pre-write.sh` | `Write` |
| `preToolUse` | `mb-context-slim-pre-agent.sh` | `Task` |
| `preToolUse` | `mb-sprint-context-guard.sh` | `Task` |
| `postToolUse` | `file-change-log.sh` | `Write|Edit` |
| `postToolUse` | `mb-plan-sync-post-write.sh` | `Write` |

Each entry is tagged `"_mb_owned": true` so reinstall/uninstall preserves user hooks. `mb-pre-compact.sh` maps to Cursor `preCompact`: on compaction it runs `scripts/mb-handoff.sh --actualize` to write a fresh `handoff/latest.md` capsule (handoff-v2). It is bounded to ~2s and never blocks compaction (on timeout/failure it WARNs and exits 0).

Opt-out: `MB_AUTOLOAD_CONTEXT=off` disables `sessionStart` auto-context injection.

---

## Hook inventory

Lifecycle hooks shipped in `hooks/`. Installed automatically by `install.sh` (Claude Code, Cursor, Codex, OpenCode); see `references/hooks.md` for per-host wiring details.

| Hook | Trigger | Purpose |
|------|---------|---------|
| `_skill_root.sh` | sourced helper | Resolve bundled skill root and effective Memory Bank path for hook scripts |
| `block-dangerous.sh` | PreToolUse (Bash) | Block dangerous shell patterns (`rm -rf /`, `~`, `/*`) — best-effort guardrail |
| `mb-protected-paths-guard.sh` | PreToolUse (Write/Edit) | Block writes to `pipeline.yaml:protected_paths` (e.g. `.env`, CI configs) |
| `mb-ears-pre-write.sh` | PreToolUse (Write) | Validate REQ bullets in `context/<topic>.md` against EARS patterns before save |
| `mb-context-slim-pre-agent.sh` | PreToolUse (Task) | Slim oversized agent prompts on subagent dispatch |
| `mb-sprint-context-guard.sh` | PreToolUse (Task) | Hard-stop subagent dispatch if `mb-session-spend.sh` shows budget exhaustion |
| `mb-graph-nudge.sh` | PreToolUse (Grep/Bash) | Non-blocking nudge toward `mb-graph-query` on structural greps, whenever the code graph exists (stale included — I-133); repeats every `MB_GRAPH_NUDGE_EVERY` structural calls (default 25) and carries the symbol lifted from the pattern, `SessionStart:compact` resets the counter, `MB_GRAPH_NUDGE=off`, fail-safe |
| `mb-plan-sync-post-write.sh` | PostToolUse (Write) | Auto-sync plan ↔ checklist + roadmap after editing a plan file |
| `file-change-log.sh` | PostToolUse (Write/Edit) | Append change log + scan for placeholders / secrets in committed files |
| `session-end-autosave.sh` | SessionEnd | Memory Bank auto-capture (`MB_AUTO_CAPTURE=auto\|strict\|off`) when `/mb done` was skipped |
| `mb-core-cap-guard.sh` | Stop | Enforce the core-file line caps (AGR-043): runs `mb-core-cap.sh fix`, and when the bank is still over cap blocks the stop **once per session** (marker `<bank>/.core-cap.nudged.<session_id>`) with `dispatch MB Manager action: actualize --strict`. **On by default** — kill-switch `MB_CORE_CAP=off` (env or `.mb-config core_cap=off`); `stop_hook_active`, no bank, or any tool error → allow |
| `mb-pre-compact.sh` | PreCompact (Claude Code) / preCompact (Cursor) | Handoff-v2: runs `mb-handoff.sh --actualize` to write a fresh `handoff/latest.md` capsule before compaction. Bounded to ~2s, never blocks (`MB_PRECOMPACT_HANDOFF=off` to disable) |
| `mb-session-start-context.sh` | sessionStart (Cursor) | Auto-inject compact Memory Bank context at session start (`MB_AUTOLOAD_CONTEXT=off` to disable) |
| `mb-session-turn.sh` | Stop | Session memory: append one per-turn bullet (request + tools + files) to `session/*.md`, no LLM (`MB_SESSION_CAPTURE=off` to disable) |
| `mb-session-end.sh` | SessionEnd | Session memory: Haiku summary + gated Sonnet auto-notes; updates `session/_recent.md` |
| `mb-session-start.sh` | SessionStart | Session memory: inject `# Recent Sessions` from `session/_recent.md` + a how-to cheat-sheet (graph / `/mb recall` / `/mb context` quick ref), read-only (`MB_SESSION_CHEATSHEET=off` to drop the cheat-sheet) |
| `mb-update-notify.sh` | SessionStart | "A newer release is out?" notice: silent when current, else a ≤3-line notice with `current -> latest` + the exact upgrade command for the detected install flavor (git/pipx/pip/brew), local-only (`--cache-only`, no network), fail-open, never blocks (`MB_UPDATE_CHECK=off` to disable). Opt-in `MB_AUTO_UPDATE=on` auto-applies for a clean git-clone install only |
| `mb-recall.sh` | `/mb recall <query>` | Session memory: hybrid recall — model-free BM25 matches first (over `agreements.md` + `progress.md` + `notes/` + `session/`; embeddings opt-in via `MB_SEMANTIC_BACKEND=embeddings`) + ripgrep lexical fallback |
| `mb-semantic-recall.sh` | UserPromptSubmit | Session memory: inject `# Relevant Memory` — top-K relevant past-chat snippets via the model-free BM25 index (I-132: ~50 MB / <0.5 s per prompt; prompt-gated — slash-commands and prompts under `MB_SEMANTIC_MIN_PROMPT` chars skip the spawn); fail-safe (`MB_SEMANTIC=off` to disable) |
| `mb-reindex.sh` | `/mb reindex` | Session memory: (re)build the per-project semantic vector index (`--full`/`--incremental`); bootstraps the venv if needed |
| `mb-semantic-bootstrap.sh` | sourced by `/mb reindex` | Session memory: idempotent venv + fastembed/numpy installer (opt-in; semantic layer falls back to lexical without it) |
| `mb-flow-closure-guard.sh` | Stop | Dynamic-flow closure gate: when a flow is active, blocks the Stop event if `mb-flow-verify.sh` exits non-zero, preventing the agent from declaring done on a red firewall (REQ-DF-045) |
| `mb-drive-resume-gate.sh` | Stop | Drive-loop resume-gate: while a `/mb drive` loop is armed, blocks a stop when the goal is not done AND no stop condition fired, so the loop resumes instead of ending early (REQ-DR-032). Decides by reading files only — never runs the firewall or a test battery (`MB_DRIVE_RESUME_GATE=off` to disable) |
| `mb-session-catchup.sh` | SessionStart | Lazy summarize sessions left `summarized:false` by a prior SIGKILLed SessionEnd; dispatched in the background so session startup is never delayed (`MB_CATCHUP_MAX` tuneable, off via `MB_SESSION_CAPTURE=off`) |
| `mb-session-summarize.sh` | sourced/dispatched (not directly registered) | Generate the Haiku `## Summary` for one session file and rotate `_recent.md`; extracted from `mb-session-end.sh` (DRY) and driven by both the SessionEnd hook and `mb-session-catchup.sh` |
