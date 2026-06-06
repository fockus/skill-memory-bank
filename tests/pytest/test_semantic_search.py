"""Tests for memory_bank_skill/semantic_search.py — pluggable semantic retrieval.

Default backend is a pure-Python BM25 ($0, zero deps, deterministic). Optional
embeddings (sentence-transformers) degrade gracefully to BM25 when absent. The
`Retriever` port lets the user pick a backend.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import semantic_embeddings as se  # noqa: E402
from memory_bank_skill import semantic_search as ss  # noqa: E402

# ── tokenizer ────────────────────────────────────────────────────────

def test_tokenize_splits_camel_case():
    assert ss.tokenize("getUserToken") == ["get", "user", "token"]


def test_tokenize_splits_snake_case():
    assert ss.tokenize("user_id_value") == ["user", "id", "value"]


def test_tokenize_lowercases_and_drops_punctuation():
    assert ss.tokenize("a.py::Foo()") == ["a", "py", "foo"]


def test_tokenize_preserves_unicode_identifiers():
    # non-ASCII tokens must not be silently dropped (review fix)
    assert ss.tokenize("café_Über") == ["café", "über"]


def test_tokenize_handles_allcaps_and_digits():
    assert ss.tokenize("HTTPServer") == ["http", "server"]
    assert ss.tokenize("io2DB") == ["io", "2", "db"]


# ── BM25 ranking ─────────────────────────────────────────────────────

def _corpus():
    return [
        {"id": "1", "file": "auth.py", "text": "validate user token authentication"},
        {"id": "2", "file": "cart.py", "text": "shopping cart total price"},
        {"id": "3", "file": "auth2.py", "text": "token refresh helper"},
    ]


def test_bm25_ranks_relevant_doc_first():
    r = ss.Bm25Retriever()
    r.index(_corpus())
    hits = r.search("user token", k=3)
    assert hits and hits[0]["id"] == "1"


def test_bm25_returns_only_matching_docs():
    r = ss.Bm25Retriever()
    r.index(_corpus())
    hits = r.search("cart", k=5)
    assert [h["id"] for h in hits] == ["2"]


def test_bm25_empty_corpus_returns_empty():
    r = ss.Bm25Retriever()
    r.index([])
    assert r.search("anything") == []


def test_bm25_deterministic_across_calls():
    r = ss.Bm25Retriever()
    r.index(_corpus())
    assert r.search("token") == r.search("token")


def test_bm25_no_match_returns_empty():
    r = ss.Bm25Retriever()
    r.index(_corpus())
    assert r.search("zzzznomatch") == []


# ── corpus builder ───────────────────────────────────────────────────

def test_build_corpus_from_nodes():
    nodes = [
        {"kind": "function", "name": "process", "file": "a.py", "line": 1},
        {"kind": "class", "name": "Cart", "file": "cart.py", "line": 1},
        {"kind": "module", "name": "a.py", "file": "a.py", "line": 1},
    ]
    docs = ss.build_corpus(nodes)
    texts = " ".join(d["text"] for d in docs)
    assert "process" in texts and "Cart" in texts
    assert len(docs) == 3


def test_build_corpus_includes_wiki_articles(tmp_path: Path):
    wiki = tmp_path / "wiki"
    wiki.mkdir()
    (wiki / "community-0.md").write_text("# Auth cluster\nhandles login", encoding="utf-8")
    nodes = [{"kind": "function", "name": "f", "file": "a.py", "line": 1}]
    docs = ss.build_corpus(nodes, wiki_dir=wiki)
    ids = {d["id"] for d in docs}
    assert any("wiki/community-0.md" in i for i in ids)


# ── factory + graceful fallback ─────────────────────────────────────

def test_make_retriever_bm25_explicit():
    r = ss.make_retriever("bm25")
    assert r.name == "bm25" and r.available


def test_make_retriever_embeddings_falls_back_when_unavailable():
    warnings: list[str] = []
    r = ss.make_retriever("embeddings", warnings=warnings)
    if not se.HAS_SENTENCE_TRANSFORMERS:
        assert r.name == "bm25"
        assert any("bm25" in w for w in warnings)
    else:  # pragma: no cover - only when the optional dep is installed
        assert r.name == "embeddings"


def test_make_retriever_auto_uses_bm25_without_embeddings():
    r = ss.make_retriever("auto")
    if not se.HAS_SENTENCE_TRANSFORMERS:
        assert r.name == "bm25"


def test_embedding_retriever_available_reflects_dependency():
    r = se.EmbeddingRetriever()
    assert r.available == se.HAS_SENTENCE_TRANSFORMERS


def test_retriever_protocol_contract():
    r = ss.Bm25Retriever()
    assert hasattr(r, "available") and hasattr(r, "index") and hasattr(r, "search")
    assert isinstance(r.available, bool)


# ── run_search (CLI core) ────────────────────────────────────────────

def _write_graph(mb: Path):
    cb = mb / "codebase"
    cb.mkdir(parents=True)
    lines = [
        {"type": "node", "kind": "function", "name": "authenticate_user", "file": "auth.py", "line": 1},
        {"type": "node", "kind": "function", "name": "render_cart", "file": "cart.py", "line": 1},
    ]
    (cb / "graph.json").write_text("\n".join(json.dumps(x) for x in lines) + "\n", encoding="utf-8")


def test_run_search_returns_ranked_hits(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    result = ss.run_search(query="authenticate user", mb_path=str(mb), backend="bm25")
    assert result["ok"] is True
    assert result["hits"] and "auth.py" in result["hits"][0]["file"]


def test_run_search_missing_graph_is_graceful(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    result = ss.run_search(query="x", mb_path=str(mb), backend="bm25")
    assert result["ok"] is False
    assert any("missing graph" in w for w in result["warnings"])
