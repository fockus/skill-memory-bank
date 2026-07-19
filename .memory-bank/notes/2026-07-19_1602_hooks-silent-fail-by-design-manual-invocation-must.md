---
type: note
tags: [session-memory]
importance: medium
source: session-memory
---

# Hooks silent-fail by design; manual invocation must stay verbose

- Convention: hooks must swallow embedder/library errors and return empty silently — a broken hook must never break the user's turn.
- Gotcha: the same swallow-and-return-empty path leaked into manual script invocation — running the embeddings search by hand with the wrong python interpreter (missing embeddings lib) silently returned nothing, with no indication of what failed.
- Fix: manual/direct script entry points now surface the real error; hook entry points keep the silent-safe fallback — same underlying function, different error-visibility contract depending on the caller.

---
*Auto-captured by MB session-memory (session 1910cfed).*
