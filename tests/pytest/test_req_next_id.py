"""Phase 2 Sprint 1 — REQ-NNN cross-spec ID generator tests.

``scripts/mb-req-next-id.sh`` scans a memory bank for any ``REQ-\\d{3,}``
identifiers across:

* ``.memory-bank/specs/*/requirements.md``
* ``.memory-bank/specs/*/design.md``
* ``.memory-bank/context/*.md``

It emits ``REQ-NNN`` (zero-padded to 3 digits) where ``NNN = max + 1``.
If no requirements exist, it emits ``REQ-001``. Numbering is monotonic
project-wide — gaps in the existing sequence are NOT filled.

With ``--spec <name>`` it switches to *per-spec-local* numbering: the scan is
scoped to that one spec's own namespace —

* ``.memory-bank/specs/<name>/requirements.md``
* ``.memory-bank/specs/<name>/design.md``
* ``.memory-bank/context/<name>.md``

so a brand-new spec starts at ``REQ-001`` regardless of other specs. This
matches the per-spec-local REQ-ID convention where the same ``REQ-NNN`` may
legitimately appear in different specs.
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


def _run(mb: Path, *flags: str) -> subprocess.CompletedProcess[str]:
    """Run with optional flags placed BEFORE the positional mb path."""
    return subprocess.run(
        ["bash", str(SCRIPT), *flags, str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def _run_raw(*argv: str) -> subprocess.CompletedProcess[str]:
    """Run with a fully-controlled argv (for ordering / usage-error tests)."""
    return subprocess.run(
        ["bash", str(SCRIPT), *argv],
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


# ── --spec <name>: per-spec-local numbering ───────────────────────────


def test_spec_flag_scopes_to_one_spec(tmp_path: Path) -> None:
    """--spec ignores REQs in OTHER specs; counts only within the named one."""
    mb = _init_mb(tmp_path)
    a = mb / "specs" / "spec_a"
    b = mb / "specs" / "spec_b"
    a.mkdir()
    b.mkdir()
    (a / "requirements.md").write_text(
        "- **REQ-001** ...\n- **REQ-002** ...\n",
        encoding="utf-8",
    )
    (b / "requirements.md").write_text("- **REQ-010** ...\n", encoding="utf-8")
    r = _run(mb, "--spec", "spec_a")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-003"  # spec_b's REQ-010 is out of scope


def test_spec_flag_unknown_spec_starts_at_req_001(tmp_path: Path) -> None:
    """A brand-new spec namespace starts at REQ-001, ignoring all other specs."""
    mb = _init_mb(tmp_path)
    other = mb / "specs" / "other"
    other.mkdir()
    (other / "requirements.md").write_text("- **REQ-042** ...\n", encoding="utf-8")
    r = _run(mb, "--spec", "brand-new")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-001"


def test_spec_flag_includes_matching_topic_context(tmp_path: Path) -> None:
    """context/<name>.md shares the spec's namespace (discuss → sdd handoff)."""
    mb = _init_mb(tmp_path)
    spec = mb / "specs" / "topic"
    spec.mkdir()
    (spec / "requirements.md").write_text("- **REQ-002** ...\n", encoding="utf-8")
    (mb / "context" / "topic.md").write_text("- **REQ-005** ...\n", encoding="utf-8")
    r = _run(mb, "--spec", "topic")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-006"  # max(2, 5) + 1


def test_spec_flag_ignores_unrelated_context(tmp_path: Path) -> None:
    """A different topic's context file does not bleed into the spec namespace."""
    mb = _init_mb(tmp_path)
    spec = mb / "specs" / "topic"
    spec.mkdir()
    (spec / "requirements.md").write_text("- **REQ-002** ...\n", encoding="utf-8")
    (mb / "context" / "other.md").write_text("- **REQ-099** ...\n", encoding="utf-8")
    r = _run(mb, "--spec", "topic")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-003"  # other.md is out of scope


def test_spec_flag_scans_design_md(tmp_path: Path) -> None:
    """REQ tokens in the spec's design.md count toward its max."""
    mb = _init_mb(tmp_path)
    spec = mb / "specs" / "topic"
    spec.mkdir()
    (spec / "requirements.md").write_text("- **REQ-001** ...\n", encoding="utf-8")
    (spec / "design.md").write_text("Binding references REQ-004 here.\n", encoding="utf-8")
    r = _run(mb, "--spec", "topic")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-005"


def test_spec_flag_equals_form(tmp_path: Path) -> None:
    """--spec=<name> is equivalent to --spec <name>."""
    mb = _init_mb(tmp_path)
    spec = mb / "specs" / "spec_a"
    spec.mkdir()
    (spec / "requirements.md").write_text("- **REQ-007** ...\n", encoding="utf-8")
    r = _run_raw("--spec=spec_a", str(mb))
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-008"


def test_spec_flag_after_path(tmp_path: Path) -> None:
    """The flag may follow the positional mb path."""
    mb = _init_mb(tmp_path)
    spec = mb / "specs" / "spec_a"
    spec.mkdir()
    (spec / "requirements.md").write_text("- **REQ-003** ...\n", encoding="utf-8")
    r = _run_raw(str(mb), "--spec", "spec_a")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-004"


def test_missing_spec_value_is_usage_error(tmp_path: Path) -> None:
    r = _run_raw("--spec")
    assert r.returncode == 2
    assert "spec" in r.stderr.lower()


def test_unknown_flag_is_usage_error(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run_raw("--bogus", str(mb))
    assert r.returncode == 2


def test_default_behavior_unchanged_without_flag(tmp_path: Path) -> None:
    """Sanity: no flag → global max+1 (spec_a + spec_b combined)."""
    mb = _init_mb(tmp_path)
    a = mb / "specs" / "spec_a"
    b = mb / "specs" / "spec_b"
    a.mkdir()
    b.mkdir()
    (a / "requirements.md").write_text("- **REQ-002** ...\n", encoding="utf-8")
    (b / "requirements.md").write_text("- **REQ-010** ...\n", encoding="utf-8")
    r = _run(mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "REQ-011"
