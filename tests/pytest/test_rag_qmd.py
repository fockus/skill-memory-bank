"""QMD provider contract. The real offline smoke requires an explicit cached GGUF."""

import hashlib
import io
import json
import os
import select
import shutil
import sqlite3
import subprocess
import sys
import urllib.request
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from scripts import mb_rag_qmd as qmd  # noqa: E402

MODEL = "Qwen3-Embedding-0.6B-Q8_0.gguf"


@pytest.fixture
def runtime(tmp_path, monkeypatch):
    package = tmp_path / "npm" / "@tobilu" / "qmd"
    (package / "bin").mkdir(parents=True)
    (package / "package.json").write_text(json.dumps({"name": "@tobilu/qmd", "version": "2.8.3"}))
    for name in ("node", "qmd"):
        exe = package / "bin" / name
        exe.touch(mode=0o700)
    monkeypatch.setenv("PATH", str(package / "bin"))
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(tmp_path / "xdg"))
    return package


def test_prepare_without_qmd_reports_install_hint(tmp_path, monkeypatch):
    monkeypatch.setenv("PATH", str(tmp_path))
    with pytest.raises(RuntimeError, match=r"npm install -g @tobilu/qmd@2\.8\.3"):
        qmd.prepare(tmp_path / "models")


def test_prepare_rejects_project_local_qmd_runtime(tmp_path, runtime, monkeypatch):
    (runtime.parent / ".git").mkdir()
    monkeypatch.chdir(runtime.parent)
    monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **kw: pytest.fail("attempted fetch"))
    with pytest.raises(RuntimeError, match=r"npm install -g @tobilu/qmd@2\.8\.3"):
        qmd.prepare(tmp_path / "models")


def test_prepare_downloads_only_pinned_gguf_and_reuses_it(tmp_path, runtime, monkeypatch):
    content = b"test model"
    monkeypatch.setattr(qmd, "_SHA256", hashlib.sha256(content).hexdigest())
    urls = []

    def download(url, *, timeout):
        urls.append(url)
        return io.BytesIO(content)

    monkeypatch.setattr(urllib.request, "urlopen", download)
    cache = tmp_path / "models"
    qmd.prepare(cache)
    qmd.prepare(cache)

    assert len(urls) == 1 and urls[0].endswith("/" + MODEL)
    assert (cache / MODEL).read_bytes() == content
    assert list(cache.iterdir()) == [cache / MODEL]


def test_prepare_reuses_verified_home_qmd_weights_with_custom_xdg_cache(
    tmp_path, runtime, monkeypatch
):
    data = b"existing verified weights"
    original = Path.home() / ".cache" / "qmd" / "models" / ("hf_Qwen_" + MODEL)
    original.parent.mkdir(parents=True)
    original.write_bytes(data)
    monkeypatch.setattr(qmd, "_SHA256", hashlib.sha256(data).hexdigest())
    monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **kw: pytest.fail("attempted fetch"))
    cache = tmp_path / "models"
    qmd.prepare(cache)
    assert (cache / MODEL).read_bytes() == original.read_bytes()


def test_prepare_does_not_publish_unverified_download(tmp_path, runtime, monkeypatch):
    monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **kw: io.BytesIO(b"bad GGUF"))
    cache = tmp_path / "models"
    with pytest.raises(RuntimeError, match="SHA-256"):
        qmd.prepare(cache)
    assert not list(cache.iterdir())


@pytest.mark.parametrize("operation", ["build", "search"])
def test_runtime_never_fetches_missing_weights(tmp_path, runtime, operation, monkeypatch):
    def no_download(*args, **kwargs):
        pytest.fail("build/search attempted a model download")

    monkeypatch.setattr(urllib.request, "urlopen", no_download)
    index = tmp_path / "index"
    index.mkdir()
    cache = tmp_path / "absent-model"
    with pytest.raises(RuntimeError, match="prepare|setup"):
        if operation == "build":
            qmd.build(index, [("0", "example")], cache)
        else:
            qmd.search(index, "example", 1, cache)
    assert not cache.exists()
    assert not list(index.iterdir())


