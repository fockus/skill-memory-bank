"""proportional-effort Sprint 2 Stage 3a — instruction tone by model strength (AGR-068).

The engineering core is calm and gives reasons; the strict addendum (Iron Law, NEVER phrasings,
rationalization table) is a separate partial that `/mb work` appends for models matching
`pipeline.yaml: discipline.strict_models`.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
AGENTS = REPO_ROOT / "agents"
WORK_PLAN = REPO_ROOT / "scripts" / "mb-work-plan.sh"
DEFAULT_PIPELINE = REPO_ROOT / "references" / "pipeline.default.yaml"


def test_core_has_no_rationalization_table_or_never() -> None:
    core = (AGENTS / "mb-engineering-core.md").read_text(encoding="utf-8")
    assert "Rationalization table" not in core
    assert "NEVER" not in core
    assert "Iron Law" not in core


def test_strict_partial_is_a_partial_carrying_the_iron_law() -> None:
    strict = (AGENTS / "mb-discipline-strict.md").read_text(encoding="utf-8")
    assert strict.splitlines()[1].strip() == "partial: true"
    assert "EVIDENCE BEFORE CLAIMS, ALWAYS." in strict
    assert "Rationalization table" in strict
    assert "SendMessage to the dispatcher, or it didn't happen" in strict


def test_work_md_appends_strict_partial_on_strict_discipline() -> None:
    work = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")
    assert '"$SKILL_DIR"/agents/mb-discipline-strict.md' in work
    assert "discipline" in work


def test_default_pipeline_lists_strict_models() -> None:
    yaml = pytest.importorskip("yaml")
    cfg = yaml.safe_load(DEFAULT_PIPELINE.read_text(encoding="utf-8"))
    patterns = cfg["discipline"]["strict_models"]
    assert any("haiku" in p for p in patterns)
    assert all(isinstance(p, str) and p for p in patterns)


def test_default_pipeline_with_discipline_still_validates() -> None:
    r = subprocess.run(
        ["bash", str(REPO_ROOT / "scripts" / "mb-pipeline-validate.sh"), str(DEFAULT_PIPELINE)],
        capture_output=True, text=True, check=False,
    )
    assert r.returncode == 0, r.stderr


def _bank_with_plan(tmp_path: Path, pipeline: str) -> tuple[Path, Path]:
    mb = tmp_path / ".memory-bank"
    (mb / "plans" / "done").mkdir(parents=True)
    (mb / "specs").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n", encoding="utf-8")
    (mb / "pipeline.yaml").write_text(pipeline, encoding="utf-8")
    plan = mb / "plans" / "p.md"
    plan.write_text(
        "---\ntype: feature\ntopic: foo\nstatus: in-progress\n---\n\n# Plan\n\n"
        "<!-- mb-stage:1 -->\n## Stage 1: do A\n\n- ⬜ DoD bit\n", encoding="utf-8")
    return mb, plan


def _pipeline(model: str, discipline: str = "") -> str:
    return f"version: 1\nroles:\n  developer: {{ agent: mb-developer, model: {model} }}\n" + discipline


def _discipline(mb: Path, plan: Path) -> str:
    r = subprocess.run(["bash", str(WORK_PLAN), "--target", str(plan), "--mb", str(mb)],
                       capture_output=True, text=True, check=False)
    assert r.returncode == 0, r.stderr
    item = json.loads(r.stdout.strip().splitlines()[0])
    return item["discipline"]


@pytest.mark.parametrize(
    ("model", "expected"),
    [("haiku", "strict"), ("claude-haiku-4-5", "strict"), ("gpt-5-mini", "strict"),
     ("ollama/qwen2.5-coder", "strict"), ("opus", "calm"), ("sonnet", "calm")],
)
def test_work_plan_discipline_follows_model(tmp_path: Path, model: str, expected: str) -> None:
    mb, plan = _bank_with_plan(tmp_path, _pipeline(model))
    assert _discipline(mb, plan) == expected


def test_project_override_of_strict_models(tmp_path: Path) -> None:
    mb, plan = _bank_with_plan(
        tmp_path, _pipeline("opus", "discipline:\n  strict_models: [\"opus\"]\n"))
    assert _discipline(mb, plan) == "strict"


def test_project_pipeline_without_discipline_falls_back_to_default_list(tmp_path: Path) -> None:
    mb, plan = _bank_with_plan(tmp_path, _pipeline("haiku"))
    assert _discipline(mb, plan) == "strict"
