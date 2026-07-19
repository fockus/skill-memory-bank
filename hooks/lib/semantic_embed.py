"""Wrapper around fastembed with an injectable backend for testing."""

from __future__ import annotations

import os
from pathlib import Path

import numpy as np

DEFAULT_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
_BATCH = 64  # fixed batches bound onnxruntime arena growth on big reindexes (I-132)


class Embedder:
    def __init__(self, model_name: str = DEFAULT_MODEL, backend=None):
        self.model_name = model_name or DEFAULT_MODEL
        self._backend = backend  # callable(list[str]) -> list[np.ndarray]
        self._model = None

    def _ensure(self):
        if self._backend is not None:
            return
        if self._model is None:
            from fastembed import TextEmbedding  # lazy: only when really embedding

            # Stable cache dir — $TMPDIR is purged by macOS, forcing re-downloads.
            cache = os.environ.get("FASTEMBED_CACHE_PATH") or str(
                Path("~/.cache/fastembed").expanduser()
            )
            self._model = TextEmbedding(model_name=self.model_name, cache_dir=cache)
        self._backend = lambda texts: list(self._model.embed(texts))

    def embed(self, texts: list[str]) -> np.ndarray:
        if not texts:
            return np.zeros((0, 0), dtype=np.float32)
        self._ensure()
        parts = []
        for i in range(0, len(texts), _BATCH):
            part = np.asarray(self._backend(texts[i : i + _BATCH]), dtype=np.float32)
            if part.ndim == 1:
                part = part.reshape(1, -1)
            parts.append(part)
        arr = parts[0] if len(parts) == 1 else np.vstack(parts)
        norms = np.linalg.norm(arr, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        return arr / norms
