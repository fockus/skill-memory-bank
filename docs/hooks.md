# Hooks reference

Memory Bank ships a set of lifecycle hooks that run automatically around tool calls and session
boundaries. `install.sh` wires them into `~/.claude/settings.json` (or the equivalent host config)
during installation — the JSON snippets on this page are useful for manual debugging, a custom
host, or understanding exactly what fires and when.

There are two families: **tool hooks**, which run around `Write`/`Edit`/`Task` calls during a
session, and **session-memory lifecycle hooks**, which run at session start/stop and implement the
session-memory contract described in `references/session-memory.md`.

## Tool hooks

### 1. `hooks/mb-protected-paths-guard.sh` — block writes to protected paths

**Event:** `PreToolUse`
**Matchers:** `tool_name ∈ {Write, Edit}` and the target path matches a glob in
`pipeline.yaml:protected_paths` (default: `.env*`, `ci/**`, `.github/workflows/**`, `Dockerfile*`,
`k8s/**`, `terraform/**`).

Reads the tool-call JSON from stdin via `jq`, skips for any tool other than `Write`/`Edit`, skips
entirely if `MB_ALLOW_PROTECTED=1` is set (mirroring `/mb work --allow-protected`), and delegates
the actual glob match to `scripts/mb-work-protected-check.sh` so the rule definition lives in one
place. By default (`MB_PROTECTED_MODE=ask`, the implicit default) a match doesn't block: it emits
a `permissionDecision: "ask"` response and exits `0`, so Claude Code prompts for approval instead
of hard-refusing. Set `MB_PROTECTED_MODE=deny` to make a match exit `2` and hard-block the call
instead.

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

Override per-session: `MB_ALLOW_PROTECTED=1 claude` (or `/mb work --allow-protected`, which sets
the variable for the whole loop subshell).

### 2. `hooks/mb-plan-sync-post-write.sh` — keep the bank consistent after Markdown edits

**Event:** `PostToolUse`
**Matchers:** `tool_name == "Write"` and the path matches `*plans/*.md` or `*specs/*/*.md`.

Triggers the deterministic sync chain that keeps `roadmap.md`, `traceability.md`, and the
active-plans block current after any plan or spec edit:

```
scripts/mb-plan-sync.sh
  → scripts/mb-roadmap-sync.sh
    → scripts/mb-traceability-gen.sh
```

Each step is best-effort: a missing script is skipped silently, a non-zero exit logs a warning but
the hook itself still exits `0` — a `PostToolUse` hook should never block downstream behavior.

### 3. `hooks/mb-ears-pre-write.sh` — reject invalid EARS requirements before they land

**Event:** `PreToolUse`
**Matchers:** `tool_name == "Write"` and the path matches `*specs/*/requirements.md` or
`*context/*.md`.

Pulls `tool_input.content` from the JSON payload and pipes it through
`scripts/mb-ears-validate.sh -`. Any `- **REQ-NNN** ...` line that fails the EARS pattern check
exits `2`, forwarding the validator's stderr to the user with each line prefixed
`[ears-pre-write]`. This complements `/mb plan --sdd` and `/mb sdd`'s own EARS enforcement, and
catches a manual edit to `requirements.md` even when the user bypasses the slash commands entirely.

### 4. `hooks/mb-context-slim-pre-agent.sh` — slim-context advisory on Task dispatch

**Event:** `PreToolUse`
**Matchers:** `tool_name == "Task"` and `MB_WORK_MODE=slim` is set.

When active and the dispatched prompt advertises `Plan: <path.md>` and `Stage: <N>` markers, this
hook delegates to `scripts/mb-context-slim.py` to build a trimmed view — the active stage block,
its DoD bullets, its `covers_requirements` REQ list, and `git diff --staged` — and emits it via
`hookSpecificOutput.additionalContext` without mutating the original tool input. It is a no-op
(advisory only, always exits `0`) when `MB_WORK_MODE` is unset or `full`, when the prompt lacks
`Plan:`/`Stage:` markers, or when the trimmer/plan file is missing.

Opt in for a session: `MB_WORK_MODE=slim claude` (or `/mb work --slim`).

### 5. `hooks/mb-sprint-context-guard.sh` — runtime token-spend watcher

**Event:** `PreToolUse`
**Matchers:** `tool_name == "Task"`.

Estimates running session token spend by accumulating the character length of every dispatched
Task prompt (rule of thumb: 1 token ≈ 4 chars), persisted via `scripts/mb-session-spend.sh` to
`<bank>/.session-spend.json`. Bank discovery uses `MB_SESSION_BANK` if set, otherwise
`${PWD}/.memory-bank` when present — the hook is a no-op without either. Thresholds are lazily
initialized from `pipeline.yaml:sprint_context_guard.{soft_warn_tokens, hard_stop_tokens}`
(defaults 150,000 / 190,000). Below the soft threshold, or in the soft warn band, the dispatch
proceeds (warning to stderr only in the warn band); at or above the hard stop, exit `2` blocks the
dispatch with a message recommending `/mb done` + `/compact` + `/mb start`.

Companion CLI for ad-hoc inspection:

```bash
bash scripts/mb-session-spend.sh status --mb .memory-bank
bash scripts/mb-session-spend.sh check --mb .memory-bank   # exit 0/1/2
bash scripts/mb-session-spend.sh clear --mb .memory-bank
```

