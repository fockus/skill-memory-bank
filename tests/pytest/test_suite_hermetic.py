"""The pytest suite drops a git hook's repo-local env before any test runs.

A linked worktree's pre-commit exports an absolute GIT_DIR; under it a test's
`git init <tmp>` sets core.bare=true in the committing repo's shared config.
"""

import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def test_conftest_import_drops_hook_git_env(tmp_path):
    env = {
        **os.environ,
        "GIT_DIR": str(tmp_path / "x.git"),
        "GIT_INDEX_FILE": str(tmp_path / "index"),
        "XDG_CONFIG_HOME": str(tmp_path / "real-config"),
    }
    probe = (
        "import os, conftest; print(os.environ.get('GIT_DIR'), os.environ.get('GIT_INDEX_FILE'),"
        " os.environ.get('XDG_CONFIG_HOME'))"
    )
    out = subprocess.run(
        [sys.executable, "-c", probe], cwd=HERE, env=env, text=True, capture_output=True, check=True
    ).stdout.split()
    assert out == ["None", "None", "None"]
