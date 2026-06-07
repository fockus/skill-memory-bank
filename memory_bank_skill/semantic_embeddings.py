"""Optional local-embedding retriever for semantic code search.

Gated behind ``HAS_SENTENCE_TRANSFORMERS`` — when ``sentence-transformers`` (and
``numpy``) are not installed, ``EmbeddingRetriever.available`` is ``False`` and the
factory in ``semantic_search`` falls back to BM25. This keeps the skill's
zero-required-dependency contract: embeddings are strictly opt-in.

Embeddings are local (no API key, no network at inference once the model is
cached). Default model: ``all-MiniLM-L6-v2`` (small, fast, offline).
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
from typing import Any

# numpy is decoupled from sentence-transformers so the on-disk vector cache is
# usable (and unit-testable) wherever numpy exists, independent of whether the
# heavy embedding model dependency is installed.
HAS_NUMPY = False
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:  # pragma: no cover - exercised when numpy is missing
    np = None  # type: ignore[assignment]

HAS_SENTENCE_TRANSFORMERS = False
try:  # optional dependency — graceful degradation when absent
    from sentence_transformers import SentenceTransformer
    HAS_SENTENCE_TRANSFORMERS = True
except ImportError:  # pragma: no cover - exercised when the dep is missing
    SentenceTransformer = None  # type: ignore[assignment,misc]

_DEFAULT_MODEL = "all-MiniLM-L6-v2"


def corpus_key(model_name: str, texts: list[str]) -> str:
    """Stable content hash of (model, ordered corpus texts) — the cache validity key.

    Pure stdlib (no numpy): order-sensitive, changes when any text or the model
    changes. Used to decide whether a persisted embedding matrix can be reused.
    """
    h = hashlib.sha256()
    # Length-prefix every field so no text content can forge a delimiter and
    # collide with a different corpus split (e.g. ['a\x00b'] vs ['a','b']).
    def _feed(b: bytes) -> None:
        h.update(str(len(b)).encode("ascii"))
        h.update(b":")
        h.update(b)
    _feed(model_name.encode("utf-8"))
    for t in texts:
        _feed(t.encode("utf-8"))
    return h.hexdigest()


def _cache_paths(cache_dir: Path) -> tuple[Path, Path]:
    """(.npy matrix, .key sidecar) under a code-search-scoped dir.

    Deliberately NOT named ``vectors.npy`` so it never collides with the
    session-recall vector store that also lives under ``.memory-bank/.index/``.
    """
    d = Path(cache_dir)
    return d / "embeddings.npy", d / "embeddings.key"


def _load_cache(cache_dir: Path, key: str, n_rows: int) -> Any:  # pragma: no cover - numpy path
    """Return the cached matrix when key + row-count match, else None."""
    if not HAS_NUMPY:
        return None
    npy, keyf = _cache_paths(cache_dir)
    if not (npy.exists() and keyf.exists()):
        return None
    try:
        if keyf.read_text(encoding="utf-8").strip() != key:
            return None
        arr = np.load(npy)
    except (OSError, ValueError):
        return None
    if getattr(arr, "shape", (0,))[0] != n_rows:
        return None
    return arr


def _save_cache(cache_dir: Path, key: str, emb: Any) -> None:  # pragma: no cover - numpy path
    """Persist the matrix then its key, each via tmp+os.replace (both atomic).

    Matrix is written first, key last, so a present+matching key always implies
    the matching matrix is already on disk; a torn write degrades to a cache miss.
    """
    if not HAS_NUMPY:
        return
    d = Path(cache_dir)
    d.mkdir(parents=True, exist_ok=True)
    npy, keyf = _cache_paths(d)
    npytmp = d / f".embeddings.{os.getpid()}.npy.tmp"
    with open(npytmp, "wb") as fh:  # file handle → np.save won't re-append .npy
        np.save(fh, emb, allow_pickle=False)
    os.replace(npytmp, npy)
    keytmp = d / f".embeddings.{os.getpid()}.key.tmp"
    keytmp.write_text(key, encoding="utf-8")
    os.replace(keytmp, keyf)


class EmbeddingRetriever:
    """Local sentence-embedding retriever (cosine similarity). Opt-in."""

    name = "embeddings"

    def __init__(self, model_name: str = _DEFAULT_MODEL,
                 *, cache_dir: Any = None) -> None:
        self.model_name = model_name
        self._cache_dir = Path(cache_dir) if cache_dir else None
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
        if not texts:
            self._emb = None
            return
        key = corpus_key(self.model_name, texts)
        if self._cache_dir is not None:
            cached = _load_cache(self._cache_dir, key, len(texts))
            if cached is not None:
                self._emb = cached
                return
        self._emb = self._ensure_model().encode(texts, normalize_embeddings=True)
        if self._cache_dir is not None:
            _save_cache(self._cache_dir, key, self._emb)

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
            "kind": self._docs[i].get("kind", ""),
            "is_test": self._docs[i].get("is_test", False),
        } for i in order if sims[i] > 0]
