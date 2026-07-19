"""Backend-routing semantic search (I-132).

Default backend is meta-only BM25: no model, no numpy, milliseconds. The
embeddings backend is opt-in (``MB_SEMANTIC_BACKEND=embeddings``) and runs
behind a non-blocking singleton flock — if another process already holds the
model, the call degrades to BM25 instead of loading a second multi-GB copy.

The embeddings time budget is enforced with a daemon thread (portable; GNU
`timeout`/`gtimeout` absent on stock macOS): if the work misses the budget the
caller gets `[]` immediately and the stalled thread is abandoned. The CLI adds
a hard process deadline on top, so an abandoned native load cannot linger.
"""

from __future__ import annotations

import contextlib
import fcntl
import os
import threading
from pathlib import Path

import bm25


def resolve_backend(backend=None, embedder=None) -> str:
    """Explicit embedder (tests) → embeddings; else arg/env; default bm25."""
    if embedder is not None:
        return "embeddings"
    b = backend or os.environ.get("MB_SEMANTIC_BACKEND", "bm25")
    return b if b in ("bm25", "embeddings") else "bm25"


def model_lock_path() -> Path:
    """Machine-wide singleton lock for anything that loads the embedding model.

    One lock per MACHINE, not per index — per-index locks would let N open
    projects load N concurrent multi-GB model copies (codex review, I-132).
    Override for tests via MB_SEMANTIC_MODEL_LOCK."""
    env = os.environ.get("MB_SEMANTIC_MODEL_LOCK")
    return Path(env) if env else Path("~/.cache/memory-bank/model.lock").expanduser()


_HELD_LOCKS: list = []  # flocks deliberately held until process exit (stuck loads)


def _try_acquire(path):
    """Open + flock non-blocking. Returns the open handle, or None when busy —
    or on ANY filesystem error (unwritable cache dir, read-only home): lock
    trouble must degrade to the caller's fallback, never crash the search."""
    try:
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        fh = open(path, "w")
    except OSError:
        return None
    try:
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fh.close()
        return None
    return fh


@contextlib.contextmanager
def try_lock(path):
    """Non-blocking exclusive flock; yields True when acquired, False when busy
    or unobtainable (fail-open)."""
    fh = _try_acquire(path)
    if fh is None:
        yield False
        return
    try:
        yield True
    finally:
        fh.close()  # close releases the flock


def run_search(
    index_dir, query, top_k=5, min_score=0.35, timeout=3.0, embedder=None, backend=None
) -> list[dict]:
    """Search the index. BM25 ignores ``min_score`` (term-match gated instead)."""
    if resolve_backend(backend, embedder) == "bm25":
        return bm25.search(index_dir, query, top_k=top_k, weights=bm25.source_weights())
    lock_fh = _try_acquire(model_lock_path())
    if lock_fh is None:  # a model already lives in another process — never load a 2nd
        return bm25.search(index_dir, query, top_k=top_k, weights=bm25.source_weights())
    return _embed_search(index_dir, query, top_k, min_score, timeout, embedder, lock_fh)


def _embed_search(index_dir, query, top_k, min_score, timeout, embedder, lock_fh) -> list[dict]:
    """Embeddings search; owns releasing ``lock_fh`` (the machine-wide model flock).

    Fast worker → released here. Timed-out worker → ownership is transferred to
    the worker's ``finally`` so a late finish in a long-lived process releases
    the lock the moment the load actually ends (codex round-3); if it never
    finishes, ``_HELD_LOCKS`` pins the handle until process exit — releasing
    early would let a second process load a second model copy while ours is
    still resident (codex round-2)."""
    box: dict = {"out": []}
    guard = threading.Lock()
    owner = {"transferred": False}

    def _work():
        try:
            _search_into(box, index_dir, query, top_k, min_score, embedder)
        finally:
            with guard:
                if owner["transferred"]:
                    lock_fh.close()  # late finish: release for this process's future calls

    t = threading.Thread(target=_work, daemon=True)
    t.start()
    t.join(timeout)
    with guard:
        if t.is_alive():
            owner["transferred"] = True  # the worker's finally releases the flock
            _HELD_LOCKS.append(lock_fh)  # backstop: never-finishing load → exit releases
            return box["out"]
    lock_fh.close()
    return box["out"]


def _search_into(box, index_dir, query, top_k, min_score, embedder) -> None:
    try:
        from semantic_store import Store  # lazy: numpy only on this path

        store = Store(index_dir)
        if not store.load():
            return
        if embedder is None:
            from semantic_embed import Embedder

            emb = Embedder(store.model_name)
        else:
            emb = embedder
        qv = emb.embed([query])
        if qv.shape[0] == 0:
            return
        box["out"] = store.search(qv[0], top_k=top_k, min_score=min_score)
    except Exception:
        box["out"] = []
