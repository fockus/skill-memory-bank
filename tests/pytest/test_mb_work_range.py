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
