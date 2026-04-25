"""Phase 2 Sprint 2 — `/mb plan` SDD-lite enhancement.

``scripts/mb-plan.sh`` accepts:

* ``--context <path>`` — explicit context file to link in the plan
* ``--sdd``           — strict mode: refuse if no context exists or if
  the EARS validator finds violations

Auto-detect: if no ``--context`` is given but ``<mb>/context/<topic>.md``
exists, link it automatically.

When a context is linked, the plan template gains a ``## Linked context``
section with a Markdown link to the file.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-plan.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "plans").mkdir()
    (mb / "plans" / "done").mkdir()
    (mb / "context").mkdir()
    return mb


def _run(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def _good_context(mb: Path, topic: str) -> Path:
    p = mb / "context" / f"{topic}.md"
    p.write_text(
        "# Context: " + topic + "\n\n"
        "## Functional Requirements (EARS)\n"
        "- **REQ-001** (ubiquitous): The system shall log every transaction.\n"
        "- **REQ-002** (event-driven): When the user logs in, "
        "the system shall record the timestamp.\n",
        encoding="utf-8",
    )
    return p


def _bad_context(mb: Path, topic: str) -> Path:
    p = mb / "context" / f"{topic}.md"
    p.write_text(
        "## Functional Requirements (EARS)\n"
        "- **REQ-009**: missing shall keyword here.\n",
        encoding="utf-8",
    )
    return p


# ──────────────────────────────────────────────────────────────────────


def test_explicit_context_links_into_plan(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    ctx = _good_context(mb, "foo")
    r = _run("feature", "foo", "--context", str(ctx), mb=mb)
    assert r.returncode == 0, r.stderr
    plan_path = Path(r.stdout.strip())
    text = plan_path.read_text(encoding="utf-8")
    assert "## Linked context" in text
    assert "context/foo.md" in text


def test_auto_detected_context_links_into_plan(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _good_context(mb, "foo")
    r = _run("feature", "foo", mb=mb)
    assert r.returncode == 0, r.stderr
    plan_path = Path(r.stdout.strip())
    text = plan_path.read_text(encoding="utf-8")
    assert "## Linked context" in text
    assert "context/foo.md" in text


def test_no_context_no_link_section(tmp_path: Path) -> None:
    """If there's no context file and no --sdd, plan is created without
    the Linked context section (backward compatibility)."""
    mb = _init_mb(tmp_path)
    r = _run("feature", "bar", mb=mb)
    assert r.returncode == 0, r.stderr
    plan_path = Path(r.stdout.strip())
    text = plan_path.read_text(encoding="utf-8")
    assert "## Linked context" not in text


def test_sdd_flag_blocks_without_context(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("feature", "missing", "--sdd", mb=mb)
    assert r.returncode == 1
    assert "context" in (r.stderr + r.stdout).lower()


def test_sdd_flag_blocks_with_invalid_ears(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _bad_context(mb, "foo")
    r = _run("feature", "foo", "--sdd", mb=mb)
    assert r.returncode == 1
    assert "ears" in (r.stderr + r.stdout).lower() or "REQ" in (r.stderr + r.stdout)


def test_sdd_flag_passes_with_valid_context(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _good_context(mb, "foo")
    r = _run("feature", "foo", "--sdd", mb=mb)
    assert r.returncode == 0, r.stderr
    plan_path = Path(r.stdout.strip())
    text = plan_path.read_text(encoding="utf-8")
    assert "## Linked context" in text
