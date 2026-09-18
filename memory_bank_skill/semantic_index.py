"""Warm the code-search vector index at graph-build time (opt-in dep, fail-safe).

``mb-codegraph.py --apply`` ends with :func:`refresh_index`, so the FIRST semantic
query reads a cached matrix instead of paying minutes of encoding at query time —
the reason ``.index/codesearch/`` never existed in practice (plan
graph-semantic-adoption, Stage 2).

Two sides on purpose:

* :func:`refresh_index` (parent, any python) — compares the corpus hash against the
  cached key, prints one honest line and spawns the builder DETACHED. It must stay
  in the millisecond range: ``--apply`` is also run by ``codegraph_catchup``, which
  SIGKILLs the whole process group after a 30 s budget.
* :func:`build_index` (child, the semantic venv python) — does the encoding under a
  non-blocking lock, so two graph builds in a row do not encode the same corpus twice.

Degradation is honest (AGR-013): no semantic interpreter → ``semantic index skipped
(no fastembed)``, exit 0, graph build untouched. A bare ``python3`` never carries
fastembed, so "no interpreter" and "no fastembed" are the same outcome here.
"""

from __future__ import annotations

import fcntl
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from memory_bank_skill.semantic_embeddings import _DEFAULT_MODEL, corpus_key
from memory_bank_skill.semantic_search import build_corpus, load_graph

_ROOT = Path(__file__).resolve().parents[1]
# Same precedence as sc_semantic_py (hooks/lib/session-common.sh): the venv the
# bootstrap hook creates beside the installed hooks, then a bank-local one.
_GLOBAL_VENV_PY = Path.home() / ".claude" / "hooks" / ".venv" / "bin" / "python"


def _cache_dir(mb: Path) -> Path:
    return mb / ".index" / "codesearch"


def _corpus(mb: Path) -> list[dict[str, Any]] | None:
    """Docs exactly as ``run_search`` builds them — full corpus, no ``source_only``.

    The cache holds one matrix, so it is keyed to the default (unfiltered) query
    path; a ``--source-only`` query has a different corpus and still re-encodes.
    """
    try:
        nodes, _ = load_graph(mb / "codebase" / "graph.json")
    except (FileNotFoundError, ValueError, OSError):
        return None
    wiki = mb / "codebase" / "wiki"
    return build_corpus(nodes, wiki if wiki.is_dir() else None)


def _is_current(mb: Path, key: str) -> bool:
    try:
        return (_cache_dir(mb) / "embeddings.key").read_text(encoding="utf-8").strip() == key
    except OSError:
        return False


def _semantic_python(mb: Path) -> str | None:
    """Interpreter that can import fastembed, or None. Mirrors ``sc_semantic_py``.

    A non-runnable ``MB_SEMANTIC_PY`` yields None rather than a crash — same
    fail-open guard the shell callers use.
    """
    override = os.environ.get("MB_SEMANTIC_PY")
    if override:
        return override if os.access(override, os.X_OK) else None
    for cand in (_GLOBAL_VENV_PY, Path(mb) / ".venv" / "bin" / "python"):
        if os.access(cand, os.X_OK):
            return str(cand)
    return None


def build_index(mb_path: Path | str) -> str:
    """Encode the corpus into ``<mb>/.index/codesearch`` (the slow half).

    Returns ``built`` · ``current`` (corpus unchanged, nothing rewritten) ·
    ``skipped`` (no fastembed) · ``no-graph`` · ``locked`` (another builder holds
    the lock — exit instead of burning the same minutes twice).
    """
    mb = Path(mb_path)
    docs = _corpus(mb)
    if docs is None:
        return "no-graph"

    from memory_bank_skill.semantic_embeddings import EmbeddingRetriever

    retriever = EmbeddingRetriever(cache_dir=_cache_dir(mb))
    if not retriever.available:
        return "skipped"
    key = corpus_key(retriever.model_name, [d["text"] for d in docs])
    if _is_current(mb, key):
        return "current"

    cache = _cache_dir(mb)
    cache.mkdir(parents=True, exist_ok=True)
    with open(cache / ".index.lock", "w") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return "locked"
        retriever.index(docs)
    return "built"


def refresh_index(mb_path: Path | str) -> str:
    """One status line for the ``--apply`` summary; spawns the builder if stale.

    Never raises and never blocks: the parent only hashes the corpus (~0.1 s on a
    9k-symbol graph) and hands the encoding to a detached child.
    """
    try:
        mb = Path(mb_path)
        docs = _corpus(mb)
        if docs is None:
            return "semantic index skipped (no graph)"
        if _is_current(mb, corpus_key(_DEFAULT_MODEL, [d["text"] for d in docs])):
            return f"semantic index: up to date ({len(docs)} docs)"
        python = _semantic_python(mb)
        if python is None:
            return "semantic index skipped (no fastembed)"
        # A venv that exists but lacks fastembed (the bootstrap hook's failed-install
        # branch) is reported by the child, not here — the parent would have to pay a
        # ~1 s fastembed import to find out, and that cost belongs nowhere near a
        # graph build. Upgrade path if it ever matters: have the child leave its
        # status word in the cache dir and read it back on the next run.
        code = (
            f"import sys;sys.path.insert(0,{str(_ROOT)!r});"
            "from memory_bank_skill.semantic_index import build_index;"
            f"build_index({str(mb)!r})"
        )
        subprocess.Popen(  # noqa: S603 - fixed argv, interpreter path is ours
            [python, "-c", code],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,  # survives the caller's process-group kill
        )
        return f"semantic index: refreshing in background ({len(docs)} docs)"
    except Exception:  # pragma: no cover - a warm cache must never fail a graph build
        return "semantic index skipped (error)"


if __name__ == "__main__":  # pragma: no cover - manual/backfill entry point
    print(build_index(sys.argv[1] if len(sys.argv) > 1 else ".memory-bank"))
