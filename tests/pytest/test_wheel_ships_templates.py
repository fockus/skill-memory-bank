"""Contract: the built wheel + sdist must ship the template bundles.

Regression guard (C-1): `pyproject.toml` shared-data listed adapters/agents/...
but NOT `templates/` nor `flow-templates/`. On pipx/pip installs the bundle tree
therefore had no `templates/locales/<lang>/.memory-bank/`, and `mb-init-bank.sh`
aborted with exit 3 ("missing template bundle"). These tests inspect the actual
packaged artifacts (not the repo tree), so the class of "works from git, broken
from wheel" bugs is caught.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

# Path prefix hatch uses for shared-data files inside a wheel.
WHEEL_DATA_PREFIX = "share/memory-bank-skill"


@pytest.fixture(scope="module")
def built_dists(tmp_path_factory: pytest.TempPathFactory) -> tuple[Path, Path]:
    """Build wheel + sdist once and return (wheel_path, sdist_path)."""
    if importlib.util.find_spec("build") is None:
        pytest.skip("python 'build' module not available")
    outdir = tmp_path_factory.mktemp("dist")
    subprocess.run(
        [sys.executable, "-m", "build", "--wheel", "--sdist", "--outdir", str(outdir)],
        cwd=str(REPO_ROOT),
        check=True,
        capture_output=True,
    )
    wheels = list(outdir.glob("*.whl"))
    sdists = list(outdir.glob("*.tar.gz"))
    assert wheels, "wheel not produced"
    assert sdists, "sdist not produced"
    return wheels[0], sdists[0]


def _wheel_names(wheel: Path) -> list[str]:
    with zipfile.ZipFile(wheel) as zf:
        return zf.namelist()


def _sdist_names(sdist: Path) -> list[str]:
    with tarfile.open(sdist, "r:gz") as tf:
        return tf.getnames()


def test_wheel_ships_templates_locales(built_dists: tuple[Path, Path]) -> None:
    wheel, _ = built_dists
    names = _wheel_names(wheel)
    # Every supported locale must carry its .memory-bank/status.md into the wheel.
    for lang in ("en", "ru", "es", "zh"):
        needle = f"{WHEEL_DATA_PREFIX}/templates/locales/{lang}/.memory-bank/status.md"
        assert any(n.endswith(needle) for n in names), (
            f"wheel is missing {needle}; templates not packaged as shared-data"
        )


def test_wheel_ships_flow_templates(built_dists: tuple[Path, Path]) -> None:
    wheel, _ = built_dists
    names = _wheel_names(wheel)
    patterns_needle = f"{WHEEL_DATA_PREFIX}/flow-templates/patterns/"
    assert any(patterns_needle in n for n in names), (
        "wheel is missing flow-templates/patterns/; flow-routing templates absent on pipx"
    )
    route_needle = f"{WHEEL_DATA_PREFIX}/flow-templates/code-change.md"
    assert any(n.endswith(route_needle) for n in names), (
        "wheel is missing flow-templates route templates"
    )


def test_sdist_ships_templates(built_dists: tuple[Path, Path]) -> None:
    _, sdist = built_dists
    names = _sdist_names(sdist)
    assert any(n.endswith("templates/locales/en/.memory-bank/status.md") for n in names), (
        "sdist is missing templates/"
    )
    assert any(n.endswith("flow-templates/patterns/tournament.md") for n in names), (
        "sdist is missing flow-templates/"
    )
