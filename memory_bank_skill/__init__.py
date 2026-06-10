"""memory-bank-skill — Universal long-term project memory for AI coding clients."""

from __future__ import annotations

from importlib.metadata import PackageNotFoundError
from importlib.metadata import version as pkg_version
from pathlib import Path


def _read_version() -> str:
    """Resolve version: source checkout reads VERSION; installed wheel uses metadata."""
    version_file = Path(__file__).resolve().parent.parent / "VERSION"
    if version_file.is_file():
        text = version_file.read_text(encoding="utf-8").strip()
        if text:
            return text
    try:
        return pkg_version("memory-bank-skill")
    except PackageNotFoundError:
        return "0.0.0"


__version__ = _read_version()
