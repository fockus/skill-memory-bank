"""The graph answer is pushed into every /mb work dispatch, not left to agent initiative."""
import os
import re
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
WORK = (ROOT / "commands" / "work.md").read_text(encoding="utf-8")
COMPOSING = ("mb-judge", "mb-reviewer-lead", "mb-reviewer-logic")


def _section(heading_prefix: str) -> str:
    m = re.search(rf"^ *### {re.escape(heading_prefix)}.*?(?=^ *### |^## )", WORK, re.S | re.M)
    assert m, f"section {heading_prefix} missing in commands/work.md"
    return m.group(0)


def test_graph_context_step_defines_cap_and_fail_open():
    body = _section("5a0c")
    assert "mb-graph.sh" in body and "## Graph" in body
    assert "40" in body
    assert "stale" in body and "absent" in body


@pytest.mark.parametrize("step", ["5a.", "5d.", "5e."])
def test_dispatch_steps_inject_graph_section(step):
    assert "## Graph" in _section(step)


@pytest.mark.parametrize("agent", COMPOSING)
def test_agent_composes_tooling_core(agent):
    text = (ROOT / "agents" / f"{agent}.md").read_text(encoding="utf-8")
    front = text.split("---", 2)[1]
    assert re.search(r"^compose:.*mb-tooling-core", front, re.M)


def test_implementer_report_has_optional_graph_line_and_verifier_info():
    core = (ROOT / "agents" / "mb-engineering-core.md").read_text(encoding="utf-8")
    assert "Graph: <n> queries" in core
    verifier = (ROOT / "agents" / "plan-verifier.md").read_text(encoding="utf-8")
    assert "Graph:" in verifier and "INFO" in verifier


@pytest.mark.parametrize("client", ["claude-code", "codex"])
def test_rendered_judge_contains_graph_wrapper(client, tmp_path):
    home, project = tmp_path / "home", tmp_path / "project"
    home.mkdir()
    project.mkdir()
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    env.update(HOME=str(home), CODEX_HOME=str(home / ".codex"), MB_SKIP_DEPS_CHECK="1",
               MB_PYTHON=sys.executable, MB_UPDATE_CHECK="off", MB_GRAPH_CATCHUP="off",
               MB_GRAPH_AUTOUPDATE="off", MB_MANIFEST_PATH=str(tmp_path / "manifest.json"))
    proc = subprocess.run(
        ["bash", str(ROOT / "install.sh"), "--non-interactive", "--clients", client,
         "--language", "en", "--project-root", str(project)],
        env=env, cwd=project, capture_output=True, text=True, timeout=300,
    )
    judges = [p for p in home.rglob("mb-judge*") if p.is_file()]
    assert judges, proc.stdout[-500:] + proc.stderr[-500:]
    assert any("mb-graph.sh" in p.read_text(encoding="utf-8") for p in judges)
