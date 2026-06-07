import sys
import time
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from semantic_store import Store
from searcher import run_search


def _norm(v):
    v = np.asarray(v, dtype=np.float32)
    return v / np.linalg.norm(v)


def _build_index(tmp_path):
    s = Store(tmp_path); s.set_model("m")
    s.upsert("a.md", 1.0, "x",
             [{"text": "kamal deploy", "source": "a.md", "kind": "note", "anchor": "p0"}],
             np.stack([_norm([1, 0, 0])]))
    s.save()
    return tmp_path


class _FastEmbedder:
    model_name = "m"

    def embed(self, texts):
        return np.stack([_norm([1, 0, 0]) for _ in texts])


class _SlowEmbedder:
    model_name = "m"

    def embed(self, texts):
        time.sleep(2.0)
        return np.stack([_norm([1, 0, 0]) for _ in texts])


def test_run_search_returns_match(tmp_path):
    idx = _build_index(tmp_path)
    out = run_search(idx, "kamal", top_k=1, min_score=0.0, timeout=5, embedder=_FastEmbedder())
    assert out and out[0]["text"] == "kamal deploy"


def test_run_search_times_out_returns_empty_quickly(tmp_path):
    idx = _build_index(tmp_path)
    t0 = time.monotonic()
    out = run_search(idx, "kamal", top_k=1, min_score=0.0, timeout=0.2, embedder=_SlowEmbedder())
    elapsed = time.monotonic() - t0
    assert out == []
    assert elapsed < 1.0          # returned promptly, did not wait the full 2s


def test_run_search_missing_index_returns_empty(tmp_path):
    out = run_search(tmp_path / "nope", "q", top_k=5, min_score=0.0, timeout=5, embedder=_FastEmbedder())
    assert out == []
