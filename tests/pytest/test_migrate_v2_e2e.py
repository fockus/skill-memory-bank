"""End-to-end contract test for the v1 → v2 migration.

This is a Contract-First test: it asserts the public contract of
`scripts/mb-migrate-v2.sh` as a whole (CLI flags + stdout/stderr +
side effects + idempotency), not the internal mechanics. If this test
passes, the script is safe to ship to end users.
"""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-migrate-v2.sh"
FIXTURE = REPO_ROOT / "tests" / "pytest" / "fixtures" / "mb_v1_layout"


def _run(mb: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["bash", str(SCRIPT), *args, str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.fixture
def fresh_v1(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    shutil.copytree(FIXTURE, mb)
    return mb


def test_e2e_contract_fresh_install(fresh_v1: Path) -> None:
    """Contract: on a clean v1 install, --dry-run describes 4 renames,
    --apply performs them, a second --apply is a no-op, and the final
    layout has exactly the v2 core files + a timestamped backup of the
    originals.
    """
    # Step 1 — dry-run MUST NOT mutate filesystem.
    before = {p.name for p in fresh_v1.iterdir()}
    dry = _run(fresh_v1, "--dry-run")
    assert dry.returncode == 0, dry.stderr
    assert "STATUS.md → status.md" in dry.stdout
    assert "BACKLOG.md → backlog.md" in dry.stdout
    assert "RESEARCH.md → research.md" in dry.stdout
    assert "plan.md → roadmap.md" in dry.stdout
    assert "no files changed" in dry.stdout
    after_dry = {p.name for p in fresh_v1.iterdir()}
    assert before == after_dry, f"dry-run mutated filesystem: {after_dry - before}"

    # Step 2 — apply.
    apply = _run(fresh_v1, "--apply")
    assert apply.returncode == 0, apply.stderr
    for line in (
        "[detected] v1 layout",
        "[backup] saved to",
        "[renamed] STATUS.md → status.md",
        "[renamed] BACKLOG.md → backlog.md",
        "[renamed] RESEARCH.md → research.md",
        "[renamed] plan.md → roadmap.md",
        "[transformed]",
        "[ok] migration complete",
    ):
        assert line in apply.stdout, f"missing expected line: {line!r}\n{apply.stdout}"

    # Step 3 — v2 layout is correct; v1 names are gone.
    files = {p.name for p in fresh_v1.iterdir() if p.is_file()}
    assert {"status.md", "backlog.md", "research.md", "roadmap.md"} <= files
    assert "STATUS.md" not in files
    assert "BACKLOG.md" not in files
    assert "RESEARCH.md" not in files
    assert "plan.md" not in files

    # Step 4 — roadmap.md has the new shape and preserves the legacy block.
    roadmap = (fresh_v1 / "roadmap.md").read_text(encoding="utf-8")
    assert roadmap.startswith("# Roadmap")
    for section in (
        "## Now (in progress)",
        "## Next (strict order",
        "## Parallel-safe",
        "## Paused / Archived",
        "## Linked Specs",
        "## See also",
        "### Legacy content (preserved from the previous plan-file format",
    ):
        assert section in roadmap, f"missing section: {section!r}"
    # Legacy active-plan block carried into Now.
    assert "<!-- mb-active-plan -->" in roadmap
    # Legacy "## Priorities" / "## Direction" preserved under Legacy content.
    assert "## Priorities" in roadmap
    assert "## Direction" in roadmap

    # Step 5 — exactly one backup exists with all four originals.
    backups = sorted(fresh_v1.glob(".migration-backup-*"))
    assert len(backups) == 1, f"expected 1 backup, got {backups}"
    backup_files = {p.name for p in backups[0].iterdir() if p.is_file()}
    assert {"STATUS.md", "BACKLOG.md", "RESEARCH.md", "plan.md"} <= backup_files
    # Backup's STATUS.md still references old names (proves fixup skipped it).
    backup_status = (backups[0] / "STATUS.md").read_text(encoding="utf-8")
    assert "plan.md" in backup_status
    assert "BACKLOG.md" in backup_status

    # Step 6 — cross-references in non-backup .md files rewritten.
    note = (fresh_v1 / "notes" / "2026-04-15_12-00_example.md").read_text(encoding="utf-8")
    assert "STATUS.md" not in note
    assert "status.md" in note
    nested_plan = (fresh_v1 / "plans" / "2026-04-20_feature_example.md").read_text(encoding="utf-8")
    assert "BACKLOG.md" not in nested_plan
    assert "plan.md" not in nested_plan
    assert "roadmap.md" in nested_plan
    assert "backlog.md" in nested_plan

    # Step 7 — idempotency. Second --apply is a no-op.
    rerun = _run(fresh_v1, "--apply")
    assert rerun.returncode == 0, rerun.stderr
    assert "no v1 files detected" in rerun.stdout
    backups_after = sorted(fresh_v1.glob(".migration-backup-*"))
    assert len(backups_after) == 1, "second run should not create a second backup"
    roadmap_after = (fresh_v1 / "roadmap.md").read_text(encoding="utf-8")
    assert roadmap == roadmap_after, "second run mutated roadmap.md"


def test_e2e_contract_unknown_flag_exits_nonzero(fresh_v1: Path) -> None:
    """Contract: unknown flag exits 1 with usage on stderr."""
    result = _run(fresh_v1, "--frobnicate")
    assert result.returncode == 1
    assert "unknown flag" in result.stderr
    assert "Usage:" in result.stderr


def test_e2e_contract_missing_mb_exits_nonzero(tmp_path: Path) -> None:
    """Contract: missing .memory-bank dir exits 1 with clear error."""
    nonexistent = tmp_path / "does-not-exist"
    result = subprocess.run(
        ["bash", str(SCRIPT), "--dry-run", str(nonexistent)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
    assert ".memory-bank not found" in result.stderr
