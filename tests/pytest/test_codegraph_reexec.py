"""Interpreter routing for `scripts/mb-codegraph.py` (plan Stage 10, AGR-053).

Under a python without networkx the build loses `community` on every node and
Top symbols fall back from PageRank to degree, so the git-tracked graph jumped
~9.5k lines with every interpreter switch. The builder now re-execs itself under
the bootstrap interpreter (`semantic_index._semantic_python`) — but only into a
candidate that has networkx AND every parser module this interpreter has, or the
re-exec would trade clusters for lost tree-sitter languages.
"""

from __future__ import annotations

import importlib.util
import os
import stat
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import codegraph_analytics as cga  # noqa: E402
from memory_bank_skill import semantic_index as si  # noqa: E402

SCRIPT = REPO_ROOT / "scripts" / "mb-codegraph.py"
REEXEC_ENV = "MB_CODEGRAPH_REEXEC"
HAS_TS_HERE = importlib.util.find_spec("tree_sitter") is not None


@pytest.fixture
def cli():
    spec = importlib.util.spec_from_file_location("mb_codegraph_cli_reexec", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def execv_calls(monkeypatch):
    calls: list[tuple[str, list[str]]] = []
    monkeypatch.setattr(os, "execv", lambda path, argv: calls.append((path, list(argv))))
    monkeypatch.setenv(REEXEC_ENV, "")  # falsy + restored: the guard cannot leak
    return calls


@pytest.fixture(autouse=True)
def _no_networkx_here(monkeypatch):
    monkeypatch.setattr(cga, "HAS_NETWORKX", False)


@pytest.fixture
def repo(tmp_path: Path) -> tuple[Path, Path]:
    src = tmp_path / "src"
    src.mkdir()
    (src / "app.py").write_text("def login():\n    return 1\n", encoding="utf-8")
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb, src


def _candidate(tmp_path: Path, monkeypatch, body: str) -> Path:
    """A stand-in interpreter; `body` decides what the module probe sees."""
    py = tmp_path / "bootstrap-venv" / "bin" / "python"
    py.parent.mkdir(parents=True)
    py.write_text(f"#!/bin/sh\n{body}\n", encoding="utf-8")
    py.chmod(py.stat().st_mode | stat.S_IXUSR)
    monkeypatch.setenv("MB_SEMANTIC_PY", str(py))
    return py


def _argv(repo: tuple[Path, Path]) -> list[str]:
    mb, src = repo
    return ["mb-codegraph.py", "--dry-run", str(mb), str(src)]


def test_reexecs_under_a_candidate_with_networkx(cli, repo, tmp_path, monkeypatch, execv_calls):
    py = _candidate(tmp_path, monkeypatch, "exit 0")  # probe: every module present
    argv = _argv(repo)
    cli.main(argv)
    assert execv_calls, "no networkx here + capable candidate must re-exec"
    path, new_argv = execv_calls[0]
    assert path == str(py)
    assert new_argv[0] == str(py)
    assert Path(new_argv[1]) == SCRIPT
    assert new_argv[2:] == argv[1:], "flags and paths must survive the re-exec"
    assert os.environ.get(REEXEC_ENV) == "1"


def test_does_not_reexec_a_second_time(cli, repo, tmp_path, monkeypatch, execv_calls):
    _candidate(tmp_path, monkeypatch, "exit 0")
    monkeypatch.setenv(REEXEC_ENV, "1")
    assert cli.main(_argv(repo)) == 0
    assert execv_calls == []


def test_candidate_without_networkx_is_not_reexeced(cli, repo, tmp_path, monkeypatch, execv_calls):
    """An old venv (fastembed only) would just re-run the same degraded build."""
    _candidate(tmp_path, monkeypatch, 'case "$*" in *networkx*) exit 1;; esac; exit 0')
    assert cli.main(_argv(repo)) == 0
    assert execv_calls == []


@pytest.mark.skipif(not HAS_TS_HERE, reason="needs tree_sitter in the running interpreter")
def test_candidate_losing_tree_sitter_is_not_reexeced(
    cli, repo, tmp_path, monkeypatch, execv_calls
):
    """networkx gained, Go/JS/TS/Rust/Java lost — a regression, not a fix."""
    _candidate(tmp_path, monkeypatch, 'case "$*" in *tree_sitter*) exit 1;; esac; exit 0')
    assert cli.main(_argv(repo)) == 0
    assert execv_calls == []


def test_reexecs_into_a_venv_that_symlinks_the_running_interpreter(
    cli, repo, tmp_path, monkeypatch, execv_calls
):
    """A venv python is a symlink to the base binary — realpath would skip the re-exec."""
    venv_py = tmp_path / "venv" / "bin" / "python"
    venv_py.parent.mkdir(parents=True)
    venv_py.symlink_to(sys.executable)
    monkeypatch.setenv("MB_SEMANTIC_PY", str(venv_py))
    monkeypatch.setattr(si, "_has_modules", lambda python, modules: True, raising=False)
    cli.main(_argv(repo))
    assert execv_calls and execv_calls[0][0] == str(venv_py)


def test_no_candidate_builds_in_the_current_python(cli, repo, monkeypatch, execv_calls, capsys):
    mb, _ = repo
    monkeypatch.setenv("MB_SEMANTIC_PY", str(mb / "absent" / "python"))
    assert cli.main(_argv(repo)) == 0
    assert execv_calls == []
    assert "nodes" in capsys.readouterr().out


def test_a_failed_exec_builds_in_the_current_python(cli, repo, tmp_path, monkeypatch, capsys):
    _candidate(tmp_path, monkeypatch, "exit 0")
    monkeypatch.setenv(REEXEC_ENV, "")

    def boom(path, argv):  # noqa: ARG001
        raise OSError("Exec format error")

    monkeypatch.setattr(os, "execv", boom)
    assert cli.main(_argv(repo)) == 0
    assert "nodes" in capsys.readouterr().out
    assert not os.environ.get(REEXEC_ENV), "a failed exec must not leave the guard set"


def test_networkx_here_does_not_reexec(cli, repo, tmp_path, monkeypatch, execv_calls):
    _candidate(tmp_path, monkeypatch, "exit 0")
    monkeypatch.setattr(cga, "HAS_NETWORKX", True)
    cli.main(_argv(repo))
    assert execv_calls == []


@pytest.mark.skipif(
    importlib.util.find_spec("tree_sitter_rust") is None,
    reason="needs tree_sitter_rust in the running interpreter",
)
def test_candidate_missing_one_grammar_is_not_reexeced(
    cli, repo, tmp_path, monkeypatch, execv_calls
):
    """Every grammar counts, not just the tree_sitter core — else Rust files vanish."""
    _candidate(tmp_path, monkeypatch, 'case "$*" in *tree_sitter_rust*) exit 1;; esac; exit 0')
    assert cli.main(_argv(repo)) == 0
    assert execv_calls == []
