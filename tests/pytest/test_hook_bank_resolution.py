"""Core context and recall share bank resolution across storage layouts."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture
def workspace(tmp_path):
    project = tmp_path / "project"
    nested = project / "src" / "feature"
    nested.mkdir(parents=True)
    home = tmp_path / "home"
    home.mkdir()
    env = dict(os.environ, HOME=str(home), MB_AGENT="codex", MB_SKILL_ROOT=str(ROOT))
    for key in ("MB_PATH", "MB_PROJECT_ROOT", "MB_ROOT", "MB_INDEX_DIR", "MB_CAPTURE_SUBPROCESS", "CODEX_HOME"):
        env.pop(key, None)
    return project, nested, home, env


def make_bank(workspace, layout):
    project, nested, home, env = workspace
    bank = project / ".memory-bank" if layout == "ancestor" else home / "stored-bank"
    bank.mkdir()
    if layout == "override":
        env["MB_PATH"] = str(bank)
    elif layout in ("registry", "codex_home"):
        config = home / ".codex"
        if layout == "codex_home":
            config = home / "custom-codex"
            env["CODEX_HOME"] = str(config)
        registry = config / "memory-bank" / "registry.json"
        registry.parent.mkdir(parents=True)
        registry.write_text(json.dumps({"projects": {str(project.resolve()): {"bank_path": str(bank)}}}))
    elif layout == "legacy":
        bank.rmdir()
        bank = home / ".claude" / "workspaces" / "sample" / ".memory-bank"
        bank.mkdir(parents=True)
        (project / ".claude-workspace").write_text("storage: external\nproject_id: sample\n")
    return bank


@pytest.mark.parametrize("layout", ["ancestor", "override", "registry", "codex_home", "legacy"])
@pytest.mark.parametrize("entry", ["hook", "session"])
def test_resolver_finds_existing_bank_from_nested_cwd(workspace, layout, entry):
    bank = make_bank(workspace, layout)
    _, nested, _, env = workspace
    helper, function = (
        ("_skill_root.sh", "mb_hook_resolve_mb_path")
        if entry == "hook"
        else ("lib/session-common.sh", "sc_resolve_mb")
    )
    result = subprocess.run(
        ["bash", "-c", f'. "$1"; {function} "$2"', "probe", str(ROOT / "hooks" / helper), str(nested)],
        env=env, cwd=nested, capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert Path(result.stdout.strip()).resolve() == bank.resolve()


@pytest.mark.parametrize("layout", ["ancestor", "override", "registry", "codex_home"])
def test_codex_core_and_recall_read_same_bank(workspace, layout):
    bank = make_bank(workspace, layout)
    _, nested, _, env = workspace
    (bank / "notes").mkdir()
    (bank / "status.md").write_text("Restore Orion core state.\n")
    (bank / "notes" / "orion-cache.md").write_text(
        "# Orion cache decision\n\nSQLite WAL keeps Orion cache readers from blocking writers.\n"
    )
    env.update(MB_GRAPH_CATCHUP="off", MB_UPDATE_CHECK="off", MB_CORE_CAP="off",
               MB_SEMANTIC_BACKEND="bm25", MB_SEMANTIC_PY=sys.executable)
    for event, expected in (("SessionStart", "Restore Orion core state."),
                            ("UserPromptSubmit", "notes/orion-cache.md")):
        result = subprocess.run(
            [sys.executable, str(ROOT / "hooks" / "mb-codex.py")],
            input=json.dumps({"hook_event_name": event, "cwd": str(nested), "session_id": "chat-B",
                              "prompt": "Why does SQLite WAL keep Orion cache readers from blocking writers?"}),
            env=env, cwd=nested, capture_output=True, text=True, check=False,
        )
        assert result.returncode == 0, result.stderr
        context = json.loads(result.stdout).get("hookSpecificOutput", {}).get("additionalContext", "")
        assert expected in context
    assert not (nested / ".memory-bank").exists()


def test_explicit_bank_wins_over_local_bank(workspace):
    bank = make_bank(workspace, "override")
    project, nested, _, env = workspace
    (project / ".memory-bank").mkdir()
    result = subprocess.run(
        ["bash", "-c", '. "$1"; sc_resolve_mb "$2"', "probe",
         str(ROOT / "hooks/lib/session-common.sh"), str(nested)],
        env=env, cwd=nested, capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert Path(result.stdout.strip()).resolve() == bank.resolve()


@pytest.mark.parametrize("layout", ["registry", "legacy"])
@pytest.mark.parametrize("entry", ["hook", "session"])
def test_project_registration_wins_over_parent_local_bank(workspace, layout, entry):
    bank = make_bank(workspace, layout)
    project, nested, _, env = workspace
    (project.parent / ".memory-bank").mkdir()
    helper, function = (
        ("_skill_root.sh", "mb_hook_resolve_mb_path")
        if entry == "hook"
        else ("lib/session-common.sh", "sc_resolve_mb")
    )
    result = subprocess.run(
        ["bash", "-c", f'. "$1"; {function} "$2"', "probe", str(ROOT / "hooks" / helper), str(nested)],
        env=env, cwd=nested, capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert Path(result.stdout.strip()).resolve() == bank.resolve()


def test_session_capture_does_not_create_missing_override_bank(workspace):
    make_bank(workspace, "ancestor")
    project, nested, home, env = workspace
    missing_bank = home / "not-initialized"
    env["MB_PATH"] = str(missing_bank)
    result = subprocess.run(
        ["bash", str(ROOT / "hooks/mb-session-turn.sh")],
        input=json.dumps({"cwd": str(nested), "session_id": "no-shadow-bank"}),
        env=env, cwd=nested, capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert not missing_bank.exists()
    assert not (project / ".memory-bank/session").exists()


def test_claude_session_hook_uses_claude_registry_with_cursor_installed(workspace):
    project, nested, home, env = workspace
    env.pop("MB_AGENT")
    (home / ".cursor/skills/memory-bank").mkdir(parents=True)
    for agent in ("claude", "cursor"):
        bank = home / f"{agent}-bank"
        (bank / "session").mkdir(parents=True)
        (bank / "session/_recent.md").write_text(f"Saved {agent} session history.\n")
        registry = home / f".{agent}/memory-bank/registry.json"
        registry.parent.mkdir(parents=True)
        registry.write_text(json.dumps({"projects": {str(project.resolve()): str(bank)}}))
    env.update(CLAUDE_PROJECT_DIR=str(nested), MB_GRAPH_CATCHUP="off", MB_SESSION_CHEATSHEET="off")
    result = subprocess.run(
        ["bash", str(ROOT / "hooks/mb-session-start.sh")],
        env=env, cwd=nested, capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    assert "Saved claude session history." in result.stdout
    assert "Saved cursor session history." not in result.stdout
