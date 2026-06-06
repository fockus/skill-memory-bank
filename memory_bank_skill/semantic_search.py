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

import math
import re
from collections import Counter
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

from memory_bank_skill.codegraph_loader import load_graph

_TOKEN_SPLIT = re.compile(r"[\W_]+")  # split on underscore + non-(unicode word char)
_CAMEL = re.compile(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|[0-9]+")
_SNIPPET = 120
_MAX_WIKI_CHARS = 8000  # bounded read for wiki article docs


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
        return [{
            "id": doc["id"],
            "file": doc.get("file", ""),
            "score": round(score, 6),
            "snippet": doc["text"][:_SNIPPET],
        } for score, doc in scored[:k]]


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
        text = f"{name} {kind} {file_name.replace('/', ' ')}"
        doc_id = file_name if name == file_name else f"{file_name}:{name}"
        docs.append({"id": doc_id, "file": file_name, "text": text})
    if wiki_dir is not None:
        wd = Path(wiki_dir)
        if wd.is_dir():
            for md in sorted(wd.glob("*.md")):
                with md.open(encoding="utf-8", errors="replace") as handle:
                    text = handle.read(_MAX_WIKI_CHARS)  # bounded read
                docs.append({
                    "id": f"wiki/{md.name}",
                    "file": f"wiki/{md.name}",
                    "text": text,
                })
    return docs


def make_retriever(backend: str = "auto", *, warnings: list[str] | None = None) -> Retriever:
    """Resolve a retriever. ``auto`` = embeddings if available else BM25.

    Explicit ``embeddings`` with the optional dependency absent → warn + BM25.
    """
    warns = warnings if warnings is not None else []
    if backend == "bm25":
        return Bm25Retriever()

    from memory_bank_skill.semantic_embeddings import EmbeddingRetriever
    embedder = EmbeddingRetriever()
    if embedder.available:
        return embedder
    if backend == "embeddings":
        warns.append("embeddings backend unavailable (install sentence-transformers); "
                     "falling back to bm25")
    return Bm25Retriever()


def run_search(
    *,
    query: str,
    mb_path: str,
    backend: str = "auto",
    k: int = 10,
) -> dict[str, Any]:
    """Load the graph, build the corpus, search. Returns a JSON-serialisable dict."""
    mb = Path(mb_path)
    graph_path = mb / "codebase" / "graph.json"
    warnings: list[str] = []
    try:
        nodes, _ = load_graph(graph_path)
    except FileNotFoundError:
        return {"ok": False, "query": query, "hits": [],
                "warnings": [f"missing graph: {graph_path} (run /mb graph --apply)"]}
    except ValueError as exc:
        return {"ok": False, "query": query, "hits": [],
                "warnings": [f"invalid/stale graph: {exc}"]}

    wiki_dir = mb / "codebase" / "wiki"
    corpus = build_corpus(nodes, wiki_dir if wiki_dir.is_dir() else None)
    retriever = make_retriever(backend, warnings=warnings)
    retriever.index(corpus)
    hits = retriever.search(query, k)
    return {
        "ok": True,
        "query": query,
        "backend": retriever.name,
        "corpus_size": len(corpus),
        "hits": hits,
        "warnings": warnings,
    }


def render_hits_md(result: dict[str, Any]) -> str:
    """Render search hits as a markdown list (CLI human output)."""
    if not result.get("ok"):
        return "\n".join(f"[warn] {w}" for w in result.get("warnings", [])) or "[warn] search failed"
    lines = [f"# Semantic search: `{result['query']}`  (backend: {result['backend']})", ""]
    for w in result.get("warnings", []):
        lines.append(f"_warning: {w}_")
    if not result["hits"]:
        lines.append("_No matches._")
        return "\n".join(lines)
    for i, h in enumerate(result["hits"], 1):
        lines.append(f"{i}. `{h['file']}` — {h['id']}  (score {h['score']})")
    return "\n".join(lines)
