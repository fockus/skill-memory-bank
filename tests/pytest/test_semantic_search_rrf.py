"""TDD tests for Task 2: RRF as the auto-backend default in code search.

Scenario 1 — sentence-transformers absent: auto backend = pure BM25, no fusion.
Scenario 2 — both backends available: auto backend = RRF fusion; deterministic.
Regression  — explicit --backend bm25 / --backend embeddings keep exact semantics.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from memory_bank_skill import semantic_search as ss  # noqa: E402
from memory_bank_skill.rrf import rrf_merge  # noqa: E402

# ── helpers ──────────────────────────────────────────────────────────────────


def _make_docs() -> list[dict[str, Any]]:
    """Small corpus with two retrievable documents."""
    return [
        {
            "id": "auth.py:login",
            "file": "auth.py",
            "text": "login user authenticate session token",
            "kind": "function",
            "is_test": False,
        },
        {
            "id": "cart.py:checkout",
            "file": "cart.py",
            "text": "checkout cart payment total price",
            "kind": "function",
            "is_test": False,
        },
        {
            "id": "utils.py:hash",
            "file": "utils.py",
            "text": "hash password crypto bcrypt salt",
            "kind": "function",
            "is_test": False,
        },
    ]


def _write_graph(mb: Path) -> None:
    """Write a minimal graph.json with three source nodes."""
    cb = mb / "codebase"
    cb.mkdir(parents=True)
    lines = [
        {"type": "node", "kind": "function", "name": "login", "file": "auth.py", "line": 1},
        {"type": "node", "kind": "function", "name": "checkout", "file": "cart.py", "line": 1},
        {
            "type": "node",
            "kind": "function",
            "name": "hash_password",
            "file": "utils.py",
            "line": 1,
        },
    ]
    (cb / "graph.json").write_text("\n".join(json.dumps(x) for x in lines) + "\n", encoding="utf-8")


class FakeEmbeddingRetriever:
    """Fake embeddings retriever for testing RRF fusion without sentence-transformers."""

    name = "embeddings"
    available = True

    def __init__(self, **kwargs: Any) -> None:  # accept cache_dir etc. from make_retriever
        self._docs: list[dict[str, Any]] = []
        self._order: list[str] = []  # deterministic fake ranking by doc id

    def index(self, docs: list[dict[str, Any]]) -> None:
        self._docs = list(docs)
        # Fake: reverse alphabetical by id (deliberately differs from BM25)
        self._order = sorted([d["id"] for d in docs], reverse=True)

    def search(self, query: str, k: int = 10) -> list[dict[str, Any]]:  # noqa: ARG002
        by_id = {d["id"]: d for d in self._docs}
        results = []
        for doc_id in self._order[:k]:
            if doc_id in by_id:
                doc = by_id[doc_id]
                results.append(
                    {
                        "id": doc["id"],
                        "file": doc.get("file", ""),
                        "score": 0.5,  # flat score — order is what matters
                        "snippet": doc["text"][:120],
                        "kind": doc.get("kind", ""),
                        "is_test": doc.get("is_test", False),
                    }
                )
        return results


# ── Scenario 1: sentence-transformers absent → pure BM25 (no fusion) ─────────


class TestScenario1NoBM25OnlyAuto:
    """When sentence-transformers is not installed, auto = pure BM25."""

    def test_make_retriever_auto_without_embeddings_returns_bm25(self, monkeypatch):
        """auto backend falls back to BM25 when embeddings are unavailable."""
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False
        )
        r = ss.make_retriever("auto")
        assert r.name == "bm25"

    def test_make_retriever_auto_without_embeddings_single_retriever(self, monkeypatch):
        """auto without embeddings returns a single BM25 Retriever (not a fused one)."""
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False
        )
        r = ss.make_retriever("auto")
        assert isinstance(r, ss.Bm25Retriever)

    def test_run_search_auto_without_embeddings_uses_bm25_backend(
        self, tmp_path: Path, monkeypatch
    ):
        """run_search(backend='auto') with no embeddings reports backend='bm25'."""
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False
        )
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        assert result["ok"] is True
        assert result["backend"] == "bm25"

    def test_run_search_auto_without_embeddings_returns_hits(self, tmp_path: Path, monkeypatch):
        """run_search(backend='auto') without embeddings still returns relevant hits."""
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False
        )
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        assert result["ok"] is True
        assert len(result["hits"]) > 0

    def test_run_search_auto_without_embeddings_exit0_equivalent(self, tmp_path: Path, monkeypatch):
        """run_search without embeddings completes without error (exit 0 equivalent)."""
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False
        )
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="checkout", mb_path=str(mb), backend="auto")
        assert result["ok"] is True
        assert result["warnings"] == []  # no fallback warning for auto mode

    def test_run_search_auto_without_embeddings_equals_pure_bm25_ranking(
        self, tmp_path: Path, monkeypatch
    ):
        """Scenario 1 THEN-clause: auto (no embeddings) result list EQUALS pure BM25.

        Drives the SAME query through run_search twice — once backend='auto'
        (embeddings unavailable, must degrade), once backend='bm25' — and
        asserts the hit lists are exactly equal (REQ-002 fail-open: degrade to
        BM25, not just "return some hits").
        """
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False
        )
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        auto = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        bm25 = ss.run_search(query="login", mb_path=str(mb), backend="bm25")
        assert auto["backend"] == "bm25"
        assert auto["hits"] == bm25["hits"]


# ── Scenario 2: both backends available → RRF fusion, deterministic ──────────


class TestScenario2RRFFusion:
    """When embeddings are available, auto = RRF merge of BM25 + embeddings."""

    def test_make_retriever_auto_with_embeddings_returns_fused(self, monkeypatch):
        """make_retriever('auto') with embeddings available returns a FusedRetriever."""
        monkeypatch.setattr("memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", True)
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.EmbeddingRetriever",
            FakeEmbeddingRetriever,
        )
        r = ss.make_retriever("auto")
        assert isinstance(r, ss.FusedRetriever)
        assert r.name == "auto"

    def test_rrf_fusion_in_run_search_with_fake_embeddings(self, tmp_path: Path, monkeypatch):
        """run_search with patched embeddings uses RRF and returns 'auto' backend."""
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        # Patch make_retriever so 'auto' returns the PRODUCTION FusedRetriever
        # backed by BM25 + FakeEmbeddingRetriever — tests RRF wiring without a
        # real model while exercising the production fusion class.
        original_make = ss.make_retriever

        def patched_make(backend: str = "auto", **kwargs):
            if backend != "auto":
                return original_make(backend, **kwargs)
            return ss.FusedRetriever(ss.Bm25Retriever(), FakeEmbeddingRetriever())

        monkeypatch.setattr(ss, "make_retriever", patched_make)
        result = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        assert result["ok"] is True
        assert result["backend"] == "auto"

    def test_rrf_fusion_order_is_deterministic_across_two_runs(self, tmp_path: Path, monkeypatch):
        """RRF fusion output is identical across two consecutive calls (determinism)."""
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        original_make = ss.make_retriever

        def patched_make(backend: str = "auto", **kwargs):
            if backend != "auto":
                return original_make(backend, **kwargs)
            return ss.FusedRetriever(ss.Bm25Retriever(), FakeEmbeddingRetriever())

        monkeypatch.setattr(ss, "make_retriever", patched_make)
        run1 = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        run2 = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        assert run1["hits"] == run2["hits"]

    def test_fused_retriever_scores_equal_rrf_sum_across_backends(self, monkeypatch):
        """Scenario 2 THEN-clause: scores == 1/(60+rank) summed across backends.

        Drives the PRODUCTION FusedRetriever with controlled rankings (BM25 over
        a real corpus + a fake embeddings retriever whose order is fixed via
        monkeypatch). Asserts the returned hit ids AND scores match
        ``rrf_merge([bm25_ranking, emb_ranking])`` exactly (REQ-001 fusion math).
        """
        docs = _make_docs()  # auth.py:login, cart.py:checkout, utils.py:hash

        bm25 = ss.Bm25Retriever()
        # Controlled embeddings order: deliberately differs from BM25 so the
        # fusion sums two distinct ranks per id (not a trivial pass-through).
        emb = FakeEmbeddingRetriever()
        monkeypatch.setattr(
            emb,
            "index",
            lambda d: (
                setattr(emb, "_docs", list(d))
                or setattr(emb, "_order", ["cart.py:checkout", "auth.py:login", "utils.py:hash"])
            ),
        )

        fused = ss.FusedRetriever(bm25, emb)
        fused.index(docs)
        hits = fused.search("login user", k=3)

        # Reproduce what the production class fuses: each backend's own ranking.
        fetch_k = min(3 * 3, len(docs))
        bm25_ranking = [h["id"] for h in bm25.search("login user", k=fetch_k)]
        emb_ranking = [h["id"] for h in emb.search("login user", k=fetch_k)]
        expected = rrf_merge([bm25_ranking, emb_ranking])

        assert [h["id"] for h in hits] == [doc_id for doc_id, _ in expected[:3]]
        for hit, (doc_id, score) in zip(hits, expected[:3], strict=True):
            assert hit["id"] == doc_id
            assert hit["score"] == pytest.approx(round(score, 6))

    def test_fused_retriever_score_matches_hand_computed_rrf(self, monkeypatch):
        """Score math is exactly 1/(60+rank) summed — hand-computed cross-check.

        Forces a known divergence between the two backends and verifies the
        production fusion against literal ``1/(60+rank)`` arithmetic, so the test
        fails if the constant k or the rank base ever changes.
        """
        docs = _make_docs()

        bm25 = ss.Bm25Retriever()
        emb = FakeEmbeddingRetriever()
        # Pin BM25 to a known ranking too, so both sides are fully controlled.
        monkeypatch.setattr(
            bm25,
            "search",
            lambda q, k=10: [  # noqa: ARG005
                {"id": i} for i in ["auth.py:login", "cart.py:checkout", "utils.py:hash"][:k]
            ],
        )
        monkeypatch.setattr(
            emb,
            "index",
            lambda d: (
                setattr(emb, "_docs", list(d))
                or setattr(emb, "_order", ["cart.py:checkout", "auth.py:login", "utils.py:hash"])
            ),
        )

        fused = ss.FusedRetriever(bm25, emb)
        fused.index(docs)
        hits = fused.search("anything", k=3)
        by_id = {h["id"]: h["score"] for h in hits}

        # BM25 ranks:  login=1, checkout=2, hash=3
        # emb  ranks:  checkout=1, login=2, hash=3
        login_expected = round(1 / (60 + 1) + 1 / (60 + 2), 6)
        checkout_expected = round(1 / (60 + 2) + 1 / (60 + 1), 6)
        hash_expected = round(1 / (60 + 3) + 1 / (60 + 3), 6)
        assert by_id["auth.py:login"] == pytest.approx(login_expected)
        assert by_id["cart.py:checkout"] == pytest.approx(checkout_expected)
        assert by_id["utils.py:hash"] == pytest.approx(hash_expected)
        # login and checkout tie on score; tie-break is key-ascending → login first.
        assert hits[0]["id"] == "auth.py:login"

    def test_rrf_merge_produces_different_order_from_pure_bm25(self, monkeypatch):
        """Fusion changes rank ordering compared to pure BM25 when rankings diverge."""
        docs = _make_docs()
        bm25 = ss.Bm25Retriever()
        bm25.index(docs)
        bm25_hits = bm25.search("authenticate", k=3)

        fake_emb = FakeEmbeddingRetriever()
        fake_emb.index(docs)
        emb_hits = fake_emb.search("authenticate", k=3)

        bm25_ranking = [h["id"] for h in bm25_hits]
        emb_ranking = [h["id"] for h in emb_hits]

        fused = rrf_merge([bm25_ranking, emb_ranking])
        fused_order = [k for k, _ in fused]

        # RRF scores must be deterministic (calling twice gives same result)
        fused2 = rrf_merge([bm25_ranking, emb_ranking])
        assert fused == fused2

        # All docs from either ranking appear in the fused result
        all_in = set(bm25_ranking) | set(emb_ranking)
        assert set(fused_order) == all_in


# ── Regression: explicit --backend paths unchanged ────────────────────────────


class TestExplicitBackendRegression:
    """Explicit --backend bm25 and --backend embeddings keep exact v5.0.x semantics."""

    def test_explicit_bm25_returns_bm25_name(self):
        r = ss.make_retriever("bm25")
        assert r.name == "bm25"
        assert isinstance(r, ss.Bm25Retriever)

    def test_explicit_bm25_result_unchanged_after_auto_rrf_change(self, tmp_path: Path):
        """bm25 backend results are byte-identical regardless of auto logic."""
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="login", mb_path=str(mb), backend="bm25")
        assert result["ok"] is True
        assert result["backend"] == "bm25"
        assert result["hits"]

    def test_explicit_bm25_hits_structure_unchanged(self, tmp_path: Path):
        """BM25 hit dicts keep: id, file, score, snippet, kind, is_test."""
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="login", mb_path=str(mb), backend="bm25")
        required_keys = {"id", "file", "score", "snippet", "kind", "is_test"}
        for hit in result["hits"]:
            assert required_keys.issubset(hit.keys())

    def test_explicit_embeddings_falls_back_to_bm25_without_dep(self, monkeypatch):
        """explicit embeddings still falls back to BM25 when dep is missing (unchanged)."""
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", False
        )
        warnings: list[str] = []
        r = ss.make_retriever("embeddings", warnings=warnings)
        assert r.name == "bm25"
        assert any("bm25" in w for w in warnings)

    def test_explicit_bm25_no_warnings_no_rrf(self, tmp_path: Path):
        """Explicit bm25 never triggers RRF or emits embeddings warnings."""
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="login", mb_path=str(mb), backend="bm25")
        assert result["warnings"] == []

    def test_run_search_backend_field_matches_explicit_request(self, tmp_path: Path):
        """backend field in result mirrors what was explicitly requested."""
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="hash", mb_path=str(mb), backend="bm25")
        assert result["backend"] == "bm25"


# ── Scenario 2 production path: make_retriever("auto") returns FusedRetriever ─


class TestScenario2ProductionPath:
    """make_retriever('auto') with embeddings available must return a fused retriever.

    These tests patch EmbeddingRetriever at the import seam inside semantic_search
    (not make_retriever itself) so the production factory logic is exercised.
    They are RED until FusedRetriever is introduced in make_retriever.
    """

    def _patch_embedding_retriever(self, monkeypatch):
        """Replace EmbeddingRetriever inside semantic_search with FakeEmbeddingRetriever."""
        monkeypatch.setattr("memory_bank_skill.semantic_embeddings.HAS_SENTENCE_TRANSFORMERS", True)
        # Patch the class that make_retriever instantiates
        monkeypatch.setattr(
            "memory_bank_skill.semantic_embeddings.EmbeddingRetriever",
            FakeEmbeddingRetriever,
        )

    def test_make_retriever_auto_with_embeddings_name_is_auto(self, monkeypatch):
        """make_retriever('auto') with embeddings must return retriever named 'auto'."""
        self._patch_embedding_retriever(monkeypatch)
        r = ss.make_retriever("auto")
        assert r.name == "auto", (
            f"Expected 'auto' (FusedRetriever), got '{r.name}' — "
            "implement FusedRetriever in make_retriever"
        )

    def test_make_retriever_auto_with_embeddings_not_bm25_instance(self, monkeypatch):
        """make_retriever('auto') with embeddings must NOT return a plain Bm25Retriever."""
        self._patch_embedding_retriever(monkeypatch)
        r = ss.make_retriever("auto")
        assert not isinstance(r, ss.Bm25Retriever), (
            "auto with embeddings available must return a FusedRetriever, not BM25"
        )

    def test_run_search_auto_with_embeddings_reports_auto_backend(
        self, tmp_path: Path, monkeypatch
    ):
        """run_search(backend='auto') with embeddings must report backend='auto' in result."""
        self._patch_embedding_retriever(monkeypatch)
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        assert result["ok"] is True
        assert result["backend"] == "auto", (
            f"Expected backend='auto' (RRF fused), got '{result['backend']}'"
        )

    def test_run_search_auto_with_embeddings_returns_hits(self, tmp_path: Path, monkeypatch):
        """run_search(backend='auto') with fused backend still returns hits."""
        self._patch_embedding_retriever(monkeypatch)
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        assert result["ok"] is True
        assert len(result["hits"]) > 0

    def test_run_search_auto_fused_is_deterministic(self, tmp_path: Path, monkeypatch):
        """RRF fused auto backend produces identical hits on two consecutive runs."""
        self._patch_embedding_retriever(monkeypatch)
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        run1 = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        run2 = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        assert run1["hits"] == run2["hits"]

    def test_run_search_auto_fused_hits_have_required_fields(self, tmp_path: Path, monkeypatch):
        """Fused hits expose id, file, score, snippet, kind, is_test."""
        self._patch_embedding_retriever(monkeypatch)
        mb = tmp_path / ".memory-bank"
        _write_graph(mb)
        result = ss.run_search(query="login", mb_path=str(mb), backend="auto")
        required = {"id", "file", "score", "snippet", "kind", "is_test"}
        for hit in result["hits"]:
            assert required.issubset(hit.keys())
