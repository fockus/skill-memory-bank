"""Phase 3 Sprint 3 — `scripts/mb-work-protected-check.sh` protected_paths matcher."""

from __future__ import annotations

import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-protected-check.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(*files: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *files, "--mb", str(mb)],
        capture_output=True, text=True, check=False,
    )


# Default `pipeline.yaml:protected_paths`:
#   - .env*
#   - ci/**
#   - .github/workflows/**
#   - Dockerfile*
#   - k8s/**
#   - terraform/**


def test_dotenv_matches(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run(".env.production", mb=mb)
    assert r.returncode == 1
    assert ".env" in (r.stderr + r.stdout)


def test_ci_glob_matches(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("ci/build.yaml", mb=mb)
    assert r.returncode == 1


def test_terraform_glob_matches(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("terraform/aws/main.tf", mb=mb)
    assert r.returncode == 1


def test_unrelated_file_no_match(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("src/foo.py", mb=mb)
    assert r.returncode == 0


def test_multiple_files_one_matches(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("src/foo.py", "Dockerfile", "tests/x.py", mb=mb)
    assert r.returncode == 1
    assert "Dockerfile" in (r.stderr + r.stdout)


def test_empty_file_list_passes(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run(mb=mb)
    assert r.returncode == 0
