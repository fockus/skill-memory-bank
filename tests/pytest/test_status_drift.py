"""Drift contract tests for `.memory-bank/status.md`.

Locks in the invariant that status.md numbers match `./VERSION`, that
"Open backlog" entries actually exist in backlog.md, and that the file
does not contain stale v3-era VERSION strings or "Gate v3.0 — in progress"
breadcrumbs.

Antidote to the "single-source rule + propagation gap" lesson: status.md
is the dashboard, drift here is the loudest contradiction in the project.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
STATUS = REPO_ROOT / ".memory-bank" / "status.md"
BACKLOG = REPO_ROOT / ".memory-bank" / "backlog.md"
VERSION_FILE = REPO_ROOT / "VERSION"


def _status_text() -> str:
    return STATUS.read_text(encoding="utf-8")


def _version() -> str:
    return VERSION_FILE.read_text(encoding="utf-8").strip()


@pytest.mark.skipif(not STATUS.exists(), reason="status.md not present")
def test_status_md_version_matches_version_file() -> None:
    """Every `VERSION: X` line in status.md must equal `./VERSION`."""
    text = _status_text()
    actual_version = _version()
    # Match `VERSION: <semver>` — bold-wrapped or plain
    declared = re.findall(r"VERSION:\s*\*?\*?([\d.]+(?:[-a-z\d.]+)?)", text)
    assert declared, "status.md must declare VERSION in '## Ключевые метрики' section"
    mismatched = [v for v in declared if v != actual_version]
    assert not mismatched, (
        f"status.md declares VERSION {mismatched}, but ./VERSION = {actual_version!r}. "
        "Update '## Ключевые метрики' section."
    )


@pytest.mark.skipif(not STATUS.exists(), reason="status.md not present")
def test_status_md_no_obsolete_v3_in_progress_markers() -> None:
    """No 'Gate v3.0 — in progress' or '(в работе)' v3 markers anywhere."""
    text = _status_text()
    obsolete_patterns = [
        r"Gate v3\.0 — in progress",
        r"v3\.0 final release.*⬜",
        r"v2\.2 → v3\.0-rc1.*\(в работе\)",
    ]
    hits = []
    for pattern in obsolete_patterns:
        if re.search(pattern, text):
            hits.append(pattern)
    assert not hits, (
        f"status.md still contains obsolete v3-era markers: {hits}. "
        "Move historic gates into an '## Архив' section or delete them outright."
    )


@pytest.mark.skipif(
    not (STATUS.exists() and BACKLOG.exists()),
    reason="status.md or backlog.md not present",
)
def test_status_md_open_backlog_consistent_with_backlog_md() -> None:
    """Each I-NNN under '## Open backlog' must be OPEN in backlog.md."""
    text = _status_text()
    # Find the Open backlog section (if it exists) and extract I-NNN ids
    section_match = re.search(
        r"##\s+Open backlog\s*\n(.*?)(?=\n##\s|\Z)",
        text,
        re.DOTALL,
    )
    if not section_match:
        pytest.skip("no '## Open backlog' section in status.md")
    section = section_match.group(1)
    referenced_ids = set(re.findall(r"\bI-(\d{3})\b", section))
    if not referenced_ids:
        pytest.skip("Open backlog section is empty")

    backlog_text = BACKLOG.read_text(encoding="utf-8")
    closed_ids: set[str] = set()
    for m in re.finditer(r"###\s+I-(\d{3}).*?\[(?:[^\]]+)\]", backlog_text):
        header_line = m.group(0)
        if re.search(r"\b(DONE|REJECTED|CLOSED|DEFERRED)\b", header_line):
            closed_ids.add(m.group(1))

    inconsistent = sorted(referenced_ids & closed_ids)
    assert not inconsistent, (
        f"status.md '## Open backlog' lists I-{inconsistent} as open, "
        f"but backlog.md marks them DONE/REJECTED/CLOSED."
    )
