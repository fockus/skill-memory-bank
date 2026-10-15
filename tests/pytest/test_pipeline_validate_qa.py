"""qa-pipeline-integration Stage 1 — pipeline.yaml `qa:` block validation (AGR-098)."""

from __future__ import annotations

import pathlib
import subprocess

import pytest

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
VALIDATE = REPO_ROOT / "scripts" / "mb-pipeline-validate.sh"
BASE = (REPO_ROOT / "references" / "pipeline.default.yaml").read_text(encoding="utf-8")
QA_START = BASE.index("\nqa:\n") + 1
QA_END = BASE.index("\n\n", QA_START)


def _validate(tmp_path: pathlib.Path, qa_block: str | None = None, extra: str = "") -> subprocess.CompletedProcess:
    text = BASE if qa_block is None else BASE[:QA_START] + qa_block + BASE[QA_END:]
    path = tmp_path / "pipeline.yaml"
    path.write_text(text + extra, encoding="utf-8")
    return subprocess.run(["bash", str(VALIDATE), str(path)], capture_output=True, text=True, check=False)


def test_validate_default_qa_block_accepted(tmp_path):
    assert "qa:" in BASE[QA_START:QA_END]
    result = _validate(tmp_path)
    assert result.returncode == 0, result.stderr


def test_validate_qa_overrides_accepted(tmp_path):
    block = (
        "qa:\n  enabled: true\n  cadence: run\n  position: after_review\n  selector: smoke\n"
        "  prepare: make stand\n  gate: {critical: 0, major: 1, medium: 5, low: 9}\n"
        "  max_cycles: 1\n  on_max_cycles: continue_with_warning"
    )
    result = _validate(tmp_path, block)
    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize(
    ("line", "needle"),
    [
        ("  enabled: yes-please", "qa.enabled"),
        ("  cadence: off", "qa.cadence"),
        ("  cadence: sprint", "qa.cadence"),
        ("  position: middle", "qa.position"),
        ("  on_max_cycles: judge_decides", "qa.on_max_cycles"),
        ("  max_cycles: 0", "qa.max_cycles"),
        ("  max_cycles: true", "qa.max_cycles"),
        ("  selector: 3", "qa.selector"),
        ("  prepare: [make]", "qa.prepare"),
        ("  gate: {critical: -1}", "qa.gate.critical"),
        ("  gate: {blocker: 0}", "qa.gate"),
        ("  gate: [critical]", "qa.gate"),
        ("  nightly: true", "qa: unknown"),
    ],
)
def test_validate_qa_bad_value_rejected(tmp_path, line, needle):
    result = _validate(tmp_path, "qa:\n" + line)
    assert result.returncode == 1
    assert needle in result.stderr, result.stderr


def test_validate_qa_not_a_mapping_rejected(tmp_path):
    result = _validate(tmp_path, "qa: true")
    assert result.returncode == 1
    assert "qa: must be a mapping" in result.stderr


def test_validate_host_qa_override_checked(tmp_path):
    ok = _validate(tmp_path, extra="\nhosts:\n  pi:\n    qa: {enabled: true, cadence: stage}\n")
    assert ok.returncode == 0, ok.stderr
    bad = _validate(tmp_path, extra="\nhosts:\n  pi:\n    qa: {cadence: weekly}\n")
    assert bad.returncode == 1
    assert "hosts.pi.qa.cadence" in bad.stderr, bad.stderr
