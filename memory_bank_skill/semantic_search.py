"""Semantic code search for Memory Bank — pluggable retrieval backend.

Default backend is a pure-Python **Okapi BM25** over graph-node text + wiki
articles: deterministic, $0, zero dependencies. Users can opt into local
embeddings (``semantic_embeddings.EmbeddingRetriever``); the factory falls back to
BM25 when that optional dependency is absent (graceful degradation).

Indexed corpus = function/class/module nodes from ``graph.json`` (+ wiki articles
if ``/mb wiki`` has been run). A code-aware tokenizer splits ``snake_case`` and
``camelCase`` so ``getUserToken`` matches a query for ``user token``.
"""

from __future__ import annotations

import json
import math
import re
from collections import Counter
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

from memory_bank_skill import community_expand as ce
from memory_bank_skill.codegraph_loader import load_graph
from memory_bank_skill.rrf import rrf_merge

_TOKEN_SPLIT = re.compile(r"[\W_]+")  # split on underscore + non-(unicode word char)
_CAMEL = re.compile(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|[0-9]+")
_SNIPPET = 120
_MAX_WIKI_CHARS = 8000  # bounded read for wiki article docs

# A path is a test/spec file when a path segment is `tests/`/`__tests__/`, the
# filename carries a `.test.`/`.spec.` infix or a `_test` suffix, or it is a
# pytest `test_*.py` file. Anchored on segment/extension boundaries so
# `latest.py` / `contest.py` are NOT matched.
_TEST_PATH = re.compile(
    r"(?:^|/)tests?/|(?:^|/)__tests__/|(?:^|/)test_[^/]*\.py$|\.(?:test|spec)\.|_test\b",
    re.IGNORECASE,
)


def is_test_path(path: str) -> bool:
    """True when *path* looks like a test/spec file rather than production source."""
    return bool(_TEST_PATH.search(path))


def tokenize(text: str) -> list[str]:
    """Code-aware tokenizer: split punctuation/underscore, then snake_case + camelCase.

    ASCII camelCase is split (``getUserToken`` → ``get user token``). Non-ASCII tokens
    the ASCII splitter cannot fully reconstruct (e.g. ``café``) are kept whole and
    lowercased rather than silently dropped.
    """
    tokens: list[str] = []
    for raw in _TOKEN_SPLIT.split(text):
        if not raw:
            continue
        parts = _CAMEL.findall(raw)
        if parts and sum(len(p) for p in parts) == len(raw):
            tokens.extend(p.lower() for p in parts)
        else:
            tokens.append(raw.lower())
    return tokens


@runtime_checkable
class Retriever(Protocol):
    """Retrieval port (ISP — 3 members). Adapters: BM25 (default), embeddings (opt-in)."""

    name: str

    @property
    def available(self) -> bool: ...

    def index(self, docs: list[dict[str, Any]]) -> None: ...

    def search(self, query: str, k: int = 10) -> list[dict[str, Any]]: ...


class Bm25Retriever:
    """Pure-Python Okapi BM25. Always available, deterministic, zero deps."""

    name = "bm25"

    def __init__(self, k1: float = 1.5, b: float = 0.75) -> None:
        self.k1 = k1
        self.b = b
        self._docs: list[dict[str, Any]] = []
        self._tok: list[list[str]] = []
        self._df: Counter[str] = Counter()
        self._avgdl: float = 0.0

    @property
    def available(self) -> bool:
        return True

    def index(self, docs: list[dict[str, Any]]) -> None:
        self._docs = list(docs)
        self._tok = [tokenize(d["text"]) for d in self._docs]
        self._df = Counter()
        for toks in self._tok:
            for term in set(toks):
                self._df[term] += 1
        lengths = [len(t) for t in self._tok]
        self._avgdl = (sum(lengths) / len(lengths)) if lengths else 0.0

    def _score(self, query_terms: list[str], tf: Counter[str], dl: int) -> float:
        n = len(self._docs)
        score = 0.0
        for term in query_terms:
            freq = tf.get(term, 0)
            if not freq:
                continue
            df = self._df.get(term, 0)
            idf = math.log(1 + (n - df + 0.5) / (df + 0.5))
            norm = self.k1 * (1 - self.b + self.b * (dl / self._avgdl if self._avgdl else 1.0))
            score += idf * (freq * (self.k1 + 1)) / (freq + norm)
        return score

    def search(self, query: str, k: int = 10) -> list[dict[str, Any]]:
        if not self._docs:
            return []
        terms = tokenize(query)
        scored: list[tuple[float, dict[str, Any]]] = []
        for doc, toks in zip(self._docs, self._tok, strict=True):
            score = self._score(terms, Counter(toks), len(toks))
            if score > 0:
                scored.append((score, doc))
        scored.sort(key=lambda s: (-s[0], str(s[1]["id"])))
        return [
            {
                "id": doc["id"],
                "file": doc.get("file", ""),
                "score": round(score, 6),
                "snippet": doc["text"][:_SNIPPET],
                "kind": doc.get("kind", ""),
                "is_test": doc.get("is_test", False),
            }
            for score, doc in scored[:k]
        ]


def build_corpus(
    nodes: list[dict[str, Any]],
    wiki_dir: Path | str | None = None,
) -> list[dict[str, Any]]:
    """Build searchable docs from graph nodes (+ wiki articles when present)."""
    docs: list[dict[str, Any]] = []
    for n in nodes:
        kind = n.get("kind")
        if kind not in ("function", "class", "module"):
            continue
        name = str(n.get("name", ""))
        file_name = str(n.get("file", ""))
        # Optional doc/signature (present only when graph built with `--docs`) enrich
        # the indexed text so search matches intent words, not just identifiers.
        extra = [str(n[f]) for f in ("signature", "doc") if n.get(f)]
        text = " ".join([name, kind, file_name.replace("/", " "), *extra])
        doc_id = file_name if name == file_name else f"{file_name}:{name}"
        docs.append(
            {
                "id": doc_id,
                "file": file_name,
                "text": text,
                "kind": kind,
                "is_test": is_test_path(file_name),
            }
        )
    if wiki_dir is not None:
        wd = Path(wiki_dir)
        if wd.is_dir():
            for md in sorted(wd.glob("*.md")):
                with md.open(encoding="utf-8", errors="replace") as handle:
                    text = handle.read(_MAX_WIKI_CHARS)  # bounded read
                docs.append(
                    {
                        "id": f"wiki/{md.name}",
                        "file": f"wiki/{md.name}",
                        "text": text,
                        "kind": "wiki",
                        "is_test": False,
                    }
                )
    return docs


def load_churn(graph_path: Path | str) -> dict[str, int]:
    """Read additive ``node-attr`` churn rows from ``graph.json`` → ``{file: churn_30d}``.

    Churn rows exist only when the graph was built with ``/mb graph --apply
    --cochange``. Absent file / no rows / malformed lines → ``{}`` (fail-open).
    The canonical graph loader ignores ``node-attr`` rows, so this reads the raw
    JSONL directly.
    """
    path = Path(graph_path)
    if not path.is_file():
        return {}
    churn: dict[str, int] = {}
    with path.open(encoding="utf-8") as stream:
        for line in stream:
            stripped = line.strip()
            if not stripped or '"node-attr"' not in stripped:
                continue
            try:
                record = json.loads(stripped)
            except json.JSONDecodeError:
                continue
            if record.get("type") != "node-attr":
                continue
            file_name = record.get("file")
            value = record.get("churn_30d")
            if isinstance(file_name, str) and isinstance(value, int):
                churn[file_name] = value
    return churn


def apply_churn_multiplier(
    hits: list[dict[str, Any]], churn: dict[str, int]
) -> list[dict[str, Any]]:
    """Scale each hit's score by ``1 + 0.1*log1p(churn_30d)`` for its file, re-sort.

    Applied AFTER ranking/fusion to final scores so it behaves identically for
    BM25, embeddings, and the RRF-fused path. A hit whose file has no churn
    attribute keeps its score unchanged. Empty ``churn`` → input returned
    untouched (order and scores byte-identical). Re-sorts by ``(score desc, id
    asc)`` to match the engine's deterministic tie-break.
    """
    if not churn:
        return hits
    for hit in hits:
        n = churn.get(hit.get("file", ""))
        if n:
            hit["score"] = round(hit["score"] * (1 + 0.1 * math.log1p(n)), 6)
    hits.sort(key=lambda h: (-h["score"], str(h["id"])))
    return hits


class FusedRetriever:
    """RRF fusion of BM25 + embeddings. Used by ``auto`` when both are available.

    Indexes both retrievers over the same corpus, then fuses their rankings with
    ``rrf_merge`` at query time.  The ``name`` is ``"auto"`` so callers can
    identify the fusion path in result metadata.
    """

    name = "auto"
    available = True

    def __init__(self, bm25: Bm25Retriever, emb: Retriever) -> None:
        self._bm25 = bm25
        self._emb = emb
        self._docs: list[dict[str, Any]] = []
        self._by_id: dict[str, dict[str, Any]] = {}

    def index(self, docs: list[dict[str, Any]]) -> None:
        self._docs = list(docs)
        # Build the id→doc map once at index time so query-time fusion stays
        # O(k) over the result lists (NFR-005), not O(corpus) per search.
        self._by_id = {d["id"]: d for d in self._docs}
        self._bm25.index(docs)
        self._emb.index(docs)

    def search(self, query: str, k: int = 10) -> list[dict[str, Any]]:
        # Retrieve from each backend with headroom so RRF can rerank properly.
        fetch_k = min(k * 3, len(self._docs)) if self._docs else k
        bm25_hits = self._bm25.search(query, k=fetch_k)
        emb_hits = self._emb.search(query, k=fetch_k)
        bm25_ranking = [h["id"] for h in bm25_hits]
        emb_ranking = [h["id"] for h in emb_hits]
        fused = rrf_merge([bm25_ranking, emb_ranking])
        results: list[dict[str, Any]] = []
        for doc_id, score in fused[:k]:
            doc = self._by_id.get(doc_id)
            if doc is None:
                continue
            results.append(
                {
                    "id": doc["id"],
                    "file": doc.get("file", ""),
                    "score": round(score, 6),
                    "snippet": doc["text"][:_SNIPPET],
                    "kind": doc.get("kind", ""),
                    "is_test": doc.get("is_test", False),
                }
            )
        return results


def make_retriever(
    backend: str = "auto",
    *,
    warnings: list[str] | None = None,
    cache_dir: Path | str | None = None,
) -> Retriever:
    """Resolve a retriever.

    ``auto`` with embeddings available → ``FusedRetriever`` (RRF of BM25 +
    embeddings).  ``auto`` without embeddings → pure BM25 (fail-open, no
    warning).  Explicit ``embeddings`` with the optional dependency absent →
    warn + BM25.  ``cache_dir`` is forwarded ONLY to the embeddings retriever.
    """
    warns = warnings if warnings is not None else []
    if backend == "bm25":
        return Bm25Retriever()

    from memory_bank_skill.semantic_embeddings import EmbeddingRetriever

    embedder = EmbeddingRetriever(cache_dir=cache_dir)
    if embedder.available:
        if backend == "embeddings":
            return embedder
        # auto: fuse BM25 + embeddings via RRF
        return FusedRetriever(Bm25Retriever(), embedder)
    if backend == "embeddings":
        warns.append(
            "embeddings backend unavailable (install sentence-transformers); falling back to bm25"
        )
    return Bm25Retriever()


def run_search(
    *,
    query: str,
    mb_path: str,
    backend: str = "auto",
    k: int = 10,
    source_only: bool = False,
) -> dict[str, Any]:
    """Load the graph, build the corpus, search. Returns a JSON-serialisable dict.

    ``source_only`` drops test/spec docs before indexing (works for any backend).
    """
    mb = Path(mb_path)
    graph_path = mb / "codebase" / "graph.json"
    warnings: list[str] = []
    try:
        nodes, _ = load_graph(graph_path)
    except FileNotFoundError:
        return {
            "ok": False,
            "query": query,
            "hits": [],
            "warnings": [f"missing graph: {graph_path} (run /mb graph --apply)"],
        }
    except ValueError as exc:
        return {
            "ok": False,
            "query": query,
            "hits": [],
            "warnings": [f"invalid/stale graph: {exc}"],
        }

    wiki_dir = mb / "codebase" / "wiki"
    corpus = build_corpus(nodes, wiki_dir if wiki_dir.is_dir() else None)
    if source_only:
        corpus = [d for d in corpus if not d.get("is_test")]
    cache_dir = mb / ".index" / "codesearch"
    retriever = make_retriever(backend, warnings=warnings, cache_dir=cache_dir)
    retriever.index(corpus)
    # Churn re-rank (design §A4) multiplies final scores then re-sorts, so it must
    # run over the FULL candidate set — a hot file below an arbitrary k*N window
    # could otherwise never be promoted into top-k. Fetch the whole corpus when
    # churn is present (graph nodes are a small corpus; retrievers already score
    # everything internally). No churn → fetch_k = k stays byte-identical.
    churn = load_churn(graph_path)
    fetch_k = len(corpus) if churn else k
    hits = retriever.search(query, fetch_k)
    hits = apply_churn_multiplier(hits, churn)[:k]
    result: dict[str, Any] = {
        "ok": True,
        "query": query,
        "backend": retriever.name,
        "corpus_size": len(corpus),
        "source_only": source_only,
        "hits": hits,
        "warnings": warnings,
    }
    # Community-summary retrieval (design §A5): top-3 wiki article → community files.
    blocks = ce.expand_hits(hits, ce.load_community_files(mb / "codebase"))
    if blocks:
        result["community_files"] = blocks
    return result


def render_hits_md(result: dict[str, Any]) -> str:
    """Render search hits as a markdown list (CLI human output)."""
    if not result.get("ok"):
        return (
            "\n".join(f"[warn] {w}" for w in result.get("warnings", [])) or "[warn] search failed"
        )
    lines = [f"# Semantic search: `{result['query']}`  (backend: {result['backend']})", ""]
    for w in result.get("warnings", []):
        lines.append(f"_warning: {w}_")
    if not result["hits"]:
        lines.append("_No matches._")
        return "\n".join(lines)
    for i, h in enumerate(result["hits"], 1):
        tag = " [test]" if h.get("is_test") else ""
        lines.append(f"{i}. `{h['file']}` — {h['id']}  (score {h['score']}){tag}")
    lines.extend(ce.render_blocks_md(result.get("community_files", [])))
    return "\n".join(lines)
