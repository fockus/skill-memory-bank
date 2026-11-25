"""An automatic writer cannot rebuild, stall a reader, or lose a published generation."""

import signal
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Event

import pytest
from test_project_rag import models as offline_models
from test_project_rag import rag, repo

models = offline_models


def test_legacy_requires_manual_migration_and_limit_is_checked_before_runtime(
    tmp_path, models, monkeypatch
):
    root, bank = repo(tmp_path / "work")
    rag.setup(root, bank, "qwen3")
    with rag.publication(root, bank) as active:
        (active.generation / "hashes.json").unlink()
    (root / "orders.py").write_text("changed\n")
    with monkeypatch.context() as env:
        env.setattr(rag, "_runtime", lambda *_: pytest.fail("legacy reached provider"))
        with pytest.raises(rag.ManualUpdateRequired, match="memory-bank rag update"):
            rag.update(root, bank, max_new_chunks=32)
    monkeypatch.setattr(models["qwen3"], "prepare", lambda *_: pytest.fail("download"))
    rag.update(root, bank)
    (root / "orders.py").write_text("x" * 2400 + "y" * 2400)
    with monkeypatch.context() as env:
        env.setattr(rag, "_runtime", lambda *_: pytest.fail("over limit reached provider"))
        with pytest.raises(rag.ManualUpdateRequired, match="memory-bank rag update"):
            rag.update(root, bank, max_new_chunks=1)
    rag.update(root, bank, max_new_chunks=2)
    assert len(rag.candidates(root, bank, "orders.py")) == 2


def test_deletes_remap_duplicate_chunks_including_last_source(tmp_path, models, monkeypatch):
    root, bank = repo(tmp_path / "work")
    for name, text in (("a.py", "remove"), ("duplicate.py", "x" * 4800)):
        (root / name).write_text(text)
    subprocess.run(["git", "-C", root, "add", "."], check=True)
    rag.setup(root, bank, "perplexity")
    monkeypatch.setattr(models["perplexity"], "prepare", lambda *_: pytest.fail("download"))
    (root / "a.py").unlink()
    rag.update(root, bank, max_new_chunks=0)
    assert [row["file"] for row in rag.candidates(root, bank, "xxx")] == ["duplicate.py"] * 2
    assert not rag.candidates(root, bank, "remove")
    (root / "duplicate.py").unlink()
    (root / "orders.py").unlink()
    rag.update(root, bank, max_new_chunks=0)
    assert not rag.candidates(root, bank, "orders.py")


def test_missing_vectors_require_manual_rebuild_without_replacing_pointer(tmp_path, models):
    root, bank = repo(tmp_path / "work")
    rag.setup(root, bank, "perplexity")
    first = models["perplexity"].generations[0]
    (first / "vectors").unlink()
    (root / "orders.py").write_text("new price")
    with pytest.raises(rag.ManualUpdateRequired, match="memory-bank rag update"):
        rag.update(root, bank, max_new_chunks=1)
    with rag.publication(root, bank) as active:
        assert active.generation == first.parent
    rag.update(root, bank)
    assert rag.candidates(root, bank, "price")[0]["file"] == "orders.py"


def test_busy_writers_fail_immediately_readers_see_old_publication_and_edit_aborts_swap(
    tmp_path, models, monkeypatch
):
    root, bank = repo(tmp_path / "work")
    rag.setup(root, bank, "qwen3")
    old = models["qwen3"].generations[0]
    building, finish = Event(), Event()
    refresh = models["qwen3"].refresh

    def slow_refresh(*args):
        building.set()
        assert finish.wait(5)
        return refresh(*args)

    monkeypatch.setattr(models["qwen3"], "refresh", slow_refresh)
    with ThreadPoolExecutor() as pool:
        writer = pool.submit(rag.update, root, bank, max_new_chunks=1)
        try:
            assert building.wait(3)
            for command in ((rag.update, root, bank), (rag.setup, root, bank, "perplexity")):
                with pytest.raises(rag.WriterBusy):
                    pool.submit(*command).result(2)
            assert pool.submit(rag.candidates, root, bank, "total").result(2)
            (root / "orders.py").write_text("revision during build")
        finally:
            finish.set()
        with pytest.raises(RuntimeError, match="changed during indexing"):
            writer.result(3)
    with rag.publication(root, bank) as active:
        assert active.generation == old.parent
    assert list(old.parent.parent.iterdir()) == [old.parent]


def test_next_writer_reaps_generation_left_by_hard_deadline(tmp_path, models):
    root, bank = repo(tmp_path / "work")
    rag.setup(root, bank, "qwen3")
    old = models["qwen3"].generations[0].parent
    killed = subprocess.run(
        [
            sys.executable,
            "-c",
            "import os, signal, sys; from pathlib import Path; sys.path.insert(0, sys.argv[1]); "
            "from test_project_rag import rag, Embeddings; provider = Embeddings(); "
            "provider.refresh = lambda *_: os.kill(os.getpid(), signal.SIGKILL); "
            "rag._provider = lambda _: provider; "
            "rag.update(Path(sys.argv[2]), Path(sys.argv[3]), max_new_chunks=1)",
            str(Path(__file__).parent),
            root,
            bank,
        ],
        cwd=Path(__file__).resolve().parents[2],
        timeout=10,
    )
    assert killed.returncode == -signal.SIGKILL
    assert len(list(old.parent.iterdir())) == 2
    assert rag.candidates(root, bank, "total")
    rag.update(root, bank, max_new_chunks=1)
    with rag.publication(root, bank) as active:
        assert list(old.parent.iterdir()) == [active.generation]
