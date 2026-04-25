"""Phase 2 Sprint 1 — EARS validator tests.

The validator (``scripts/mb-ears-validate.sh``) checks that every
``- **REQ-NNN** ...`` line in the input matches one of the five EARS
patterns:

    Ubiquitous:        The <system> shall <response>
    Event-driven:      When <trigger>, the <system> shall <response>
    State-driven:      While <state>, the <system> shall <response>
    Optional feature:  Where <feature>, the <system> shall <response>
    Unwanted:          If <trigger>, then the <system> shall <response>

Lines that are not ``- **REQ-NNN** ...`` items are ignored — the
validator targets requirement bullets only.

Exit codes: 0 = all REQ lines valid (or no REQ lines at all),
1 = at least one violation, 2 = usage error.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-ears-validate.sh"


def _run(content: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), "-"],
        input=content,
        capture_output=True,
        text=True,
        check=False,
    )


# ──────────────────────────────────────────────────────────────────────
# Valid patterns — one per EARS type
# ──────────────────────────────────────────────────────────────────────


def test_ubiquitous_valid() -> None:
    r = _run("- **REQ-001** (ubiquitous): The system shall log every transaction.\n")
    assert r.returncode == 0, r.stderr


def test_event_driven_valid() -> None:
    r = _run(
        "- **REQ-002** (event-driven): When the user logs in, "
        "the system shall record the timestamp.\n"
    )
    assert r.returncode == 0, r.stderr


def test_state_driven_valid() -> None:
    r = _run(
        "- **REQ-003** (state-driven): While the door is open, "
        "the alarm shall stay active.\n"
    )
    assert r.returncode == 0, r.stderr


def test_optional_feature_valid() -> None:
    r = _run(
        "- **REQ-004** (optional): Where biometric auth is enabled, "
        "the system shall require a fingerprint.\n"
    )
    assert r.returncode == 0, r.stderr


def test_unwanted_valid() -> None:
    r = _run(
        "- **REQ-005** (unwanted): If the connection times out, "
        "then the system shall retry up to 3 times.\n"
    )
    assert r.returncode == 0, r.stderr


# ──────────────────────────────────────────────────────────────────────
# Invalid patterns
# ──────────────────────────────────────────────────────────────────────


def test_req_without_shall_invalid() -> None:
    r = _run("- **REQ-010**: The system will log every transaction.\n")
    assert r.returncode == 1
    assert "REQ-010" in r.stderr


def test_req_without_trigger_keyword_invalid() -> None:
    # Lacks any of the 5 EARS opening keywords (The/When/While/Where/If)
    r = _run("- **REQ-011**: A transaction shall be logged.\n")
    assert r.returncode == 1
    assert "REQ-011" in r.stderr


def test_req_with_broken_format_invalid() -> None:
    # Has REQ-NNN but no shall at all
    r = _run("- **REQ-012**: When the user logs in, record the timestamp.\n")
    assert r.returncode == 1
    assert "REQ-012" in r.stderr


def test_garbage_with_req_marker_invalid() -> None:
    r = _run("- **REQ-013**: lorem ipsum dolor sit amet\n")
    assert r.returncode == 1
    assert "REQ-013" in r.stderr


# ──────────────────────────────────────────────────────────────────────
# Edge cases
# ──────────────────────────────────────────────────────────────────────


def test_empty_input_passes() -> None:
    r = _run("")
    assert r.returncode == 0, r.stderr


def test_no_req_lines_only_prose_passes() -> None:
    """Non-REQ lines must be ignored — only `- **REQ-NNN**` bullets are validated."""
    r = _run(
        "# Some heading\n\n"
        "Free-text paragraph that mentions the system but is not a REQ.\n"
        "- A bullet point that is not a REQ.\n"
    )
    assert r.returncode == 0, r.stderr


def test_mixed_3_valid_1_invalid_reports_only_invalid() -> None:
    content = (
        "- **REQ-020** (ubiquitous): The system shall persist state.\n"
        "- **REQ-021** (event): When X, the system shall Y.\n"
        "- **REQ-022**: missing shall keyword here.\n"
        "- **REQ-023** (unwanted): If err, then the system shall retry.\n"
    )
    r = _run(content)
    assert r.returncode == 1
    # Only REQ-022 should be flagged
    assert "REQ-022" in r.stderr
    assert "REQ-020" not in r.stderr
    assert "REQ-021" not in r.stderr
    assert "REQ-023" not in r.stderr


def test_usage_error_exits_2(tmp_path: Path) -> None:
    """File argument that does not exist → exit 2 (usage error)."""
    bogus = tmp_path / "does-not-exist.md"
    r = subprocess.run(
        ["bash", str(SCRIPT), str(bogus)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert r.returncode == 2
