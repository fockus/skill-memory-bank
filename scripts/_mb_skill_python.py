"""Interpreter bootstrap shared by every ``scripts/*.py`` entry point.

Problem: on a pipx install the skill data lives at
``<venv>/share/memory-bank-skill`` while the ``memory_bank_skill`` package lives
in ``<venv>``'s site-packages. A bare ``python3 scripts/mb-*.py`` therefore
cannot import the package (the ``parents[1]`` sys.path fallback points at
``share/``), and an old system ``python3`` (e.g. macOS CLT 3.9) additionally
lacks 3.11-only stdlib such as ``datetime.UTC``.

Fix: before any 3.11-only or package import, an entry script calls
``ensure_skill_python(__file__)``. When the current interpreter cannot run the
skill, the process re-execs itself exactly once under a better interpreter,
chosen with the same precedence as ``_lib.sh::mb_resolve_python``:

1. ``$MB_PYTHON`` (exported by the packaged ``memory-bank`` CLI);
2. the pipx venv interpreter, derived from this file's real path;
3. otherwise nothing: return and let the caller's import fail loudly.

No-op when the interpreter already works (pipx venv python, git clone with a
modern ``python3``, test runners). This module must stay importable by
Python 3.9: stdlib only, no 3.10+ syntax at runtime.
"""

from __future__ import annotations

import importlib.util
import os
import shutil
import sys
from pathlib import Path

MIN_VERSION = (3, 11)
PACKAGE = "memory_bank_skill"
# Set only for the single re-exec'd process and popped on entry, so it never
# leaks into grandchildren (a leaked guard would stop a child entry point from
# re-exec'ing and resurrect the bug one level down).
_GUARD_ENV = "_MB_SKILL_PYTHON_REEXEC"


def _skill_root() -> Path:
    return Path(__file__).resolve().parents[1]


def interpreter_is_usable(skill_root: Path | None = None) -> bool:
    """True when this interpreter is new enough and can import the package."""
    root = skill_root or _skill_root()
    if sys.version_info < MIN_VERSION:
        return False
    return importlib.util.find_spec(PACKAGE) is not None or (root / PACKAGE).is_dir()


def candidate_interpreter(skill_root: Path | None = None) -> str | None:
    """Return the interpreter to re-exec under, or None when none is better."""
    override = os.environ.get("MB_PYTHON", "")
    if override:
        return shutil.which(override)
    root = skill_root or _skill_root()
    if root.parent.name != "share":
        return None  # not a pipx/pip data-dir layout: nothing to derive
    venv_root = root.parents[1]
    # Compare venv identity via sys.prefix, NOT realpath: every venv's
    # bin/python3 symlinks to the same base interpreter.
    if Path(sys.prefix).resolve() == venv_root.resolve():
        return None
    return shutil.which(str(venv_root / "bin" / "python3"))


def ensure_skill_python(script: str) -> None:
    """Re-exec ``script`` once under a usable interpreter, if needed.

    ``script`` is the entry point's ``__file__``. Returns normally when no
    re-exec is needed or possible; otherwise does not return.
    """
    already_reexeced = os.environ.pop(_GUARD_ENV, None) == "1"
    if already_reexeced or interpreter_is_usable():
        return
    target = candidate_interpreter()
    if not target or os.path.abspath(target) == os.path.abspath(sys.executable):
        return
    env = dict(os.environ, **{_GUARD_ENV: "1"})
    script_path = str(Path(script).resolve())
    os.execve(target, [target, script_path, *sys.argv[1:]], env)
