---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Codex hooks.json schema — wrong casing/extra fields cause silent skip

- Codex CLI 0.144.1 silently ignores `~/.codex/hooks.json` when the schema is off — no error, no log, the hook just never fires.
- Two independent root causes found: (1) event key must be exact-case `UserPromptSubmit` with a nested `hooks` array, not lowercase `userpromptsubmit`; (2) any extra top-level field (`version`, `_mb_warning`) makes Codex skip the whole file, not just the unknown field.
- Fix landed in `adapters/codex.sh`: writes the correct schema and migrates old files on reinstall, preserving foreign hooks and the user's own `version`.
- Also discovered: Codex only loads project-level hooks if the project is in its trusted list (`~/.codex/config.toml`) — now documented.
- False lead to avoid repeating: a first fix attempt assumed Codex doesn't honor `exit 2` like Claude Code hooks do and switched to a JSON response — wrong, the real bug was the schema; that change was reverted.

---
*Auto-captured by MB session-memory (session ab6e3348).*
