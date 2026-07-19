---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Semantic recall OOM root cause + disable decision

- Root cause of the memory-growth/OOM popups: 4 independent entry points (recall-hook on every prompt, session-start, session-summarize/close, `/mb recall`) each loaded their own copy of the embedding model (~2.6GB), no shared/singleton loader — hence "4 copies" resident at once on long sessions.
- Fix: `MB_SEMANTIC: "off"` in `~/.claude/settings.json` gates all four entry points; the hook now returns `{}` in ~12ms instead of spawning the python embedder.
- Decision: BM25 lexical recall stays the default; semantic embeddings become strictly opt-in (cost ~60s indexing + ~1GB RAM per search) — not worth default-path cost at current corpus size.
- AST code graph and semantic search are deliberately kept independent/parallel, not merged into one index.

---
*Auto-captured by MB session-memory (session 1910cfed).*
