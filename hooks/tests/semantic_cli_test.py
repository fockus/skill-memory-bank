import json, subprocess, sys, os
from pathlib import Path

BIN = Path(__file__).resolve().parents[1]
CLI = BIN / "mb-semantic.py"


def _run(*args, env=None):
    e = dict(os.environ)
    e.update(env or {})
    return subprocess.run([sys.executable, str(CLI), *args],
                          capture_output=True, text=True, env=e)


def test_search_on_missing_index_returns_empty_json_exit0():
    r = _run("search", "anything", "--json", env={"MB_INDEX_DIR": "/tmp/mb_nope_xyz"})
    assert r.returncode == 0
    assert json.loads(r.stdout) == []


def test_stats_without_deps_is_graceful():
    r = _run("stats", env={"MB_INDEX_DIR": "/tmp/mb_nope_xyz"})
    assert r.returncode == 0


def test_index_then_search_returns_relevant(tmp_path, monkeypatch):
    sys.path.insert(0, str(BIN / "lib"))
    import numpy as np
    import indexer, semantic_embed
    # deterministic fake embedder: bag-of-words over a tiny vocab
    vocab = ["deploy", "kamal", "expo", "webview", "цена", "faberlic"]

    def fake(texts):
        out = []
        for t in texts:
            v = np.array([t.lower().count(w) for w in vocab], dtype=np.float32) + 0.01
            out.append(v)
        return out

    monkeypatch.setattr(semantic_embed.Embedder, "_ensure",
                        lambda self: setattr(self, "_backend", fake))

    mb = tmp_path / "mb"
    (mb / "notes").mkdir(parents=True)
    (mb / "notes" / "a.md").write_text("# Deploy\nuse kamal proxy host for deploy")
    (mb / "notes" / "b.md").write_text("# UI\nexpo webview tweaks")
    idx = tmp_path / "idx"
    monkeypatch.setenv("MB_SEMANTIC_INDEX_TRANSCRIPTS", "0")
    indexer.index_sources(mb, idx, sources=None, full=True)

    from semantic_store import Store
    st = Store(idx)
    assert st.load()
    emb = semantic_embed.Embedder(st.model_name)
    qv = emb.embed(["kamal deploy"])
    res = st.search(qv[0], top_k=1, min_score=0.0)
    assert res and "kamal" in res[0]["text"]
