"""Contract tests for scripts/_mb_skill_python.py (interpreter bootstrap).

The helper is loaded from its file path, in a synthetic pipx-style tree
(<venv>/share/memory-bank-skill/scripts/), because the venv interpreter is
derived from the helper's own location.
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import stat
import subprocess
import sys
import textwrap
from pathlib import Path
from types import ModuleType

import pytest

HELPER = Path(__file__).resolve().parents[2] / "scripts" / "_mb_skill_python.py"
GUARD = "_MB_SKILL_PYTHON_REEXEC"


def _load(path: Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location(f"_mbsp_{abs(hash(path))}", path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _fake_venv(tmp_path: Path) -> tuple[Path, Path]:
    """<tmp>/venv/{bin/python3, share/memory-bank-skill/scripts/_mb_skill_python.py}."""
    venv = tmp_path / "venv"
    scripts = venv / "share" / "memory-bank-skill" / "scripts"
    scripts.mkdir(parents=True)
    shutil.copy(HELPER, scripts / HELPER.name)
    py = venv / "bin" / "python3"
    py.parent.mkdir()
    py.write_text(f'#!/bin/sh\nPROBE_VIA_VENV_SHIM=1 exec "{sys.executable}" "$@"\n')
    py.chmod(py.stat().st_mode | stat.S_IXUSR)
    return venv, scripts / HELPER.name


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("MB_PYTHON", raising=False)
    monkeypatch.delenv(GUARD, raising=False)


def test_candidate_interpreter_pipx_layout_returns_venv_python(tmp_path: Path) -> None:
    venv, helper = _fake_venv(tmp_path)
    assert _load(helper).candidate_interpreter() == str(venv / "bin" / "python3")


def test_candidate_interpreter_mb_python_set_wins_over_venv(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    _, helper = _fake_venv(tmp_path)
    monkeypatch.setenv("MB_PYTHON", sys.executable)
    assert _load(helper).candidate_interpreter() == shutil.which(sys.executable)


def test_candidate_interpreter_git_clone_layout_returns_none(tmp_path: Path) -> None:
    scripts = tmp_path / "skill-memory-bank" / "scripts"
    scripts.mkdir(parents=True)
    shutil.copy(HELPER, scripts / HELPER.name)
    assert _load(scripts / HELPER.name).candidate_interpreter() is None


def test_ensure_skill_python_guard_set_pops_guard_and_never_execs(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    mod = _load(HELPER)
    monkeypatch.setenv(GUARD, "1")
    monkeypatch.setattr(mod, "interpreter_is_usable", lambda *a: False)
    monkeypatch.setattr(os, "execve", lambda *a: pytest.fail("must not re-exec twice"))
    mod.ensure_skill_python(__file__)
    assert GUARD not in os.environ


def test_ensure_skill_python_unusable_interpreter_reexecs_under_venv_once(tmp_path: Path) -> None:
    """End to end: an entry script whose interpreter is 'unusable' re-execs under the
    derived venv python exactly once, keeps its argv, and does not leak the guard."""
    venv, helper = _fake_venv(tmp_path)
    entry = helper.parent / "mb-probe.py"
    entry.write_text(
        textwrap.dedent(
            """
            import os, sys
            import _mb_skill_python as h
            if os.environ.get("PROBE_FORCE_UNUSABLE") == "1" and not os.environ.get("_MB_SKILL_PYTHON_REEXEC"):
                h.interpreter_is_usable = lambda *a: False
            h.ensure_skill_python(__file__)
            print("argv=" + ",".join(sys.argv[1:]))
            print("guard=" + repr(os.environ.get("_MB_SKILL_PYTHON_REEXEC")))
            print("via_venv=" + os.environ.get("PROBE_VIA_VENV_SHIM", "0"))
            """
        )
    )
    env = {k: v for k, v in os.environ.items() if k not in ("MB_PYTHON", GUARD)}
    env["PROBE_FORCE_UNUSABLE"] = "1"
    out = subprocess.run(
        [sys.executable, str(entry), "a", "b c"], env=env, capture_output=True, text=True, check=True
    ).stdout
    assert "argv=a,b c" in out
    assert "guard=None" in out
    assert "via_venv=1" in out  # really re-exec'd under the derived venv interpreter
    assert out.count("argv=") == 1  # exactly one process printed: exec replaced, no loop
