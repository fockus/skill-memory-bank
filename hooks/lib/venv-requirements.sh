# shellcheck shell=bash
# Packages the bootstrap venv carries (AGR-053) — the one list, sourced by
# hooks/mb-semantic-bootstrap.sh. The code-graph half equals pyproject.toml's
# [project.optional-dependencies].codegraph; tests/pytest/test_pyproject_dev_dependencies.py
# holds the two together.
# shellcheck disable=SC2034 # consumed by the sourcing script
MB_VENV_SEMANTIC_PKGS="fastembed numpy"
# shellcheck disable=SC2034
MB_VENV_CODEGRAPH_PKGS="tree-sitter>=0.21 tree-sitter-python>=0.21 tree-sitter-go>=0.21 tree-sitter-javascript>=0.21 tree-sitter-typescript>=0.21 tree-sitter-rust>=0.21 tree-sitter-java>=0.21 networkx>=3.6,<3.7"
