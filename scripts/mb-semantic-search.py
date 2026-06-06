#!/usr/bin/env python3
"""Semantic code search over the Memory Bank code graph.

Usage:
    mb-semantic-search.py "<query>" [--backend auto|bm25|embeddings] [--k N]
                          [--json] [mb_path]

Ranks function/class/module symbols (+ wiki articles, if `/mb wiki` was run) by
relevance to the query. Default backend is pure-Python BM25 (deterministic, $0,
zero deps); `--backend embeddings` uses local sentence-transformers when installed
(falls back to BM25 otherwise). Complements the deterministic structural queries in
`mb-graph-query.py` — use this for "where is the logic for X?" questions.

Exit: 0 on success (even with 0 hits), 3 when the graph is missing/invalid.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from memory_bank_skill import semantic_search as ss
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill import semantic_search as ss

EXIT_OK = 0
EXIT_MISSING_GRAPH = 3


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Semantic code search over graph.json")
    parser.add_argument("query")
    parser.add_argument("--backend", choices=["auto", "bm25", "embeddings"], default="auto")
    parser.add_argument("--k", type=int, default=10)
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of markdown")
    parser.add_argument("mb_path", nargs="?", default=".memory-bank")
    args = parser.parse_args(argv[1:])

    result = ss.run_search(query=args.query, mb_path=args.mb_path,
                           backend=args.backend, k=args.k)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(ss.render_hits_md(result))
    return EXIT_OK if result.get("ok") else EXIT_MISSING_GRAPH


if __name__ == "__main__":
    sys.exit(main(sys.argv))
