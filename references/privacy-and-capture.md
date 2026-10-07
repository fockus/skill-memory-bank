# Privacy and capture

Private content, progress auto-capture, native session logging, and the PreCompact handoff capsule.
Session-memory schema and recall internals live in `references/session-memory.md`.

## Contents

- [Private content — `<private>...</private>` (since v2.1)](#private-content--privateprivate-since-v21)
- [Auto-capture (since v2.1)](#auto-capture-since-v21)
- [Session memory — native session logging (session-memory subsystem)](#session-memory--native-session-logging-session-memory-subsystem)
- [PreCompact handoff capsule (handoff-v2)](#precompact-handoff-capsule-handoff-v2)

---

## Private content — `<private>...</private>` (since v2.1)

Markdown syntax for excluding sensitive information (client data, API keys, partner names) from indexing and search:

```markdown
---
type: note
tags: [auth, partner-x]
importance: high
---

Discussed with client <private>Jane Doe, +1-555-***</private>.
Integration with <private>api_key=sk-abc123...</private> is scheduled for Tuesday.
```

**Protection model:**
- Content inside `<private>...</private>` does **not** go into `index.json` (neither `summary` nor `tags`)
- `mb-search` output redacts it as `[REDACTED]` (inline) or `[REDACTED match in private block]` (multi-line)
- The entry gets a `has_private: true` flag for downstream filtering
- An unclosed `<private>` without `</private>` makes the rest of the file private (fail-safe)
- `hooks/file-change-log.sh` warns when committing a file containing `<private>` blocks (reminder to review git exposure)

**Double confirmation for reveal:**
```bash
# Rejected without env:
mb-search --show-private <query>
# [error] --show-private requires MB_SHOW_PRIVATE=1

# Only with explicit opt-in:
MB_SHOW_PRIVATE=1 mb-search --show-private <query>
```

**Important:** `<private>` protects against leakage through `index.json` / `mb-search`, but it does **not** filter `git diff`. For full protection, consider `.gitattributes` filters or git hooks.

---

## Auto-capture (since v2.1)

The SessionEnd hook automatically appends a placeholder entry to `progress.md` when a session ends without an explicit `/mb done`. Work is not lost even if manual actualization was skipped.

**Modes (`MB_AUTO_CAPTURE` env):**
- `auto` (default) — hook writes an entry on session end
- `strict` — hook skips but prints a warning to stderr (for flows where manual actualization is required)
- `off` — full noop

**How it works:**
- After successful `/mb done`, the command writes `.memory-bank/.session-lock` → the hook sees the fresh lock (<1h) and skips auto-capture (manual actualization already happened)
- Without a lock, the hook adds a short note to `progress.md`. Full details can be reconstructed by `/mb start` in the next session (MB Manager can read the JSONL transcript)
- Concurrency-safe through a short `.auto-lock` (30 seconds) — prevents duplicates on parallel invocations
- Idempotent by `session_id` — same session + same day = one entry

**Opt-out:** `export MB_AUTO_CAPTURE=off` in `~/.zshrc` or disable the hook via `/mb upgrade` once that flag is available.

---

## Session memory — native session logging (session-memory subsystem)

A richer, native alternative to the placeholder auto-capture above. Logs every session to
`.memory-bank/session/*.md` (markdown, git-tracked) and auto-curates notes. Scripts live in
`~/.claude/hooks/` (and the repo's `.memory-bank/bin/` when present); registered in `settings.json`.

- **Stop → `mb-session-turn.sh`** — appends one `## Live log` bullet per turn (last user request,
  tools, touched files) **without an LLM**; persists the transcript path to frontmatter; deduped by
  turn `uuid` so duplicate (project + global) registration is safe. Guards: `stop_hook_active`,
  `MB_CAPTURE_SUBPROCESS`, `MB_SESSION_CAPTURE=off`, missing jq → exit 0.
- **SessionEnd → `mb-session-end.sh`** — a Haiku `claude -p` writes `## Summary` + updates
  `_recent.md`; then a **gated** Sonnet judge (only if the session had Write/Edit or ≥4 turns) writes
  0–2 durable `notes/`. Idempotent by `session_id` (`summarized` frontmatter flag). Anti-recursion:
  `env -u CLAUDECODE MB_CAPTURE_SUBPROCESS=1 claude -p --strict-mcp-config --no-session-persistence --no-chrome`.
- **SessionStart → `mb-session-start.sh`** — injects `# Recent Sessions` from `_recent.md`;
  drains stdin (`exec < /dev/null`) to avoid hanging on `claude --resume` (macOS). Read-only (runs
  even while capture is `off`). When a code graph exists it also dispatches the bounded
  `mb-graph-query.py catchup` detached (flock + budget + cooldown, result in
  `codebase/.graph-catchup.log`) without blocking startup. It catches the graph up to new
  commits and tracked edits only — a bank whose graph is merely OLD (no drift, empty dirty
  queue) still needs `/mb graph --apply`. `MB_GRAPH_CATCHUP=off` disables it.
- **Recall:** `/mb recall <query>` → hybrid semantic + lexical search over `session/` + `notes/`,
  fused by RRF (Reciprocal Rank Fusion) when the semantic backend is available; fails open to
  lexical-only otherwise.

**Off-switch:** `export MB_SESSION_CAPTURE=off`. **Suppress the legacy stub** (above) with
`MB_AUTO_CAPTURE=off` so `progress.md` is not double-written once this subsystem owns capture.
**Cost:** a significant session spends 2 `claude -p` calls on SessionEnd (Haiku summary + Sonnet
judge); trivial sessions spend only the summary. **Portable lock:** mkdir-based (no `flock` on macOS).
Active only where an active Memory Bank resolves.

---

## PreCompact handoff capsule (handoff-v2)

The PreCompact hook `hooks/mb-pre-compact.sh` runs just before context compaction. It invokes
`scripts/mb-handoff.sh --actualize <bank> pre_compact`, which writes a fresh handoff capsule to
`.memory-bank/handoff/latest.md`. The NEXT session's SessionStart hook
(`hooks/mb-session-start-context.sh`) prepends that capsule when it is newer than the most recent
`progress.md` entry, so the agent resumes from an up-to-date snapshot instead of stale state.

**Never blocks compaction (design §9):**
- bounded to ~2s via a portable background-poll-and-kill loop (no `timeout`/`flock`, macOS-safe)
- on timeout, actualize failure, or missing handoff script → one-line stderr WARN and `exit 0`
- on no resolvable bank → silent `exit 0`
- on success → one-line stderr marker `[mb] handoff capsule actualized (pre_compact)`

**Opt-out:** `export MB_PRECOMPACT_HANDOFF=off`.
