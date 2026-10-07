"""hooks/lib/venv_unmet.py — bootstrap readiness checks versions, not only imports.

AGR-054: a venv holding networkx 3.7 answered "ready" against the ``>=3.6,<3.7``
pin, so the pin never reached existing users. The checker prints every
requirement the venv does not satisfy (absent, wrong version, or not importable).
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

CHECKER = Path(__file__).resolve().parents[2] / "hooks" / "lib" / "venv_unmet.py"


def _dist(site: Path, name: str, version: str, *, module: bool = True) -> None:
    info = site / f"{name.replace('-', '_')}-{version}.dist-info"
    info.mkdir(parents=True)
    (info / "METADATA").write_text(f"Metadata-Version: 2.1\nName: {name}\nVersion: {version}\n")
    if module:
        pkg = site / name.replace("-", "_")
        pkg.mkdir()
        (pkg / "__init__.py").write_text("")


def test_unmet_lists_wrong_version_missing_and_unimportable(tmp_path):
    site = tmp_path / "site"
    _dist(site, "mbfake-newer", "3.7")
    _dist(site, "mbfake-pinned", "3.6.1")
    _dist(site, "mbfake-noimport", "1.0", module=False)
    reqs = [
        "mbfake-newer>=3.6,<3.7",
        "mbfake-pinned>=3.6,<3.7",
        "mbfake-absent>=1",
        "mbfake-noimport",
    ]
    env = {**os.environ, "PYTHONPATH": str(site), "PYTHONDONTWRITEBYTECODE": "1"}
    proc = subprocess.run(
        [sys.executable, str(CHECKER), *reqs], capture_output=True, text=True, env=env
    )
    assert proc.returncode == 0, proc.stderr
    assert proc.stdout.splitlines() == [
        "mbfake-newer>=3.6,<3.7",
        "mbfake-absent>=1",
        "mbfake-noimport",
    ]
