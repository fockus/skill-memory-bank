"""Stage 3 — ``scripts/mb-spec-tasks-migrate.sh`` contract tests.

Migrates legacy ``tasks.md`` files (``## N. Title`` headings without
``<!-- mb-task:N -->`` markers) to the new format used by mb-spec-validate.sh.

Contract
--------
* ``--dry-run`` (default): prints planned output to stdout; writes nothing.
* ``--apply``: writes migrated content atomically; creates ``.bak.<ts>`` backup first.
* Idempotent: if markers already present → exit 0, "already migrated" on stdout.
* Empty file: exit 0, clean message; no crash, no backup.

Exit codes:
    0 — success / dry-run / idempotent / empty
    1 — file not found or fundamental error
    2 — usage error

Stage 3 is RED until ``scripts/mb-spec-tasks-migrate.sh`` exists.
"""

from __future__ import annotations

import subprocess
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-spec-tasks-migrate.sh"

# ──────────────────────────────────────────────────────────────────────
# Shared fixtures / helpers
# ──────────────────────────────────────────────────────────────────────

_LEGACY_TWO_TASKS = """\
# Tasks: demo

## 1. Persist work items

**What to do:**
- Implement disk persistence.

**Testing:**
- Unit test for round-trip serialization.

**DoD:**
- [ ] disk write succeeds

## 2. Refresh checklist

**What to do:**
- Wire stage-completion event.

**Testing:**
- Integration test for checklist update.

**DoD:**
- [ ] checklist line flips
"""

_LEGACY_WITH_COVERS = """\
# Tasks: demo

## 1. Persist work items

**Covers:** REQ-007

**What to do:**
- Implement disk persistence.

**DoD:**
- [ ] disk write succeeds
"""

_ALREADY_MIGRATED = """\
# Tasks: demo

<!-- mb-task:1 -->
## Task 1: Persist work items

**Covers:** REQ-001

**What to do:**
- Implement disk persistence.

**DoD:**
- [ ] disk write succeeds
"""


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
    )


def _write_tasks(tmp_path: Path, content: str, name: str = "tasks.md") -> Path:
    p = tmp_path / name
    p.write_text(content, encoding="utf-8")
    return p


# ──────────────────────────────────────────────────────────────────────
# Tests
# ──────────────────────────────────────────────────────────────────────


def test_migrate_legacy_two_tasks_apply(tmp_path: Path) -> None:
    """Legacy ## N. Title headings → markers + reshaped headings after --apply."""
    tasks_file = _write_tasks(tmp_path, _LEGACY_TWO_TASKS)
    r = _run(str(tasks_file), "--apply")
    assert r.returncode == 0, f"stderr={r.stderr!r}"
    content = tasks_file.read_text(encoding="utf-8")
    assert "<!-- mb-task:1 -->" in content
    assert "<!-- mb-task:2 -->" in content
    assert "## Task 1: Persist work items" in content
    assert "## Task 2: Refresh checklist" in content


def test_migrate_preserves_body_content(tmp_path: Path) -> None:
    """Body lines (What to do, Testing, DoD) survive migration unchanged."""
    tasks_file = _write_tasks(tmp_path, _LEGACY_TWO_TASKS)
    _run(str(tasks_file), "--apply")
    content = tasks_file.read_text(encoding="utf-8")
    assert "**What to do:**" in content
    assert "- Implement disk persistence." in content
    assert "**Testing:**" in content
    assert "**DoD:**" in content
    assert "- [ ] disk write succeeds" in content
    assert "- [ ] checklist line flips" in content


def test_migrate_adds_covers_placeholder_when_missing(tmp_path: Path) -> None:
    """Task without **Covers:** gets REQ-NNN placeholder inserted."""
    tasks_file = _write_tasks(tmp_path, _LEGACY_TWO_TASKS)
    _run(str(tasks_file), "--apply")
    content = tasks_file.read_text(encoding="utf-8")
    # Both tasks in _LEGACY_TWO_TASKS have no Covers field
    assert "**Covers:** REQ-NNN" in content


