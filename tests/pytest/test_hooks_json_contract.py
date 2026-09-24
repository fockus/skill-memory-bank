"""Contract for settings/hooks.json: every registered hook reaches the model it is meant for.

Claude Code shows plain stdout to the model only for SessionStart and UserPromptSubmit;
PreCompact stdout becomes instructions for the compaction summarizer. Echo hooks on other
events are dead text, and a PreToolUse matcher must name the current subagent tool (Agent).
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOKS_JSON = REPO_ROOT / "settings" / "hooks.json"
MERGE_SCRIPT = REPO_ROOT / "settings" / "merge-hooks.py"
HOOKS_5_3_1 = REPO_ROOT / "tests" / "fixtures" / "hooks" / "hooks-5.3.1.json"

AGENT_DISPATCH_HOOKS = ("mb-context-slim-pre-agent.sh", "mb-sprint-context-guard.sh")


def _hooks() -> dict:
    return json.loads(HOOKS_JSON.read_text(encoding="utf-8"))


def _commands(event: dict) -> list[str]:
    return [h["command"] for h in event.get("hooks", [])]


def test_agent_dispatch_hooks_match_agent_and_task_tools() -> None:
    entries = [
        e for e in _hooks()["PreToolUse"]
        if any(name in cmd for cmd in _commands(e) for name in AGENT_DISPATCH_HOOKS)
    ]
    assert entries, "agent-dispatch hooks are not registered"
    for entry in entries:
        matcher = re.compile(entry["matcher"])
        assert matcher.fullmatch("Agent"), entry["matcher"]
        assert matcher.fullmatch("Task"), entry["matcher"]


def test_no_echo_hooks_on_events_the_model_never_reads() -> None:
    hooks = _hooks()
    assert "Setup" not in hooks
    for entry in hooks.get("PreToolUse", []):
        for cmd in _commands(entry):
            assert not cmd.lstrip().startswith(("echo", "cat <<")), cmd


def test_precompact_text_is_written_for_the_summarizer() -> None:
    texts = [
        cmd for entry in _hooks()["PreCompact"] for cmd in _commands(entry)
        if cmd.lstrip().startswith("echo")
    ]
    assert texts, "PreCompact guidance for the summarizer is missing"
    for text in texts:
        assert "Agent" not in text and "sonnet" not in text.lower(), text
        assert "do not call tools" in text.lower(), text


def _merge(settings: Path, hooks: Path) -> None:
    result = subprocess.run(
        [sys.executable, str(MERGE_SCRIPT), str(settings), str(hooks)],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr


def test_upgrade_from_5_3_1_drops_dead_hooks_and_keeps_user_hooks(tmp_path: Path) -> None:
    settings = tmp_path / "settings.json"
    user_hook = {"matcher": "Write", "hooks": [{"type": "command", "command": "~/my-own-hook.sh"}]}
    settings.write_text(json.dumps({"hooks": {"PreToolUse": [user_hook]}}), encoding="utf-8")

    _merge(settings, HOOKS_5_3_1)
    _merge(settings, HOOKS_JSON)

    merged = json.loads(settings.read_text(encoding="utf-8"))["hooks"]
    all_commands = [cmd for entries in merged.values() for e in entries for cmd in _commands(e)]
    assert "Setup" not in merged
    assert not any("[PRE-WRITE]" in cmd for cmd in all_commands)
    assert not any("run MB Manager" in cmd for cmd in all_commands)
    assert "~/my-own-hook.sh" in all_commands
    skill_entries = [
        (event, e.get("matcher"), cmd)
        for event, entries in merged.items() for e in entries for cmd in _commands(e)
        if "memory-bank-skill" in cmd
    ]
    assert len(skill_entries) == len(set(skill_entries)), "duplicate skill hook entries"
