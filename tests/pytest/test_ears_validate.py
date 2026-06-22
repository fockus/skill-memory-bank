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
    r = _run("- **REQ-003** (state-driven): While the door is open, the alarm shall stay active.\n")
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


def test_wrapped_requirement_with_shall_on_continuation_line_valid() -> None:
    """A requirement that wraps across physical lines (``shall`` on the second
    line) is still valid EARS — the validator must read the whole bullet.

    Before the wrap-aware fix the line-oriented check saw only the first line
    (``...the system``) and falsely reported a violation.
    """
    r = _run(
        "- **REQ-RS-001** (event-driven): When research yields candidates, the system\n"
        "  shall return three recommendations; when only two exist, it shall return two.\n"
    )
    assert r.returncode == 0, r.stderr


def test_wrapped_requirement_without_shall_anywhere_invalid() -> None:
    r = _run(
        "- **REQ-RS-099** (event-driven): When research yields candidates, the system\n"
        "  returns three recommendations without using the modal verb.\n"
    )
    assert r.returncode == 1
    assert "REQ-RS-099" in r.stderr


def test_wrapped_continuation_does_not_excuse_a_triggerless_requirement_line() -> None:
    """The EARS trigger keyword must be on the requirement line itself; only the
    ``shall`` clause may wrap. A title-only requirement whose continuation (e.g.
    acceptance notes) merely contains 'When … shall' must still be flagged.
    """
    content = (
        "- **REQ-001** This requirement is just a title placeholder.\n"
        "  Acceptance: When the user does X the system shall eventually do Y.\n"
    )
    r = _run(content)
    assert r.returncode == 1
    assert "REQ-001" in r.stderr


def test_wrap_stops_at_a_nested_sub_bullet_whose_shall_must_not_excuse() -> None:
    """A nested sub-bullet under a requirement is a boundary, not a continuation:
    its ``shall`` must not be absorbed to excuse a requirement line that lacks one.
    """
    content = (
        "- **REQ-001** (event-driven): When X happens, the system records it.\n"
        "  - a nested acceptance note that says the system shall do Y.\n"
    )
    r = _run(content)
    assert r.returncode == 1
    assert "REQ-001" in r.stderr


def test_wrapped_valid_followed_by_invalid_does_not_mask_the_invalid() -> None:
    """Aggregation must stop at the next REQ bullet so a preceding valid
    requirement's ``shall`` cannot satisfy the following invalid one."""
    content = (
        "- **REQ-100** (event-driven): When X happens, the system\n"
        "  shall do Y.\n"
        "- **REQ-101** (event-driven): When Z happens, the system records it.\n"
    )
    r = _run(content)
    assert r.returncode == 1
    assert "REQ-101" in r.stderr
    assert "REQ-100" not in r.stderr


def test_canonical_kiro_uppercase_ears_valid() -> None:
    """Canonical-Kiro uppercase EARS keywords (WHEN/IF/THE SYSTEM SHALL) are valid.

    The validator is case-insensitive on the trigger keyword and ``shall`` so the
    hybrid Kiro-cosmetic form (``- **REQ-NNN**: WHEN ... THE SYSTEM SHALL ...``)
    passes alongside the lowercase form.
    """
    content = (
        "- **REQ-001**: THE SYSTEM SHALL log every transaction.\n"
        "- **REQ-002**: WHEN the user logs in THE SYSTEM SHALL record the timestamp.\n"
        "- **REQ-003**: WHILE the door is open THE SYSTEM SHALL keep the alarm active.\n"
        "- **REQ-004**: WHERE biometric auth is enabled THE SYSTEM SHALL require a fingerprint.\n"
        "- **REQ-005**: IF the connection times out THEN THE SYSTEM SHALL retry up to 3 times.\n"
    )
    r = _run(content)
    assert r.returncode == 0, r.stderr


def test_uppercase_missing_shall_still_invalid() -> None:
    """Case-insensitivity widens acceptance but does not excuse a missing modal verb."""
    r = _run("- **REQ-009**: THE SYSTEM WILL log every transaction.\n")
    assert r.returncode == 1
    assert "REQ-009" in r.stderr


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
