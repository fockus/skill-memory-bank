# Cursor host — engineering reference

How Memory Bank runs inside Cursor, and why it is built the way it is. For
**install and day-to-day usage**, see [`cross-agent-setup.md`](cross-agent-setup.md)
(§ Cursor) — this page is the architecture/maintenance companion, not a second
install guide.

## Model: CC-compat hooks, run from the bundle

Cursor 1.7+ supports a Claude-Code-compatible `hooks.json`. Memory Bank reuses the
**same hook scripts** as the Claude Code host — there is no Cursor-specific fork of
the hook logic. The integration is therefore a *wiring* concern, not a code-duplication
one:

- `install.sh` writes `~/.cursor/hooks.json` with ten hook commands tagged
  `_mb_owned: true`. Each command invokes the script **from the installed skill
  bundle** (`~/.cursor/skills/memory-bank/hooks/…`).
- **Nothing is copied into `~/.cursor/hooks/`.** Earlier versions copied
  self-contained hook scripts there; that drifted from the bundle on every skill
  update. The current model keeps a single source of truth (the bundle) and points
  every hook event at it.

### Skill-bundle resolution

Hook scripts that need bundled `scripts/` or the global registry locate the bundle
through [`hooks/_skill_root.sh`](../hooks/_skill_root.sh):

- `mb_skill_root_resolve` — prefers `$MB_SKILL_ROOT`, then the hook's own parent
  (when it carries `SKILL.md`/`VERSION`), then the known global install paths
  (`~/.cursor/skills/memory-bank`, `~/.claude/skills/…`, `~/.codex/skills/…`).
- `mb_skill_lib_sh` / `mb_skill_scripts_dir` — derive `scripts/_lib.sh` and `scripts/`
  from the resolved root.

This is what lets the same hook work whether it was invoked from a project checkout,
a global Cursor install, or a Claude Code install.

## Storage modes

| Mode | Init | Resolution |
| --- | --- | --- |
| Local | `/mb init --storage=local` | `<project>/.memory-bank/` (walk-up) |
| Global | `/mb init --storage=global --agent=cursor` | registry lookup keyed by project root |
| Rules-only | (no init) | `[MEMORY BANK: ABSENT]` — engineering rules still apply |

Global storage is registry-driven: `~/.cursor/memory-bank/registry.json` maps a
project root to an out-of-tree bank directory. The hook entrypoint
`mb_hook_resolve_mb_path` (in `_skill_root.sh`) resolves in this order: `MB_PATH`
override → local `<cwd>/.memory-bank/` → **registry lookup via the active agent**
(`mb_hook_default_agent`, which honours `MB_AGENT=cursor`). The Cursor `hooks.json`
commands export `MB_AGENT=cursor`, so both directions work without a local bank:

- **sessionStart** — `mb-session-start-context.sh` injects `status/checklist/roadmap`
  context from the registry bank.
- **sessionEnd** — `session-end-autosave.sh` appends the append-only auto-capture stub
  to the registry bank's `progress.md` (idempotent by session id).

## Testing surface

| Test | Covers |
| --- | --- |
| `tests/bats/test_cursor_adapter.bats` | adapter install/uninstall, `hooks.json` shape, `MB_AGENT` global support |
| `tests/bats/test_cursor_docs.bats` | docs assert ten hooks + bundle paths, no "self-contained copies" claim |
| `tests/e2e/test_cursor_global.bats` | global install does not copy hooks; bundle references |
| `tests/e2e/test_cursor_global_storage.bats` | sessionStart context **and** sessionEnd auto-capture resolve the registry bank |
| `tests/pytest/test_cursor_hooks_registration.py` | manifest contract (hooks.json + skill hooks dir) |

## Limitations

- **IDE vs CLI hook firing.** The Cursor *agent CLI* fires the full CC-compatible hook
  set. The Cursor *IDE* does not guarantee every hook event (notably `sessionEnd`)
  fires on every interaction; treat IDE auto-capture as best-effort and rely on
  explicit `/mb done` for durable session closure.
- **Parallel dispatch** is documented as a protocol in
  [`adapters/cursor/dispatch.md`](../adapters/cursor/dispatch.md); the executable
  `/mb run` orchestrator is gated behind the `parallel-pipeline` spec.
