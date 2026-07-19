import sys
import threading
import time
from pathlib import Path

import pytest

np = pytest.importorskip("numpy")

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
# E402 is deliberate: the import must run AFTER importorskip, or this module
# fails to collect on an interpreter without numpy instead of skipping.
from searcher import run_search  # noqa: E402
from semantic_store import Store  # noqa: E402


@pytest.fixture(autouse=True)
def _isolated_model_lock(tmp_path, monkeypatch):
    """Keep the machine-wide model lock out of these tests' way (and vice versa)."""
    monkeypatch.setenv("MB_SEMANTIC_MODEL_LOCK", str(tmp_path / "model.lock"))


def _norm(v):
    v = np.asarray(v, dtype=np.float32)
    return v / np.linalg.norm(v)


def _build_index(tmp_path):
    s = Store(tmp_path)
    s.set_model("m")
    s.upsert(
        "a.md",
        1.0,
        "x",
        [{"text": "kamal deploy", "source": "a.md", "kind": "note", "anchor": "p0"}],
        np.stack([_norm([1, 0, 0])]),
    )
    s.save()
    return tmp_path


class _FastEmbedder:
    model_name = "m"

    def embed(self, texts):
        return np.stack([_norm([1, 0, 0]) for _ in texts])


class _SlowEmbedder:
    model_name = "m"

    def embed(self, texts):
        time.sleep(2.0)
        return np.stack([_norm([1, 0, 0]) for _ in texts])


class _GatedEmbedder:
    """Blocks in embed() until released — a deterministic slow model load."""

    model_name = "m"

    def __init__(self):
        self.release = threading.Event()

    def embed(self, texts):
        self.release.wait(10.0)
        return np.stack([_norm([1, 0, 0]) for _ in texts])


def test_run_search_returns_match(tmp_path):
    idx = _build_index(tmp_path)
    out = run_search(idx, "kamal", top_k=1, min_score=0.0, timeout=5, embedder=_FastEmbedder())
    assert out and out[0]["text"] == "kamal deploy"


def test_run_search_times_out_returns_empty_quickly(tmp_path):
    idx = _build_index(tmp_path)
    t0 = time.monotonic()
    out = run_search(idx, "kamal", top_k=1, min_score=0.0, timeout=0.2, embedder=_SlowEmbedder())
    elapsed = time.monotonic() - t0
    assert out == []
    assert elapsed < 1.0  # returned promptly, did not wait the full 2s


def test_run_search_missing_index_returns_empty(tmp_path):
    out = run_search(
        tmp_path / "nope", "q", top_k=5, min_score=0.0, timeout=5, embedder=_FastEmbedder()
    )
    assert out == []


def test_stuck_model_load_keeps_the_flock_held(tmp_path):
    """codex round-2 blocker: a timed-out (possibly still-loading) worker must
    NOT release the machine-wide model lock — a second process could otherwise
    start a second multi-GB copy while ours is still resident."""
    import fcntl

    idx = _build_index(tmp_path)
    out = run_search(idx, "kamal", top_k=1, min_score=0.0, timeout=0.2, embedder=_SlowEmbedder())
    assert out == []
    lock = tmp_path / "model.lock"  # pinned by the autouse fixture
    with open(lock, "w") as fh, pytest.raises(OSError):
        fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)


def test_timed_out_worker_releases_the_flock_after_late_finish(tmp_path):
    """codex round-4 minor: pin the aa1c692 headline behavior — a worker that
    misses the deadline but later genuinely finishes must release the machine
    lock ITSELF (ownership transfer), or a long-lived process self-starves
    until exit."""
    import fcntl

    idx = _build_index(tmp_path)
    emb = _GatedEmbedder()
    out = run_search(idx, "kamal", top_k=1, min_score=0.0, timeout=0.2, embedder=emb)
    assert out == []
    lock = tmp_path / "model.lock"  # pinned by the autouse fixture
    with open(lock, "w") as fh:
        with pytest.raises(OSError):  # load still in flight → flock stays held
            fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
        emb.release.set()  # the "load" completes late
        deadline = time.monotonic() + 5.0
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break  # the worker's own finally released it
            except OSError:
                assert time.monotonic() < deadline, "worker never released the flock"
                time.sleep(0.05)


def test_try_lock_unwritable_path_fails_open(tmp_path):
    """codex round-2 major: filesystem trouble at the lock path degrades
    (yields False) instead of raising out of the search."""
    from searcher import try_lock

    blocker = tmp_path / "not-a-dir"
    blocker.write_text("file where a directory is needed")
    with try_lock(blocker / "sub" / "model.lock") as got:
        assert got is False
