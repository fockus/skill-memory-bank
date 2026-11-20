"""Contract: shell helpers never let the caller's working directory shadow the bundle.

`python -m mod`, `python -c` and `python -` put the working directory first on
sys.path, ahead of PYTHONPATH. Scripts run inside the user's project, so a
`memory_bank_skill/` folder there ran instead of the bundled package. Every call
that finds the package through PYTHONPATH sets PYTHONSAFEPATH=1 (3.11+; older
interpreters ignore it).
"""

from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SHELL_FILES = [
    *REPO_ROOT.glob("scripts/*.sh"),
    *REPO_ROOT.glob("hooks/*.sh"),
    *REPO_ROOT.glob("adapters/*.sh"),
    REPO_ROOT / "install.sh",
    REPO_ROOT / "uninstall.sh",
]
# An env assignment that prefixes one command; `export` lines and comments are out of scope.
_INLINE_PYTHONPATH = re.compile(r'^(?!\s*(#|export\b)).*\bPYTHONPATH="\$')


def test_inline_pythonpath_calls_set_safe_path() -> None:
    offenders = [
        f"{path.relative_to(REPO_ROOT)}:{n}"
        for path in SHELL_FILES
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if _INLINE_PYTHONPATH.search(line) and "PYTHONSAFEPATH=1 PYTHONPATH=" not in line
    ]
    assert offenders == []


def test_profile_script_from_hostile_cwd_runs_bundled_package(tmp_path: Path) -> None:
    # Arrange
    planted = tmp_path / "memory_bank_skill"
    planted.mkdir()
    (planted / "__init__.py").write_text("raise SystemExit('HIJACKED')\n", encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if k not in ("PYTHONSAFEPATH", "MB_SKILL_BUNDLE")}

    # Act
    run = subprocess.run(
        ["bash", str(REPO_ROOT / "scripts/mb-profile.sh"), "quality", "--json"],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    # Assert
    assert "HIJACKED" not in run.stdout + run.stderr
    assert run.returncode == 0, run.stderr
