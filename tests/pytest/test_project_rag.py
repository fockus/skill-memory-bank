"""Offline lifecycle and tracked-source contracts (mb_project_rag_corpus.py)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import mb_project_rag as rag  # noqa: E402


class Embeddings:
    def __init__(self):
        self.generations: list[Path] = []
        self.caches: set[Path] = set()
        self.fail_build = False

    def prepare(self, cache: Path):
        self.caches.add(cache)
        (cache / "weights").touch()

    def build(self, index: Path, docs: list[tuple[str, str]], cache: Path):
        assert (cache / "weights").exists()
        self.generations.append(index)
        (index / "ids.json").write_text(json.dumps([key for key, _ in docs]))
        (index / "vectors").write_text(json.dumps(dict(docs)))
        if self.fail_build:
            raise RuntimeError("build interrupted")

    def search(self, index: Path, query: str, k: int, cache: Path) -> list[str]:
        assert index in self.generations, "QMD retains the absolute path used for build"
        (cache / "weights").stat()
        docs = json.loads((index / "vectors").read_text())
        return [key for key, text in docs.items() if query in text][:k]

    def refresh(self, index, docs, cache, old, reuse, max_new_chunks=None):
        if not (old / "vectors").exists():
            return False
        previous = json.loads((old / "vectors").read_text())
        for (_, text), source in zip(docs, reuse, strict=True):
            if source is not None:
                assert previous[str(source)] == text
        self.build(index, docs, cache)
        return True


@pytest.fixture
def models(tmp_path, monkeypatch):
    home = tmp_path / "home"
    monkeypatch.setenv("HOME", str(home))
    monkeypatch.setenv("XDG_STATE_HOME", str(home / ".local/state"))
    monkeypatch.setenv("XDG_CACHE_HOME", str(home / ".cache"))
    providers = {"qwen3": Embeddings(), "perplexity": Embeddings()}
    monkeypatch.setattr(rag, "_provider", providers.__getitem__)
    return providers


def repo(path: Path, filename="orders.py") -> tuple[Path, Path]:
    path.mkdir()
    subprocess.run(["git", "init", "-q", path], check=True)
    (path / filename).write_text("def compute_total(): return 2\n")
    subprocess.run(["git", "-C", path, "add", filename], check=True)
    return path, path / ".memory-bank"


def test_no_selection_does_not_import_models_or_create_state(tmp_path, models, monkeypatch):
    root, bank = repo(tmp_path / "work")
    monkeypatch.setattr(rag, "_provider", lambda _: pytest.fail("provider not selected"))
    assert rag.selected(root, bank) is None
    assert rag.candidates(root, bank, "total") == []
    with pytest.raises(ValueError, match="model"):
        rag.setup(root, bank, "auto")
    with pytest.raises((RuntimeError, ValueError), match="setup"):
        rag.update(root, bank)
    assert not (tmp_path / "home").exists()


@pytest.mark.parametrize("model", ["qwen3", "perplexity"])
def test_setup_reuses_selected_model_and_private_project_index(tmp_path, models, model):
    root, bank = repo(tmp_path / "one")
    other, other_bank = repo(tmp_path / "two", "other.py")
    rag.setup(root, bank, model)
    rag.setup(root, bank, model)
    rag.setup(other, other_bank, model)
    provider = models[model]
    assert rag.selected(root, bank) == model
    assert [r["file"] for r in rag.candidates(root, bank, "orders.py")] == ["orders.py"]
    assert not rag.candidates(other, other_bank, "orders.py")
    assert len(set(provider.generations)) == 2 and len(provider.generations) == 2
    assert len(provider.caches) == 1
    assert not any(models[m].caches for m in models if m != model)
    assert not any(p.is_relative_to(root) or p.is_relative_to(other) for p in provider.caches)
    assert all(p.stat().st_mode & 0o077 == 0 for p in provider.caches)


def test_index_includes_only_tracked_redacted_source(tmp_path, models):
    root, bank = repo(tmp_path / "one")
    (root / "orders.py").write_text(
        "def first():\n"
        + "# <private>\n"
        + "LEAK\n" * 2500
        + "# </private>\n"
        + "def last(): return 42\n"
    )
    for name in [
        "docs.md",
        "wiki/item.py",
        "notes/item.py",
        "Secrets.js",
        "credentials/helper.go",
        ".memory-bank/qa/sample.py",
        ".env.local.sh",
        "sub/replaced.py",
    ]:
        p = root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("LEAK\n")
    (root / "link.py").symlink_to(root / "docs.md")
    subprocess.run(["git", "-C", root, "add", "-f", "."], check=True)
    outside = tmp_path / "outside"
    (root / "sub").rename(outside)
    (root / "sub").symlink_to(outside, target_is_directory=True)
    (root / "untracked.py").write_text("LEAK\n")

    rag.setup(root, bank, "qwen3")
    docs = json.loads((models["qwen3"].generations[0] / "vectors").read_text())
    assert len(docs) > 1, "long sources need chunks"
    assert all("LEAK" not in text and "orders.py" in text for text in docs.values())
    (hit,) = rag.candidates(root, bank, "def last()")
    assert hit["file"] == "orders.py" and hit["line"] <= 2504 <= hit["end_line"]


def test_worktree_changes_stale_even_after_indexing_dirty_source(tmp_path, models):
    root, bank = repo(tmp_path / "one")
    file = root / "orders.py"
    rag.setup(root, bank, "qwen3")
    for value in ["v = 2\n", "v = 3\n"]:
        original = file.stat()
        file.write_text(value)
        os.utime(file, ns=(original.st_atime_ns, original.st_mtime_ns))
        with pytest.raises(rag.IndexStale, match="stale.*update"):
            rag.candidates(root, bank, "total")
        rag.update(root, bank)
        assert rag.candidates(root, bank, value.strip())[0]["file"] == "orders.py"
    file.unlink()
    with pytest.raises(RuntimeError, match="stale"):
        rag.candidates(root, bank, "3")


def test_failed_switch_keeps_old_model_and_working_index(tmp_path, models):
    root, bank = repo(tmp_path / "one")
    rag.setup(root, bank, "qwen3")
    models["perplexity"].fail_build = True
    with pytest.raises(RuntimeError, match="build interrupted"):
        rag.setup(root, bank, "perplexity")
    assert rag.selected(root, bank) == "qwen3"
    assert rag.candidates(root, bank, "total")[0]["file"] == "orders.py"
    assert not models["perplexity"].generations[0].exists()


def test_repeated_init_repairs_partial_index_and_returns_a_semantic_hit(tmp_path, models):
    root, bank = repo(tmp_path / "work")
    rag.setup(root, bank, "perplexity")
    index = models["perplexity"].generations[0]
    (index / "vectors").unlink()
    assert (index / "ids.json").is_file()
    rag.setup(root, bank, "perplexity")
    assert rag.candidates(root, bank, "compute_total")[0]["file"] == "orders.py"


@pytest.mark.parametrize("missing", ["model", "index"])
def test_missing_assets_fail_read_only_and_setup_repairs(tmp_path, models, monkeypatch, missing):
    root, bank = repo(tmp_path / "one")
    rag.setup(root, bank, "qwen3")
    provider = models["qwen3"]
    absent = (
        next(iter(provider.caches)) / "weights" if missing == "model" else provider.generations[0]
    )
    if absent.is_dir():
        shutil.rmtree(absent)
    else:
        absent.unlink()
    with monkeypatch.context() as patch:
        patch.setattr(provider, "prepare", lambda *_: pytest.fail("query downloaded a model"))
        patch.setattr(provider, "build", lambda *_: pytest.fail("query rebuilt the index"))
        with pytest.raises((RuntimeError, ValueError), match="setup|update"):
            rag.candidates(root, bank, "total")
    assert not absent.exists()
    rag.setup(root, bank, "qwen3")
    assert rag.candidates(root, bank, "total")[0]["file"] == "orders.py"


def test_cache_under_project_rejected_before_provider_runs(tmp_path, models, monkeypatch):
    root, bank = repo(tmp_path / "one")
    monkeypatch.setenv("XDG_CACHE_HOME", str(root / "runtime"))
    with pytest.raises((ValueError, RuntimeError), match="outside"):
        rag.setup(root, bank, "qwen3")
    assert not models["qwen3"].caches and not (root / "runtime").exists()


def test_unconfigured_repo_does_not_consult_unsafe_storage(tmp_path, models, monkeypatch):
    root, bank = repo(tmp_path / "one")
    monkeypatch.setenv("XDG_STATE_HOME", str(root / "state"))
    assert rag.selected(root, bank) is None
    assert rag.candidates(root, bank, "total") == []
    assert not (root / "state").exists()


def test_project_executable_on_path_cannot_run_as_qmd_runtime(tmp_path, models, monkeypatch):
    root, bank = repo(tmp_path / "one")
    (root / "node").touch(mode=0o700)
    monkeypatch.setenv("PATH", str(root) + os.pathsep + os.environ["PATH"])
    with pytest.raises(ValueError, match="outside"):
        rag.setup(root, bank, "qwen3")
    assert not models["qwen3"].caches


def test_damaged_partial_index_has_actionable_repair(tmp_path, models, monkeypatch):
    root, bank = repo(tmp_path / "one")
    rag.setup(root, bank, "perplexity")
    provider = models["perplexity"]
    original = provider.search

    def damaged(index, query, k, cache):
        raise subprocess.CalledProcessError(1, "embed")

    monkeypatch.setattr(provider, "search", damaged)
    with pytest.raises(RuntimeError, match="update"):
        rag.candidates(root, bank, "total")
    monkeypatch.setattr(provider, "search", original)
    rag.update(root, bank)
    assert rag.candidates(root, bank, "total")[0]["file"] == "orders.py"


def test_invalid_project_does_not_download_or_select_model(tmp_path, models):
    root = tmp_path / "not-a-repo"
    root.mkdir()
    bank = root / ".memory-bank"
    with pytest.raises(ValueError, match="Git"):
        rag.setup(root, bank, "qwen3")
    assert not models["qwen3"].caches and rag.selected(root, bank) is None


def test_new_source_during_build_cannot_publish_old_contents(tmp_path, models, monkeypatch):
    root, bank = repo(tmp_path / "one")
    build = models["qwen3"].build

    def concurrent_edit(index, docs, cache):
        build(index, docs, cache)
        (root / "orders.py").write_text("def new(): return 5")

    monkeypatch.setattr(models["qwen3"], "build", concurrent_edit)
    with pytest.raises(RuntimeError, match="changed during indexing"):
        rag.setup(root, bank, "qwen3")
    assert rag.selected(root, bank) is None