def test_migrate_does_not_duplicate_covers_when_present(tmp_path: Path) -> None:
    """Task already has **Covers:** → no duplicate placeholder added."""
    tasks_file = _write_tasks(tmp_path, _LEGACY_WITH_COVERS)
    _run(str(tasks_file), "--apply")
    content = tasks_file.read_text(encoding="utf-8")
    # Exactly one Covers line
    covers_lines = [ln for ln in content.splitlines() if "**Covers:**" in ln]
    assert len(covers_lines) == 1, f"Expected 1 Covers line, got {len(covers_lines)}: {covers_lines}"
    assert "REQ-007" in covers_lines[0]


def test_migrate_creates_backup_on_apply(tmp_path: Path) -> None:
    """--apply writes a .bak.<unix-ts> file next to tasks.md."""
    tasks_file = _write_tasks(tmp_path, _LEGACY_TWO_TASKS)
    before = time.time()
    r = _run(str(tasks_file), "--apply")
    assert r.returncode == 0, f"stderr={r.stderr!r}"
    backups = sorted(tmp_path.glob("tasks.md.bak.*"))
    assert backups, "Expected at least one backup file"
    bak = backups[0]
    # Backup suffix is a unix timestamp; it should be a valid integer >= before
    suffix = bak.name.split(".bak.")[-1]
    assert suffix.isdigit(), f"Backup suffix is not a unix timestamp: {suffix}"
    assert int(suffix) >= int(before)
    # Backup content is original content
    assert bak.read_text(encoding="utf-8") == _LEGACY_TWO_TASKS


def test_migrate_dry_run_does_not_write(tmp_path: Path) -> None:
    """Default (dry-run) mode: file unchanged, no backup, stdout has plan."""
    tasks_file = _write_tasks(tmp_path, _LEGACY_TWO_TASKS)
    original_content = tasks_file.read_text(encoding="utf-8")
    r = _run(str(tasks_file))  # no flag → dry-run by default
    assert r.returncode == 0, f"stderr={r.stderr!r}"
    # File must be unchanged
    assert tasks_file.read_text(encoding="utf-8") == original_content
    # No backup created
    backups = list(tmp_path.glob("tasks.md.bak.*"))
    assert not backups, f"Unexpected backup created: {backups}"
    # stdout must contain dry-run output
    assert r.stdout.strip(), "Expected dry-run output on stdout"


def test_migrate_idempotent_on_already_migrated(tmp_path: Path) -> None:
    """File with existing markers → exit 0, 'already migrated', no changes."""
    tasks_file = _write_tasks(tmp_path, _ALREADY_MIGRATED)
    original_content = tasks_file.read_text(encoding="utf-8")
    r = _run(str(tasks_file), "--apply")
    assert r.returncode == 0, f"stderr={r.stderr!r}"
    assert "already migrated" in r.stdout.lower()
    # Content unchanged
    assert tasks_file.read_text(encoding="utf-8") == original_content
    # No backup
    backups = list(tmp_path.glob("tasks.md.bak.*"))
    assert not backups, f"Unexpected backup created on idempotent run: {backups}"


def test_migrate_handles_empty_tasks_file(tmp_path: Path) -> None:
    """Empty tasks.md → exit 0, no crash, no backup created."""
    tasks_file = _write_tasks(tmp_path, "")
    r = _run(str(tasks_file), "--apply")
    assert r.returncode == 0, f"stderr={r.stderr!r} stdout={r.stdout!r}"
    # No backup for empty file
    backups = list(tmp_path.glob("tasks.md.bak.*"))
    assert not backups, f"Unexpected backup for empty file: {backups}"


def test_migrate_explicit_dry_run_flag_does_not_write(tmp_path: Path) -> None:
    """Explicit --dry-run: same guarantees as default mode."""
    tasks_file = _write_tasks(tmp_path, _LEGACY_TWO_TASKS)
    original_content = tasks_file.read_text(encoding="utf-8")
    r = _run(str(tasks_file), "--dry-run")
    assert r.returncode == 0, f"stderr={r.stderr!r}"
    assert tasks_file.read_text(encoding="utf-8") == original_content
    backups = list(tmp_path.glob("tasks.md.bak.*"))
    assert not backups
