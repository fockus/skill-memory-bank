"""Phase 3 Sprint 3 — `scripts/mb-work-severity-gate.sh` severity gate enforcement."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-severity-gate.sh"
PIPELINE_INIT = REPO_ROOT / "scripts" / "mb-pipeline.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _run(
    *args: str,
    stdin: str | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        input=stdin,
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )


def _env_without_yaml(tmp_path: Path) -> dict[str, str]:
    fake = tmp_path / "fake-pythonpath"
    fake.mkdir()
    (fake / "yaml.py").write_text("raise ModuleNotFoundError('yaml')\n", encoding="utf-8")
    env = os.environ.copy()
    env["PYTHONPATH"] = str(fake)
    return env


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
        check=True,
        capture_output=True,
        text=True,
    )
    yaml_path = mb / "pipeline.yaml"
    text = yaml_path.read_text(encoding="utf-8")
    # The opt-in `review:` block nests severity_gate at 4-space indent.
    text = text.replace("    minor: 3", "    minor: 0")
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


def test_default_gate_works_without_pyyaml(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    counts = {"blocker": 0, "major": 0, "minor": 2}
    r = _run(
        "--counts",
        json.dumps(counts),
        "--mb",
        str(mb),
        env=_env_without_yaml(tmp_path),
    )
    assert r.returncode == 0, r.stderr
    assert "No module named" not in r.stderr


def test_no_review_configured_passes(tmp_path: Path) -> None:
    """REQ-011: no review anywhere in the pipeline → gate PASSes no-op."""
    mb = _init_mb(tmp_path)
    pipeline = mb / "pipeline.yaml"
    pipeline.write_text(
        "version: 1\n"
        "stage_pipeline:\n"
        "  - step: implement\n"
        "    role: auto\n"
        "  - step: verify\n"
        "    role: verifier\n"
        "  - step: done\n"
        "    role: verifier\n",
        encoding="utf-8",
    )
    # High counts must still PASS because no review policy is configured.
    counts = {"blocker": 9, "major": 9, "minor": 9}
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 0, r.stderr
    assert "PASS" in r.stdout


def test_no_review_configured_passes_without_pyyaml(tmp_path: Path) -> None:
    """NFR-005: the no-review PASS no-op holds on the no-PyYAML fallback path."""
    mb = _init_mb(tmp_path)
    pipeline = mb / "pipeline.yaml"
    pipeline.write_text(
        "version: 1\n"
        "stage_pipeline:\n"
        "  - step: implement\n"
        "    role: auto\n"
        "  - step: verify\n"
        "    role: verifier\n"
        "  - step: done\n"
        "    role: verifier\n",
        encoding="utf-8",
    )
    counts = {"blocker": 9, "major": 9, "minor": 9}
    r = _run(
        "--counts",
        json.dumps(counts),
        "--mb",
        str(mb),
        env=_env_without_yaml(tmp_path),
    )
    assert r.returncode == 0, r.stderr
    assert "No module named" not in r.stderr


def _approval_pipeline(mb: Path) -> None:
    """A pipeline whose review step requires reviewer approval. Resolved on BOTH
    the PyYAML and the no-PyYAML fallback parsers (stage_pipeline review step)."""
    (mb / "pipeline.yaml").write_text(
        "version: 1\n"
        "stage_pipeline:\n"
        "  - step: review\n"
        "    role: reviewer\n"
        "    approval_required: true\n"
        "    severity_gate: {blocker: 0, major: 0, minor: 0}\n",
        encoding="utf-8",
    )


def test_approval_required_without_verdict_fails_by_default(tmp_path: Path) -> None:
    """Baseline (unchanged): a raw-counts call (no verdict) against an
    approval-required policy fails — the work-loop reviewer contract is intact."""
    mb = _init_mb(tmp_path)
    _approval_pipeline(mb)
    counts = {"blocker": 0, "major": 0, "minor": 0}
    r = _run("--counts", json.dumps(counts), "--mb", str(mb))
    assert r.returncode == 1
    assert "approval_required" in (r.stderr + r.stdout).lower()


def test_ignore_approval_skips_approval_enforcement(tmp_path: Path) -> None:
    """--ignore-approval: a firewall-style raw-counts call (no verdict) passes the
    approval check, so a closure gate is never subject to reviewer-approval policy."""
    mb = _init_mb(tmp_path)
    _approval_pipeline(mb)
    counts = {"blocker": 0, "major": 0, "minor": 0}
    r = _run(
        "--counts",
        json.dumps(counts),
        "--mb",
        str(mb),
        "--gate",
        json.dumps({"blocker": 0, "major": 0, "minor": 0}),
        "--ignore-approval",
    )
    assert r.returncode == 0, r.stderr


def test_ignore_approval_still_enforces_severity(tmp_path: Path) -> None:
    """--ignore-approval bypasses ONLY approval — a severity breach still fails."""
    mb = _init_mb(tmp_path)
    _approval_pipeline(mb)
    counts = {"blocker": 1, "major": 0, "minor": 0}
    r = _run(
        "--counts",
        json.dumps(counts),
        "--mb",
        str(mb),
        "--gate",
        json.dumps({"blocker": 0, "major": 0, "minor": 0}),
        "--ignore-approval",
    )
    assert r.returncode == 1
    assert "blocker" in (r.stderr + r.stdout).lower()


def test_ignore_approval_rejects_verdict_bearing_payload(tmp_path: Path) -> None:
    """--ignore-approval is for raw-count (no-verdict) closure callers ONLY. It must
    NOT be usable to silently override a reviewer's explicit CHANGES_REQUESTED — a
    verdict-bearing payload combined with the flag is a usage error (exit 2), never
    a fall-through PASS."""
    mb = _init_mb(tmp_path)
    _approval_pipeline(mb)
    payload = {"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 0, "major": 0, "minor": 0}}
    r = _run(
        "--counts",
        json.dumps(payload),
        "--mb",
        str(mb),
        "--gate",
        json.dumps({"blocker": 0, "major": 0, "minor": 0}),
        "--ignore-approval",
    )
    assert r.returncode == 2, (r.returncode, r.stderr, r.stdout)
    assert "ignore-approval" in (r.stderr + r.stdout).lower()


def test_ignore_approval_rejects_verdict_even_with_no_review_policy(tmp_path: Path) -> None:
    """The verdict guard is UNCONDITIONAL — it fires BEFORE the no-review PASS no-op,
    so a verdict-bearing payload + --ignore-approval is rejected (exit 2) even when
    the bank has no review policy and no --gate override (which would otherwise
    silently no-op PASS, bypassing the guard)."""
    mb = _init_mb(tmp_path)
    (mb / "pipeline.yaml").write_text(
        "version: 1\nstage_pipeline:\n  - step: implement\n    role: auto\n",
        encoding="utf-8",
    )
    payload = {"verdict": "CHANGES_REQUESTED", "counts": {"blocker": 0, "major": 0, "minor": 0}}
    r = _run("--counts", json.dumps(payload), "--mb", str(mb), "--ignore-approval")
    assert r.returncode == 2, (r.returncode, r.stderr, r.stdout)
    assert "ignore-approval" in (r.stderr + r.stdout).lower()
