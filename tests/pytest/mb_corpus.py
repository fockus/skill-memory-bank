"""Shared reader for the /mb command text.

commands/mb.md holds only the router; each subcommand section lives in
references/mb/<sub>.md. Tests that assert on subcommand text read the union.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MB_MD = ROOT / "commands" / "mb.md"
MB_REFS = ROOT / "references" / "mb"


def read_mb_corpus() -> str:
    """Return commands/mb.md followed by every references/mb/*.md, sorted by name."""
    parts = [MB_MD.read_text(encoding="utf-8")]
    parts += [p.read_text(encoding="utf-8") for p in sorted(MB_REFS.glob("*.md"))]
    return "\n".join(parts)


def read_mb_router() -> str:
    """Return commands/mb.md alone (router table and always-loaded rules)."""
    return MB_MD.read_text(encoding="utf-8")
