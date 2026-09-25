"""Tests for memory_bank_skill/semantic_index.py — warm the vector index at graph build.

`/mb graph --apply` ends by refreshing `<mb>/.index/codesearch/` so the FIRST semantic
query hits a warm cache instead of paying minutes of encoding (plan
graph-semantic-adoption, Stage 2). Two sides, two contracts:

* `build_index(mb)` — child side, does the encoding. `built` / `current` /
  `skipped` (no fastembed) / `no-graph` / `locked`.
* `refresh_index(mb)` — parent side, returns ONE honest status line and spawns the
  child detached, so `--apply` stays seconds even on a 9k-symbol corpus. No semantic
  interpreter → `semantic index skipped (no fastembed)` and the graph build is
  unaffected (honest degradation, AGR-013).

numpy-backed paths use `importorskip` like `test_semantic_embeddings.py` (numpy is
optional and absent in CI).
"""

from __future__ import annotations

import fcntl
import importlib
import importlib.util
import json
import os
import sys
import time
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import semantic_embeddings as se  # noqa: E402

CODEGRAPH_SCRIPT = REPO_ROOT / "scripts" / "mb-codegraph.py"

STUB_FASTEMBED = '''\
"""Stub `fastembed` package — importable by the in-process test AND by the
detached child process (via PYTHONPATH), so no 90 MB model is ever downloaded."""
import numpy as np


class TextEmbedding:
    def __init__(self, model_name, **kwargs):
        self.model_name = model_name

    def embed(self, texts, **kwargs):
        for _ in texts:
            yield np.ones(4, dtype="float32")
'''


# ── fixtures ─────────────────────────────────────────────────────────

def _write_graph(mb: Path, texts=("authenticate_user", "render_cart")) -> None:
    cb = mb / "codebase"
    cb.mkdir(parents=True, exist_ok=True)
    lines = [
        {"type": "node", "kind": "function", "name": n, "file": f"{n}.py", "line": 1}
        for n in texts
    ]
    (cb / "graph.json").write_text(
        "\n".join(json.dumps(x) for x in lines) + "\n", encoding="utf-8"
    )


@pytest.fixture
def stub_fastembed(tmp_path_factory):
    """Directory holding a stub `fastembed.py`; also importable in-process."""
    d = tmp_path_factory.mktemp("stub_fastembed")
    (d / "fastembed.py").write_text(STUB_FASTEMBED, encoding="utf-8")
    return d


@pytest.fixture
def with_fastembed(stub_fastembed):
    """Make `import fastembed` succeed in THIS process; restore afterwards."""
    missing = object()
    saved = sys.modules.get("fastembed", missing)
    sys.path.insert(0, str(stub_fastembed))
    sys.modules.pop("fastembed", None)
    importlib.reload(se)
    yield stub_fastembed
    sys.path.remove(str(stub_fastembed))
    if saved is missing:
        sys.modules.pop("fastembed", None)
    else:  # pragma: no cover - only when fastembed is really installed
        sys.modules["fastembed"] = saved
    importlib.reload(se)


@pytest.fixture
def si():
    from memory_bank_skill import semantic_index

    return importlib.reload(semantic_index)


# ── build_index: the child side ──────────────────────────────────────

def test_build_index_writes_embeddings_cache(tmp_path: Path, si, with_fastembed):
    pytest.importorskip("numpy")
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    assert si.build_index(mb) == "built"
    assert (mb / ".index" / "codesearch" / "embeddings.npy").is_file()
    assert (mb / ".index" / "codesearch" / "embeddings.key").is_file()


def test_build_index_second_run_is_current_and_leaves_files_untouched(
    tmp_path: Path, si, with_fastembed
):
    pytest.importorskip("numpy")
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    si.build_index(mb)
    npy = mb / ".index" / "codesearch" / "embeddings.npy"
    before = npy.stat().st_mtime_ns
    assert si.build_index(mb) == "current"     # unchanged corpus → no re-encode
    assert npy.stat().st_mtime_ns == before


def test_build_index_rebuilds_when_the_corpus_changed(tmp_path: Path, si, with_fastembed):
    pytest.importorskip("numpy")
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    si.build_index(mb)
    _write_graph(mb, texts=("authenticate_user", "render_cart", "charge_card"))
    assert si.build_index(mb) == "built"


