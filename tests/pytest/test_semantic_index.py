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
    assert not (mb / ".index").exists()         # nothing written on the skip path


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
