"""Interpreter routing for `scripts/mb-semantic-search.py` (plan Stage 8, AGR-047).

The documented invocation is `python3 scripts/mb-semantic-search.py ...` — and a
bare `python3` never carries `fastembed`, so every documented call answered from
BM25 and the warm vector index built by `/mb graph --apply` was unreachable.
The CLI now re-execs itself under the semantic interpreter
(`semantic_index._semantic_python`) when embeddings are wanted but absent here.

Scope of the re-exec (owner decision AGR-047): BOTH `--backend embeddings` and
the default `--backend auto`, because agents call without a flag. `--backend
bm25` never re-execs, and no interpreter means today's behaviour — BM25.
"""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import semantic_embeddings as se  # noqa: E402

SCRIPT = REPO_ROOT / "scripts" / "mb-semantic-search.py"
REEXEC_ENV = "MB_SEMANTIC_REEXEC"


@pytest.fixture
def cli():
    spec = importlib.util.spec_from_file_location("mb_semantic_search_cli_routing", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def execv_calls(monkeypatch):
    """Record `os.execv` instead of replacing the process."""
    calls: list[tuple[str, list[str]]] = []
    monkeypatch.setattr(os, "execv", lambda path, argv: calls.append((path, list(argv))))
    # Empty (falsy) rather than deleted: monkeypatch then restores/removes it, so a
    # test that triggers the real re-exec guard cannot leak the flag into the suite.
    monkeypatch.setenv(REEXEC_ENV, "")
    return calls


@pytest.fixture
def bank(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    (mb / "codebase").mkdir(parents=True)
    (mb / "codebase" / "graph.json").write_text(
        json.dumps(
            {"type": "node", "kind": "function", "name": "login_user",
             "file": "auth.py", "line": 1}
        )
        + "\n",
        encoding="utf-8",
    )
    return mb


@pytest.fixture
def semantic_py(tmp_path: Path, monkeypatch) -> Path:
    """An executable stand-in for the semantic venv python."""
    py = tmp_path / "semantic-venv" / "bin" / "python"
    py.parent.mkdir(parents=True)
    py.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    py.chmod(py.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setenv("MB_SEMANTIC_PY", str(py))
    return py


@pytest.fixture(autouse=True)
def _no_fastembed_here(monkeypatch):
    monkeypatch.setattr(se, "HAS_FASTEMBED", False)


@pytest.mark.parametrize("backend", ["auto", "embeddings"])
def test_reexecs_under_the_semantic_interpreter(cli, bank, semantic_py, execv_calls, backend):
    """AGR-047: auto AND embeddings both reach the warm index via the venv python."""
    argv = ["mb-semantic-search.py", "login user", str(bank), "--backend", backend]
    cli.main(argv)
    assert execv_calls, f"--backend {backend} must re-exec under {semantic_py}"
    path, new_argv = execv_calls[0]
    assert path == str(semantic_py)
    assert new_argv[0] == str(semantic_py)
    assert Path(new_argv[1]) == SCRIPT
    assert new_argv[2:] == argv[1:], "query, bank and flags must survive the re-exec"


def test_reexec_sets_the_recursion_guard(cli, bank, semantic_py, execv_calls):
    cli.main(["mb-semantic-search.py", "login user", str(bank)])
    assert execv_calls
    assert os.environ.get(REEXEC_ENV) == "1"


def test_does_not_reexec_a_second_time(cli, bank, semantic_py, execv_calls, monkeypatch):
    """The child already ran under the venv python — a second exec would loop forever."""
    monkeypatch.setenv(REEXEC_ENV, "1")
    cli.main(["mb-semantic-search.py", "login user", str(bank)])
    assert execv_calls == []


def test_bm25_backend_never_reexecs(cli, bank, semantic_py, execv_calls):
    cli.main(["mb-semantic-search.py", "login user", str(bank), "--backend", "bm25"])
    assert execv_calls == []


def test_no_semantic_interpreter_answers_on_bm25_without_reexec(
    cli, bank, execv_calls, monkeypatch, capsys
):
    monkeypatch.setenv("MB_SEMANTIC_PY", str(bank / "absent" / "python"))
    rc = cli.main(["mb-semantic-search.py", "login user", str(bank), "--json"])
    assert execv_calls == []
    assert rc == 0
    payload = json.loads(capsys.readouterr().out)
    assert payload["ok"] is True
    assert payload["backend"] == "bm25"


def test_fastembed_present_here_does_not_reexec(cli, bank, semantic_py, execv_calls, monkeypatch):
    monkeypatch.setattr(se, "HAS_FASTEMBED", True)
    cli.main(["mb-semantic-search.py", "login user", str(bank)])
    assert execv_calls == []


def test_a_failed_exec_falls_back_instead_of_crashing(
    cli, bank, semantic_py, monkeypatch, capsys
):
    """Fail-open: a dead interpreter must still answer, never raise at the user."""
    monkeypatch.setenv(REEXEC_ENV, "")

    def boom(path, argv):  # noqa: ARG001
        raise OSError("Exec format error")

    monkeypatch.setattr(os, "execv", boom)
    rc = cli.main(["mb-semantic-search.py", "login user", str(bank), "--json"])
    assert rc == 0
    assert json.loads(capsys.readouterr().out)["backend"] == "bm25"


def test_reexecs_into_a_venv_that_symlinks_the_running_interpreter(
    cli, bank, tmp_path: Path, monkeypatch, execv_calls
):
    """A venv python IS a symlink to the base interpreter — resolving it kills the feature.

    `~/.claude/hooks/.venv/bin/python` → `python3.14` → the same Homebrew binary
    `python3` runs from, so a realpath comparison says "same interpreter" and skips
    the re-exec, while the venv is exactly where fastembed lives.
    """
    venv_py = tmp_path / "venv" / "bin" / "python"
    venv_py.parent.mkdir(parents=True)
    venv_py.symlink_to(sys.executable)
    monkeypatch.setenv("MB_SEMANTIC_PY", str(venv_py))
    cli.main(["mb-semantic-search.py", "login user", str(bank)])
    assert execv_calls and execv_calls[0][0] == str(venv_py)
