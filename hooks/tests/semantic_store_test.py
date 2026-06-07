import sys
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from semantic_store import Store


def _norm(v):
    v = np.asarray(v, dtype=np.float32)
    return v / np.linalg.norm(v)


def test_save_load_roundtrip_and_search(tmp_path):
    s = Store(tmp_path)
    s.set_model("m")
    chunks = [{"text": "deploy kamal", "source": "a.md", "kind": "note", "anchor": "p0"},
              {"text": "expo webview", "source": "a.md", "kind": "note", "anchor": "p1"}]
    vecs = np.stack([_norm([1, 0, 0]), _norm([0, 1, 0])])
    s.upsert("a.md", mtime=1.0, sha="x", chunks=chunks, vectors=vecs)
    s.save()

    s2 = Store(tmp_path)
    assert s2.load() is True
    assert s2.model_name == "m"
    res = s2.search(_norm([1, 0, 0]), top_k=1, min_score=0.5)
    assert len(res) == 1 and res[0]["text"] == "deploy kamal"
    assert res[0]["score"] >= 0.99


def test_min_score_filters(tmp_path):
    s = Store(tmp_path); s.set_model("m")
    s.upsert("a.md", 1.0, "x",
             [{"text": "t", "source": "a.md", "kind": "note", "anchor": "p0"}],
             np.stack([_norm([1, 0, 0])]))
    res = s.search(_norm([0, 1, 0]), top_k=5, min_score=0.5)
    assert res == []


def test_incremental_needs_reindex(tmp_path):
    s = Store(tmp_path); s.set_model("m")
    s.upsert("a.md", 1.0, "sha1",
             [{"text": "t", "source": "a.md", "kind": "note", "anchor": "p0"}],
             np.stack([_norm([1, 0, 0])]))
    assert s.needs_reindex("a.md", 1.0, "sha1") is False
    assert s.needs_reindex("a.md", 2.0, "sha2") is True
    assert s.needs_reindex("b.md", 1.0, "z") is True


def test_remove_and_prune(tmp_path):
    s = Store(tmp_path); s.set_model("m")
    for name in ("a.md", "b.md"):
        s.upsert(name, 1.0, "x",
                 [{"text": name, "source": name, "kind": "note", "anchor": "p0"}],
                 np.stack([_norm([1, 0, 0])]))
    s.prune(keep={"a.md"})
    assert s.sources() == {"a.md"}


def test_model_change_resets(tmp_path):
    s = Store(tmp_path); s.set_model("m1")
    s.upsert("a.md", 1.0, "x",
             [{"text": "t", "source": "a.md", "kind": "note", "anchor": "p0"}],
             np.stack([_norm([1, 0, 0])]))
    s.set_model("m2")           # different model → index invalidated
    assert s.sources() == set()


def test_save_load_empty_roundtrip(tmp_path):
    s = Store(tmp_path); s.set_model("m")
    s.save()
    s2 = Store(tmp_path)
    assert s2.load() is True
    assert s2.search(_norm([1, 0, 0]), top_k=5, min_score=0.0) == []


def test_vectors_file_has_single_npy_suffix(tmp_path):
    s = Store(tmp_path); s.set_model("m")
    s.upsert("a.md", 1.0, "x",
             [{"text": "t", "source": "a.md", "kind": "note", "anchor": "p0"}],
             np.stack([_norm([1, 0, 0])]))
    s.save()
    assert (tmp_path / "vectors.npy").exists()
    assert not (tmp_path / "vectors.npy.npy").exists()