Pair this hook with `mb-context-slim-pre-agent.sh` on the same `Task` matcher — one trims the
prompt, the other tracks cumulative spend, and together they keep long `/mb work` runs from
silently exhausting the context window.

### Combined snippet

Order does not matter — the host runs every matching hook for an event. To register all five at
once, merge the array entries:

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
        "matcher": "Task",
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

### Operational notes

- All five hooks require `jq` on `PATH`; if it's missing they fail-open (exit `0`) so a missing
  dependency never breaks a session.
- `protected-paths-guard` and `ears-pre-write` fail-open if their underlying validators are
  missing — infrastructure errors never block a tool call.
- `plan-sync-post-write` skips any chain step whose script isn't installed, so older bank layouts
  keep working without a forced migration.
- Every hook logs to stderr with a `[<hook-name>]` prefix so the source of a diagnostic is always
  obvious.

## Session-memory lifecycle hooks

Memory Bank records every agent session to `.memory-bank/session/*.md`. These hooks implement the
session-memory contract (`references/session-memory.md`):

| Hook script | Event | Purpose |
|-------------|-------|---------|
| `mb-session-start.sh` | `SessionStart` | Inject `_recent.md` context only. |
| `mb-session-turn.sh` | `Stop` | Append a turn entry to the live session log. |
| `mb-session-end.sh` | `SessionEnd` | Finalize the log, summarize, rebuild `_recent.md`. |
| `mb-session-catchup.sh` | `SessionStart` (registered separately, alongside `mb-session-start.sh`) | Summarize stale `summarized:false` sessions in the background. |
| `mb-session-summarize.sh` | sourced by end/catchup | Generate a Haiku/CLI summary for one session file. |
| `mb-pre-compact.sh` | `PreCompact` | Write a handoff capsule before context compaction. |
| `mb-semantic-recall.sh` | `UserPromptSubmit` | Semantic recall with a lexical fallback. |
| `session-end-autosave.sh` | `SessionEnd` (legacy) | Writes a `progress.md` auto-capture stub; disable via `MB_AUTO_CAPTURE=off`. |

### Pi adapter hooks

The Pi adapter is a TypeScript extension (`adapters/pi_session_memory_extension.ts`) that listens
to Pi's own lifecycle events and calls the same core scripts as the Claude Code hooks above:

| Pi event | Session-memory action |
|----------|------------------------|
| `session_start` | Resolve bank, run catchup, rebuild `_recent.md`, inject into context. |
| `input` | Append the user prompt to the live log. |
| `tool_execution_end` | Append tool name, files, and outcome to the live log. |
| `agent_end` / `turn_end` | Finalize the turn entry. |
| `session_before_compact` | Write a handoff capsule via `mb-pre-compact.sh`. |
| `session_shutdown` | Finalize the session, summarize, rebuild `_recent.md`, background reindex. |

### Doctor diagnostics

`/mb doctor` calls `mb-session-doctor.sh`, which inspects: unsummarized sessions
(`summarized:false`), a missing or stale `_recent.md`, an empty semantic index, missing adapter
files (catchup, precompact, Pi extension), and legacy auto-capture stubs still sitting in
`progress.md`.

## Cursor adapter wiring

Cursor 1.7+ uses Claude-Code-compatible `hooks.json`. The `adapters/cursor.sh` installer registers
ten Memory Bank hooks globally (`~/.cursor/hooks.json`) and, when a project-level Cursor adapter is
requested, in project `.cursor/hooks.json`:

| Cursor event | Script | Matcher |
|--------------|--------|---------|
| `sessionStart` | `mb-session-start-context.sh` | — |
| `sessionEnd` | `mb-session-end.sh` | — |
| `preCompact` | `mb-pre-compact.sh` | — |
| `beforeShellExecution` | `block-dangerous.sh` | — |
| `preToolUse` | `mb-protected-paths-guard.sh` | `Write\|Edit` |
| `preToolUse` | `mb-ears-pre-write.sh` | `Write` |
| `preToolUse` | `mb-context-slim-pre-agent.sh` | `Task` |
| `preToolUse` | `mb-sprint-context-guard.sh` | `Task` |
| `postToolUse` | `file-change-log.sh` | `Write\|Edit` |
| `postToolUse` | `mb-plan-sync-post-write.sh` | `Write` |

Each entry is tagged `"_mb_owned": true` so a reinstall or uninstall preserves any user-added
hooks. `mb-pre-compact.sh` maps to Cursor's `preCompact`: on compaction it runs
`scripts/mb-handoff.sh --actualize` to write a fresh `handoff/latest.md` capsule (handoff-v2),
bounded to roughly 2 seconds and never blocking compaction (on timeout or failure it WARNs and
exits `0`).

Opt-out: `MB_AUTOLOAD_CONTEXT=off` disables the `sessionStart` auto-context injection.

## Related

- [pipeline.yaml reference](pipeline-yaml.md) — declares `protected_paths` and
  `sprint_context_guard`, the config every hook above reads.
- [Environment variables](environment-variables.md) — `MB_ALLOW_PROTECTED`, `MB_WORK_MODE`,
  `MB_SESSION_BANK`, `MB_AUTOLOAD_CONTEXT`, and the rest of the toggles referenced here.
- [/mb work](mb-work.md) — the loop that runs the same protected-path and context-guard checks
  deterministically, independent of these hooks.
