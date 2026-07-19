import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

BIN = Path(__file__).resolve().parents[1]
CLI = BIN / "mb-semantic.py"


def _run(*args, env=None):
    e = dict(os.environ)
    e.update(env or {})
    return subprocess.run([sys.executable, str(CLI), *args], capture_output=True, text=True, env=e)


def test_search_on_missing_index_returns_empty_json_exit0():
    r = _run("search", "anything", "--json", env={"MB_INDEX_DIR": "/tmp/mb_nope_xyz"})
    assert r.returncode == 0
    assert json.loads(r.stdout) == []


def test_stats_without_deps_is_graceful():
    r = _run("stats", env={"MB_INDEX_DIR": "/tmp/mb_nope_xyz"})
    assert r.returncode == 0


def _mk_bank(tmp_path):
    mb = tmp_path / "mb"
    (mb / "notes").mkdir(parents=True)
    (mb / "notes" / "a.md").write_text("# Deploy\nkamal proxy host deploy notes")
    return mb


def test_cli_bm25_default_never_touches_the_model(tmp_path):
    """A bogus model name is harmless on the default path ⇒ no model was loaded."""
    mb = _mk_bank(tmp_path)
    env = {"MB_ROOT": str(mb), "MB_SEMANTIC_MODEL": "definitely/not-a-real-model"}
    r = _run("reindex", env=env)
    assert r.returncode == 0
    r = _run("search", "kamal deploy", "--json", env=env)
    assert r.returncode == 0
    hits = json.loads(r.stdout)
    assert hits and "kamal" in hits[0]["text"]


def test_cli_search_cold_start_bootstraps_index(tmp_path):
    """No index yet → the first BM25 search builds it inline (bounded, locked)."""
    mb = _mk_bank(tmp_path)
    env = {"MB_ROOT": str(mb), "MB_SEMANTIC_MODEL": "definitely/not-a-real-model"}
    r = _run("search", "kamal deploy", "--json", env=env)
    assert r.returncode == 0
    assert json.loads(r.stdout)
    assert (mb / ".index" / "meta.jsonl").exists()


def test_cli_search_picks_up_dirty_marker(tmp_path):
    mb = _mk_bank(tmp_path)
    env = {"MB_ROOT": str(mb), "MB_SEMANTIC_MODEL": "definitely/not-a-real-model"}
    assert _run("reindex", env=env).returncode == 0
    (mb / "notes" / "b.md").write_text("# New\nzanzibar cadence retrospective")
    (mb / ".index" / ".dirty").touch()
    r = _run("search", "zanzibar cadence", "--json", env=env)
    hits = json.loads(r.stdout)
    assert hits and "zanzibar" in hits[0]["text"]
    assert not (mb / ".index" / ".dirty").exists()


def test_cli_default_path_never_imports_numpy_or_fastembed(tmp_path):
    """Executable invariant (I-132): search + dirty catch-up + index write on
    the default backend must touch neither numpy nor fastembed — checked on
    sys.modules in a clean subprocess, so a transitive import fails loudly."""
    mb = _mk_bank(tmp_path)
    (mb / ".index").mkdir()
    (mb / ".index" / ".dirty").touch()
    code = (
        "import importlib.util, sys\n"
        f"spec = importlib.util.spec_from_file_location('mbsem', {str(CLI)!r})\n"
        "m = importlib.util.module_from_spec(spec)\n"
        "spec.loader.exec_module(m)\n"
        "rc = m.main(['search', 'kamal deploy', '--json'])\n"
        "banned = [n for n in ('numpy', 'fastembed') if n in sys.modules]\n"
        "assert rc == 0 and not banned, f'banned modules on hot path: {banned}'\n"
    )
    env = dict(os.environ, MB_ROOT=str(mb))
    env.pop("MB_SEMANTIC_BACKEND", None)
    r = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, env=env)
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout.splitlines()[-1])  # the search actually found the note
    assert not (mb / ".index" / ".dirty").exists()  # catch-up consumed the marker


