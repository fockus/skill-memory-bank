# Memory Bank Hooks — Installation & Reference

This document covers the four critical hooks shipped by Phase 4 Sprint 1 (spec §13). They are deterministic shell scripts that Claude Code invokes around tool calls and subagent dispatches. They are independent of `/mb work` orchestration — they fire whenever the matching tool / file pattern is touched, even from manual edits.

> **Sprint 1 = scripts shipped + manual install.** Phase 4 Sprint 3 will auto-register these hooks via `install.sh`. Until then, register them yourself in `~/.claude/settings.json` per the snippets below.

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
**Matchers:** `tool_name == "Task"` and `MB_WORK_MODE=slim` is set in the environment.

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
        "matcher": "Task",
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
**Matchers:** `tool_name == "Task"`.

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
        "matcher": "Task",
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

---

## Operational notes

- All five hooks require `jq` on the `PATH`; if it is missing, they fail-open (exit 0) so your session never breaks because of the hook.
- The `protected-paths-guard` and `ears-pre-write` hooks fail-open if their underlying validators are missing — they never block on infrastructure errors.
- `plan-sync-post-write` skips chain steps whose scripts are not installed; older bank layouts continue working.
- `context-slim-pre-agent` and `sprint-context-guard` both fire on `Task` invocations: the first emits a trimmed prompt as `additionalContext` (advisory if it cannot detect plan/stage), the second tracks cumulative session spend and hard-stops at `pipeline.yaml:sprint_context_guard.hard_stop_tokens`.
- The hooks log to stderr with a `[<hook-name>]` prefix so the source of every diagnostic is obvious.

## Related

- `references/pipeline.default.yaml` — declares `protected_paths` and the rest of the engine config the hooks consume.
- `commands/work.md` — `/mb work` workflow that complements these hooks (the loop runs the same checks deterministically).
- `scripts/mb-work-protected-check.sh`, `scripts/mb-ears-validate.sh`, `scripts/mb-context-slim.py`, `scripts/mb-session-spend.sh` — underlying helpers.

## Phase 4 follow-ups

- **Sprint 3** — auto-register all five hooks during `install.sh`; add a `superpowers:requesting-code-review` skill detector that flips the reviewer override declared in `pipeline.yaml:roles.reviewer.override_if_skill_present`.
- **Sprint 3** — auto-register all four hooks during `install.sh`; add a `superpowers:requesting-code-review` skill detector that flips the reviewer override declared in `pipeline.yaml:roles.reviewer.override_if_skill_present`.
