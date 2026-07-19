---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Copilot CLI requires quoted argument-hint YAML values

PR #6 (accepted): Copilot CLI ≥1.0.65 fails to load skills whose command frontmatter has an unquoted `argument-hint:` value (e.g. `argument-hint: <topic>`) — YAML parses the angle brackets oddly and Copilot's loader chokes, silently dropping the skill.

Fix: quote all `argument-hint` values in `commands/*.md` frontmatter (`argument-hint: "<topic>"`).

**Convention going forward:** always quote `argument-hint` in new/edited command files — cheap and avoids cross-agent (Copilot CLI) breakage that isn't visible when testing only in Claude Code.

---
*Auto-captured by MB session-memory (session 5d8d86ec).*
