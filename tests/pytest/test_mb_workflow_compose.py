"""composable-work-pipeline — `scripts/mb-workflow.sh` stage composition.

Covers the 3-layer merge (launch flags > pipeline.yaml > built-in default),
the canonical stage order, per-stage toggles, `--stages` override, the
brainstorm→discuss alias, and judge-without-review fail-fast.
"""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-workflow.sh"
PIPELINE_INIT = REPO_ROOT / "scripts" / "mb-pipeline.sh"


def _run(*args: str) -> subprocess.CompletedProcess[str]:
    # Isolated cwd: without --mb the script resolves the bank from the
    # current directory, and running from the repo root would leak this
    # project's live .memory-bank/pipeline.yaml into "built-in default" tests.
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        cwd=tempfile.mkdtemp(prefix="mb-workflow-isolated-"),
    )


def _steps(*args: str) -> list[str]:
    r = _run(*args, "--steps")
    assert r.returncode == 0, r.stderr
    return [line for line in r.stdout.splitlines() if line.strip()]


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    subprocess.run(
        ["bash", str(PIPELINE_INIT), "init", str(mb)],
        check=True,
        capture_output=True,
        text=True,
    )
    return mb


def _enable_review(mb: Path) -> None:
    yaml_path = mb / "pipeline.yaml"
    text = yaml_path.read_text(encoding="utf-8")
    # The opt-in review block ships `enabled: false`; flip it on.
    assert "enabled: false" in text
    text = text.replace("enabled: false", "enabled: true", 1)
    yaml_path.write_text(text, encoding="utf-8")


# ── built-in default ───────────────────────────────────────────────────────


def test_default_is_execution() -> None:
    assert _steps() == ["implement", "verify", "done"]


def test_workflow_full_preset() -> None:
    assert _steps("--workflow", "full") == [
        "discuss",
        "sdd",
        "plan",
        "implement",
        "verify",
        "review",
        "judge",
        "done",
    ]


# ── per-stage launch flags (canonical insertion / removal) ─────────────────


def test_review_flag_inserts_at_canonical_position() -> None:
    assert _steps("--review") == ["implement", "verify", "review", "done"]


def test_brainstorm_flag_enables_discuss() -> None:
    assert _steps("--brainstorm") == ["discuss", "implement", "verify", "done"]


def test_no_stage_flag_removes_from_preset() -> None:
    # full minus sdd, canonically ordered (REQ-006).
    assert _steps("--workflow", "full", "--no-sdd") == [
        "discuss",
        "plan",
        "implement",
        "verify",
        "review",
        "judge",
        "done",
    ]


def test_stages_override_beats_everything() -> None:
    # --stages discards preset + flags (REQ-009).
    assert _steps("--workflow", "full", "--stages", "implement,verify") == [
        "implement",
        "verify",
    ]


# ── pipeline.yaml per-stage enabled blocks + precedence ────────────────────


def test_yaml_enabled_adds_stage(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _enable_review(mb)
    assert _steps("--mb", str(mb)) == ["implement", "verify", "review", "done"]


def test_launch_flag_beats_yaml(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _enable_review(mb)  # pipeline.yaml turns review ON …
    # … but --no-review wins (REQ-008).
    assert _steps("--mb", str(mb), "--no-review") == ["implement", "verify", "done"]


# ── fail-fast + determinism ────────────────────────────────────────────────


def test_judge_without_review_fails() -> None:
    r = _run("--judge", "--steps")
    assert r.returncode != 0
    assert "review" in (r.stderr + r.stdout).lower()


def test_unknown_stage_in_stages_fails() -> None:
    r = _run("--stages", "implement,bogus", "--steps")
    assert r.returncode != 0
    assert "bogus" in (r.stderr + r.stdout).lower()


def test_composition_is_deterministic() -> None:
    a = _steps("--workflow", "full", "--no-sdd", "--no-judge", "--no-review")
    b = _steps("--workflow", "full", "--no-sdd", "--no-judge", "--no-review")
    assert a == b


def test_json_output_carries_steps(tmp_path: Path) -> None:
    r = _run("--review", "--json")
    assert r.returncode == 0, r.stderr
    payload = json.loads(r.stdout)
    assert payload["steps"] == ["implement", "verify", "review", "done"]
    assert "source" in payload


# ── doc contract (NFR-004) ─────────────────────────────────────────────────


def test_work_md_documents_composition() -> None:
    """commands/work.md must document the flags, `full` preset, and precedence."""
    text = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")
    for needle in (
        "--review",
        "--no-review",
        "--judge",
        "--brainstorm",
        "--sdd",
        "--plan",
        "--stages",
        "precedence",
    ):
        assert needle in text, f"work.md missing composition doc: {needle}"
    # The `full` preset row and the default-no-review statement.
    assert "Review is OFF by default" in text
    assert "discuss → sdd → plan → implement → verify → review → judge → done" in text
