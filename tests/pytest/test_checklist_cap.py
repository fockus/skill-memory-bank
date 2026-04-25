"""I-033 — enforce hard cap on `.memory-bank/checklist.md`.

Locks in the convention declared in the file's own header. If the cap is
breached, run `bash scripts/mb-checklist-prune.sh --apply --mb .memory-bank`
and (if anything still over) trim manually.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
CHECKLIST = REPO_ROOT / ".memory-bank" / "checklist.md"
HARD_CAP_LINES = 120


@pytest.mark.skipif(not CHECKLIST.exists(), reason="checklist.md not present in this checkout")
def test_repo_checklist_under_hard_cap() -> None:
    line_count = len(CHECKLIST.read_text(encoding="utf-8").splitlines())
    assert line_count <= HARD_CAP_LINES, (
        f"checklist.md has {line_count} lines, exceeds hard cap {HARD_CAP_LINES}. "
        "Run: bash scripts/mb-checklist-prune.sh --apply --mb .memory-bank"
    )
