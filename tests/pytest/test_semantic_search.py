"""Tests for memory_bank_skill/semantic_search.py — pluggable semantic retrieval.

Default backend is a pure-Python BM25 ($0, zero deps, deterministic). Optional
embeddings (sentence-transformers) degrade gracefully to BM25 when absent. The
`Retriever` port lets the user pick a backend.
"""

from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest

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


# ── Goal B: is_test detection + --source-only + kind/is_test surfacing ──

@pytest.mark.parametrize("path", [
    "src/auth/auth.test.ts",
    "components/Cart.spec.js",
    "src/__tests__/hooks.py",
    "faberlic-agent/tests/test_config.py",
    "internal/handler_test.go",
    "pkg/tests/helpers.py",
    "test_config.py",            # pytest prefix at repo root
    "src/handlers/test_handler.py",  # pytest prefix beside the module
])
def test_is_test_path_detects_test_files(path: str):
    assert ss.is_test_path(path) is True


@pytest.mark.parametrize("path", [
    "src/utils/latest.py",       # 'test' substring, not a test file
    "internal/contest.py",       # 'test' substring, not a test file
    "src/config/api.ts",
    "faberlic-api/src/db.js",
])
def test_is_test_path_rejects_non_test_files(path: str):
    assert ss.is_test_path(path) is False


def test_build_corpus_marks_kind_and_is_test():
    nodes = [
        {"kind": "function", "name": "process", "file": "src/a.py", "line": 1},
        {"kind": "function", "name": "test_process", "file": "tests/test_a.py", "line": 1},
    ]
    docs = ss.build_corpus(nodes)
    by_file = {d["file"]: d for d in docs}
    assert by_file["src/a.py"]["is_test"] is False
    assert by_file["src/a.py"]["kind"] == "function"
    assert by_file["tests/test_a.py"]["is_test"] is True


def test_build_corpus_folds_doc_and_signature_into_text():
    nodes = [{"kind": "function", "name": "greet", "file": "a.py", "line": 1,
              "signature": "(name, *, loud=False)", "doc": "Say hi politely"}]
    text = ss.build_corpus(nodes)[0]["text"]
    assert "loud" in text and "politely" in text


def test_build_corpus_without_doc_signature_text_unchanged():
    nodes = [{"kind": "function", "name": "greet", "file": "a.py", "line": 1}]
    assert ss.build_corpus(nodes)[0]["text"] == "greet function a.py"


def test_build_corpus_wiki_doc_is_kind_wiki_not_test(tmp_path: Path):
    wiki = tmp_path / "wiki"
    wiki.mkdir()
    (wiki / "community-0.md").write_text("# cluster", encoding="utf-8")
    docs = ss.build_corpus([], wiki_dir=wiki)
    wiki_doc = next(d for d in docs if d["id"].startswith("wiki/"))
    assert wiki_doc["kind"] == "wiki" and wiki_doc["is_test"] is False


def test_bm25_hits_expose_kind_and_is_test():
    r = ss.Bm25Retriever()
    r.index([{"id": "tests/test_a.py:test_x", "file": "tests/test_a.py",
              "text": "validate token", "kind": "function", "is_test": True}])
    hits = r.search("token", k=1)
    assert hits[0]["kind"] == "function" and hits[0]["is_test"] is True


def _write_graph_with_test(mb: Path):
    cb = mb / "codebase"
    cb.mkdir(parents=True)
    lines = [
        {"type": "node", "kind": "function", "name": "authenticate_user",
         "file": "src/auth.py", "line": 1},
        {"type": "node", "kind": "function", "name": "test_authenticate_user",
         "file": "tests/test_auth.py", "line": 1},
    ]
    (cb / "graph.json").write_text("\n".join(json.dumps(x) for x in lines) + "\n",
                                   encoding="utf-8")


def test_run_search_source_only_excludes_test_files(tmp_path: Path):
    mb = tmp_path / ".memory-bank"
    _write_graph_with_test(mb)
    full = ss.run_search(query="authenticate", mb_path=str(mb), backend="bm25")
    src_only = ss.run_search(query="authenticate", mb_path=str(mb),
                             backend="bm25", source_only=True)
    assert any(h["is_test"] for h in full["hits"])
    assert all(not h["is_test"] for h in src_only["hits"])
    assert src_only["hits"], "source files must still be returned"


def test_render_hits_md_marks_test_hits():
    result = {"ok": True, "query": "q", "backend": "bm25", "warnings": [],
              "hits": [{"id": "tests/t.py:x", "file": "tests/t.py", "score": 1.0,
                        "kind": "function", "is_test": True}]}
    out = ss.render_hits_md(result)
    assert "[test]" in out


def _load_cli():
    path = REPO_ROOT / "scripts" / "mb-semantic-search.py"
    spec = importlib.util.spec_from_file_location("mb_semantic_search_cli", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_cli_source_only_flag_filters(tmp_path: Path, capsys):
    _write_graph_with_test(tmp_path / ".memory-bank")
    cli = _load_cli()
    rc = cli.main(["mb-semantic-search.py", "authenticate", str(tmp_path / ".memory-bank"),
                   "--backend", "bm25", "--source-only", "--json"])
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["hits"] and all(not h["is_test"] for h in payload["hits"])


# Note: corpus_key + embedding-cache tests live in test_semantic_embeddings.py
# (split out to keep this file under the 400-line gate).


def test_make_retriever_bm25_ignores_cache_dir(tmp_path: Path):
    # Zero-dep / CI-runnable: BM25 path must never receive or create a cache.
    r = ss.make_retriever("bm25", cache_dir=tmp_path)
    assert isinstance(r, ss.Bm25Retriever)
    r.index([{"id": "1", "file": "a", "text": "x", "kind": "function", "is_test": False}])
    r.search("x")
    assert list(tmp_path.iterdir()) == []          # nothing persisted by BM25
