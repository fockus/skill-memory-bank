# Session Memory — contract v2

Agent-agnostic session-memory subsystem inside Memory Bank. Records every agent session as
structured Markdown in `.memory-bank/session/`, summarizes finished sessions, maintains a
rolling `_recent.md` handoff window, and exposes lexical/semantic recall.

## Design principles

1. **Agent-agnostic core.** The same schema and scripts work for Claude Code, Pi, Codex,
   OpenCode, Cursor, Windsurf, and any future agent that can capture lifecycle events.
2. **Adapters, not bridges.** Each agent has a thin adapter that translates its native
   lifecycle events into core calls. No agent must depend on another agent's runtime.
3. **Fail-open everywhere.** Missing summarizer, venv, network, or semantic model must
   never block session capture or lexical recall.
4. **Summarization is best-effort.** Without a configured model, sessions are recorded as
   raw Live log and the doctor can still rebuild `_recent.md` from available summaries.
5. **Consolidation is opt-in.** Sessions stay as individual files until explicit
   consolidation archives them and optionally promotes findings to notes/lessons/ADR.

## File layout

```text
.memory-bank/session/
  2026-06-26_2130_claude_<sid>.md    # raw session file
  2026-06-26_2145_pi_<sid>.md        # Pi session
  _recent.md                          # rolling window of last N summarized sessions
  archive/                            # archived session files (consolidation target)
.memory-bank/.index/                  # optional semantic index
```

## Session file schema v2

Every session file is Markdown with YAML frontmatter and the sections below. All fields
in frontmatter are required unless marked optional.

```yaml
---
session_id: <agent-specific id>    # e.g. Pi session file UUID, Claude JSONL session_id
agent: claude | pi | codex | opencode | cursor | windsurf
started: ISO-8601 timestamp
ended: ISO-8601 timestamp          # optional, absent when session is still in progress
turns: <N>
transcript: <path>                 # optional, agent-native transcript location
summarized: true | false           # whether `## Summary` has been written
summary_backend: claude-code | pi | command | none   # optional
summary_schema: v2
branch: <name>                     # optional, git branch or user label
mtime: <unix_seconds>              # file modification time, used for ordering
---
```

### Section `## Live log`

Turn-level raw audit entries. One entry per completed turn. Required even when no summary
is available.

```markdown
## Live log

- 14:23 — User: "refactor auth module"
  - Tools: Write auth.go, Edit main.go
  - Files: auth/auth.go, main.go
  - Outcome: ok
- 14:30 — Assistant answer (3 tool calls)
  - Tools: bash go test ./...
  - Files: auth/auth_test.go
  - Outcome: ok
```

Each line is a turn marker. The format is human-readable and grep-friendly.

### Section `## Summary`

Compiled summary in standard but human-readable structure. This is the section that
`_recent.md` consumes and that recall surfaces.

```markdown
## Summary

### What changed
- <files and high-level description>

### Decisions
- <architecture choices, ADR links if applicable>

### Open questions
- <unresolved items>

### Files
- <paths of files read or modified>

### Verification
- <test runner output, lint status, checks>

### Next actions
- <concrete follow-up items>
```

### Section `## Diagnostics`

Optional. Capture backend, error messages, and summarizer-did-not-run reasons.

```markdown
## Diagnostics

- summary_backend: none
- error: MB_SUMMARY_BACKEND not configured
- reason: SessionEnd hook was not executed or was killed before completion
```

## Lifecycle states

```
[agent session starts]
  └─► SessionStart event
        ├─► catchup: summarize any stale summarized:false files from prior sessions
        ├─► rebuild _recent.md if stale
        └─► inject _recent.md content into agent context (size-capped)

[each turn]
  └─► append turn entry to Live log (idempotent by turn index/sequence)

[agent session ends]
  └─► SessionEnd event
        ├─► finalize Live log
        ├─► write summary via configured backend (claude-code, pi, command, none)
        ├─► mark summarized: true (or false + diagnostics if backend failed)
        └─► rebuild _recent.md

[compaction / context overflow]
  └─► PreCompact event
        └─► write handoff capsule: compact summary of all turns since last handoff
```

