"""Phase 3 Sprint 1 — `scripts/mb-pipeline-validate.sh` schema check.

Validates pipeline.yaml against spec §9 structural rules.
"""

from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

yaml = pytest.importorskip("yaml")

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-pipeline-validate.sh"
DEFAULT = REPO_ROOT / "references" / "pipeline.default.yaml"


def _run(path: Path | str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), str(path)],
        capture_output=True,
        text=True,
        check=False,
    )


def _write(p: Path, data: dict) -> None:
    p.write_text(yaml.safe_dump(data, sort_keys=False), encoding="utf-8")


def _valid_minimal() -> dict:
    return {
        "version": 1,
        "roles": {
            "developer": {"agent": "mb-developer"},
            "reviewer": {"agent": "mb-reviewer"},
            "verifier": {"agent": "plan-verifier"},
        },
        "stage_pipeline": [
            {"step": "implement", "role": "developer", "tdd": True},
            {
                "step": "review",
                "role": "reviewer",
                "categories": ["logic"],
                "severity_gate": {"blocker": 0, "major": 0, "minor": 3},
                "max_cycles": 3,
                "on_max_cycles": "stop_for_human",
            },
            {"step": "verify", "role": "verifier", "checks": ["dod_checkboxes"]},
        ],
        "budget": {
            "default_limit": None,
            "warn_at_percent": 80,
            "stop_at_percent": 100,
        },
        "protected_paths": [".env*"],
        "sprint_context_guard": {
            "soft_warn_tokens": 150000,
            "hard_stop_tokens": 190000,
        },
        "review_rubric": {
            "logic": ["assertion required"],
            "code_rules": ["no placeholders"],
            "security": ["no secrets"],
            "scalability": ["no N+1"],
            "tests": ["protocol-first"],
        },
        "sdd": {
            "require_ears_in_sdd_command": True,
            "require_ears_in_plan_command": False,
            "require_ears_in_plan_with_sdd_flag": True,
            "covers_requirements_policy": "warn",
            "full_mode_path": ".memory-bank/specs",
        },
    }


# ──────────────────────────────────────────────────────────────────────────


def test_default_passes(tmp_path: Path) -> None:
    r = _run(DEFAULT)
    assert r.returncode == 0, r.stderr


def test_minimal_valid_passes(tmp_path: Path) -> None:
    p = tmp_path / "pipeline.yaml"
    _write(p, _valid_minimal())
    r = _run(p)
    assert r.returncode == 0, r.stderr


def test_missing_top_level_key_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    del cfg["roles"]
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1
    assert "roles" in r.stderr.lower()


def test_wrong_version_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    cfg["version"] = 2
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1
    assert "version" in r.stderr.lower()


def test_severity_gate_unknown_key_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    review = cfg["stage_pipeline"][1]
    review["severity_gate"]["fatal"] = 0
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1
    assert "severity" in r.stderr.lower()


def test_unknown_role_in_stage_pipeline_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    cfg["stage_pipeline"][0]["role"] = "nonexistent"
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1
    assert "role" in r.stderr.lower()


def test_role_without_agent_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    cfg["roles"]["developer"] = {}
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1
    assert "agent" in r.stderr.lower()


def test_negative_budget_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    cfg["budget"]["warn_at_percent"] = -10
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1


def test_sprint_guard_inverted_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    cfg["sprint_context_guard"]["soft_warn_tokens"] = 200000
    cfg["sprint_context_guard"]["hard_stop_tokens"] = 100000
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1
    assert "sprint_context_guard" in r.stderr.lower()


def test_empty_file_fails(tmp_path: Path) -> None:
    p = tmp_path / "pipeline.yaml"
    p.write_text("", encoding="utf-8")
    r = _run(p)
    assert r.returncode == 1


def test_nonexistent_path_fails(tmp_path: Path) -> None:
    r = _run(tmp_path / "missing.yaml")
    assert r.returncode != 0
    combined = (r.stderr + r.stdout).lower()
    assert "not found" in combined or "no such file" in combined


def test_invalid_max_cycles_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    cfg["stage_pipeline"][1]["max_cycles"] = 0
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1


def test_invalid_on_max_cycles_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    cfg["stage_pipeline"][1]["on_max_cycles"] = "panic"
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1


def test_invalid_covers_requirements_policy_fails(tmp_path: Path) -> None:
    cfg = _valid_minimal()
    cfg["sdd"]["covers_requirements_policy"] = "shrug"
    p = tmp_path / "pipeline.yaml"
    _write(p, cfg)
    r = _run(p)
    assert r.returncode == 1
