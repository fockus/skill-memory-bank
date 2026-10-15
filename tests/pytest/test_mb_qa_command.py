"""/mb qa contract: runs in the mb-qa-runner subagent on every host, files bugs through the registry script."""

from __future__ import annotations

import re
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
COMMAND = REPO / "commands" / "qa.md"
AGENT = REPO / "agents" / "mb-qa-runner.md"


def _split(path: Path) -> tuple[dict, str]:
    _, fm, body = path.read_text(encoding="utf-8").split("---\n", 2)
    return yaml.safe_load(fm), body


def test_command_dispatches_runner_on_every_host_with_inline_fallback():
    fm, body = _split(COMMAND)
    assert "Task" in fm["allowed-tools"]
    for host in ("Claude Code", "Codex", "OpenCode", "Pi"):
        assert f"**{host}**" in body
    assert 'subagent_type="mb-qa-runner"' in body
    assert 'spawn_agent(agent_type="mb-qa-runner"' in body
    assert "agents/mb-qa-runner.md" in body and "follow it yourself" in body


def test_command_selectors_and_skill_root_are_host_neutral():
    _, body = _split(COMMAND)
    for selector in ("`all`", "`<name>`", "`@<tag>`", "`<dir>/`"):
        assert selector in body
    assert "~/.claude" not in body and "$HOME/.claude" not in body


def test_runner_can_write_and_has_a_browser_path_without_mcp():
    fm, body = _split(AGENT)
    tools = [t.strip() for t in fm["tools"].split(",")]
    assert {"Bash", "Write", "SendMessage"} <= set(tools)
    assert fm["effort"] in {"low", "medium", "high"} and "model" not in fm
    assert "@playwright/cli" in body
    assert "--browser chromium" in body and "install-browser chromium" in body


def test_runner_defines_four_severities_and_strict_report_sections():
    _, body = _split(AGENT)
    for severity in ("critical", "major", "medium", "low"):
        assert re.search(rf"^\| `{severity}` \|", body, re.M), severity
    for status in ("PASS", "FAIL", "BLOCKED", "SKIP"):
        assert re.search(rf"^\| `{status}` \|", body, re.M), status
    template = body.split("```markdown\n# QA <run_id>", 1)[1].split("```", 1)[0]
    sections = re.findall(r"^## (.+)$", template, re.M)
    assert sections == ["Results", "Bugs", "Not verified", "Cleanup"]
    assert "mb-qa-bug.sh" in body


def test_router_and_docs_list_qa():
    assert re.search(r"^\| `qa ", (REPO / "commands" / "mb.md").read_text(encoding="utf-8"), re.M)
    assert "| `/qa` |" in (REPO / "README.md").read_text(encoding="utf-8")
    assert "`mb-qa-runner`" in (REPO / "references" / "agents.md").read_text(encoding="utf-8")