def test_build_index_skips_without_fastembed(tmp_path: Path, si):
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    saved = sys.modules.get("fastembed")
    sys.modules["fastembed"] = None            # None in sys.modules → ImportError
    try:
        importlib.reload(se)
        assert si.build_index(mb) == "skipped"
    finally:
        if saved is None:
            sys.modules.pop("fastembed", None)
        else:  # pragma: no cover - only when fastembed is really installed
            sys.modules["fastembed"] = saved
        importlib.reload(se)
    # Stage 8: the skip path writes its verdict (and nothing else) so the parent
    # stops re-spawning a child that can never build — no vectors, no lock.
    cache = mb / ".index" / "codesearch"
    assert sorted(p.name for p in cache.iterdir()) == [".index.status"]
    assert cache.joinpath(".index.status").read_text(encoding="utf-8").split("\t")[0] == "skipped"


def test_build_index_without_graph_reports_no_graph(tmp_path: Path, si):
    assert si.build_index(tmp_path / ".memory-bank") == "no-graph"


# ── refresh_index: the parent side (one line, never blocks) ──────────

def test_refresh_index_reports_skip_without_a_semantic_interpreter(
    tmp_path: Path, si, monkeypatch
):
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    monkeypatch.setenv("MB_SEMANTIC_PY", str(tmp_path / "nope" / "python"))
    assert si.refresh_index(mb) == "semantic index skipped (no fastembed)"
    assert not (mb / ".index").exists()


def test_refresh_index_reports_up_to_date_without_spawning(
    tmp_path: Path, si, with_fastembed, monkeypatch
):
    pytest.importorskip("numpy")
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    si.build_index(mb)
    # No interpreter at all: "up to date" can only come from the cache-key check,
    # never from a child process.
    monkeypatch.setenv("MB_SEMANTIC_PY", str(tmp_path / "nope" / "python"))
    assert si.refresh_index(mb) == "semantic index: up to date (2 docs)"


def test_refresh_index_spawns_a_detached_builder(tmp_path: Path, si, stub_fastembed, monkeypatch):
    pytest.importorskip("numpy")
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    monkeypatch.setenv("MB_SEMANTIC_PY", sys.executable)
    monkeypatch.setenv("PYTHONPATH", str(stub_fastembed))
    line = si.refresh_index(mb)
    assert line == "semantic index: refreshing in background (2 docs)"
    npy = mb / ".index" / "codesearch" / "embeddings.npy"
    deadline = time.time() + 30
    while time.time() < deadline and not npy.is_file():
        time.sleep(0.1)
    assert npy.is_file(), "detached builder never produced the vector cache"


def test_refresh_index_survives_a_broken_graph(tmp_path: Path, si, monkeypatch):
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    (mb / "codebase" / "graph.json").write_text("{not json", encoding="utf-8")
    monkeypatch.setenv("MB_SEMANTIC_PY", str(tmp_path / "nope" / "python"))
    assert si.refresh_index(mb).startswith("semantic index skipped")


# ── wiring: mb-codegraph.py --apply ends with the index step ─────────

