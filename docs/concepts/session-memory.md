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
| `mb-session-turn.sh` | Stop | Appends one per-turn bullet (your request + tools used + files touched, plus the turn **outcome** `ok \| err(N)` and an aggregate `+A/-B` diffstat) — **no LLM, $0**. |
| `mb-session-end.sh` | SessionEnd | Writes a structured **Haiku** summary (schema v2 — see below) + gated Sonnet auto-notes; refreshes the rolling `session/_recent.md` window. |
| `mb-session-start.sh` | SessionStart | Injects `# Recent Sessions` (from `_recent.md`) + a how-to cheat-sheet (graph / `/mb recall` / `/mb context` quick ref). |
| `mb-semantic-recall.sh` | UserPromptSubmit | Injects `# Relevant Memory` — top-K semantically relevant past-chat snippets via a local index; fail-safe lexical fallback. |

So with zero effort the next session already opens with a digest of recent work,
and every prompt is silently augmented with the most relevant past context.

### Structured summary schema v2

The session-end summarizer reads the session's own distilled Live log (never the
raw transcript tail) and is prompted for exactly four sections — **What changed /
Decisions / Open questions / Files**. The frontmatter is stamped
`summary_schema: v2` **only after** a strict in-order heading validation passes
(a duplicate or out-of-order `### …` heading is rejected); non-conforming output
is still stored, just without the flag — so the flag never lies and downstream
parsers can trust a v2-stamped summary.

## How to recall — `/mb recall <query>`

```bash
/mb recall "auth token refresh"          # compact index (default)
/mb recall --expand <id> "auth token"    # one full chunk for that hit id
/mb recall --full "auth token refresh"   # legacy full bodies for every hit
```

Hybrid recall over `.memory-bank/session/` + `notes/`: semantic and lexical hits
are **fused via Reciprocal Rank Fusion** when the semantic backend is available
(fail-open to **lexical-only** otherwise). Use it to answer "did we already
discuss X?", "what did we decide about Y?", "which session touched Z?".

**Progressive disclosure** keeps recall token-cheap. The default output is a
**compact index** — one `id · age · summary · source` line per hit (~15
tokens/line, no chunk bodies). Drill into a single hit with `--expand <id>`
(exit code `3` on an unknown id); `--full` restores the legacy behaviour of
printing every chunk body. `[SUPERSEDED]` chunks sort last, marked with a `⊘`.

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
| `MB_REDACT_SECRETS` | on | `off` disables automatic secret redaction (below). |
| `MB_SESSION_CAPTURE` | on | `off` disables the per-turn / session-end capture entirely. |
| `MB_SEMANTIC` | on | `off` disables the semantic UserPromptSubmit injection (lexical only). |
| `MB_SESSION_CHEATSHEET` | on | `off` drops the how-to cheat-sheet from the SessionStart injection. |
| `MB_RECENT_KEEP` | `5` | How many sessions the rolling `_recent.md` window keeps. |

**Automatic secret redaction (default on).** Session capture redacts recognizable
API keys and tokens **before anything reaches disk**: vendor-prefixed keys
(`sk-…` — OpenAI/Anthropic/OpenRouter, `ghp_…`/`github_pat_…`, `AKIA…`,
`xox?-…`, `AIza…`, `hf_…`, `npm_…`, `pypi-…`), JWTs, `Bearer <token>` values, and
`*_API_KEY=` / `*_TOKEN=` / `*_SECRET=` env-style assignments. Redaction applies
at three layers: the per-turn Live-log bullet, the transcript fed to the
summarizer/judge (a secret that never enters the prompt cannot reappear in a
summary), and the semantic-index chunker. Implementation:
`hooks/lib/redact.py` + `sc_redact_secrets` in `hooks/lib/session-common.sh`.

Wrap secrets/PII in `<private>…</private>` in any bank file to keep them out of
`index.json`, redacted from `/mb search` output, and excluded from
semantic-index chunks.

> **Related but distinct:** the `session-end-autosave.sh` hook
> (`MB_AUTO_CAPTURE=auto|strict|off`) appends a placeholder entry to
> `progress.md` when a session ends without an explicit `/mb done`, so work is
> never lost. That's the *progress log*; session-memory is the *cross-chat
> recall index*.

---

## Curating the memory — `$0` hygiene commands

Three commands turn the raw capture stream into durable, de-duplicated memory.
All three are **deterministic, zero-LLM by default** (no API key), and only the
ones that write do so when you explicitly ask.

| Command | What it does | Writes? |
|---|---|---|
| `/mb recap <sid>` | Rebuilds a full `progress.md` entry from a session's auto-capture **stub** via one Haiku call, replacing only that stub in place (neighbors byte-identical, idempotent via `recapped` frontmatter). Missing session or an already-real entry → refuse without writing; an ambiguous `<sid>` → list candidates instead of guessing. | yes (one stub) |
| `/mb conflicts [--judge]` | Surfaces pairs of memory entries with high lexical overlap **and** an opposing/replacement assertion (en+ru negation markers) over `notes/` + `lessons.md` + recent `progress.md` — `$0`, zero LLM. `--judge` confirms each via one Sonnet call and prints a suggested `[SUPERSEDED: YYYY-MM-DD -> <ref>]` marker. **PRINT-ONLY** — never writes. | no |
| `/mb consolidate [--apply]` | Folds sessions older than `--days N` (default 30) that cluster by shared files / lexical overlap into 5–15 line `notes/` candidates, archives those session files verbatim → `session/archive/`, and moves only their auto-capture progress **stubs** verbatim → `progress-archive.md`. Zero LLM. **Dry-run is the default**; `--apply` performs it. Real progress entries never move. | only with `--apply` |

The `[SUPERSEDED: YYYY-MM-DD -> <ref>]` convention (append the new fact, mark the
old one — never edit in place) is enforced by `mb-drift.sh`, which flags
malformed markers and dangling references.

---

## Memory stack — MB primary, memsearch search-only

When both Memory Bank and [memsearch](https://github.com/) are installed, they overlap on
one axis: both can summarize a turn with Haiku on the Stop hook. The decision (2026-07-04,
backlog I-087 B4) is **Memory Bank owns per-session summaries; memsearch is search-only** —
otherwise every turn pays for two Haiku calls that produce near-duplicate notes.

Disable memsearch's per-turn summarizer while keeping its search/embeddings:

```toml
# ~/.memsearch/config.toml  (user config, not a repo file)
[plugins.claude-code.summarize]
enabled = false
```

memsearch's `stop.sh` reads `plugins.claude-code.summarize.enabled` (defaults to `true`
when absent); `embedding.*` and recall stay untouched, so `memsearch` search still returns
results. MB's own summary path (`mb-session-summarize.sh`, one Haiku per session, capped by
`MB_CATCHUP_MAX`) remains the single source of session summaries.

---

## See also

- **[Code graph & semantic search](code-graph.md)** — searching your *source* (a different index).
- `commands/mb.md` — `/mb recall`, `/mb reindex`, `/mb recap`, `/mb conflicts`, `/mb consolidate` reference.
- `SKILL.md` `## Hooks` — the full hook registry + events.
