# Adapter Manifest Schema

All project-level adapters write a versioned JSON manifest so uninstall and
debug tooling can reason about owned files deterministically.

## Required keys

| Key | Type | Meaning |
|-----|------|---------|
| `schema_version` | integer | Manifest format version. Current value: `1` |
| `installed_at` | string | UTC timestamp in ISO-8601 format |
| `adapter` | string | Adapter name (`cursor`, `windsurf`, `cline`, `kilo`, `opencode`, `pi`, `codex`, `git-hooks-fallback`) |
| `skill_version` | string | Version from `VERSION` when available |
| `files` | array of strings | Absolute file paths owned by this adapter |

## Optional keys

| Key | Type | Used by |
|-----|------|---------|
| `hooks_events` | array of strings | adapters with native hook config (`cursor`, `windsurf`, `cline`) |
| `agents_md_owned` | boolean | adapters using shared `AGENTS.md` ownership (`opencode`, `pi`, `codex`) |
| `plugin_ref` | string | `opencode` plugin registration |
| `git_hooks_installed` | boolean | `kilo`, `pi` (`agents-md` mode) |
| `experimental_hooks` | boolean | `codex` |
| `mode` | string | `pi` adapter mode (`agents-md` or `skill`) |
| `pi_skill_dir` | string | `pi` skill-mode install target |
| `had_user_post_commit` | boolean | `git-hooks-fallback` backup metadata |
| `had_user_pre_commit` | boolean | `git-hooks-fallback` backup metadata |

## Example

```json
{
  "schema_version": 1,
  "installed_at": "2026-04-21T11:00:00Z",
  "adapter": "cursor",
  "skill_version": "3.1.1",
  "files": [
    "/project/.cursor/rules/memory-bank.mdc",
    "/project/.cursor/hooks/session-end-autosave.sh"
  ],
  "hooks_events": ["sessionEnd", "preCompact", "beforeShellExecution"]
}
```
