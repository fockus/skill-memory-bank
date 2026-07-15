# Environment variables

Memory Bank behavior is tunable through a small set of environment variables. Every one of them
is fail-open by design: an unset or invalid value falls back to a safe default rather than
breaking a session.

| Variable | Purpose | Default |
|----------|---------|---------|
| `MB_AUTO_CAPTURE` | SessionEnd auto-capture mode: `auto` / `strict` / `off`. | `auto` |
| `MB_REDACT_SECRETS` | Redact API keys/tokens (`sk-…`, `ghp_…`, `AKIA…`, JWTs, `*_API_KEY=` values, …) from session capture and the semantic index before they ever reach disk. | `on` |
| `MB_COMPACT_REMIND` | Weekly `/mb compact` reminder: `auto` / `off`. | `auto` |
| `MB_ALLOW_METRICS_OVERRIDE` | Allow executing a project-local `.memory-bank/metrics.sh` override. | `0` |
| `MB_PI_MODE` | Pi project adapter mode. `agents-md` writes project `AGENTS.md`; `skill` writes `~/.pi/agent/skills/memory-bank` (leaves an existing global symlink unchanged). | `agents-md` |
| `MB_SKILL_BUNDLE` | Override the resolved bundle path — dev/testing use. | auto-detected |
| `MB_SKIP_DEPS_CHECK` | Skip the preflight dependency check in `install.sh`. | `0` |
| `MB_LANGUAGE` | Non-interactive install language selection (`en` / `ru`), equivalent to `--language`. | `en` |
| `MB_SESSION_CAPTURE` | Kill-switch for the session-memory subsystem's automatic logging. `off` disables capture entirely. | `on` |
| `MB_ALLOW_PROTECTED` | Bypass the protected-paths write guard for this session — mirrors `/mb work --allow-protected`. | unset |
| `MB_WORK_MODE` | Context strategy for `/mb work` sub-dispatches: `slim` trims the prompt via `mb-context-slim.py`; `full` (or unset) sends the whole item body. | unset (full) |
| `MB_WORK_PARALLEL` | Opt-in switch to per-run state/budget slots (`<bank>/.work-state/<run_id>.json`) so several `/mb work` runs can execute concurrently. Off by default — single-run behavior stays byte-identical. | `0` |
| `MB_SESSION_BANK` | Explicit bank path for hooks that cannot infer it from `$PWD` (e.g. the sprint-context-guard hook). | unset (falls back to `${PWD}/.memory-bank`) |
| `MB_CONSOLIDATE_DAYS` | Age threshold (days) for `/mb consolidate` to consider a session "old" and eligible for folding. | `30` |
| `MB_RECENT_KEEP` | How many most-recent sessions `mb-session-recent-rebuild.sh` keeps in `_recent.md`. | `5` |
| `MB_AUTOLOAD_CONTEXT` | Cursor adapter only — `off` disables the `sessionStart` auto-context injection hook. | `on` |

## Notes

- These variables are read by shell scripts under `scripts/` and hooks under `hooks/`; none of
  them require a restart beyond starting a new session/shell, since each script re-reads its
  environment on every invocation.
- Security-sensitive toggles (`MB_REDACT_SECRETS`, `MB_ALLOW_METRICS_OVERRIDE`) default to the
  safer setting — redaction on, override off — so a fresh install is safe out of the box.
- `MB_SKIP_DEPS_CHECK` exists for CI and isolated environments where dependency availability is
  verified through a different mechanism than `install.sh`'s own preflight.

## Related

- [/mb work](mb-work.md) — the primary consumer of `MB_WORK_MODE`, `MB_WORK_PARALLEL`, and
  `MB_ALLOW_PROTECTED`.
- [Hooks reference](hooks.md) — the hook scripts that read `MB_SESSION_BANK`, `MB_ALLOW_PROTECTED`,
  and `MB_WORK_MODE` at dispatch time.
- [Installation](install.md) — `MB_LANGUAGE`, `MB_SKIP_DEPS_CHECK`, and the Pi adapter toggles in
  their install-time context.
