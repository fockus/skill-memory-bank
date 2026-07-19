"""Meta-only Okapi BM25 over the semantic store's meta.jsonl — the model-free hot path.

I-132: the default recall backend. Reads chunk metadata straight from the index
directory (no numpy, no vectors, no embedding model) and scores with Okapi BM25,
so a per-prompt search process stays ~tens of MB and returns in milliseconds.
The tokenizer mirrors ``memory_bank_skill.semantic_search.tokenize`` (code-aware
snake_case/camelCase splits, unicode tokens kept) — keep the two in sync until
the planned engine unification lands (backlog I-132).
"""

from __future__ import annotations

import contextlib
import json
import math
import os
import re
from pathlib import Path

_TOKEN_SPLIT = re.compile(r"[\W_]+")  # split on underscore + non-(unicode word char)
_CAMEL = re.compile(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|[0-9]+")
_K1 = 1.5
_B = 0.75

# Default per-`kind` ranking multipliers: durable decisions out-rank raw session
# logs at comparable relevance. Shared by this backend and the embeddings path
# (semantic_store imports these — single source of truth for recall ranking).
DEFAULT_SOURCE_WEIGHTS = {
    "agreement": 1.05,
    "progress": 1.0,
    "note": 1.0,
    "session": 0.95,
    "transcript": 0.85,
}


def source_weights():
    """Resolve per-kind ranking weights. ``MB_RECALL_SOURCE_WEIGHTS=off`` → None
    (pure relevance order). Otherwise the defaults, overlaid with any
    ``kind=factor`` pairs from the env (comma-separated). Unset → defaults."""
    raw = os.environ.get("MB_RECALL_SOURCE_WEIGHTS")
    if raw is not None and raw.strip().lower() == "off":
        return None
    weights = dict(DEFAULT_SOURCE_WEIGHTS)
    if raw:
        for pair in raw.split(","):
            if "=" in pair:
                k, _, v = pair.partition("=")
                with contextlib.suppress(ValueError):
                    weights[k.strip()] = float(v.strip())
    return weights


def tokenize(text: str) -> list[str]:
    """Code-aware tokenizer (mirror of memory_bank_skill.semantic_search.tokenize)."""
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


def load_meta(index_dir) -> list[dict]:
    """All indexed chunk rows from meta.jsonl (the flat, current corpus)."""
    path = Path(index_dir) / "meta.jsonl"
    try:
        raw = path.read_text()
    except OSError:
        return []
    rows = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except (ValueError, TypeError):
            continue
        if isinstance(row, dict) and row.get("text"):
            rows.append(row)
    return rows


def search(index_dir, query: str, top_k: int = 5, weights=None) -> list[dict]:
    """Top-k Okapi BM25 hits over the indexed chunks; [] when nothing matches.

    Scores are BM25 (not cosine): only hits with at least one matching term
    survive, so there is no min-score knob on this path.
    """
    q_terms = tokenize(query)
    rows = load_meta(index_dir)
    if not q_terms or not rows:
        return []
    docs = [tokenize(r["text"]) for r in rows]
    n = len(docs)
    avgdl = (sum(len(d) for d in docs) / n) or 1.0
    df: dict[str, int] = {}
    for d in docs:
        for t in set(d):
            df[t] = df.get(t, 0) + 1

    w = weights if weights is not None else {}
    scored: list[tuple[float, float, dict]] = []
    for row, doc in zip(rows, docs):
        counts: dict[str, int] = {}
        for t in doc:
            counts[t] = counts.get(t, 0) + 1
        score = 0.0
        for t in q_terms:
            f = counts.get(t)
            if not f:
                continue
            idf = math.log(1.0 + (n - df[t] + 0.5) / (df[t] + 0.5))
            score += idf * f * (_K1 + 1) / (f + _K1 * (1 - _B + _B * len(doc) / avgdl))
        if score > 0.0:
            rank = score * w.get(str(row.get("kind", "")), 1.0)
            scored.append((rank, score, row))

    scored.sort(key=lambda sr: (-sr[0], str(sr[2].get("source", "")), str(sr[2].get("anchor", ""))))
    out = []
    for _rank, score, row in scored[:top_k]:
        m = dict(row)
        m["score"] = round(score, 4)
        out.append(m)
    return out
