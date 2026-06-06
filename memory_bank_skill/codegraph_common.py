"""Shared primitives for the Memory Bank code-graph extractors.

Tiny, dependency-free helpers used by both the Python (`codegraph_python`) and
tree-sitter (`codegraph_treesitter`) extractors. Kept in one place so the two
extractor modules never import each other (no cycles).
"""

from __future__ import annotations

import hashlib
from pathlib import Path


def sha256(text: str) -> str:
    """Hex SHA-256 of ``text`` (UTF-8). Used for the incremental per-file cache."""
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def rel(path: Path, root: Path) -> str:
    """POSIX path of ``path`` relative to ``root``; absolute string when outside."""
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)