## Adapter contracts

### Claude Code adapter

- Hook events: `SessionStart`, `Stop` (per turn), `SessionEnd`, `PreCompact`, `UserPromptSubmit`
- Session id from Claude JSONL `session_id`
- Transcript path from Claude `~/.claude/projects/<slug>/<uuid>.jsonl`
- Summary backend: `claude -p` or external `command`

### Pi adapter

- Extension events: `session_start`, `input`, `tool_execution_end`, `agent_end`/`turn_end`,
  `session_before_compact`, `session_shutdown`
- Session id from `ctx.sessionManager.getSessionFile()` (Pi session JSONL path)
- No transcript hook — Pi sessions are JSONL inside `~/.pi/agent/sessions/`
- Summary backend: `pi` (through `ctx` model) or external `command`

### Codex / OpenCode / Cursor / Windsurf / others

- Each agent has its own adapter via `adapters/<name>.sh` or `adapters/<name>.ts`
- Must implement at minimum: session start context injection, turn-level capture,
  session-end summarization (best-effort)

## Recall subsystem

```
/mb recall <query>
  ├─► lexical: ripgrep/grep over .memory-bank/session/ + notes/ (always works)
  └─► semantic: optional vector index (requires fastembed venv + mb-reindex.sh)
        └─► when unavailable → silently fall back to lexical
```

## Doctor checks

`mb-session-doctor.sh` (or `/mb doctor` session-memory section) must detect:

| Check | Severity | Remedy |
|-------|----------|--------|
| `.memory-bank/session/*.md` contains `summarized: false` files | WARN | `mb-session-catchup.sh` |
| `.memory-bank/session/_recent.md` is missing or stale | WARN | `mb-session-recent-rebuild.sh` |
| Installed Claude hooks are missing `mb-session-catchup.sh`, `mb-session-summarize.sh`, `mb-pre-compact.sh` | WARN | run adapter install |
| Semantic index has `chunks=0, sources=0` | INFO | `mb-reindex.sh --full` |
| `session-end-autosave.sh` is active with `MB_AUTO_CAPTURE=auto` | INFO | set `MB_AUTO_CAPTURE=off` or remove from hooks |
| Pi adapter is not installed | INFO | `adapters/pi.sh install` |
| `progress.md` contains auto-capture stubs (`### Auto-capture`) | WARN | `mb-consolidate.sh --dry-run` |

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MB_SESSION_CAPTURE` | on | Master off-switch for session logging |
| `MB_SUMMARY_BACKEND` | none | `claude-code`, `pi`, `command`, `none` |
| `MB_SUMMARIZE_BIN` | (auto) | Override summarizer command |
| `MB_CATCHUP_MAX` | 5 | Max stale sessions to summarize per SessionStart |
| `MB_RECENT_KEEP` | 5 | Number of recent sessions in `_recent.md` |
| `MB_RECALL` | on | Enable `/mb recall` |
| `MB_SEMANTIC` | auto | `auto` (venv if available), `off`, `on` |
| `MB_SEMANTIC_MODEL` | `sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` | Embedding model |
| `MB_AUTO_CAPTURE` | off | Legacy; `auto` writes progress stubs |

## Privacy and redaction

Session log and summary must not contain:
- API keys (regex `sk-...`, `sk-ant-...`, `Bearer <long>`)
- Email addresses
- OAuth tokens

The capture helper must redact before writing. Transcript references (`transcript:` field) may
remain as paths; the file content is agent-private.

## Failure modes

| Failure | Behavior |
|---------|----------|
| Summarizer command missing | `summarized: false`, doctor reports, fallback to none |
| Summarizer timeout (>30s) | `summarized: false` with diagnostics, catchup retries later |
| Session file corrupted | skip with warning in doctor, other sessions unaffected |
| No write permission | fail loudly, log to stderr, exit 0 (never crash the agent) |
| Semantic model venv missing | lexical recall still works, doctor explains bootstrap command |
