import sys
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from semantic_embed import Embedder


def _fake_backend(texts):
    # deterministic 3-dim vectors based on text length
    return [np.array([len(t), len(t) % 3, 1.0], dtype=np.float32) for t in texts]


def test_embed_returns_normalized_matrix():
    emb = Embedder("fake", backend=_fake_backend)
    m = emb.embed(["abc", "abcdef"])
    assert m.shape == (2, 3)
    norms = np.linalg.norm(m, axis=1)
    assert np.allclose(norms, 1.0, atol=1e-5)


def test_embed_empty_returns_empty():
    emb = Embedder("fake", backend=_fake_backend)
    assert emb.embed([]).shape[0] == 0


def test_model_name_preserved():
    assert Embedder("my-model", backend=_fake_backend).model_name == "my-model"
