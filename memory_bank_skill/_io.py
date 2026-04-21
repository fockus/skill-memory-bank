"""Shared file IO helpers for memory-bank-skill."""

from __future__ import annotations

import os
import tempfile
from pathlib import Path


def atomic_write(path: str | Path, content: str, *, encoding: str = "utf-8") -> None:
    """Write text atomically with rollback on failure."""
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        dir=str(target.parent),
        prefix=f".{target.name}.",
        suffix=".tmp",
    )
    try:
        with os.fdopen(fd, "w", encoding=encoding) as handle:
            handle.write(content)
        os.replace(tmp_path, target)
    except BaseException:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise
