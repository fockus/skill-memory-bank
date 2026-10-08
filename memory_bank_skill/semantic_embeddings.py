"""Optional local-embedding retriever for semantic code search.

Gated behind ``HAS_FASTEMBED`` — when ``fastembed`` is not installed,
``EmbeddingRetriever.available`` is ``False`` and the factory in
``semantic_search`` falls back to BM25. This keeps the skill's
zero-required-dependency contract: embeddings are strictly opt-in.

Backend is ``fastembed`` (ONNX, ~50 MB, no torch) — exactly what
``hooks/mb-semantic-bootstrap.sh`` installs (AGR-045); the previous
``sentence-transformers`` import never matched the bootstrap, so ``available``
was always ``False`` in practice.

Embeddings are local (no API key, no network at inference once the model is
cached). Default model: ``sentence-transformers/all-MiniLM-L6-v2`` (384-dim,
small, fast, offline) — the same weights as before under the namespaced id
fastembed requires. The id is part of ``corpus_key``, so it names the encoder
that actually produced the vectors instead of a name it no longer uses.
"""

from __future__ import annotations

import hashlib
import os
import tempfile
from pathlib import Path
from typing import Any

# numpy is decoupled from fastembed so the on-disk vector cache is usable (and
# unit-testable) wherever numpy exists, independent of whether the embedding
# model dependency is installed.
HAS_NUMPY = False
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:  # pragma: no cover - exercised when numpy is missing
    np = None  # type: ignore[assignment]

HAS_FASTEMBED = False
try:  # optional dependency — graceful degradation when absent
    from fastembed import TextEmbedding
    HAS_FASTEMBED = True
except ImportError:  # pragma: no cover - exercised when the dep is missing
    TextEmbedding = None  # type: ignore[assignment,misc]

_DEFAULT_MODEL = "sentence-transformers/all-MiniLM-L6-v2"


class EmbeddingModelUnavailable(RuntimeError):
    """The query encoder cannot be loaded (missing offline, corrupt, unreadable cache)."""


def model_cache_dir() -> Path:
    """Where FastEmbed model files live — persistent, never the OS temp dir by default.

    FastEmbed's own default is ``<tempdir>/fastembed_cache``: macOS purges it and a
    sandboxed or restarted process can see a different ``TMPDIR``, so an offline query
    after a restart found no model (Pi-native Stage 3 diagnosis). Same location and
    override as session recall (``hooks/lib/semantic_embed.py``): ``FASTEMBED_CACHE_PATH``,
    else ``~/.cache/fastembed``. A model that only exists in the legacy temp cache is read
    from there (no copy, no re-download) until the persistent cache holds one.
    """
    override = os.environ.get("FASTEMBED_CACHE_PATH")
    if override:
        return Path(override)
    persistent = Path.home() / ".cache" / "fastembed"
    legacy = Path(tempfile.gettempdir()) / "fastembed_cache"

    def has_model(root: Path) -> bool:
        return any(root.glob("models--*/**/*.onnx"))

    if not has_model(persistent) and has_model(legacy):
        return legacy
    return persistent


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


def cache_key_matches(cache_dir: Path | str, key: str) -> bool:
    """True when the persisted matrix was built from exactly this (model, corpus).

    Key compare only — no matrix load, no fastembed import — so any interpreter can
    ask "is the index warm?" in microseconds. Single source of truth for that
    question: the query path (``is_warm``) and the builder (``semantic_index``)
    both route through here.
    """
    _, keyf = _cache_paths(Path(cache_dir))
    try:
        return keyf.read_text(encoding="utf-8").strip() == key
    except OSError:
        return False


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
        return HAS_FASTEMBED

    def is_warm(self, docs: list[dict[str, Any]]) -> bool:
        """True when ``index(docs)`` would read the cache instead of encoding.

        The query path asks this BEFORE indexing (AGR-048): encoding a 9k-symbol
        corpus takes minutes, which a search must never spend in the foreground.
        No cache dir (unit/ad-hoc use) counts as cold.
        """
        if self._cache_dir is None:
            return False
        texts = [d["text"] for d in docs]
        return bool(texts) and cache_key_matches(self._cache_dir, corpus_key(self.model_name, texts))

    def _ensure_model(self) -> Any:  # pragma: no cover - requires optional model
        if self._model is None:
            cache = model_cache_dir()
            try:
                self._model = TextEmbedding(self.model_name, cache_dir=str(cache))
            except Exception as exc:  # fastembed raises ValueError/ONNX/OSError variants
                raise EmbeddingModelUnavailable(
                    f"embedding model unavailable ({self.model_name} from {cache}): "
                    f"{type(exc).__name__}: {str(exc)[:300]}"
                ) from exc
        return self._model

    def _encode(self, texts: list[str]) -> Any:  # pragma: no cover - optional model
        """Embed texts into an ``(n, dim)`` matrix.

        ``TextEmbedding.embed`` yields one vector per text (already L2-normalised
        for this model), so cosine similarity stays a plain dot product — the
        matrix shape and the on-disk cache format are unchanged.
        """
        return np.asarray(list(self._ensure_model().embed(texts)), dtype="float32")

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
        self._emb = self._encode(texts)
        if self._cache_dir is not None:
            _save_cache(self._cache_dir, key, self._emb)

    def search(self, query: str, k: int = 10) -> list[dict[str, Any]]:  # pragma: no cover
        if self._emb is None or not self._docs:
            return []
        q = self._encode([query])[0]
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
