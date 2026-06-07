"""Wrapper around fastembed with an injectable backend for testing."""
from __future__ import annotations
import numpy as np

DEFAULT_MODEL = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"


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
            self._model = TextEmbedding(model_name=self.model_name)
        self._backend = lambda texts: list(self._model.embed(texts))

    def embed(self, texts: list[str]) -> np.ndarray:
        if not texts:
            return np.zeros((0, 0), dtype=np.float32)
        self._ensure()
        arr = np.asarray(self._backend(texts), dtype=np.float32)
        if arr.ndim == 1:
            arr = arr.reshape(1, -1)
        norms = np.linalg.norm(arr, axis=1, keepdims=True)
        norms[norms == 0] = 1.0
        return arr / norms
