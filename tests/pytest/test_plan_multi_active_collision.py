"""Sprint 3 — I-028 multi-active plan checklist collision tests.

Two plans with identical stage headings (e.g. both have ``## Task 1: Setup``)
must not interfere via ``checklist.md``.

Contract (post-Sprint-3):
  * ``mb-plan-sync.sh`` writes a ``<!-- mb-plan:<basename> -->`` marker line
    immediately before each new heading section it appends to ``checklist.md``.
  * Idempotency is keyed on the (marker, heading) pair — re-syncing the same
    plan does NOT duplicate.
  * ``mb-plan-done.sh`` removes ONLY sections preceded by the closing plan's
    marker; sections owned by other plans (including pre-existing legacy
    sections without any marker) survive.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SYNC_SCRIPT = REPO_ROOT / "scripts" / "mb-plan-sync.sh"
DONE_SCRIPT = REPO_ROOT / "scripts" / "mb-plan-done.sh"


# ──────────────────────────────────────────────────────────────────────
# Fixture helpers
# ──────────────────────────────────────────────────────────────────────


def _init_mb(tmp_path: Path) -> Path:
    """Create the minimum core layout needed by sync/done scripts."""
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n## Active plans\n\n"
        "<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n",
        encoding="utf-8",
    )
    (mb / "status.md").write_text(
        "# Status\n\n## Active plans\n\n"
        "<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n\n"
        "## Recently done\n\n"
        "<!-- mb-recent-done -->\n<!-- /mb-recent-done -->\n",
        encoding="utf-8",
    )
    (mb / "backlog.md").write_text(
        "# Backlog\n\n## Ideas\n\n## ADR\n", encoding="utf-8"
    )
    (mb / "plans").mkdir()
    (mb / "plans" / "done").mkdir()
    return mb


def _make_plan(mb: Path, basename: str, title: str, stage_name: str) -> Path:
    """Write a tiny one-stage plan that will produce ``## Stage 1: <stage_name>``."""
    plan_path = mb / "plans" / basename
    plan_path.write_text(
        f"# Plan: refactor — {title}\n\n"
        "## Stages\n\n"
        "<!-- mb-stage:1 -->\n"
        f"### Stage 1: {stage_name}\n\n"
        "content\n",
        encoding="utf-8",
    )
    return plan_path


def _run(script: Path, plan: Path, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(script), str(plan), str(mb)],
        capture_output=True,
        text=True,
        check=False,
    )


def _count_substring(haystack: str, needle: str) -> int:
    return haystack.count(needle)


# ──────────────────────────────────────────────────────────────────────
# Tests
# ──────────────────────────────────────────────────────────────────────


def test_two_plans_with_identical_heading_get_separate_marker_sections(
    tmp_path: Path,
) -> None:
    """Sync of two plans with the SAME ``## Stage 1: Setup`` produces two
    independent checklist sections, each preceded by its own
    ``<!-- mb-plan:<basename> -->`` marker."""
    mb = _init_mb(tmp_path)
    plan_a = _make_plan(mb, "2026-04-25_refactor_a.md", "alpha", "Setup")
    plan_b = _make_plan(mb, "2026-04-25_refactor_b.md", "beta", "Setup")

    r_a = _run(SYNC_SCRIPT, plan_a, mb)
    r_b = _run(SYNC_SCRIPT, plan_b, mb)
    assert r_a.returncode == 0, r_a.stderr
    assert r_b.returncode == 0, r_b.stderr

    checklist = (mb / "checklist.md").read_text(encoding="utf-8")

    # 1. There must be exactly TWO `## Stage 1: Setup` sections (one per plan)
    assert _count_substring(checklist, "## Stage 1: Setup") == 2, (
        "Expected two independent Stage-1 sections (one per plan), got:\n"
        f"{checklist}"
    )

    # 2. Each plan's marker must be present once
    assert "<!-- mb-plan:2026-04-25_refactor_a.md -->" in checklist
    assert "<!-- mb-plan:2026-04-25_refactor_b.md -->" in checklist


def test_close_one_plan_preserves_other_plans_section(tmp_path: Path) -> None:
    """Closing plan A must NOT remove plan B's checklist section, even when
    both plans defined identical stage headings."""
    mb = _init_mb(tmp_path)
    plan_a = _make_plan(mb, "2026-04-25_refactor_a.md", "alpha", "Setup")
    plan_b = _make_plan(mb, "2026-04-25_refactor_b.md", "beta", "Setup")

    assert _run(SYNC_SCRIPT, plan_a, mb).returncode == 0
    assert _run(SYNC_SCRIPT, plan_b, mb).returncode == 0
    assert _run(DONE_SCRIPT, plan_a, mb).returncode == 0

    checklist = (mb / "checklist.md").read_text(encoding="utf-8")

    # Plan B's section must survive
    assert "<!-- mb-plan:2026-04-25_refactor_b.md -->" in checklist, (
        "Plan B marker disappeared after closing plan A:\n" + checklist
    )
    assert "## Stage 1: Setup" in checklist, (
        "Plan B's Stage 1 heading vanished:\n" + checklist
    )

    # Plan A's marker must be gone
    assert "<!-- mb-plan:2026-04-25_refactor_a.md -->" not in checklist


def test_resync_same_plan_is_idempotent(tmp_path: Path) -> None:
    """Re-running sync on the same plan must not duplicate marker sections."""
    mb = _init_mb(tmp_path)
    plan = _make_plan(mb, "2026-04-25_refactor_a.md", "alpha", "Setup")

    assert _run(SYNC_SCRIPT, plan, mb).returncode == 0
    assert _run(SYNC_SCRIPT, plan, mb).returncode == 0

    checklist = (mb / "checklist.md").read_text(encoding="utf-8")
    assert (
        _count_substring(checklist, "<!-- mb-plan:2026-04-25_refactor_a.md -->") == 1
    ), "Marker duplicated on re-sync:\n" + checklist
    assert _count_substring(checklist, "## Stage 1: Setup") == 1


def test_legacy_unmarked_section_preserved_by_new_plan_with_same_heading(
    tmp_path: Path,
) -> None:
    """A pre-existing checklist section without any marker (legacy v1 format)
    must NOT be merged with a freshly synced plan that happens to share the
    same heading. Sync writes its own marker section; legacy stays as-is."""
    mb = _init_mb(tmp_path)

    # Pre-seed checklist with a legacy section (no marker)
    legacy_text = (
        "# Checklist\n\n"
        "## Stage 1: Setup\n"
        "- ⬜ Setup (legacy, no marker)\n"
    )
    (mb / "checklist.md").write_text(legacy_text, encoding="utf-8")

    plan = _make_plan(mb, "2026-04-25_refactor_new.md", "new", "Setup")
    assert _run(SYNC_SCRIPT, plan, mb).returncode == 0

    checklist = (mb / "checklist.md").read_text(encoding="utf-8")

    # Legacy item still present
    assert "Setup (legacy, no marker)" in checklist, (
        "Legacy unmarked section was lost:\n" + checklist
    )
    # New plan's marker section also present
    assert "<!-- mb-plan:2026-04-25_refactor_new.md -->" in checklist
    # And there are now two `## Stage 1: Setup` headings
    assert _count_substring(checklist, "## Stage 1: Setup") == 2