@pytest.fixture
def bridge_build(tmp_path):
    if not shutil.which("node"):
        pytest.skip("requires Node.js")
    dist = tmp_path / "dist"
    dist.mkdir()
    (tmp_path / "package.json").write_text('{"type":"module"}')
    (dist / "llm.js").write_text(
        "export class LlamaCpp { getDeviceInfo() {} dispose() {} }\n"
        "export function setDefaultLlamaCpp() {}\n"
    )
    (dist / "store.js").write_text(
        # Open the pipe in nonblocking mode, as in the real QMD process.
        "void process.stdin;\n"
        "setImmediate(() => console.log('ready'));\n"
        "const pending = new Map();\n"
        "export function createStore() { return {\n"
        "  db: {transaction: fn => fn, pragma() {}}, insertDocument() {}, close() {},\n"
        "  insertContent(hash, text) {pending.set(hash, text)},\n"
        "  getHashesNeedingEmbedding() {return pending.size}\n"
        "}; }\n"
        "export function generateEmbeddings(store, {maxDurationMs = 30 * 60 * 1000}) {\n"
        "  let elapsed = 0;\n"
        "  for (const [hash, text] of pending) {\n"
        "    if (maxDurationMs > 0 && elapsed >= maxDurationMs) break;\n"
        "    if (text !== 'missing vector') {pending.delete(hash); console.log(hash)}\n"
        # Advance past any enabled deadline before the next batch.
        "    elapsed = Infinity;\n"
        "  }\n"
        "  return {errors: 0};\n"
        "}\n"
        "export function upsertStoreCollection() {} export function searchVec() {}\n"
    )
    return ["node", Path(qmd.__file__).with_suffix(".mjs"), tmp_path, "build", "db", "model"]


def test_bridge_build_reads_complete_utf8_document_from_delayed_pipe(bridge_build):
    text = "💡€" * 1_200_000
    payload = json.dumps([["0", text]], ensure_ascii=False).encode()
    split = payload.index("💡".encode()) + 1
    with subprocess.Popen(
        bridge_build, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    ) as proc:
        try:
            assert proc.stdin is not None and proc.stdout is not None
            proc.stdin.write(payload[:split])
            proc.stdin.flush()
            # Withhold the tail until the reader yields; no startup timing assumptions.
            assert select.select([proc.stdout], [], [], 10)[0], "bridge did not read stdin"
            ready = proc.stdout.readline()
            stdout, stderr = proc.communicate(payload[split:], timeout=20)
        finally:
            proc.kill()
    assert proc.returncode == 0, stderr.decode()
    assert ready == b"ready\n"
    assert stdout.strip().decode() == hashlib.sha256(text.encode()).hexdigest()


def test_long_build_embeds_last_batch_after_default_session_deadline(bridge_build):
    result = subprocess.run(
        bridge_build,
        input='[["0","first"],["1","last"]]',
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert hashlib.sha256(b"last").hexdigest() in result.stdout.splitlines()


def test_build_rejects_missing_vector_even_without_reported_sdk_errors(bridge_build):
    result = subprocess.run(
        bridge_build, input='[["0","missing vector"]]', text=True, capture_output=True, timeout=10
    )
    assert result.returncode != 0
    assert "QMD could not embed every document" in result.stderr


def test_refresh_rejects_unexpected_pending_vectors_before_opening_model(bridge_build):
    package = bridge_build[2]
    (package / "dist" / "llm.js").write_text(
        "export class LlamaCpp { getDeviceInfo() {throw Error('model opened')} dispose() {} }\n"
        "export function setDefaultLlamaCpp() {}"
    )
    (package / "dist" / "store.js").write_text(
        "export function createStore() { return {db: {transaction: fn => fn, "
        "prepare: () => ({all: () => []})}, deleteInactiveDocuments() {}, close() {}, "
        "cleanupOrphanedContent() {}, cleanupOrphanedVectors() {}, "
        "insertDocument() {}, insertContent() {}, getHashesNeedingEmbedding: () => 1 }; }\n"
        "export function generateEmbeddings() {throw Error('unexpected embedding')}\n"
        "export function upsertStoreCollection() {} export function searchVec() {}"
    )
    command = [*bridge_build[:3], "refresh", *bridge_build[4:]]
    result = subprocess.run(
        command, input='{"docs":[["0","retained"]],"missing":0}', text=True, capture_output=True
    )
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) is False


