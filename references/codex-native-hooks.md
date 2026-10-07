# Native Codex hooks

For Codex versions with native lifecycle hooks (validated with Desktop 0.153.4),
use the additive installer bundled with this skill:

```bash
python3 "$SKILL_DIR/adapters/codex-native-hooks.py" install /absolute/project/.codex
```

Use `~/.codex` as the destination only when user-wide installation is intended.
The installer preserves unrelated hooks and config, backs up an existing hooks.json
once, and is idempotent. `uninstall` removes only entries marked `_mb_codex_native`.
It does not change approval policies or grant trust. Review the exact definitions
in Codex `/hooks`; trust must match their current hashes. A project config is loaded
only for a trusted project. Reopen/resume the session after changing registration;
check actual `hook/completed` events before claiming automatic execution.

The runner reuses the existing checks rather than copying their rules:

| Event | Action |
|---|---|
| SessionStart | Recent memory, graph freshness, update notification; reset graph nudge after compaction |
| UserPromptSubmit | Relevant-memory retrieval |
| PreToolUse | Protected paths, EARS for added requirement files, graph nudge; map spawn_agent message to Agent prompt for slim/context-budget checks |
| PostToolUse | Validate complete edited requirement files; sync changed plans and spec indexes |
| PreCompact / SessionEnd | Portable handoff capsule; no model call |
| Stop | Flow closure, drive-resume and core-file-cap checks |

Codex passes `apply_patch` input as a patch string. The adapter extracts paths,
including move destinations. New requirement files are checked before writing;
updates are checked after writing because a patch can omit unchanged continuation
lines. A post-write rejection cannot undo the edit. Fix the file and revalidate.
Protected-path denials reuse the existing checker. Codex does not support its
Claude `ask` response, so this adapter selects `MB_PROTECTED_MODE=deny`.
When the user already authorized a protected edit, use the existing
`MB_ALLOW_PROTECTED=1` execution mechanism within that authorized scope.

Limitations: arbitrary shell/MCP writes do not produce a structured file diff;
run the explicit EARS/spec/plan checks after such writes. These hooks are not a
filesystem security boundary and do not prove the implementation works. Legacy
Claude transcript capture, automatic Claude CLI summaries/judge, and notification
hooks are not registered by this adapter; retain explicit `/mb done` for progress.
It does not install the old Codex prompt-text blacklist or git hooks.

Protocol reference: [OpenAI hook documentation](https://learn.chatgpt.com/docs/hooks).
The local `codex app-server generate-json-schema --experimental` and `hooks/list`
provide version-specific schemas, errors, current hashes and trust status.
