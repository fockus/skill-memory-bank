"""mb-team Stage 6 (T-ENGINE): `mb-work-plan.sh --step-model role=model`.

A team track in `mode: work` passes its verifier/reviewer/judge models to the
engine; the override touches only the named step and nothing else.
"""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest

pytest.importorskip("yaml")

REPO_ROOT = Path(__file__).resolve().parents[2]
WORK_PLAN = REPO_ROOT / "scripts" / "mb-work-plan.sh"
DEFAULT = REPO_ROOT / "references" / "pipeline.default.yaml"


def _bank(tmp_path: Path, stages: int = 2) -> tuple[Path, Path]:
    mb = tmp_path / ".memory-bank"
    (mb / "plans" / "done").mkdir(parents=True)
    (mb / "specs").mkdir()
    (mb / "checklist.md").write_text("# Checklist\n", encoding="utf-8")
    (mb / "roadmap.md").write_text(
        "# Roadmap\n\n<!-- mb-active-plans -->\n<!-- /mb-active-plans -->\n", encoding="utf-8")
    (mb / "pipeline.yaml").write_text(DEFAULT.read_text(encoding="utf-8"), encoding="utf-8")
    body = "".join(f"<!-- mb-stage:{n} -->\n## Stage {n}: do {n}\n\n- ⬜ DoD bit\n\n"
                   for n in range(1, stages + 1))
    plan = mb / "plans" / "p.md"
    plan.write_text("---\ntype: feature\ntopic: foo\nstatus: in-progress\n---\n\n# Plan\n\n" + body,
                    encoding="utf-8")
    return mb, plan


def _run(mb: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(WORK_PLAN), "--mb", str(mb), "--host", "claude-code", *args],
        capture_output=True, text=True, check=False, env=dict(os.environ))


def _items(mb: Path, *args: str) -> list[dict]:
    r = _run(mb, *args)
    assert r.returncode == 0, r.stderr
    return [json.loads(x) for x in r.stdout.splitlines() if x.startswith("{")]


def test_step_model_reviewer_overrides_only_the_reviewer(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    base = _items(mb, "--target", str(plan))
    over = _items(mb, "--target", str(plan), "--step-model", "reviewer=opus")
    for b, o in zip(base, over, strict=True):
        assert o["step_models"]["reviewer"] == "opus"
        assert o["step_models"]["verifier"] == b["step_models"]["verifier"]
        assert o["step_models"]["judge"] == b["step_models"]["judge"]
        assert {k: v for k, v in o.items() if k != "step_models"} == \
               {k: v for k, v in b.items() if k != "step_models"}


def test_step_model_is_repeatable(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    item = _items(mb, "--target", str(plan), "--step-model", "verifier=sonnet",
                  "--step-model=judge=opus")[0]
    assert item["step_models"]["verifier"] == "sonnet"
    assert item["step_models"]["judge"] == "opus"


def test_step_model_reaches_every_plan_of_a_multi_target_run(tmp_path: Path) -> None:
    mb, plan = _bank(tmp_path)
    second = plan.with_name("q.md")
    second.write_text(plan.read_text(encoding="utf-8").replace("topic: foo", "topic: bar"),
                      encoding="utf-8")
    items = _items(mb, "--target", str(plan), "--target", str(second),
                   "--step-model", "reviewer=opus")
    assert len(items) == 4
    assert {i["step_models"]["reviewer"] for i in items} == {"opus"}


@pytest.mark.parametrize("value", ["implementer=opus", "reviewer", "reviewer=", "=opus"])
def test_step_model_invalid_role_or_form_exits_2(tmp_path: Path, value: str) -> None:
    mb, plan = _bank(tmp_path)
    r = _run(mb, "--target", str(plan), "--step-model", value)
    assert r.returncode == 2
    assert "--step-model" in r.stderr