def test_cli_reindex_lock_busy_exits_zero_without_indexing(tmp_path):
    import fcntl

    mb = _mk_bank(tmp_path)
    idx = mb / ".index"
    idx.mkdir()
    env = {"MB_ROOT": str(mb), "MB_SEMANTIC_MODEL": "definitely/not-a-real-model"}
    with open(idx / ".write.lock", "w") as lockf:
        fcntl.flock(lockf, fcntl.LOCK_EX | fcntl.LOCK_NB)
        r = _run("reindex", env=env)
        assert r.returncode == 0
        assert not (idx / "meta.jsonl").exists()


def test_cli_reindex_hung_source_is_killed_by_hard_deadline(tmp_path):
    """codex round-5: maintenance commands (index/reindex/prune) need the same
    hard process deadline as search — a hung reindex would otherwise hold the
    machine-wide model lock forever. A FIFO in notes/ makes read_text() block
    indefinitely, a faithful stand-in for a stalled model download."""
    mb = _mk_bank(tmp_path)
    os.mkfifo(mb / "notes" / "hang.md")
    env = dict(os.environ, MB_ROOT=str(mb), MB_SEMANTIC_MAINTENANCE_TIMEOUT="0.3")
    r = subprocess.run(
        [sys.executable, str(CLI), "reindex"],
        capture_output=True,
        text=True,
        env=env,
        timeout=20,  # without the deadline the process hangs → TimeoutExpired
    )
    assert r.returncode == 0


def test_maintenance_deadline_budget_is_decoupled_from_search(monkeypatch):
    """codex round-6 major: `reindex --full` must not inherit search's ~3 s
    per-prompt budget — a large-but-healthy full reindex would be routinely
    force-exited before finishing. Maintenance gets its own generous default
    (MB_SEMANTIC_MAINTENANCE_TIMEOUT), independent of MB_SEMANTIC_TIMEOUT."""
    import importlib.util

    spec = importlib.util.spec_from_file_location("mbsem_deadline", CLI)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    monkeypatch.setenv("MB_SEMANTIC_TIMEOUT", "0.1")  # tight per-prompt budget
    monkeypatch.delenv("MB_SEMANTIC_MAINTENANCE_TIMEOUT", raising=False)
    monkeypatch.delenv("MB_SEMANTIC_BACKEND", raising=False)
    t = m._maintenance_deadline()
    try:
        assert t.interval >= 300.0  # its own default, not search's 0.1 + grace
    finally:
        t.cancel()


def test_index_then_search_returns_relevant(tmp_path, monkeypatch):
    pytest.importorskip("numpy")
    sys.path.insert(0, str(BIN / "lib"))
    import indexer
    import numpy as np
    import semantic_embed

    # deterministic fake embedder: bag-of-words over a tiny vocab
    vocab = ["deploy", "kamal", "expo", "webview", "цена", "faberlic"]

    def fake(texts):
        out = []
        for t in texts:
            v = np.array([t.lower().count(w) for w in vocab], dtype=np.float32) + 0.01
            out.append(v)
        return out

    monkeypatch.setattr(
        semantic_embed.Embedder, "_ensure", lambda self: setattr(self, "_backend", fake)
    )

    mb = tmp_path / "mb"
    (mb / "notes").mkdir(parents=True)
    (mb / "notes" / "a.md").write_text("# Deploy\nuse kamal proxy host for deploy")
    (mb / "notes" / "b.md").write_text("# UI\nexpo webview tweaks")
    idx = tmp_path / "idx"
    monkeypatch.setenv("MB_SEMANTIC_INDEX_TRANSCRIPTS", "0")
    # The embeddings pipeline is opt-in now (BM25 is the default backend).
    monkeypatch.setenv("MB_SEMANTIC_BACKEND", "embeddings")
    indexer.index_sources(mb, idx, sources=None, full=True)

    from semantic_store import Store

    st = Store(idx)
    assert st.load()
    emb = semantic_embed.Embedder(st.model_name)
    qv = emb.embed(["kamal deploy"])
    res = st.search(qv[0], top_k=1, min_score=0.0)
    assert res and "kamal" in res[0]["text"]
