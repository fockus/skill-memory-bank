"""Run a script's ``main(argv)`` in-process so coverage sees it.

CI uses pytest-cov 7, which no longer measures Python subprocesses; a test that shells out
to ``python script.py`` checks behaviour but leaves the module at 0% coverage. This helper
returns the same ``CompletedProcess`` shape, so a test helper can switch without touching
its assertions. Child processes the script starts itself are unaffected.
"""

from __future__ import annotations

import contextlib
import io
import os
import pathlib
import subprocess
import sys
from collections.abc import Callable, Mapping
from unittest import mock

SCRIPTS = pathlib.Path(__file__).resolve().parents[2] / "scripts"


def run_main(
    main: Callable[[list[str]], int | None],
    argv: list[str],
    env: Mapping[str, str] | None = None,
    cwd: str | os.PathLike[str] | None = None,
    stdin: str | None = None,
) -> subprocess.CompletedProcess:
    out, err = io.StringIO(), io.StringIO()
    # subprocess.run(env=...) replaces the whole environment; clear=True mirrors that.
    env_ctx = (
        mock.patch.dict(os.environ, env, clear=True)
        if env is not None
        else contextlib.nullcontext()
    )
    cwd_ctx = contextlib.chdir(cwd) if cwd is not None else contextlib.nullcontext()
    in_ctx = mock.patch.object(sys, "stdin", io.StringIO(stdin or ""))
    with env_ctx, cwd_ctx, in_ctx, contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            rc = main(list(argv))
        except SystemExit as exc:  # argparse usage errors
            rc = exc.code if isinstance(exc.code, int) else (0 if exc.code is None else 1)
    return subprocess.CompletedProcess(argv, rc or 0, out.getvalue(), err.getvalue())


def load_adapt():
    if str(SCRIPTS) not in sys.path:
        sys.path.insert(0, str(SCRIPTS))
    import mb_work_adapt

    return mb_work_adapt
