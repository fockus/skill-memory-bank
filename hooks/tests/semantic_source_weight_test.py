"""A4 — recall source-type weighting: curated note/session out-rank raw transcript
at comparable cosine; MB_RECALL_SOURCE_WEIGHTS=off restores pure-cosine order."""
import sys
import numpy as np
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from semantic_store import Store


def _norm(v):
    v = np.asarray(v, dtype=np.float32)
    return v / np.linalg.norm(v)


def _store(tmp_path):
    s = Store(tmp_path)
    s.set_model("m")
    # transcript has HIGHER raw cosine (0.9); note LOWER (0.8).
    s.upsert("t.md", 1.0, "x",
             [{"text": "t", "source": "t.md", "kind": "transcript", "anchor": "p0"}],
             np.stack([_norm([0.9, 0.19 ** 0.5, 0])]))
    s.upsert("n.md", 1.0, "y",
             [{"text": "n", "source": "n.md", "kind": "note", "anchor": "p0"}],
             np.stack([_norm([0.8, 0.6, 0])]))
    return s


def test_weighting_lifts_note_above_transcript(tmp_path, monkeypatch):
    monkeypatch.delenv("MB_RECALL_SOURCE_WEIGHTS", raising=False)
    res = _store(tmp_path).search(_norm([1, 0, 0]), top_k=5, min_score=0.0)
    assert res[0]["kind"] == "note"          # 0.8*1.0 > 0.9*0.85


def test_off_restores_pure_cosine(tmp_path, monkeypatch):
    monkeypatch.setenv("MB_RECALL_SOURCE_WEIGHTS", "off")
    res = _store(tmp_path).search(_norm([1, 0, 0]), top_k=5, min_score=0.0)
    assert res[0]["kind"] == "transcript"    # pure cosine 0.9 > 0.8


def test_missing_kind_is_weight_one(tmp_path, monkeypatch):
    monkeypatch.delenv("MB_RECALL_SOURCE_WEIGHTS", raising=False)
    s = Store(tmp_path)
    s.set_model("m")
    s.upsert("x.md", 1.0, "z",
             [{"text": "x", "source": "x.md", "anchor": "p0"}],
             np.stack([_norm([1, 0, 0])]))
    res = s.search(_norm([1, 0, 0]), top_k=5, min_score=0.0)
    assert res and res[0]["score"] == 1.0    # no crash; raw cosine reported


def test_custom_weights_env(tmp_path, monkeypatch):
    # Make transcript win again by overriding weights to neutral.
    monkeypatch.setenv("MB_RECALL_SOURCE_WEIGHTS", "note=1.0,transcript=1.0")
    res = _store(tmp_path).search(_norm([1, 0, 0]), top_k=5, min_score=0.0)
    assert res[0]["kind"] == "transcript"
