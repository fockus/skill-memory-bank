"""Contract: the npm package staged from an sdist runs the bundled CLI from a persistent copy.

install.sh symlinks the skill to the directory it runs from; under npx that is the
npm cache, so `packaging/npm/memory-bank.js` must copy the bundle out first.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tarfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
VERSION = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()

pytestmark = pytest.mark.skipif(
    shutil.which("node") is None or shutil.which("npm") is None, reason="node/npm not installed"
)


def _fake_sdist(tmp_path: Path) -> Path:
    sdist = tmp_path / f"memory_bank_skill-{VERSION}.tar.gz"
    prefix = f"memory_bank_skill-{VERSION}"
    with tarfile.open(sdist, "w:gz") as tar:
        for name in ("memory_bank_skill", "install.sh", "VERSION"):
            tar.add(REPO_ROOT / name, arcname=f"{prefix}/{name}")
    return sdist


def test_npm_bin_staged_from_sdist_runs_cli_from_persistent_copy(tmp_path: Path) -> None:
    # Arrange
    pkg = tmp_path / "pkg"
    subprocess.run(
        ["bash", str(REPO_ROOT / "packaging/npm/stage.sh"), str(_fake_sdist(tmp_path)), str(pkg)],
        check=True,
        capture_output=True,
    )
    data_home = tmp_path / "data"
    env = {**os.environ, "XDG_DATA_HOME": str(data_home), "MB_PYTHON": sys.executable}

    # Act
    run = subprocess.run(
        ["node", str(pkg / "bin/memory-bank.js"), "version"],
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )

    # Assert
    assert run.returncode == 0, run.stderr
    assert run.stdout.strip() == f"memory-bank-skill {VERSION}"
    assert (data_home / "memory-bank-skill/npm" / VERSION / "install.sh").is_file()
    assert '"version": "' + VERSION + '"' in (pkg / "package.json").read_text(encoding="utf-8")
