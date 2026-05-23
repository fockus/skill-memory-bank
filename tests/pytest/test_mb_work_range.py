"""Phase 3 Sprint 2 — `scripts/mb-work-range.sh` range / level detector."""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-range.sh"


def _plan_with_stages(n: int, sprint: int | None = None) -> str:
    fm = "---\ntype: feature\ntopic: foo\nstatus: in-progress\n"
    if sprint is not None:
        fm += f"sprint: {sprint}\n"
    fm += "---\n\n# Plan\n\n"
    body = "".join(
        f"<!-- mb-stage:{i} -->\n## Stage {i}: do thing {i}\n\n- ✅ done bit\n\n"
        for i in range(1, n + 1)
    )
    return fm + body


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True, text=True, check=False,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_plan_no_range_emits_all_stages(tmp_path: Path) -> None:
    plan = tmp_path / "myplan.md"
    plan.write_text(_plan_with_stages(4), encoding="utf-8")
    r = _run(str(plan))
    assert r.returncode == 0, r.stderr
    out = r.stdout.strip().splitlines()
    assert out == ["1", "2", "3", "4"]


def test_plan_range_closed(tmp_path: Path) -> None:
    plan = tmp_path / "myplan.md"
    plan.write_text(_plan_with_stages(5), encoding="utf-8")
    r = _run(str(plan), "--range", "2-4")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip().splitlines() == ["2", "3", "4"]


def test_plan_range_single(tmp_path: Path) -> None:
    plan = tmp_path / "myplan.md"
    plan.write_text(_plan_with_stages(5), encoding="utf-8")
    r = _run(str(plan), "--range", "3")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "3"


def test_plan_range_open_ended(tmp_path: Path) -> None:
    plan = tmp_path / "myplan.md"
    plan.write_text(_plan_with_stages(4), encoding="utf-8")
    r = _run(str(plan), "--range", "2-")
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip().splitlines() == ["2", "3", "4"]


def test_plan_range_out_of_bounds(tmp_path: Path) -> None:
    plan = tmp_path / "myplan.md"
    plan.write_text(_plan_with_stages(3), encoding="utf-8")
    r = _run(str(plan), "--range", "99")
    assert r.returncode == 1
    assert "out of bounds" in (r.stderr + r.stdout).lower()


def test_plan_with_no_stage_markers(tmp_path: Path) -> None:
    plan = tmp_path / "myplan.md"
    plan.write_text("---\nfoo: bar\n---\n\n# nothing here\n", encoding="utf-8")
    r = _run(str(plan))
    assert r.returncode == 1
    assert "no stages" in (r.stderr + r.stdout).lower()


def test_phase_mode_sprint_level(tmp_path: Path) -> None:
    p1 = tmp_path / "p1.md"
    p1.write_text(_plan_with_stages(2, sprint=1), encoding="utf-8")
    p2 = tmp_path / "p2.md"
    p2.write_text(_plan_with_stages(2, sprint=2), encoding="utf-8")
    p3 = tmp_path / "p3.md"
    p3.write_text(_plan_with_stages(2, sprint=3), encoding="utf-8")
    r = _run("--phase", str(p1), str(p2), str(p3), "--range", "1-2")
    assert r.returncode == 0, r.stderr
    out = r.stdout.strip().splitlines()
    assert out == [str(p1.resolve()), str(p2.resolve())]


def test_phase_mode_missing_sprint_frontmatter(tmp_path: Path) -> None:
    p1 = tmp_path / "p1.md"
    p1.write_text(_plan_with_stages(2), encoding="utf-8")
    r = _run("--phase", str(p1), "--range", "1")
    assert r.returncode == 1
    assert "sprint" in (r.stderr + r.stdout).lower()


def test_invalid_range_expr(tmp_path: Path) -> None:
    plan = tmp_path / "myplan.md"
    plan.write_text(_plan_with_stages(3), encoding="utf-8")
    r = _run(str(plan), "--range", "abc")
    assert r.returncode == 1


# ── NEW: spec-task auto-detect (Stage 1 RED tests) ────────────────────────


def _spec_tasks_with_n(n: int) -> str:
    """Return tasks.md content with n mb-task markers."""
    header = "# Tasks: foo\n\n"
    blocks = "".join(
        f"<!-- mb-task:{i} -->\n## Task {i}: thing {i}\n\n- [ ] done {i}\n\n"
        for i in range(1, n + 1)
    )
    return header + blocks


def test_range_auto_detects_mb_task_marker_in_spec_tasks(tmp_path: Path) -> None:
    """mb-work-range.sh on a spec tasks.md file emits task indices 1..N (auto-detect)."""
    # Arrange
    tasks = tmp_path / "tasks.md"
    tasks.write_text(_spec_tasks_with_n(4), encoding="utf-8")

    # Act
    r = _run(str(tasks))

    # Assert — currently fails because range.sh only looks for mb-stage markers
    assert r.returncode == 0, r.stderr
    out = r.stdout.strip().splitlines()
    assert out == ["1", "2", "3", "4"], f"expected [1,2,3,4], got {out}"


def test_range_rejects_mixed_marker_file(tmp_path: Path) -> None:
    """File with both mb-stage and mb-task markers causes exit 1; stderr mentions mixed format."""
    # Arrange
    mixed = tmp_path / "mixed.md"
    mixed.write_text(
        "# Mixed\n\n"
        "<!-- mb-stage:1 -->\n## Stage 1: old\n\n- [ ] done\n\n"
        "<!-- mb-task:1 -->\n## Task 1: new\n\n- [ ] done\n",
        encoding="utf-8",
    )

    # Act
    r = _run(str(mixed))

    # Assert
    assert r.returncode == 1, f"expected exit 1, got {r.returncode}"
    combined = (r.stderr + r.stdout).lower()
    assert "mixed" in combined, f"expected 'mixed' in output, got:\n{combined}"
