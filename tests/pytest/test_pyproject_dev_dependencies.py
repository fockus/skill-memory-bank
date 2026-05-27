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
