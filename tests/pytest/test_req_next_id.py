"""Phase 2 Sprint 1 — REQ-NNN cross-spec ID generator tests.

``scripts/mb-req-next-id.sh`` scans a memory bank for any ``REQ-\\d{3,}``
identifiers across:

* ``.memory-bank/specs/*/requirements.md``
* ``.memory-bank/specs/*/design.md``
* ``.memory-bank/context/*.md``

It emits ``REQ-NNN`` (zero-padded to 3 digits) where ``NNN = max + 1``.
If no requirements exist, it emits ``REQ-001``. Numbering is monotonic
project-wide — gaps in the existing sequence are NOT filled.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-req-next-id.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "specs").mkdir()
    (mb / "context").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text("# Roadmap\n", encoding="utf-8")
    return mb


def _run(mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


# ──────────────────────────────────────────────────────────────────────


def test_empty_bank_returns_req_001(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run(mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-001"


def test_single_spec_with_two_reqs_returns_req_003(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    spec = mb / "specs" / "feature-a"
    spec.mkdir()
    (spec / "requirements.md").write_text(
        "- **REQ-001** ...\n- **REQ-002** ...\n",
        encoding="utf-8",
    )
    r = _run(mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-003"


def test_two_specs_max_across_both(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    a = mb / "specs" / "spec_a"
    b = mb / "specs" / "spec_b"
    a.mkdir()
    b.mkdir()
    (a / "requirements.md").write_text(
        "- **REQ-001** ...\n- **REQ-002** ...\n- **REQ-005** ...\n",
        encoding="utf-8",
    )
    (b / "requirements.md").write_text(
        "- **REQ-006** ...\n- **REQ-008** ...\n",
        encoding="utf-8",
    )
    r = _run(mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-009"


def test_context_only_returns_max_plus_one(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    (mb / "context" / "topic.md").write_text(
        "## Functional Requirements\n"
        "- **REQ-001** The system shall ...\n"
        "- **REQ-002** When X, the system shall ...\n"
        "- **REQ-003** ...\n",
        encoding="utf-8",
    )
    r = _run(mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-004"


def test_mixed_specs_and_context_returns_global_max_plus_one(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    spec = mb / "specs" / "feature-a"
    spec.mkdir()
    (spec / "requirements.md").write_text(
        "- **REQ-001** ...\n- **REQ-002** ...\n",
        encoding="utf-8",
    )
    (mb / "context" / "topic.md").write_text(
        "- **REQ-007** The system shall ...\n",
        encoding="utf-8",
    )
    r = _run(mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-008"


def test_gaps_are_not_filled(tmp_path: Path) -> None:
    """If REQ-001 and REQ-005 exist (no 002–004), next is REQ-006, not REQ-002."""
    mb = _init_mb(tmp_path)
    (mb / "context" / "topic.md").write_text(
        "- **REQ-001** ...\n- **REQ-005** ...\n",
        encoding="utf-8",
    )
    r = _run(mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-006"
