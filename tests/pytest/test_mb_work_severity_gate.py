"""Phase 3 Sprint 3 — `scripts/mb-work-severity-gate.sh` severity gate enforcement."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-severity-gate.sh"
PIPELINE_INIT = REPO_ROOT / "scripts" / "mb-pipeline.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(*args: str, stdin: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        input=stdin,
        capture_output=True, text=True, check=False,
    )


# ──────────────────────────────────────────────────────────────────────────


def test_default_gate_pass(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    counts = {"blocker": 0, "major": 0, "minor": 2}
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 0, r.stderr


def test_blocker_breach(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    counts = {"blocker": 1, "major": 0, "minor": 0}
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 1
    assert "blocker" in (r.stderr + r.stdout).lower()


def test_major_breach(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    counts = {"blocker": 0, "major": 1, "minor": 0}
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 1


def test_minor_breach_above_limit(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    counts = {"blocker": 0, "major": 0, "minor": 5}
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 1


def test_minor_at_limit_passes(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    counts = {"blocker": 0, "major": 0, "minor": 3}
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 0, r.stderr


def test_project_pipeline_overrides_default(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    # Init project pipeline.yaml with stricter minor=0
    subprocess.run(
        ["bash", str(PIPELINE_INIT), "init", str(mb)],
        check=True, capture_output=True, text=True,
    )
    yaml_path = mb / "pipeline.yaml"
    text = yaml_path.read_text(encoding="utf-8")
    text = text.replace("      minor: 3", "      minor: 0")
    yaml_path.write_text(text, encoding="utf-8")
    counts = {"blocker": 0, "major": 0, "minor": 1}
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 1


def test_counts_via_stdin(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    counts = {"blocker": 0, "major": 0, "minor": 0}
    r = _run("--counts-stdin", "--mb", str(mb), stdin=json.dumps(counts))
    assert r.returncode == 0, r.stderr


def test_missing_severity_treated_as_zero(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    counts = {"minor": 1}  # blocker / major absent
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 0


def test_invalid_counts_json_usage(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    r = _run("--counts", "not-json", "--mb", str(mb))
    assert r.returncode == 2
