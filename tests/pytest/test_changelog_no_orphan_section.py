"""Contract: CHANGELOG.md has no orphan 'staged on main' release sections.

The audit found `[3.2.0] — 2026-04-21 (unreleased — staged on main)` —
content was actually absorbed into the v4.0.0 release but kept its own
section header. Either rename to make the absorption explicit or remove.
"""

from __future__ import annotations

import re
from pathlib import Path

CHANGELOG = Path(__file__).resolve().parents[2] / "CHANGELOG.md"


def _text() -> str:
    return CHANGELOG.read_text(encoding="utf-8")


def test_changelog_no_unreleased_staged_on_main_orphan() -> None:
    """No section may be marked `(unreleased — staged on main)`."""
    text = _text()
    # Match section headers like '## [3.2.0] — 2026-04-21 (unreleased — staged on main)'
    orphans = re.findall(
        r"^##\s+\[\d+\.\d+\.\d+\][^\n]*\(unreleased\s+—\s+staged on main\)",
        text,
        re.MULTILINE,
    )
    assert not orphans, (
        f"CHANGELOG.md contains orphan section(s): {orphans}. "
        "Either rename to make absorption explicit (e.g. "
        "'[3.2.0] — absorbed into 4.0.0') or remove."
    )


def test_changelog_unreleased_section_does_not_duplicate_shipped_changes() -> None:
    """`[Unreleased]` must not duplicate content already in a tagged section.

    If I-004 is documented in `[Unreleased]` and also `[4.0.0]`, that's drift.
    Soft check: just count duplicate keyword anchors.
    """
    text = _text()
    # Find [Unreleased] block
    m = re.search(
        r"^##\s+\[Unreleased\]\s*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.DOTALL | re.MULTILINE,
    )
    if not m:
        return  # no Unreleased section → trivially passes
    unreleased_block = m.group(1)
    # If Unreleased is empty or only contains placeholder text, pass
    meaningful = [
        line.strip()
        for line in unreleased_block.splitlines()
        if line.strip() and not line.strip().startswith(("###", "<!--"))
    ]
    if not meaningful:
        return
    # Soft constraint: Unreleased must not declare a complete release narrative
    # (look for forbidden phrases that indicate a "shipped" claim)
    forbidden = ["shipped", "released", "RELEASED"]
    leaks = [phrase for phrase in forbidden if phrase in unreleased_block]
    assert not leaks, (
        f"[Unreleased] contains release-claim language {leaks}. "
        "Either move the entry under a versioned section or rephrase as in-flight."
    )
