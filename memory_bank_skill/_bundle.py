"""Resolve paths to bundled skill files (install.sh, hooks/, adapters/, etc.).

Priority order:
1. $MB_SKILL_BUNDLE env override (for dev/testing)
2. Installed package data via sys.prefix/share/memory-bank-skill/
3. Development layout (running from repo checkout: ../install.sh relative to this file)
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def _candidate_paths() -> list[Path]:
    paths: list[Path] = []

    override = os.environ.get("MB_SKILL_BUNDLE")
    if override:
        paths.append(Path(override))

    # Installed via pipx / pip — shared-data goes to <prefix>/share/memory-bank-skill/
    prefix_share = Path(sys.prefix) / "share" / "memory-bank-skill"
    paths.append(prefix_share)

    # Dev layout: repo root is parent of memory_bank_skill/
    dev_root = Path(__file__).resolve().parent.parent
    paths.append(dev_root)

    return paths


def find_bundle_root() -> Path:
    """Return directory containing install.sh + skill resources, or raise."""
    for p in _candidate_paths():
        if (p / "install.sh").is_file():
            return p
    searched = "\n  ".join(str(p) for p in _candidate_paths())
    raise FileNotFoundError(
        f"Cannot locate memory-bank-skill bundle. Searched:\n  {searched}\n"
        "Set MB_SKILL_BUNDLE env to point at the skill directory."
    )


def bundle_file(relative: str) -> Path:
    """Get absolute path to a bundled file like 'install.sh' or 'adapters/cursor.sh'."""
    return find_bundle_root() / relative
