---
type: pattern
tags: [rag, retrieval, qwen3, perplexity, refresh, embedding]
related_features: [project-code-rag, agent-retrieval-routing, bounded-rag-refresh]
sprint: null
importance: high
source: manual
created: 2026-11-25
---

# project-code-rag-and-bounded-refresh
Date: 2026-11-25 18:34

## What was done
- Added opt-in multilingual project retrieval with Qwen3/QMD and Perplexity ONNX Q4.
- Routed agents through project-scoped tracked-source indexes with graph/text fallback.
- Added bounded automatic refresh with reuse, debounce, cooldown, locking, deadline, and vector limits.

## New knowledge
- Background refresh is safe only after explicit enrollment; it must never provision or repair models.
- Reuse unchanged embeddings and publish atomically so failed refreshes cannot replace a healthy index.
- Return graph/text evidence immediately and treat semantic freshness as an asynchronous improvement.
