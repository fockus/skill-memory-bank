"""BM25 hot path — recall must work with NO embedding model in the process.

I-132: the per-prompt UserPromptSubmit hook used to spawn a fresh python that
loaded a ~2.5 GB ONNX model per invocation (and detached SessionEnd reindexers
multiplied it). The default backend is now meta-only BM25. These tests pin the
core invariant: **the default search/index path never constructs an embedding
backend**, and anything that could is a singleton behind a non-blocking flock.
"""

from __future__ import annotations

import fcntl
import sys
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

BIN = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BIN / "lib"))

import indexer  # noqa: E402
import semantic_embed  # noqa: E402
from searcher import run_search  # noqa: E402


@pytest.fixture()
def mb(tmp_path):
    mb = tmp_path / "mb"
    (mb / "session").mkdir(parents=True)
    (mb / "notes").mkdir()
    (mb / "notes" / "a.md").write_text("# Deploy\nkamal proxy host deploy notes")
    (mb / "session" / "2026-01-01_s.md").write_text("## Live log\n- did the expo webview tweak")
    (mb / "progress.md").write_text("## 2026-01-02\n- I-042 done: kamal deploy pipeline green")
    (mb / "agreements.md").write_text("- AGR-007: releases go through the kamal proxy only")
    return mb


@pytest.fixture()
def no_model(monkeypatch):
    """Poison the embedder: constructing a real backend fails the test."""

    def boom(self):
        raise AssertionError("embedding model must not be constructed on the BM25 path")

    monkeypatch.setattr(semantic_embed.Embedder, "_ensure", boom)


# ── discovery ────────────────────────────────────────────────────────


def test_discover_includes_progress_and_agreements(mb):
    kinds = {sid: kind for _, kind, sid in indexer._discover(mb)}
    assert kinds.get("progress.md") == "progress"
    assert kinds.get("agreements.md") == "agreement"


def test_discover_transcripts_default_off(mb, tmp_path, monkeypatch):
    home = tmp_path / "home"
    slug = str(mb.parent).replace("/", "-").replace(".", "-")
    td = home / ".claude" / "projects" / slug
    td.mkdir(parents=True)
    (td / "x.jsonl").write_text('{"type":"user","message":{"role":"user","content":"hi"}}')
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.delenv("MB_SEMANTIC_INDEX_TRANSCRIPTS", raising=False)
    assert not [s for _, k, s in indexer._discover(mb) if k == "transcript"]
    monkeypatch.setenv("MB_SEMANTIC_INDEX_TRANSCRIPTS", "1")
    assert [s for _, k, s in indexer._discover(mb) if k == "transcript"]


# ── BM25 index + search, model-free ──────────────────────────────────


def test_bm25_index_and_search_without_model(mb, tmp_path, no_model, monkeypatch):
    monkeypatch.delenv("MB_SEMANTIC_BACKEND", raising=False)
    idx = tmp_path / "idx"
    res = indexer.index_sources(mb, idx, sources=None, full=True)
    assert res["indexed"] >= 4
    out = run_search(idx, "kamal deploy", top_k=3, min_score=0.35, timeout=3)
    assert out and any("kamal" in h["text"] for h in out)


def test_bm25_surfaces_agreements(mb, tmp_path, no_model):
    idx = tmp_path / "idx"
    indexer.index_sources(mb, idx, sources=None, full=True)
    out = run_search(idx, "releases kamal proxy", top_k=5, min_score=0.35, timeout=3)
    assert any(h.get("kind") == "agreement" for h in out)


def test_bm25_no_match_returns_empty(mb, tmp_path, no_model):
    idx = tmp_path / "idx"
    indexer.index_sources(mb, idx, sources=None, full=True)
    assert run_search(idx, "quantum zebra blockchain", top_k=3, min_score=0.35, timeout=3) == []


def test_bm25_missing_index_returns_empty(tmp_path, no_model):
    assert run_search(tmp_path / "nope", "anything", top_k=3, min_score=0.35, timeout=3) == []


# ── singleton locks ──────────────────────────────────────────────────


def test_index_write_lock_busy_skips(mb, tmp_path, no_model):
    idx = tmp_path / "idx"
    idx.mkdir()
    with open(idx / ".write.lock", "w") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
        res = indexer.index_sources(mb, idx, sources=None, full=True)
        assert res.get("skipped") == "locked"
        assert not (idx / "meta.jsonl").exists()


def test_embeddings_model_lock_busy_falls_back_to_bm25(mb, tmp_path, no_model):
    idx = tmp_path / "idx"
    indexer.index_sources(mb, idx, sources=None, full=True)
    idx.mkdir(exist_ok=True)
    with open(idx / ".model.lock", "w") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
        out = run_search(
            idx, "kamal deploy", top_k=3, min_score=0.35, timeout=3, backend="embeddings"
        )
        assert out and any("kamal" in h["text"] for h in out)
