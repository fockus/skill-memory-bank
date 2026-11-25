"""A QMD budget counts the provider's token chunks, not Python's source rows."""

import json
import os
import shutil
import sqlite3
import subprocess
import urllib.request
from pathlib import Path

import pytest
from test_project_rag import rag, repo

BRIDGE = Path(rag.__file__).with_name("mb_rag_qmd.mjs")
DENSE = "# " + "".join(chr(0x4E00 + i) for i in range(1700)) + "\n"


@pytest.mark.skipif(not shutil.which("node"), reason="requires Node")
def test_qmd_rejects_36_token_chunks_before_any_embedding(tmp_path):
    dist = tmp_path / "dist"
    dist.mkdir()
    (tmp_path / "package.json").write_text('{"type":"module"}')
    (dist / "llm.js").write_text(
        "export class LlamaCpp { getDeviceInfo() {} dispose() {} }\n"
        "export function setDefaultLlamaCpp() {}"
    )
    (dist / "store.js").write_text(
        "const pending = [];\n"
        "export function createStore() { return {db: {transaction: f => f, "
        "prepare: () => ({all: () => [], get: () => null})}, close() {}, cleanupOrphanedVectors() {}, "
        "cleanupOrphanedContent() {}, deleteInactiveDocuments() {}, insertDocument() {}, "
        "insertContent(hash, body) {pending.push({hash, body, path: '0/chunk'})}, "
        "getHashesNeedingEmbedding() {return pending.length}} }\n"
        "export function getHashesForEmbedding() {return pending}\n"
        "export function chunkDocumentByTokens(body) {return Array(body.includes('一') ? 5 : 1)}\n"
        "export function generateEmbeddings() {throw Error('embedding called above budget')}\n"
        "export function upsertStoreCollection() {} export function searchVec() {}"
    )
    docs = [[str(i), str(i)] for i in range(31)] + [["31", DENSE]]
    result = subprocess.run(
        ["node", BRIDGE, tmp_path, "refresh", "db", "model"],
        input=json.dumps({"docs": docs, "missing": 32, "maxNewChunks": 32}),
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) is False


@pytest.mark.skipif(not os.getenv("MB_RAG_QMD_SMOKE_MODEL"), reason="requires cached Qwen3 GGUF")
def test_real_qmd_32_source_rows_require_36_token_chunks_and_keep_prior_pointer(
    tmp_path, monkeypatch
):
    import mb_rag_qmd as qmd

    root, bank = repo(tmp_path / "work")
    cache, state = tmp_path / "cache", tmp_path / "state"
    monkeypatch.setenv("XDG_CACHE_HOME", str(cache))
    monkeypatch.setenv("XDG_STATE_HOME", str(state))
    monkeypatch.setattr(urllib.request, "urlopen", lambda *_a, **_k: pytest.fail("not offline"))
    source = Path(os.environ["MB_RAG_QMD_SMOKE_MODEL"]).resolve(strict=True)
    weights = cache / "qmd/models" / ("hf_Qwen_" + qmd._MODEL)
    weights.parent.mkdir(parents=True)
    weights.symlink_to(source)
    rag.setup(root, bank, "qwen3")
    (root / "orders.py").unlink()
    rag.update(root, bank, max_new_chunks=0)
    (pointer,) = state.rglob("current.json")
    before = pointer.read_bytes()
    for i in range(31):
        (root / f"short_{i}.py").write_text(f"def number_{i}(): return {i}\n")
    (root / "dense.py").write_text(DENSE)
    subprocess.run(["git", "-C", root, "add", "--all"], check=True)

    with pytest.raises(rag.ManualUpdateRequired, match="memory-bank rag update"):
        rag.update(root, bank, max_new_chunks=32)
    assert pointer.read_bytes() == before

    def vectors():
        with rag.publication(root, bank) as active:
            db_path = (active.generation / "index/code.sqlite").as_uri() + "?mode=ro"
            with sqlite3.connect(db_path, uri=True) as db:
                return set(db.execute("SELECT hash, seq, embedded_at FROM content_vectors"))

    assert vectors() == set()
    rag.update(root, bank, max_new_chunks=36)
    first = vectors()
    assert len(first) == 36
    (root / "short_0.py").write_text("def zero(): return 0\n")
    rag.update(root, bank, max_new_chunks=1)
    second = vectors()
    assert len(first & second) == 35 and len(second - first) == 1
