---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Claude Code statusLine integration — stdin JSON contract

- `statusLine` in `~/.claude/settings.json` runs a shell command whose **stdout** (one line) becomes the status bar text.
- The command receives a JSON payload on **stdin** with transcript metadata: `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`, and `model_id`.
- Context-fill % = `(input + cache_creation + cache_read) / model_limit`; limit is 1M for `[1m]`-suffix models, 200k otherwise.
- Installer should refuse to overwrite an existing `statusLine` without `--force`, and always write a `.bak` before patching.
- Implemented in `scripts/mb-statusline.py`; `/mb statusline [--install [--force]]` is the user-facing command.

---
*Auto-captured by MB session-memory (session d066df83).*
