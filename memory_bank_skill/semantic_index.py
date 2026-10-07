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
import sysconfig
from pathlib import Path
from typing import Any

from memory_bank_skill.semantic_embeddings import (
    _DEFAULT_MODEL,
    cache_key_matches,
    corpus_key,
)
from memory_bank_skill.semantic_search import build_corpus, load_graph

_ROOT = Path(__file__).resolve().parents[1]
# Same precedence as sc_semantic_py (hooks/lib/session-common.sh): the venv the
# bootstrap hook creates beside the installed hooks, then a bank-local one.
_GLOBAL_VENV_PY = Path.home() / ".claude" / "hooks" / ".venv" / "bin" / "python"


def _cache_dir(mb: Path) -> Path:
    return mb / ".index" / "codesearch"


def _corpus(mb: Path) -> list[dict[str, Any]] | None:
    """Docs exactly as ``run_search`` builds them — always the FULL corpus.

    The cache holds one matrix and every query keys it identically: ``run_search``
    indexes the full corpus and applies ``--source-only`` after retrieval (AGR-048),
    so no query variant can evict the warm matrix.
    """
    try:
        nodes, _ = load_graph(mb / "codebase" / "graph.json")
    except (FileNotFoundError, ValueError, OSError):
        return None
    wiki = mb / "codebase" / "wiki"
    return build_corpus(nodes, wiki if wiki.is_dir() else None)


def _is_current(mb: Path, key: str) -> bool:
    return cache_key_matches(_cache_dir(mb), key)


def _site_packages() -> tuple[str, str]:
    """(site-packages dir, its mtime) — changes when anything is pip-installed.

    Recorded with a ``skipped`` status so the skip un-sticks by itself once
    ``hooks/mb-semantic-bootstrap.sh`` installs fastembed into that interpreter,
    instead of pinning "no fastembed" forever.
    """
    try:
        purelib = sysconfig.get_paths()["purelib"]
        return purelib, str(os.stat(purelib).st_mtime_ns)
    except (OSError, KeyError):  # pragma: no cover - exotic/relocated installs
        return "", "0"


def _write_status(mb: Path, word: str, python: str | None = None) -> None:
    """Persist the child's terminal status: ``<word>\\t<python>\\t<site-packages>\\t<mtime>``.

    *python* is the path the PARENT spawned, not ``sys.executable``: launching
    ``/opt/homebrew/bin/python3`` yields a child that calls itself
    ``/opt/homebrew/opt/python@3.14/bin/python3.14``, and a status filed under that
    second name is one the parent can never recognise as its own verdict.
    """
    try:
        cache = _cache_dir(mb)
        cache.mkdir(parents=True, exist_ok=True)
        (cache / ".index.status").write_text(
            "\t".join((word, python or sys.executable, *_site_packages())) + "\n",
            encoding="utf-8",
        )
    except OSError:  # pragma: no cover - a status note must never fail a build
        pass


def _reported_skip(mb: Path, python: str) -> bool:
    """True when THIS interpreter already reported "no fastembed" and nothing changed."""
    try:
        fields = (_cache_dir(mb) / ".index.status").read_text(encoding="utf-8").strip().split("\t")
    except OSError:
        return False
    if len(fields) != 4 or fields[0] != "skipped" or fields[1] != python:
        return False
    try:
        return str(os.stat(fields[2]).st_mtime_ns) == fields[3]
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


def _has_modules(python: str, modules: list[str]) -> bool:
    """True when *python* can find every module (``find_spec``: no import cost)."""
    code = (
        "import importlib.util as u,sys;sys.exit(any(u.find_spec(m) is None for m in sys.argv[1:]))"
    )
    try:
        run = subprocess.run(  # noqa: S603 - fixed argv, interpreter path is ours
            [python, "-c", code, *modules], capture_output=True, timeout=10, check=False
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return run.returncode == 0


def reexec_under_semantic_python(
    mb: Path | str, script: Path, argv: list[str], guard_env: str, needs: tuple[str, ...] = ()
) -> None:
    """Replace this process with ``script argv`` under ``_semantic_python()``.

    Shared by the CLIs that want the bootstrap venv (AGR-047 search, AGR-053 graph).
    ``os.execv`` keeps the PID, so a caller's process-group kill still reaches it.
    Returns (keeps running here) when *guard_env* is set, there is no candidate,
    the candidate lacks any of *needs*, or the exec fails — fail-open everywhere.
    """
    if os.environ.get(guard_env):
        return
    python = _semantic_python(Path(mb))
    # Literal compare, never realpath: a venv python is a SYMLINK to the base
    # interpreter, so resolving it would call the venv "the same interpreter we are
    # already running" and skip the very re-exec that reaches its packages.
    if not python or python == sys.executable:
        return
    if needs and not _has_modules(python, list(needs)):
        return
    os.environ[guard_env] = "1"  # the child runs or degrades; it never re-execs
    try:
        os.execv(python, [python, str(script), *argv])
    except OSError:
        os.environ.pop(guard_env, None)


def build_index(mb_path: Path | str, python: str | None = None) -> str:
    """Encode the corpus into ``<mb>/.index/codesearch`` (the slow half).

    Returns ``built`` · ``current`` (corpus unchanged, nothing rewritten) ·
    ``skipped`` (no fastembed) · ``no-graph`` · ``locked`` (another builder holds
    the lock — exit instead of burning the same minutes twice). Terminal statuses
    are also persisted under *python* (the name the parent knows this interpreter
    by) so the parent can read the verdict back instead of re-spawning blindly.
    """
    mb = Path(mb_path)
    docs = _corpus(mb)
    if docs is None:
        return "no-graph"

    from memory_bank_skill.semantic_embeddings import EmbeddingRetriever

    retriever = EmbeddingRetriever(cache_dir=_cache_dir(mb))
    if not retriever.available:
        # Persisted, not just returned: the parent starts this child on DEVNULL and
        # would otherwise re-spawn the same doomed process on every graph build.
        _write_status(mb, "skipped", python)
        return "skipped"
    key = corpus_key(retriever.model_name, [d["text"] for d in docs])
    if _is_current(mb, key):
        _write_status(mb, "current", python)
        return "current"

    cache = _cache_dir(mb)
    cache.mkdir(parents=True, exist_ok=True)
    with open(cache / ".index.lock", "w") as fh:
        try:
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return "locked"
        retriever.index(docs)
    _write_status(mb, "built", python)
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
        # branch) costs a ~1 s fastembed import to detect, which belongs nowhere near
        # a graph build — so the child pays it once and leaves its verdict in
        # `.index.status`, and we read it back instead of spawning it again.
        if _reported_skip(mb, python):
            return "semantic index skipped (no fastembed)"
        code = (
            f"import sys;sys.path.insert(0,{str(_ROOT)!r});"
            "from memory_bank_skill.semantic_index import build_index;"
            f"build_index({str(mb)!r},{python!r})"
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