def _load_codegraph_module():
    spec = importlib.util.spec_from_file_location("mb_codegraph_idx", CODEGRAPH_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_graph_apply_prints_the_index_line_and_still_exits_zero(
    tmp_path: Path, monkeypatch, capsys
):
    cg = _load_codegraph_module()
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.py").write_text("def hello():\n    return 1\n", encoding="utf-8")
    monkeypatch.setenv("MB_SEMANTIC_PY", str(tmp_path / "nope" / "python"))
    rc = cg.main(["mb-codegraph.py", "--apply", str(mb), str(src)])
    out = capsys.readouterr().out
    assert rc == 0
    assert "semantic index skipped (no fastembed)" in out
    assert (mb / "codebase" / "graph.json").is_file()   # graph build unaffected


def test_graph_apply_index_line_carries_no_key_value_pair(tmp_path: Path, monkeypatch, capsys):
    # codegraph_catchup parses `--apply` stdout as key=value lines; the index line
    # must not look like one, or it would land in the catchup result dict.
    cg = _load_codegraph_module()
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.py").write_text("def hello():\n    return 1\n", encoding="utf-8")
    monkeypatch.setenv("MB_SEMANTIC_PY", str(tmp_path / "nope" / "python"))
    cg.main(["mb-codegraph.py", "--apply", str(mb), str(src)])
    index_lines = [ln for ln in capsys.readouterr().out.splitlines() if "semantic index" in ln]
    assert index_lines and all("=" not in ln for ln in index_lines)


def test_graph_dry_run_does_not_touch_the_index(tmp_path: Path, monkeypatch, capsys):
    cg = _load_codegraph_module()
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    src = tmp_path / "src"
    src.mkdir()
    (src / "a.py").write_text("def hello():\n    return 1\n", encoding="utf-8")
    monkeypatch.setenv("MB_SEMANTIC_PY", str(tmp_path / "nope" / "python"))
    cg.main(["mb-codegraph.py", "--dry-run", str(mb), str(src)])
    assert "semantic index" not in capsys.readouterr().out


def test_semantic_python_prefers_the_explicit_override(tmp_path: Path, si, monkeypatch):
    monkeypatch.setenv("MB_SEMANTIC_PY", sys.executable)
    assert si._semantic_python(tmp_path) == sys.executable


def test_semantic_python_ignores_a_non_executable_override(tmp_path: Path, si, monkeypatch):
    dud = tmp_path / "python"
    dud.write_text("", encoding="utf-8")
    os.chmod(dud, 0o644)
    monkeypatch.setenv("MB_SEMANTIC_PY", str(dud))
    assert si._semantic_python(tmp_path) is None


def test_semantic_python_falls_back_to_a_bank_local_venv(tmp_path: Path, si, monkeypatch):
    monkeypatch.delenv("MB_SEMANTIC_PY", raising=False)
    monkeypatch.setattr(si, "_GLOBAL_VENV_PY", tmp_path / "absent" / "python")
    venv_py = tmp_path / ".venv" / "bin" / "python"
    venv_py.parent.mkdir(parents=True)
    venv_py.write_text("#!/bin/sh\n", encoding="utf-8")
    os.chmod(venv_py, 0o755)
    assert si._semantic_python(tmp_path) == str(venv_py)


# ── the child's terminal status: an honest skip, not an eternal "refreshing" ──

def test_build_index_locked_when_another_builder_holds_the_lock(
    tmp_path: Path, si, with_fastembed
):
    """WARNING-2 of verify Stage 2: the documented `locked` branch had no test."""
    pytest.importorskip("numpy")
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    cache = mb / ".index" / "codesearch"
    cache.mkdir(parents=True)
    with open(cache / ".index.lock", "w") as held:
        fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
        assert si.build_index(mb) == "locked"
    assert not (cache / "embeddings.npy").exists()   # the holder does the encoding


def test_build_index_records_its_terminal_status(tmp_path: Path, si, with_fastembed):
    pytest.importorskip("numpy")
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    assert si.build_index(mb) == "built"
    status = (mb / ".index" / "codesearch" / ".index.status").read_text(encoding="utf-8")
    assert status.split("\t")[0] == "built"


def test_refresh_index_stops_spawning_once_the_child_reported_no_fastembed(
    tmp_path: Path, si, monkeypatch
):
    """CRITICAL-1: `MB_SEMANTIC_PY` runs but has no fastembed → skip, not a loop.

    The child is spawned with both streams on DEVNULL, so its `skipped` return is
    invisible to the parent; before the status file every later `--apply` printed
    `refreshing in background` while the index never appeared.
    """
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    monkeypatch.setenv("MB_SEMANTIC_PY", sys.executable)   # real python, no fastembed
    monkeypatch.delenv("PYTHONPATH", raising=False)

    spawns: list[list[str]] = []
    real_popen = si.subprocess.Popen

    def counting_popen(argv, **kwargs):
        spawns.append(list(argv))
        return real_popen(argv, **kwargs)

    monkeypatch.setattr(si.subprocess, "Popen", counting_popen)

    assert si.refresh_index(mb) == "semantic index: refreshing in background (2 docs)"
    status = mb / ".index" / "codesearch" / ".index.status"
    deadline = time.time() + 30
    while time.time() < deadline and not status.is_file():
        time.sleep(0.1)
    assert status.is_file(), "the child must persist its terminal status"
    assert status.read_text(encoding="utf-8").split("\t")[0] == "skipped"

    assert si.refresh_index(mb) == "semantic index skipped (no fastembed)"
    assert len(spawns) == 1, "a reported skip must not spawn the same doomed child again"


def test_run_search_cache_miss_answers_bm25_and_warms_in_background(
    tmp_path: Path, si, with_fastembed, monkeypatch
):
    """AGR-048: a query never pays the encode — CRITICAL-2 (1:00 and 3:49 runs)."""
    pytest.importorskip("numpy")
    from memory_bank_skill import semantic_search as ss

    mb = tmp_path / ".memory-bank"
    _write_graph(mb)

    def never(self, texts):  # noqa: ARG001
        raise AssertionError("run_search must not encode in the foreground")

    monkeypatch.setattr(se.EmbeddingRetriever, "_encode", never)
    refreshed: list[str] = []
    monkeypatch.setattr(si, "refresh_index", lambda mb_path: refreshed.append(str(mb_path)) or "x")

    result = ss.run_search(query="authenticate", mb_path=str(mb), backend="embeddings")
    assert result["ok"] is True
    assert result["backend"] == "bm25"
    assert result["hits"], "a cold index still answers, from BM25"
    assert refreshed == [str(mb)], "the cold query must kick off a background build"


def test_run_search_uses_the_warm_matrix_without_encoding(
    tmp_path: Path, si, with_fastembed, monkeypatch
):
    pytest.importorskip("numpy")
    from memory_bank_skill import semantic_search as ss

    mb = tmp_path / ".memory-bank"
    _write_graph(mb, texts=("authenticate_user", "render_cart"))
    # A test doc makes --source-only a REAL filter: under the old pre-index filter
    # the two queries had different corpus keys and evicted each other's matrix.
    cb = mb / "codebase" / "graph.json"
    cb.write_text(
        cb.read_text(encoding="utf-8")
        + json.dumps({"type": "node", "kind": "function", "name": "test_authenticate_user",
                      "file": "tests/test_auth.py", "line": 1})
        + "\n",
        encoding="utf-8",
    )
    assert si.build_index(mb) == "built"          # warm the one cache slot

    def never(self, texts):  # noqa: ARG001
        if len(texts) > 1:
            raise AssertionError("corpus re-encoded despite a warm cache")
        return se.np.ones((1, 4), dtype="float32")

    monkeypatch.setattr(se.EmbeddingRetriever, "_encode", never)
    for source_only in (False, True):
        result = ss.run_search(query="authenticate", mb_path=str(mb),
                               backend="embeddings", source_only=source_only)
        assert result["backend"] == "embeddings", f"source_only={source_only} fell back"


def test_refresh_index_skip_is_keyed_to_the_path_the_PARENT_spawned(
    tmp_path: Path, si, monkeypatch
):
    """The child's own `sys.executable` is NOT the path the parent resolved.

    Live repro: `MB_SEMANTIC_PY=$(which python3)` spawns `/opt/homebrew/bin/python3`
    while the child reports `/opt/homebrew/opt/python@3.14/bin/python3.14`. Keyed on
    the child's view, the parent never recognises its own verdict and re-spawns the
    doomed builder forever. A `sh` shim reproduces that indirection exactly.
    """
    mb = tmp_path / ".memory-bank"
    _write_graph(mb)
    shim = tmp_path / "bin" / "python3"
    shim.parent.mkdir(parents=True)
    shim.write_text(f'#!/bin/sh\nexec "{sys.executable}" "$@"\n', encoding="utf-8")
    shim.chmod(0o755)
    monkeypatch.setenv("MB_SEMANTIC_PY", str(shim))
    monkeypatch.delenv("PYTHONPATH", raising=False)

    spawns: list[list[str]] = []
    real_popen = si.subprocess.Popen
    monkeypatch.setattr(
        si.subprocess, "Popen",
        lambda argv, **kw: (spawns.append(list(argv)), real_popen(argv, **kw))[1],
    )

    assert si.refresh_index(mb).startswith("semantic index: refreshing in background")
    status = mb / ".index" / "codesearch" / ".index.status"
    deadline = time.time() + 30
    while time.time() < deadline and not status.is_file():
        time.sleep(0.1)
    assert status.is_file()
    fields = status.read_text(encoding="utf-8").strip().split("\t")
    assert fields[1] == str(shim), "the status must name the interpreter the parent spawned"

    assert si.refresh_index(mb) == "semantic index skipped (no fastembed)"
    assert len(spawns) == 1
