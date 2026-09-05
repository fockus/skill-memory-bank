"""mb-work-cost-diet Sprint 1 Stage 2 — cheap default + a documented cost ladder.

Two contracts:
  * both `/mb work` docs carry a "Cost ladder" table listing all four presets,
    so the cheap path is a visible choice rather than folklore;
  * this repository's own bank resolves to `execution` (implement → verify →
    done) with the governed cycle reachable only via `--workflow codex-governed`.
"""

from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_SH = REPO_ROOT / "scripts" / "mb-workflow.sh"
REPO_BANK = REPO_ROOT / ".memory-bank"

PRESETS = ("implement-only", "execution", "codex-governed", "governed-execution")
COST_LADDER_RE = re.compile(r"^#+\s+cost ladder\b", re.IGNORECASE | re.MULTILINE)


def _workflow_json(*args: str) -> dict:
    result = subprocess.run(
        ["bash", str(WORKFLOW_SH), "--mb", str(REPO_BANK), *args, "--json"],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


@pytest.mark.parametrize("doc", ["docs/mb-work.md", "commands/work.md"])
def test_mb_work_docs_have_cost_ladder_table(doc: str) -> None:
    text = (REPO_ROOT / doc).read_text(encoding="utf-8")
    assert COST_LADDER_RE.search(text), f"{doc}: no 'Cost ladder' heading"
    rows = [line for line in text.splitlines() if line.lstrip().startswith("|")]
    for preset in PRESETS:
        assert any(f"`{preset}`" in row for row in rows), f"{doc}: no table row for `{preset}`"


def test_pipeline_default_is_execution_in_repo_bank() -> None:
    resolved = _workflow_json()
    assert resolved["name"] == "execution"
    assert resolved["steps"] == ["implement", "verify", "done"]
    assert resolved["entrypoint"] == "plan_or_spec"


def test_codex_governed_preset_still_resolves_six_steps() -> None:
    resolved = _workflow_json("--workflow", "codex-governed")
    assert resolved["name"] == "codex-governed"
    assert resolved["steps"] == ["implement", "verify", "review", "judge", "fix", "done"]
