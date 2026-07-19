#!/usr/bin/env python3
# mb-semantic.py — semantic recall CLI for MB session-memory.
# Subcommands: index | reindex | search | stats | prune. Fail-safe: never raises to the hook.
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parent / "lib"
sys.path.insert(0, str(LIB))


def _mb_root() -> Path:
    # Data root = the project's .memory-bank/ (holds session/, notes/, .index/).
    # Global install: hooks pass MB_ROOT (resolved per-project), since the CLI itself
    # lives at ~/.claude/hooks/. Project-local fallback: parent of bin/.
    env = os.environ.get("MB_ROOT")
    if env:
        return Path(env)
    return Path(__file__).resolve().parents[1]


def _index_dir(mb_root: Path) -> Path:
    env = os.environ.get("MB_INDEX_DIR")
    return Path(env) if env else (mb_root / ".index")


def _debug(label: str):
    # Failures are swallowed by design (fail-safe for hooks); surface them on demand.
    if os.environ.get("MB_SEMANTIC_DEBUG"):
        import traceback

        sys.stderr.write(f"[mb-semantic:{label}] ")
        traceback.print_exc()


def cmd_search(args) -> int:
    out = []
    timer = None
    try:
        from searcher import resolve_backend, run_search

        backend = resolve_backend()
        index_dir = _index_dir(_mb_root())
        timer = _arm_deadline(args.timeout, backend)  # covers catch-up + search
        _catchup(index_dir, backend)
        out = run_search(
            index_dir,
            args.query,
            top_k=args.top_k,
            min_score=args.min_score,
            timeout=args.timeout,
            backend=backend,
        )
    except Exception:
        out = []
    finally:
        if timer is not None:
            timer.cancel()
    print(json.dumps(out, ensure_ascii=False))
    return 0


def _catchup(index_dir, backend: str) -> int:
    """Catch-up reindex (I-132) when the index is marked dirty or missing.

    Runs for BOTH backends so a `.dirty` marker never rots: BM25 is chunk-only
    (no model); embeddings additionally takes the machine-wide model lock
    inside ``index_sources``. All locks are non-blocking — a busy writer means
    we just search the stale index and leave the marker for the next call."""
    try:
        idx = Path(index_dir)
        if not (idx / ".dirty").exists() and (idx / "meta.jsonl").exists():
            return 0
        from indexer import index_sources

        res = index_sources(_mb_root(), idx, sources=None, full=False, backend=backend)
        if not res.get("skipped"):
            (idx / ".dirty").unlink(missing_ok=True)
    except Exception:
        _debug("catchup")
    return 0


def _arm_deadline(timeout: float, backend: str):
    """Hard process deadline (I-132): a stuck native model load must never
    outlive its budget as a multi-GB zombie. Fires only when the normal path is
    stuck — emits an empty result and force-exits the whole process. The
    embeddings budget is larger (model load + catch-up embedding) but still a
    hard bound; the singleton model lock keeps concurrent callers on BM25."""
    import threading

    def _kill():
        sys.stdout.write("[]\n")
        sys.stdout.flush()
        os._exit(0)

    grace = 120.0 if backend == "embeddings" else 5.0
    t = threading.Timer(float(timeout) + grace, _kill)
    t.daemon = True
    t.start()
    return t


def cmd_stats(args) -> int:
    try:
        from semantic_store import Store

        store = Store(_index_dir(_mb_root()))
        store.load()
        print(json.dumps(store.stats(), ensure_ascii=False))
    except Exception:
        print(json.dumps({"chunks": 0, "sources": 0, "model": None}))
    return 0


def cmd_index(args) -> int:
    try:
        from indexer import index_sources

        index_sources(_mb_root(), _index_dir(_mb_root()), sources=args.source, full=False)
    except Exception:
        _debug("index")
    return 0


def cmd_reindex(args) -> int:
    try:
        from indexer import index_sources

        index_sources(_mb_root(), _index_dir(_mb_root()), sources=None, full=args.full)
    except Exception:
        _debug("reindex")
    return 0


def cmd_prune(args) -> int:
    try:
        from indexer import prune_index

        prune_index(_mb_root(), _index_dir(_mb_root()))
    except Exception:
        _debug("prune")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="mb-semantic")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("search")
    s.add_argument("query")
    s.add_argument("--top-k", type=int, default=int(os.environ.get("MB_SEMANTIC_TOPK", "5")))
    s.add_argument(
        "--min-score", type=float, default=float(os.environ.get("MB_SEMANTIC_MIN_SCORE", "0.35"))
    )
    s.add_argument(
        "--timeout", type=float, default=float(os.environ.get("MB_SEMANTIC_TIMEOUT", "3"))
    )
    s.add_argument("--json", action="store_true")
    s.set_defaults(func=cmd_search)

    sub.add_parser("stats").set_defaults(func=cmd_stats)

    i = sub.add_parser("index")
    i.add_argument("--source", action="append")
    i.set_defaults(func=cmd_index)

    r = sub.add_parser("reindex")
    r.add_argument("--full", action="store_true")
    r.add_argument("--incremental", action="store_true")
    r.set_defaults(func=cmd_reindex)

    sub.add_parser("prune").set_defaults(func=cmd_prune)

    args = p.parse_args(argv)
    try:
        return args.func(args)
    except Exception:
        return 0


if __name__ == "__main__":
    sys.exit(main())
