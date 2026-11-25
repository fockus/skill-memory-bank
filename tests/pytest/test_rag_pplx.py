"""Perplexity's optional runtime must never be taken from the indexed project."""

from __future__ import annotations

import hashlib
import io
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import mb_rag_pplx as pplx  # noqa: E402


@pytest.mark.parametrize("operation", ["build", "search"])
def test_offline_operations_do_not_bootstrap_a_missing_cache(tmp_path, operation):
    index = tmp_path / "generation"
    index.mkdir()
    cache = tmp_path / "absent"
    with pytest.raises(RuntimeError, match="setup"):
        if operation == "build":
            pplx.build(index, [("9", "document")], cache)
        else:
            pplx.search(index, "query", 1, cache)
    assert not cache.exists()
    assert not list(index.iterdir())


def test_prepare_rejects_a_cache_symlink_into_a_project(tmp_path):
    project = tmp_path / "checkout"
    (project / ".git").mkdir(parents=True)
    cache = tmp_path / "user-cache"
    cache.symlink_to(project, target_is_directory=True)
    with pytest.raises(ValueError, match="outside"):
        pplx.prepare(cache)
    assert set(project.iterdir()) == {project / ".git"}


def test_reject_an_interpreter_symlink_out_of_the_provider_venv(tmp_path):
    cache = tmp_path / "cache"
    bindir = cache / "pplx-venv" / "bin"
    bindir.mkdir(parents=True)
    (bindir.parent / "pyvenv.cfg").touch()
    # A cache venv must not borrow a project interpreter, even outside a Git checkout.
    foreign = tmp_path / "checkout" / ".venv" / "bin" / "python"
    foreign.parent.mkdir(parents=True)
    foreign.touch()
    (bindir / "python").symlink_to(foreign)
    with pytest.raises(ValueError, match="private"):
        pplx.search(tmp_path, "query", 1, cache)


def test_setup_reuses_verified_artifacts_and_never_publishes_a_bad_download(tmp_path, monkeypatch):
    url = "https://huggingface.co/model/resolve/revision/weights"
    weights = tmp_path / "weights"
    digest = hashlib.sha256(b"complete").hexdigest()
    monkeypatch.setattr(pplx, "urlopen", lambda *a, **kw: io.BytesIO(b"truncated"))
    with pytest.raises(ValueError, match="SHA-256"):
        pplx._fetch(url, weights, digest)
    assert not list(tmp_path.iterdir())

    monkeypatch.setattr(pplx, "urlopen", lambda *a, **kw: io.BytesIO(b"complete"))
    pplx._fetch(url, weights, digest)
    monkeypatch.setattr(pplx, "urlopen", lambda *a, **kw: pytest.fail("unexpected download"))
    pplx._fetch(url, weights, digest)
    assert weights.read_bytes() == b"complete"


def test_index_survives_move_and_returns_only_the_nearest_ids(tmp_path, monkeypatch):
    np = pytest.importorskip("numpy", reason="Numerical index runs in the optional PPLX runtime")
    index = tmp_path / "building"
    index.mkdir()

    def embed(texts):
        # The ONNX boundary returns unit vectors; cosine similarity is the index's job.
        basis = np.zeros((len(texts), 1024), dtype=np.float32)
        for i, text in enumerate(texts):
            basis[i, 0 if text.startswith("food") else 1] = 1
        return basis

    monkeypatch.setattr(pplx, "_encoder", lambda model: embed)
    docs = [("12", "food recipe"), ("28", "database restart"), ("7", "database")]
    pplx._build(index, docs, tmp_path)
    moved = index.rename(tmp_path / "published")
    assert pplx._search(moved, "database recovery", 2, tmp_path) == ["28", "7"]
    assert pplx._search(moved, "food", 1, tmp_path) == ["12"]


def test_refresh_reuses_remapped_rows_and_encodes_each_new_text_once(tmp_path, monkeypatch):
    np = pytest.importorskip("numpy")
    old, new = tmp_path / "old", tmp_path / "new"
    old.mkdir()
    new.mkdir()
    encoded = []

    def embed(texts):
        encoded.extend(texts)
        return np.asarray([[len(text)] * 1024 for text in texts], dtype=np.float32)

    monkeypatch.setattr(pplx, "_encoder", lambda _: embed)
    pplx._build(old, [("0", "deleted"), ("1", "kept")], tmp_path)
    original = (old / "pplx.npy").read_bytes()
    encoded.clear()
    docs = [("0", "kept"), ("1", "a"), ("2", "kept"), ("3", "a")]
    assert pplx._build(new, docs, tmp_path, old, [1, None, 1, None])
    assert encoded == ["a"]
    assert np.load(new / "pplx.npy")[:, 0].tolist() == [4, 1, 4, 1]
    assert (old / "pplx.npy").read_bytes() == original
    (old / "pplx.npy").write_bytes(b"truncated")
    assert not pplx._build(new, docs, tmp_path, old, [1, None, 1, None])
    assert encoded == ["a"]
