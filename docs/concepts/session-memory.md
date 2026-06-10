# Cross-session memory

Most agents forget everything when a chat ends. Memory Bank's **session-memory**
subsystem gives the agent a rolling, searchable record of what happened in past
chats — what you asked, which files changed, what was decided — so a new session
can pick up where the last one left off. It runs through lifecycle **hooks**, is
**read-only by default** (it never edits your code), and **fails open** (no
index, no model, no problem — it degrades to lexical search).

This is distinct from the two other "memory" surfaces:

| Surface | What it indexes | Command |
|---|---|---|
| **Session memory** (this doc) | past **chats** (`.memory-bank/session/` + `notes/`) | `/mb recall` |
| Core-file search | the bank's core files (status/plans/notes) | `/mb search` |
| [Code graph](code-graph.md) | your **source code** | `mb-semantic-search.py` |

---

## How it captures (hooks)

Each session is logged to `.memory-bank/session/*.md` automatically:

| Hook | Event | What it does |
|---|---|---|
| `mb-session-turn.sh` | Stop | Appends one per-turn bullet (your request + tools used + files touched) — **no LLM, $0**. |
| `mb-session-end.sh` | SessionEnd | Writes a **Haiku** summary + gated Sonnet auto-notes; refreshes the rolling `session/_recent.md` window. |
| `mb-session-start.sh` | SessionStart | Injects `# Recent Sessions` (from `_recent.md`) + a how-to cheat-sheet (graph / `/mb recall` / `/mb context` quick ref). |
| `mb-semantic-recall.sh` | UserPromptSubmit | Injects `# Relevant Memory` — top-K semantically relevant past-chat snippets via a local index; fail-safe lexical fallback. |

So with zero effort the next session already opens with a digest of recent work,
and every prompt is silently augmented with the most relevant past context.

## How to recall — `/mb recall <query>`

```bash
/mb recall "auth token refresh"
```

Hybrid recall over `.memory-bank/session/` + `notes/`: **semantic matches first**
(when the vector index is built), then a ripgrep lexical fallback, printing
`file:line` + context. Use it to answer "did we already discuss X?", "what did we
decide about Y?", "which session touched Z?".

## The semantic layer (optional, $0, local)

The semantic index is **opt-in** and runs entirely locally (no API key):

```bash
/mb reindex            # build / refresh the per-project vector index
/mb reindex --full     # full rebuild;  --incremental for just new sessions
```

`/mb reindex` bootstraps a small venv with `fastembed` + `numpy` on first run
(`mb-semantic-bootstrap.sh`, idempotent). Without it, recall and the
UserPromptSubmit hook **degrade to lexical** search — nothing breaks, results are
just keyword- rather than meaning-based.

Rebuild the rolling window after pruning empty sessions:

```bash
bash scripts/mb-session-recent-rebuild.sh   # newest MB_RECENT_KEEP (default 5)
```

---

## Privacy & toggles

Everything stays on your machine, and every layer has an off-switch:

| Variable | Default | Effect |
|---|---|---|
| `MB_SESSION_CAPTURE` | on | `off` disables the per-turn / session-end capture entirely. |
| `MB_SEMANTIC` | on | `off` disables the semantic UserPromptSubmit injection (lexical only). |
| `MB_SESSION_CHEATSHEET` | on | `off` drops the how-to cheat-sheet from the SessionStart injection. |
| `MB_RECENT_KEEP` | `5` | How many sessions the rolling `_recent.md` window keeps. |

Wrap secrets/PII in `<private>…</private>` in any bank file to keep them out of
`index.json` and redacted from `/mb search` output.

> **Related but distinct:** the `session-end-autosave.sh` hook
> (`MB_AUTO_CAPTURE=auto|strict|off`) appends a placeholder entry to
> `progress.md` when a session ends without an explicit `/mb done`, so work is
> never lost. That's the *progress log*; session-memory is the *cross-chat
> recall index*.

---

## See also

- **[Code graph & semantic search](code-graph.md)** — searching your *source* (a different index).
- `commands/mb.md` — `/mb recall`, `/mb reindex` reference.
- `SKILL.md` `## Hooks` — the full hook registry + events.
