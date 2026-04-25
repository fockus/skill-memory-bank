"""Phase 4 Sprint 3 — `scripts/mb-reviewer-resolve.sh` reviewer-agent resolver.

Contract:
- Reads `pipeline.yaml` (project override → references/pipeline.default.yaml).
- Default output: value of `roles.reviewer.agent` (e.g. `mb-reviewer`).
- If `roles.reviewer.override_if_skill_present` is set AND the named skill is
  detected at `<skills-root>/<skill>/` (or env-injected via MB_SKILLS_ROOT),
  output the override agent name instead.
- Exit 0 in both cases. Exit non-zero only on malformed pipeline.yaml.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-reviewer-resolve.sh"
DEFAULT_PIPELINE = REPO_ROOT / "references" / "pipeline.default.yaml"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(mb: Path, *, skills_root: Path | None = None) -> subprocess.CompletedProcess[str]:
    env = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"}
    if skills_root is not None:
        env["MB_SKILLS_ROOT"] = str(skills_root)
    return subprocess.run(
        ["bash", str(SCRIPT), "--mb", str(mb)],
        capture_output=True, text=True, check=False, env=env,
    )


def test_default_when_no_override_skill_dir(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    skills_root = tmp_path / "skills-empty"
    skills_root.mkdir()
    r = _run(mb, skills_root=skills_root)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "mb-reviewer"


def test_override_when_skill_dir_exists(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    skills_root = tmp_path / "skills-with-superpowers"
    (skills_root / "superpowers").mkdir(parents=True)
    r = _run(mb, skills_root=skills_root)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "superpowers:requesting-code-review"


def test_project_override_takes_precedence(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    project_pipeline = mb / "pipeline.yaml"
    shutil.copy(DEFAULT_PIPELINE, project_pipeline)
    text = project_pipeline.read_text(encoding="utf-8")
    text = text.replace("agent: mb-reviewer\n", "agent: my-custom-reviewer\n", 1)
    project_pipeline.write_text(text, encoding="utf-8")
    skills_root = tmp_path / "skills-empty"
    skills_root.mkdir()
    r = _run(mb, skills_root=skills_root)
    assert r.returncode == 0, r.stderr
    assert r.stdout.strip() == "my-custom-reviewer"


def test_uses_default_pipeline_when_no_project_override(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    skills_root = tmp_path / "skills-empty"
    skills_root.mkdir()
    r = _run(mb, skills_root=skills_root)
    assert r.returncode == 0
    # mb-reviewer is the default ships in references/pipeline.default.yaml
    assert "mb-reviewer" in r.stdout


def test_help_flag(tmp_path: Path) -> None:
    r = subprocess.run(
        ["bash", str(SCRIPT), "--help"],
        capture_output=True, text=True, check=False,
    )
    assert r.returncode == 0
    assert "reviewer" in (r.stdout + r.stderr).lower()
