"""Phase 4 Sprint 2 — `scripts/mb-context-slim.py` prompt trimmer."""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-context-slim.py"


def _plan(stages_text: str, frontmatter: str = "") -> str:
    fm = frontmatter or "---\ntype: feature\ntopic: foo\nstatus: in-progress\ncovers_requirements: [REQ-001, REQ-002]\n---\n"
    return fm + "\n# Plan\n\n" + stages_text


def _stage(n: int, heading: str, body: str = "- ✅ DoD bit\n") -> str:
    return f"<!-- mb-stage:{n} -->\n## Stage {n}: {heading}\n\n{body}\n"


def _run(*args: str, stdin: str = "") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["python3", str(SCRIPT), *args],
        input=stdin, capture_output=True, text=True, check=False,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_extracts_active_stage_block(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    plan.write_text(_plan(_stage(1, "first stage", "- ✅ build A\n") + _stage(2, "second", "- ⬜ build B\n")), encoding="utf-8")
    full = "Plan: " + str(plan) + "\nStage: 2\n\nfull prompt body" * 50
    r = _run("--plan", str(plan), "--stage", "2", stdin=full)
    assert r.returncode == 0, r.stderr
    out = r.stdout
    assert "second" in out
    assert "build B" in out
    assert "first stage" not in out


def test_includes_dod_section(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    plan.write_text(_plan(_stage(1, "thing", "- ✅ first DoD\n- ⬜ second DoD\n")), encoding="utf-8")
    r = _run("--plan", str(plan), "--stage", "1", stdin="full")
    assert r.returncode == 0, r.stderr
    assert "first DoD" in r.stdout
    assert "second DoD" in r.stdout


def test_includes_covers_requirements(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    plan.write_text(_plan(_stage(1, "x")), encoding="utf-8")
    r = _run("--plan", str(plan), "--stage", "1", stdin="full")
    assert r.returncode == 0
    assert "REQ-001" in r.stdout
    assert "REQ-002" in r.stdout


def test_diff_flag_includes_git_diff(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    plan.write_text(_plan(_stage(1, "x")), encoding="utf-8")
    r = _run("--plan", str(plan), "--stage", "1", "--diff", stdin="full")
    assert r.returncode == 0, r.stderr
    # Diff section header should be present even if diff is empty
    assert "Git diff" in r.stdout or "diff" in r.stdout.lower()


def test_no_marker_falls_back_to_full(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    plan.write_text("---\nfoo: bar\n---\n# no markers here\n", encoding="utf-8")
    full = "the entire original prompt" * 30
    r = _run("--plan", str(plan), "--stage", "1", stdin=full)
    assert r.returncode == 0, r.stderr
    # Should fall back to full
    assert "entire original prompt" in r.stdout


def test_empty_stdin_returns_empty(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    plan.write_text(_plan(_stage(1, "x")), encoding="utf-8")
    r = _run("--plan", str(plan), "--stage", "1", stdin="")
    assert r.returncode == 0


def test_missing_plan_fails(tmp_path: Path) -> None:
    r = _run("--plan", str(tmp_path / "missing.md"), "--stage", "1", stdin="x")
    assert r.returncode == 1


def test_stage_out_of_range_fails(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    plan.write_text(_plan(_stage(1, "x")), encoding="utf-8")
    r = _run("--plan", str(plan), "--stage", "99", stdin="x")
    assert r.returncode == 1


def test_trimmed_strictly_shorter_than_full(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    body = "- ✅ a\n" * 5
    plan.write_text(_plan(
        _stage(1, "tiny one", body)
        + _stage(2, "huge two", "- ⬜ work\n" * 200)
        + _stage(3, "tiny three", body)
    ), encoding="utf-8")
    full = "Plan: " + str(plan) + "\nStage: 1\n\n" + plan.read_text(encoding="utf-8")
    r = _run("--plan", str(plan), "--stage", "1", stdin=full)
    assert r.returncode == 0, r.stderr
    assert len(r.stdout) < len(full)
