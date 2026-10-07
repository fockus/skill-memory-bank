"""Packaging contract tests for local/CI development dependencies."""

from __future__ import annotations

import tomllib
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PYPROJECT = REPO_ROOT / "pyproject.toml"


def test_dev_extra_installs_pipeline_yaml_runtime_dependency() -> None:
    data = tomllib.loads(PYPROJECT.read_text(encoding="utf-8"))
    optional_deps = data["project"]["optional-dependencies"]
    dev_deps = optional_deps["dev"]

    assert any(dep.lower().startswith("pyyaml") for dep in dev_deps)


def _bootstrap_packages(var: str) -> list[str]:
    """Packages the bootstrap venv installs, read from the one list the hook sources."""
    import subprocess

    lib = REPO_ROOT / "hooks" / "lib" / "venv-requirements.sh"
    out = subprocess.run(
        ["bash", "-c", f'. "$1" && printf "%s\\n" ${var}', "_", str(lib)],
        capture_output=True,
        text=True,
        check=False,  # a missing list reads as empty and fails the assertion
    ).stdout
    return out.split()


def test_bootstrap_venv_installs_exactly_the_codegraph_extra() -> None:
    """AGR-053: `pip install .[codegraph]` and the bootstrap venv carry the same graph deps."""
    data = tomllib.loads(PYPROJECT.read_text(encoding="utf-8"))
    codegraph = data["project"]["optional-dependencies"]["codegraph"]

    assert _bootstrap_packages("MB_VENV_CODEGRAPH_PKGS") == codegraph


def test_networkx_pinned_to_one_minor_everywhere() -> None:
    """I-219: louvain output differs across networkx minors — the dev venv and the
    bootstrap venv must build the same git-tracked clusters, so one minor is pinned."""
    import re

    data = tomllib.loads(PYPROJECT.read_text(encoding="utf-8"))
    extras = data["project"]["optional-dependencies"]
    specs = {d for extra in ("codegraph", "dev") for d in extras[extra] if d.startswith("networkx")}

    assert len(specs) == 1, specs
    m = re.fullmatch(r"networkx>=(\d+)\.(\d+),<(\d+)\.(\d+)", specs.pop())
    assert m and m[1] == m[3] and int(m[4]) == int(m[2]) + 1, m
