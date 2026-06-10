"""Time-bounded semantic search — portable timeout via a daemon thread.

GNU `timeout`/`gtimeout` are not always present (e.g. stock macOS), so the time
budget is enforced here: the work runs in a daemon thread; if it does not finish
within `timeout` seconds the caller gets `[]` immediately and the stalled thread
is abandoned (it dies when the process exits).
"""
from __future__ import annotations

import threading

from semantic_embed import Embedder
from semantic_store import Store


def run_search(index_dir, query, top_k=5, min_score=0.35, timeout=3.0, embedder=None) -> list[dict]:
    box: dict = {"out": []}

    def work():
        try:
            store = Store(index_dir)
            if not store.load():
                return
            emb = embedder or Embedder(store.model_name)
            qv = emb.embed([query])
            if qv.shape[0] == 0:
                return
            box["out"] = store.search(qv[0], top_k=top_k, min_score=min_score)
        except Exception:
            box["out"] = []

    t = threading.Thread(target=work, daemon=True)
    t.start()
    t.join(timeout)
    # if the thread is still alive, it timed out → box still holds the default []
    return box["out"]
