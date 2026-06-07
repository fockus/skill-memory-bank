"""Tests for memory_bank_skill/semantic_embeddings.py — corpus hash + on-disk cache.

`corpus_key` is pure stdlib and always runs. The numpy-backed cache (load/save +
EmbeddingRetriever.index hit/miss) is exercised via an injected fake model and is
guarded by `pytest.importorskip("numpy")` — it runs locally where numpy is present
and SKIPS in CI (numpy absent), matching the `# pragma: no cover` on those paths.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import semantic_embeddings as se  # noqa: E402

# ── corpus_key (pure, always runs) ───────────────────────────────────

def test_corpus_key_is_deterministic():
    assert se.corpus_key("m", ["x", "y"]) == se.corpus_key("m", ["x", "y"])
    assert len(se.corpus_key("m", ["x"])) == 64


def test_corpus_key_changes_with_text_and_order():
    assert se.corpus_key("m", ["x"]) != se.corpus_key("m", ["x", "y"])
    assert se.corpus_key("m", ["a", "b"]) != se.corpus_key("m", ["b", "a"])
    assert se.corpus_key("m", ["x"]) != se.corpus_key("m", ["z"])


def test_corpus_key_changes_with_model():
    assert se.corpus_key("m1", ["x"]) != se.corpus_key("m2", ["x"])


def test_corpus_key_length_prefix_resists_delimiter_injection():
    # ['a\x00b'] must NOT collide with ['a','b'] (length-prefixed, not NUL-split)
    assert se.corpus_key("m", ["a\x00b"]) != se.corpus_key("m", ["a", "b"])


def test_has_numpy_flag_is_bool():
    assert isinstance(se.HAS_NUMPY, bool)


# ── numpy-backed cache (injected fake model; skipped in CI) ───────────

class _SpyModel:
    """Fake sentence-transformer: counts encode() calls, returns ones-matrix."""

    def __init__(self, np_) -> None:
        self.np = np_
        self.calls = 0

    def encode(self, texts, normalize_embeddings=True):  # noqa: ARG002
        self.calls += 1
        return self.np.ones((len(texts), 4), dtype="float32")


def _embedder_with_spy(np_, cache):
    r = se.EmbeddingRetriever(cache_dir=cache)
    spy = _SpyModel(np_)
    r._model = spy  # inject fake model so _ensure_model() skips loading sentence-transformers
    return r, spy


def test_embedding_cache_hit_skips_reencode(tmp_path: Path):
    np_ = pytest.importorskip("numpy")
    cache = tmp_path / "codesearch"
    docs = [{"id": "1", "file": "a.py", "text": "alpha"},
            {"id": "2", "file": "b.py", "text": "beta"}]
    r1, spy1 = _embedder_with_spy(np_, cache)
    r1.index(docs)
    assert spy1.calls == 1                       # cold: encode + save
    assert (cache / "embeddings.npy").exists()
    r2, spy2 = _embedder_with_spy(np_, cache)
    r2.index(docs)
    assert spy2.calls == 0                        # warm: load from cache, no encode
    assert r2._emb is not None and r2._emb.shape[0] == 2


def test_embedding_cache_miss_on_changed_text(tmp_path: Path):
    np_ = pytest.importorskip("numpy")
    cache = tmp_path / "codesearch"
    r1, spy1 = _embedder_with_spy(np_, cache)
    r1.index([{"id": "1", "file": "a", "text": "alpha"}])
    r2, spy2 = _embedder_with_spy(np_, cache)
    r2.index([{"id": "1", "file": "a", "text": "CHANGED"}])
    assert spy2.calls == 1                        # text changed → key miss → re-encode


def test_embedding_cache_miss_on_changed_model(tmp_path: Path):
    np_ = pytest.importorskip("numpy")
    cache = tmp_path / "codesearch"
    r1 = se.EmbeddingRetriever(model_name="m1", cache_dir=cache)
    s1 = _SpyModel(np_)
    r1._model = s1
    r1.index([{"id": "1", "file": "a", "text": "x"}])
    r2 = se.EmbeddingRetriever(model_name="m2", cache_dir=cache)
    s2 = _SpyModel(np_)
    r2._model = s2
    r2.index([{"id": "1", "file": "a", "text": "x"}])
    assert s2.calls == 1                          # model changed → key miss → re-encode


def test_embedding_cache_uses_codesearch_scope_not_session_recall(tmp_path: Path):
    np_ = pytest.importorskip("numpy")
    cache = tmp_path / "codesearch"
    r, _ = _embedder_with_spy(np_, cache)
    r.index([{"id": "1", "file": "a", "text": "x"}])
    # writes its own embeddings.npy and never session-recall's vectors.npy
    assert (cache / "embeddings.npy").exists()
    assert not (cache / "vectors.npy").exists()


def test_embedding_retriever_without_cache_does_not_persist(tmp_path: Path):
    np_ = pytest.importorskip("numpy")
    r = se.EmbeddingRetriever()  # no cache_dir
    r._model = _SpyModel(np_)
    r.index([{"id": "1", "file": "a", "text": "x"}])
    assert list(tmp_path.iterdir()) == []         # nothing written anywhere


def test_embedding_hits_expose_kind_and_is_test(tmp_path: Path):
    np_ = pytest.importorskip("numpy")
    r = se.EmbeddingRetriever()
    r._model = _SpyModel(np_)
    r.index([{"id": "tests/t.py:x", "file": "tests/t.py", "text": "validate token",
              "kind": "function", "is_test": True}])
    hits = r.search("token", k=1)
    assert hits and hits[0]["kind"] == "function" and hits[0]["is_test"] is True


def test_load_cache_corrupt_npy_falls_back_to_reencode(tmp_path: Path):
    np_ = pytest.importorskip("numpy")
    cache = tmp_path / "codesearch"
    cache.mkdir(parents=True)
    docs = [{"id": "1", "file": "a", "text": "x"}]
    key = se.corpus_key(se._DEFAULT_MODEL, [d["text"] for d in docs])
    (cache / "embeddings.npy").write_text("not a real npy", encoding="utf-8")
    (cache / "embeddings.key").write_text(key, encoding="utf-8")  # key matches → forces np.load
    r, spy = _embedder_with_spy(np_, cache)
    r.index(docs)
    assert spy.calls == 1                          # corrupt matrix → recover by re-encode
