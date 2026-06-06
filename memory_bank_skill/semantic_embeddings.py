"""Optional local-embedding retriever for semantic code search.

Gated behind ``HAS_SENTENCE_TRANSFORMERS`` — when ``sentence-transformers`` (and
``numpy``) are not installed, ``EmbeddingRetriever.available`` is ``False`` and the
factory in ``semantic_search`` falls back to BM25. This keeps the skill's
zero-required-dependency contract: embeddings are strictly opt-in.

Embeddings are local (no API key, no network at inference once the model is
cached). Default model: ``all-MiniLM-L6-v2`` (small, fast, offline).
"""

from __future__ import annotations

from typing import Any

HAS_SENTENCE_TRANSFORMERS = False
try:  # optional dependency — graceful degradation when absent
    import numpy as np
    from sentence_transformers import SentenceTransformer
    HAS_SENTENCE_TRANSFORMERS = True
except ImportError:  # pragma: no cover - exercised when the dep is missing
    np = None  # type: ignore[assignment]
    SentenceTransformer = None  # type: ignore[assignment,misc]

_DEFAULT_MODEL = "all-MiniLM-L6-v2"


class EmbeddingRetriever:
    """Local sentence-embedding retriever (cosine similarity). Opt-in."""

    name = "embeddings"

    def __init__(self, model_name: str = _DEFAULT_MODEL) -> None:
        self.model_name = model_name
        self._model: Any = None
        self._docs: list[dict[str, Any]] = []
        self._emb: Any = None

    @property
    def available(self) -> bool:
        return HAS_SENTENCE_TRANSFORMERS

    def _ensure_model(self) -> Any:  # pragma: no cover - requires optional model
        if self._model is None:
            self._model = SentenceTransformer(self.model_name)
        return self._model

    def index(self, docs: list[dict[str, Any]]) -> None:  # pragma: no cover - optional model
        self._docs = list(docs)
        texts = [d["text"] for d in self._docs]
        self._emb = (self._ensure_model().encode(texts, normalize_embeddings=True)
                     if texts else None)

    def search(self, query: str, k: int = 10) -> list[dict[str, Any]]:  # pragma: no cover
        if self._emb is None or not self._docs:
            return []
        q = self._ensure_model().encode([query], normalize_embeddings=True)[0]
        sims = self._emb @ q
        order = np.argsort(-sims)[:k]
        return [{
            "id": self._docs[i]["id"],
            "file": self._docs[i].get("file", ""),
            "score": round(float(sims[i]), 6),
            "snippet": self._docs[i]["text"][:120],
        } for i in order if sims[i] > 0]
