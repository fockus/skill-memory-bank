"""Phase 2 Sprint 2 — `/mb sdd` Kiro-style spec triple.

``scripts/mb-sdd.sh <topic> [--force] [mb_path]`` creates the directory
``<mb>/specs/<topic>/`` with three files:

* ``requirements.md`` — EARS-only REQ list (copied from
  ``context/<topic>.md`` if present)
* ``design.md`` — architecture, interfaces, decisions, risks
* ``tasks.md`` — numbered task list with checkboxes

Idempotency guard: re-running on an existing spec exits 1; ``--force``
overwrites.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-sdd.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "specs").mkdir()
    (mb / "context").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text("# Roadmap\n", encoding="utf-8")
    return mb


def _run(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


# ──────────────────────────────────────────────────────────────────────


def test_sdd_creates_three_files(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("foo", mb=mb)
    assert r.returncode == 0, r.stderr
    spec = mb / "specs" / "foo"
    assert (spec / "requirements.md").is_file()
    assert (spec / "design.md").is_file()
    assert (spec / "tasks.md").is_file()


def test_sdd_requirements_template_has_ears_section(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("foo", mb=mb)
    assert r.returncode == 0
    text = (mb / "specs" / "foo" / "requirements.md").read_text(encoding="utf-8")
    # Should mention EARS and at least the heading
    assert "Requirements" in text
    assert "EARS" in text


def test_sdd_design_template_has_architecture_and_interfaces(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("foo", mb=mb)
    assert r.returncode == 0
    text = (mb / "specs" / "foo" / "design.md").read_text(encoding="utf-8")
    for section in ("Architecture", "Interfaces", "Decisions"):
        assert section in text, f"design.md missing section: {section}"


def test_sdd_tasks_template_has_checkbox_items(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("foo", mb=mb)
    assert r.returncode == 0
    text = (mb / "specs" / "foo" / "tasks.md").read_text(encoding="utf-8")
    assert "- [ ]" in text, "tasks.md must contain unchecked checkbox items"


def test_sdd_copies_ears_from_context(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    (mb / "context" / "foo.md").write_text(
        "---\ntopic: foo\nstatus: ready\n---\n\n"
        "# Context: foo\n\n"
        "## Purpose & Users\n\nstuff\n\n"
        "## Functional Requirements (EARS)\n\n"
        "- **REQ-007** (ubiquitous): The system shall do X.\n"
        "- **REQ-008** (event-driven): When Y, the system shall Z.\n\n"
        "## Non-Functional Requirements\n\n- NFR-1\n",
        encoding="utf-8",
    )
    r = _run("foo", mb=mb)
    assert r.returncode == 0, r.stderr
    text = (mb / "specs" / "foo" / "requirements.md").read_text(encoding="utf-8")
    assert "REQ-007" in text
    assert "REQ-008" in text
    # Non-EARS sections should NOT have leaked over
    assert "NFR-1" not in text
    assert "Purpose & Users" not in text


def test_sdd_idempotency_guard_blocks_on_existing(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("foo", mb=mb).returncode == 0
    r = _run("foo", mb=mb)
    assert r.returncode == 1
    assert "exists" in (r.stderr + r.stdout).lower() or "force" in (r.stderr + r.stdout).lower()


def test_sdd_force_overwrites(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("foo", mb=mb).returncode == 0
    # Mutate one of the files
    req = mb / "specs" / "foo" / "requirements.md"
    req.write_text("# overridden by user\n", encoding="utf-8")
    r = _run("--force", "foo", mb=mb)
    assert r.returncode == 0, r.stderr
    text = req.read_text(encoding="utf-8")
    assert "overridden by user" not in text
    assert "Requirements" in text
