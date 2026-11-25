"""CLI and mb_code_context_core.py evidence-pack contracts for the optional index."""

from __future__ import annotations

import io
import json
import os
import runpy
import shutil
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"


def _cli(cwd: Path, bundle: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "memory_bank_skill", "rag", *args],
        cwd=cwd,
        env={**os.environ, "PYTHONPATH": str(ROOT), "MB_SKILL_BUNDLE": str(bundle), "MB_PATH": ""},
        input="",
        text=True,
        capture_output=True,
    )


def test_unattended_init_without_model_leaves_project_untouched(tmp_path, bundle):
    project = tmp_path / "project"
    project.mkdir()
    result = _cli(project, bundle, "init")
    assert result.returncode == 0, result.stderr
    assert "--model" in result.stdout + result.stderr
    assert not list(project.iterdir())


@pytest.mark.parametrize(
    ("script", "args", "exit_code"),
    [("mb-rag.py", ["update"], 1), ("mb-code-context.py", ["--query", "refresh"], 0)],
)
def test_source_script_uses_its_checkout_from_another_project(tmp_path, script, args, exit_code):
    # A caller may already have an older checkout on PYTHONPATH.
    old_package = tmp_path / "memory_bank_skill"
    old_package.mkdir()
    (old_package / "__init__.py").touch()
    project = tmp_path / "project"
    project.mkdir()
    result = subprocess.run(
        [str(SCRIPTS / script), *args],
        cwd=project,
        env={
            **os.environ,
            "PYTHONPATH": str(tmp_path),
            "XDG_STATE_HOME": str(tmp_path / "state"),
            "MB_PATH": "",
            "PATH": str(Path(sys.executable).parent) + os.pathsep + os.environ["PATH"],
        },
        capture_output=True,
        text=True,
    )
    assert result.returncode == exit_code, result.stderr
    if script == "mb-rag.py":
        assert "memory-bank rag init" in result.stderr
    else:
        assert "memory-bank rag" not in result.stderr


@pytest.fixture
def bundle(tmp_path):
    # A wheel stores scripts outside the package. Substitute only its model lifecycle.
    bundle = tmp_path / "share" / "memory-bank-skill"
    scripts = bundle / "scripts"
    scripts.mkdir(parents=True)
    (bundle / "install.sh").touch()
    for name in ("mb-rag.py", "_mb_skill_python.py", "mb_project_rag_corpus.py", "_lib.sh"):
        shutil.copy(SCRIPTS / name, scripts)
    (scripts / "mb_project_rag.py").write_text(
        "def setup(root, bank, model):\n"
        "    bank.mkdir(exist_ok=True)\n"
        "    (bank / 'model').write_text(model)\n"
        "def update(root, bank):\n"
        "    (bank / 'index').write_text((bank / 'model').read_text() + ':' + str(root))\n"
    )
    return bundle


def test_cli_uses_selected_bundle_and_targets_same_project_for_update(tmp_path, bundle):
    project = tmp_path / "project"
    project.mkdir()
    for args in (("init", "--model", "perplexity"), ("update",)):
        result = _cli(tmp_path, bundle, *args, "--project-root", str(project))
        assert result.returncode == 0, result.stderr
    assert (project / ".memory-bank/index").read_text() == f"perplexity:{project}"


@pytest.mark.parametrize("answer", ["qwen3", ""])
def test_interactive_init_requires_explicit_model_or_cancels(tmp_path, monkeypatch, answer):
    class Terminal(io.StringIO):
        def isatty(self):
            return True

    def setup(root, bank, model):
        (root / "chosen").write_text(model)

    monkeypatch.chdir(tmp_path)
    monkeypatch.syspath_prepend(str(SCRIPTS))
    monkeypatch.setattr(sys, "stdin", Terminal(answer + "\n"))
    monkeypatch.setitem(sys.modules, "mb_project_rag", SimpleNamespace(setup=setup))
    monkeypatch.setattr(sys, "argv", [str(SCRIPTS / "mb-rag.py"), "init"])
    with pytest.raises(SystemExit) as exit_info:
        runpy.run_path(sys.argv[0], run_name="__main__")
    assert exit_info.value.code == 0
    if answer:
        assert (tmp_path / "chosen").read_text() == answer
    else:
        assert not list(tmp_path.iterdir())


def _evidence(root, monkeypatch, lifecycle, query, *, mode="auto", explicit=None):
    monkeypatch.syspath_prepend(str(SCRIPTS))
    monkeypatch.setitem(sys.modules, "mb_project_rag", lifecycle)
    from mb_code_context_core import build_evidence

    return build_evidence(
        query=query,
        project_root=root,
        mb_path=root / ".memory-bank",
        mode=mode,
        semantic_provider="none",
        semantic_candidates_path=explicit,
    )


def test_project_candidates_receive_original_query_and_reach_reads(tmp_path, monkeypatch):
    question = "Где обновляется ключ?"

    def candidates(root, bank, query, k=10):
        if root == tmp_path and bank == root / ".memory-bank" and query == question:
            return [{"file": "tokens.py"}]
        return []

    lifecycle = SimpleNamespace(selected=lambda *_: "qwen3", candidates=candidates)
    pack = _evidence(tmp_path, monkeypatch, lifecycle, question)
    assert "semantic" in pack["channels_used"]
    assert pack["recommended_next_reads"] == ["tokens.py"]


@pytest.mark.parametrize("selected", [None, "perplexity"])
def test_missing_selection_or_stale_index_reports_repair_and_returns_text(
    tmp_path, monkeypatch, selected
):
    (tmp_path / "tokens.py").write_text("def refresh(): return 1")

    def candidates(*args, **kwargs):
        if selected is None:
            return []
        raise RuntimeError("index is stale")

    lifecycle = SimpleNamespace(selected=lambda *_: selected, candidates=candidates)
    pack = _evidence(tmp_path, monkeypatch, lifecycle, "refresh")
    if selected:
        assert any("memory-bank rag update" in message for message in pack["warnings"])
    else:
        assert not any("memory-bank rag" in message for message in pack["warnings"])
    assert "text" in pack["channels_used"]
    assert pack["recommended_next_reads"] == ["tokens.py"]


@pytest.mark.parametrize("mode", ["graph", "auto"])
def test_graph_and_explicit_candidates_bypass_project_provider(tmp_path, monkeypatch, mode):
    def forbidden(*_):
        pytest.fail("must not consult the project index")

    path = tmp_path / "candidates.json"
    path.write_text(json.dumps({"candidates": [{"file": "explicit.py"}]}))
    pack = _evidence(
        tmp_path,
        monkeypatch,
        SimpleNamespace(selected=forbidden),
        "Где?",
        mode=mode,
        explicit=path if mode == "auto" else None,
    )
    assert pack["candidate_files"] == (["explicit.py"] if mode == "auto" else [])
