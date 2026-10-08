#!/usr/bin/env python3
"""Semantic code search over the Memory Bank code graph.

Usage:
    mb-semantic-search.py "<query>" [--backend auto|bm25|embeddings] [--k N]
                          [--json] [mb_path]

Ranks function/class/module symbols (+ wiki articles, if `/mb wiki` was run) by
relevance to the query. Default backend is pure-Python BM25 (deterministic, $0,
zero deps); `--backend embeddings` uses local fastembed embeddings when installed
(falls back to BM25 otherwise). Complements the deterministic structural queries in
`mb-graph-query.py` — use this for "where is the logic for X?" questions.

Exit: 0 on success (even with 0 hits), 3 when the graph is missing/invalid.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __name__ == "__main__":  # re-exec under an interpreter that can import the package
    # Explicit: `python3 -P` / `-I` / PYTHONSAFEPATH do not put the script dir on sys.path.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from _mb_skill_python import ensure_skill_python

    ensure_skill_python(__file__)

try:
    from memory_bank_skill import semantic_search as ss
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill import semantic_search as ss

EXIT_OK = 0
EXIT_MISSING_GRAPH = 3
_REEXEC_ENV = "MB_SEMANTIC_REEXEC"


def _maybe_reexec(backend: str, mb_path: str, argv: list[str]) -> None:
    """Re-run this CLI under the interpreter that HAS fastembed (AGR-047).

    The documented invocation is a bare ``python3``, which never carries fastembed —
    so every documented call fell back to BM25 and the vector index warmed by
    ``/mb graph --apply`` was unreachable. Covers ``embeddings`` AND the default
    ``auto`` (agents call without a flag); ``bm25`` is answered right here.
    Fail-open: no such interpreter, or an exec that fails, keeps today's behaviour.
    """
    if backend == "bm25":
        return
    from memory_bank_skill import semantic_embeddings as sem_emb

    if sem_emb.HAS_FASTEMBED:
        return
    from memory_bank_skill.semantic_index import reexec_under_semantic_python

    reexec_under_semantic_python(mb_path, Path(__file__).resolve(), argv, _REEXEC_ENV)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Semantic code search over graph.json")
    parser.add_argument("query")
    parser.add_argument("--backend", choices=["auto", "bm25", "embeddings"], default="auto")
    parser.add_argument("--k", type=int, default=10)
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of markdown")
    parser.add_argument(
        "--source-only",
        action="store_true",
        help="Exclude test/spec files from results (find the implementation)",
    )
    parser.add_argument("mb_path", nargs="?", default=".memory-bank")
    # parse_intermixed_args so the optional `mb_path` positional is accepted even
    # when it trails the options (`query --backend bm25 --json <mb_path>`). Plain
    # parse_args rejects that ordering on argparse < 3.13 ("unrecognized arguments").
    args = parser.parse_intermixed_args(argv[1:])
    _maybe_reexec(args.backend, args.mb_path, argv[1:])

    result = ss.run_search(
        query=args.query,
        mb_path=args.mb_path,
        backend=args.backend,
        k=args.k,
        source_only=args.source_only,
    )
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(ss.render_hits_md(result))
    return EXIT_OK if result.get("ok") else EXIT_MISSING_GRAPH


if __name__ == "__main__":
    sys.exit(main(sys.argv))