@pytest.mark.skipif(not os.getenv("MB_RAG_QMD_SMOKE_MODEL"), reason="requires cached Qwen3 GGUF")
def test_offline_smoke_relocated_generation_is_read_only(tmp_path, monkeypatch):
    source = Path(os.environ["MB_RAG_QMD_SMOKE_MODEL"]).resolve(strict=True)
    xdg = tmp_path / "xdg"
    external = xdg / "qmd" / "models" / ("hf_Qwen_" + MODEL)
    external.parent.mkdir(parents=True)
    external.symlink_to(source)
    monkeypatch.setenv("XDG_CACHE_HOME", str(xdg))
    default_db = xdg / "qmd" / "index.sqlite"
    default_db.write_bytes(b"not an index")
    monkeypatch.setenv("INDEX_PATH", str(default_db))
    monkeypatch.setenv("QMD_EMBED_MODEL", "hf:unselected/wrong/model.gguf")
    monkeypatch.setattr(urllib.request, "urlopen", lambda *a, **kw: pytest.fail("not offline"))

    cache = tmp_path / "models"
    stage = tmp_path / "generation.tmp"
    stage.mkdir()
    qmd.prepare(cache)
    external.unlink()
    qmd.build(
        stage,
        [
            ("0", "def hash_password(password): return argon2.hash(password)"),
            ("1", "def rotate_image(pixels, degrees): return pixels.rotate(degrees)"),
        ],
        cache,
    )
    index = stage.rename(tmp_path / "published")
    before = {p.name: p.stat().st_mtime_ns for p in index.iterdir()}
    assert qmd.search(index, "Как повернуть картинку?", 1, cache) == ["1"]
    assert qmd.search(index, "Как хешируется пароль?", 2, cache) == ["0", "1"]
    assert {p.name: p.stat().st_mtime_ns for p in index.iterdir()} == before
    assert default_db.read_bytes() == b"not an index"


@pytest.mark.skipif(not os.getenv("MB_RAG_QMD_SMOKE_MODEL"), reason="requires cached Qwen3 GGUF")
def test_real_refresh_preserves_embedding_timestamps_and_reassigns_duplicate_ids(
    tmp_path, monkeypatch
):
    cache = tmp_path / "models"
    cache.mkdir()
    (cache / MODEL).symlink_to(Path(os.environ["MB_RAG_QMD_SMOKE_MODEL"]).resolve(strict=True))
    monkeypatch.setattr(urllib.request, "urlopen", lambda *_a, **_k: pytest.fail("not offline"))
    old, new = tmp_path / "old", tmp_path / "new"
    old.mkdir()
    new.mkdir()

    def vectors(index):
        with sqlite3.connect((index / "code.sqlite").as_uri() + "?mode=ro", uri=True) as db:
            return dict(db.execute("select hash, embedded_at from content_vectors"))

    kept, added = "def hash_password(): return argon2()", "def send_email(): return smtp()"
    qmd.build(old, [("0", "def rotate(): return image()"), ("1", kept)], cache)
    initial = vectors(old)
    assert qmd.refresh(new, [("0", kept), ("1", added), ("2", kept)], cache, old, [1, None, 1])
    current = vectors(new)
    h = hashlib.sha256(kept.encode()).hexdigest()
    assert current[h] == initial[h]
    assert vectors(old) == initial and len(initial.keys() & current.keys()) == 1
    assert set(qmd.search(new, "password hashing", 2, cache)) == {"0", "2"}
