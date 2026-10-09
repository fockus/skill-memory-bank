"""Native Codex registration preserves user state and works from any project."""

import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
INSTALLER = ROOT / "adapters/codex-native-hooks.py"
EVENTS = {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact", "Stop", "SessionEnd", "SubagentStart"}


def native(action, target, installer=INSTALLER):
    return subprocess.run([sys.executable, str(installer), action, str(target)],
                          capture_output=True, text=True, check=False)


@pytest.mark.parametrize("value", [None, 1, [], "broken", {"hooks": [1]}, {"hooks": None}])
def test_malformed_groups_preserve_original_bytes(tmp_path, value):
    path = tmp_path / "hooks.json"
    original = json.dumps({"hooks": {"Stop": [value]}}) + "  \n"
    path.write_text(original)
    result = native("install", tmp_path)
    assert result.returncode != 0
    assert path.read_text() == original
    assert not (tmp_path / "config.toml").exists()


def test_uninstall_removes_owned_legacy_and_native_only(tmp_path):
    foreign = {"type": "command", "command": "echo foreign"}
    original = {"hooks": {
        "UserPromptSubmit": [{"matcher": "*", "hooks": [foreign, {"_mb_owned": True}]}],
        "userpromptsubmit": [{"_mb_owned": True}, foreign],
        "Stop": [{"hooks": [{"_mb_codex_native": True}]}],
        "SessionEnd": [],
    }}
    path = tmp_path / "hooks.json"
    path.write_text(json.dumps(original))
    result = native("uninstall", tmp_path)
    assert result.returncode == 0, result.stderr
    assert json.loads(path.read_text()) == {"hooks": {
        "UserPromptSubmit": [{"matcher": "*", "hooks": [foreign]}],
        "userpromptsubmit": [foreign], "SessionEnd": [],
    }}


def test_uninstall_without_owned_hooks_is_byte_preserving(tmp_path):
    path = tmp_path / "hooks.json"
    original = '{"hooks": {"Stop": []}}  \n'
    path.write_text(original)
    assert native("uninstall", tmp_path).returncode == 0
    assert path.read_text() == original
    assert not (tmp_path / "hooks.json.pre-mb-native").exists()


def test_install_from_skill_alias_keeps_installed_alias_in_command(tmp_path):
    alias = tmp_path / "installed skill"
    alias.symlink_to(ROOT, target_is_directory=True)
    target = tmp_path / "codex"
    result = native("install", target, alias / "adapters/codex-native-hooks.py")
    assert result.returncode == 0, result.stderr
    data = json.loads((target / "hooks.json").read_text())
    assert set(data["hooks"]) == EVENTS
    command = data["hooks"]["SessionStart"][0]["hooks"][0]["command"]
    assert shlex.split(command)[1] == str(alias / "hooks/mb-codex.py")


def test_default_install_global_roundtrip_and_selected_project_migration(tmp_path):
    home = tmp_path / "home"
    project = tmp_path / "project"
    codex = tmp_path / "custom codex"
    project.mkdir()
    codex.mkdir()
    home.mkdir()
    foreign = {"type": "command", "command": "echo foreign"}
    hooks = codex / "hooks.json"
    hooks.write_text(json.dumps({"hooks": {"Stop": [{"hooks": [foreign]}]}}))
    config = codex / "config.toml"
    original_config = 'approval_policy = "never"\n[hooks]\n'
    config.write_text(original_config)
    local = project / ".codex"
    local.mkdir()
    (local / "hooks.json").write_text(json.dumps({"hooks": {
        "UserPromptSubmit": [{"hooks": [foreign, {"_mb_owned": True}]}],
        "Stop": [{"hooks": [{"_mb_codex_native": True}]}],
    }}))
    bank = project / ".memory-bank"
    bank.mkdir()
    pipeline = (ROOT / "references/pipeline.default.yaml").read_text()
    (bank / "pipeline.yaml").write_text(pipeline.replace("gpt-6.1-sol", "gpt-project-private-model"))
    manifest = tmp_path / "manifest.json"
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    env.update(HOME=str(home), CODEX_HOME=str(codex), MB_MANIFEST_PATH=str(manifest),
               MB_SKIP_DEPS_CHECK="1", MB_PYTHON=sys.executable, MB_UPDATE_CHECK="off",
               MB_GRAPH_CATCHUP="off", MB_GRAPH_AUTOUPDATE="off")
    for _ in range(2):
        result = subprocess.run(["bash", str(ROOT / "install.sh"), "--non-interactive",
                                 "--language", "en", "--project-root", str(project)],
                                cwd=project, env=env, capture_output=True, text=True, timeout=120)
        assert result.returncode == 0, result.stdout + result.stderr
    data = json.loads(hooks.read_text())
    assert set(data["hooks"]) == EVENTS
    for groups in data["hooks"].values():
        assert sum(h.get("_mb_codex_native") is True for g in groups for h in g["hooks"]) == 1
    assert data["hooks"]["Stop"][0]["hooks"] == [foreign]
    assert config.read_text() == original_config
    assert str(codex / "skills/memory-bank/SKILL.md") in (codex / "AGENTS.md").read_text()
    assert json.loads((local / "hooks.json").read_text()) == {"hooks": {
        "UserPromptSubmit": [{"hooks": [foreign]}]}}
    assert "gpt-project-private-model" not in (codex / "agents/mb-developer.toml").read_text()
    command = data["hooks"]["SessionStart"][0]["hooks"][0]["command"]
    assert str(ROOT) not in command
    other_project = tmp_path / "other project"
    other_project.mkdir()
    executed = subprocess.run(shlex.split(command), input=json.dumps({
        "hook_event_name": "SessionStart", "cwd": str(other_project), "session_id": "install-test"}),
        cwd=other_project, env=env, capture_output=True, text=True, timeout=60)
    assert executed.returncode == 0, executed.stderr
    assert not (other_project / ".memory-bank").exists()
    data["hooks"]["Stop"][0]["hooks"].append({"type": "command", "command": "echo later"})
    hooks.write_text(json.dumps(data))
    result = subprocess.run(["bash", str(ROOT / "uninstall.sh"), "-y"], cwd=project, env=env,
                            capture_output=True, text=True, timeout=120)
    assert result.returncode == 0, result.stdout + result.stderr
    assert json.loads(hooks.read_text()) == {"hooks": {"Stop": [{"hooks": [
        foreign, {"type": "command", "command": "echo later"}]}]}}
    assert config.read_text() == original_config


@pytest.mark.parametrize("legacy", [False, True])
def test_project_adapter_uses_global_native_hooks_without_duplicate_prompt_guard(tmp_path, legacy):
    project = tmp_path / "project"
    target = tmp_path / "global"
    project.mkdir()
    assert native("install", target).returncode == 0
    local = project / ".codex"
    local.mkdir()
    if legacy:
        (local / "hooks.json").write_text(json.dumps({"hooks": {
            "UserPromptSubmit": [{"hooks": [{"_mb_owned": True}]}]}}))
    env = dict(os.environ, CODEX_HOME=str(target), MB_PYTHON=sys.executable)
    result = subprocess.run(["bash", str(ROOT / "adapters/codex.sh"), "install", str(project)],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    if legacy:
        assert json.loads((local / "hooks.json").read_text()) == {"hooks": {}}
    else:
        assert not (local / "hooks.json").exists()
    assert not (local / "hooks/before-prompt.sh").exists()
    assert "approval_policy" not in (local / "config.toml").read_text()
    manifest = json.loads((local / ".mb-manifest.json").read_text())
    assert manifest["platform_limited"] == ["statusline"]
    assert "session-memory" not in manifest["platform_limited_notes"]
    assert "lifecycle-hooks" not in manifest["platform_limited_notes"]


def test_reinstall_restores_missing_discovery_config(tmp_path):
    assert native("install", tmp_path).returncode == 0
    config = tmp_path / "config.toml"
    config.unlink()
    assert native("install", tmp_path).returncode == 0
    assert config.is_file()
