"""Phase 3 Sprint 1 — `scripts/mb-pipeline.sh` dispatcher (init/show/validate/path)."""

from __future__ import annotations

import filecmp
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-pipeline.sh"
DEFAULT = REPO_ROOT / "references" / "pipeline.default.yaml"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text("# Roadmap\n", encoding="utf-8")
    return mb


def _run(*args: str, mb: Path | None = None) -> subprocess.CompletedProcess[str]:
    cmd = ["bash", str(SCRIPT), *args]
    if mb is not None:
        cmd.append(str(mb))
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


# ──────────────────────────────────────────────────────────────────────────


def test_init_copies_default_into_bank(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("init", mb=mb)
    assert r.returncode == 0, r.stderr
    target = mb / "pipeline.yaml"
    assert target.is_file()
    assert filecmp.cmp(str(DEFAULT), str(target), shallow=False)


def test_init_idempotency_guard(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("init", mb=mb).returncode == 0
    r = _run("init", mb=mb)
    assert r.returncode == 1
    assert "exists" in (r.stderr + r.stdout).lower()


def test_init_force_overwrites(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    assert _run("init", mb=mb).returncode == 0
    target = mb / "pipeline.yaml"
    target.write_text("garbage\n", encoding="utf-8")
    r = _run("init", "--force", mb=mb)
    assert r.returncode == 0, r.stderr
    assert filecmp.cmp(str(DEFAULT), str(target), shallow=False)


def test_show_prints_default_when_no_project_override(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("show", mb=mb)
    assert r.returncode == 0, r.stderr
    assert "stage_pipeline" in r.stdout
    assert "review_rubric" in r.stdout


def test_show_prints_project_when_present(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    target = mb / "pipeline.yaml"
    target.write_text("# project override\nversion: 1\n", encoding="utf-8")
    r = _run("show", mb=mb)
    assert r.returncode == 0, r.stderr
    assert "project override" in r.stdout


def test_path_returns_default_when_no_project(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("path", mb=mb)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == str(DEFAULT.resolve())


def test_path_returns_project_when_present(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    target = mb / "pipeline.yaml"
    target.write_text("version: 1\n", encoding="utf-8")
    r = _run("path", mb=mb)
    assert r.returncode == 0
    assert r.stdout.strip() == str(target.resolve())


def test_validate_default_via_resolution(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("validate", mb=mb)
    assert r.returncode == 0, r.stderr


def test_validate_explicit_path(tmp_path: Path) -> None:
    bad = tmp_path / "broken.yaml"
    bad.write_text("not: valid: yaml: : :\n", encoding="utf-8")
    r = subprocess.run(
        ["bash", str(SCRIPT), "validate", str(bad)],
        capture_output=True, text=True, check=False,
    )
    assert r.returncode != 0


def test_unknown_subcommand_fails() -> None:
    r = _run("nonsense")
    assert r.returncode == 2


def test_help_flag_exits_zero() -> None:
    r = subprocess.run(
        ["bash", str(SCRIPT), "--help"],
        capture_output=True, text=True, check=False,
    )
    assert r.returncode == 0
    assert "usage" in (r.stdout + r.stderr).lower() or "init" in r.stdout.lower()
