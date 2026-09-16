"""Real installer/init contracts in copied bundles and subprocess-scoped homes."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]
PI_SKILL = "~/.pi/agent/skills/memory-bank"


@pytest.fixture
def sandbox(tmp_path: Path) -> tuple[Path, Path, dict[str, str]]:
    home = tmp_path / "isolated home"
    project = tmp_path / "project with spaces"
    home.mkdir()
    project.mkdir()
    env = {key: value for key, value in os.environ.items() if not key.startswith("MB_")}
    env.update(
        HOME=str(home),
        XDG_CONFIG_HOME=str(home / ".config"),
        XDG_DATA_HOME=str(home / ".local/share"),
        XDG_CACHE_HOME=str(home / ".cache"),
        PYTHONPATH="",
        MB_PYTHON=sys.executable,
        MB_SKIP_DEPS_CHECK="1",
        MB_GRAPH_AUTOUPDATE="off",
    )
    return home, project, env


def copy_bundle(destination: Path) -> Path:
    destination.mkdir(parents=True)
    for name in (
        "install.sh", "uninstall.sh", "VERSION", "SKILL.md", "adapters", "agents",
        "commands", "hooks", "rules", "scripts", "references", "settings", "templates",
        "flow-templates", "memory_bank_skill",
    ):
        source = REPO / name
        if source.is_dir():
            shutil.copytree(source, destination / name, ignore=shutil.ignore_patterns("__pycache__"))
        else:
            shutil.copy2(source, destination / name)
    return destination


def run_script(
    script: Path, project: Path, env: dict[str, str], *args: str,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(script), *args], cwd=project, env=env,
        input="", text=True, capture_output=True, timeout=90,
    )


def install(bundle: Path, project: Path, env: dict[str, str], clients: str = "claude-code") -> None:
    result = run_script(
        bundle / "install.sh", project, env, "--non-interactive", "--clients", clients,
        "--language", "en", "--project-root", str(project),
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_pi_settings_roundtrip_preserves_existing_and_later_user_changes(
    sandbox: tuple[Path, Path, dict[str, str]], tmp_path: Path,
) -> None:
    home, project, env = sandbox
    bundle = copy_bundle(tmp_path / "bundle")
    settings = home / ".pi/agent/settings.json"
    settings.parent.mkdir(parents=True)
    original = {"theme": "custom", "packages": ["npm:user-package"], "skills": ["~/user-skill"]}
    settings.write_text(json.dumps(original))
    install(bundle, project, env)
    installed = json.loads(settings.read_text())
    assert PI_SKILL in installed["skills"]
    installed["theme"] = "changed-after-install"
    installed["skills"].append("~/later-skill")
    installed["customOption"] = {"enabled": True}
    settings.write_text(json.dumps(installed))
    install(bundle, project, env)

    result = run_script(bundle / "uninstall.sh", project, env, "-y")

    assert result.returncode == 0, result.stdout + result.stderr
    assert settings.is_file(), "uninstall removed the user's Pi settings.json"
    expected = {**installed, "skills": ["~/user-skill", "~/later-skill"]}
    assert json.loads(settings.read_text()) == expected


@pytest.mark.parametrize("relative", [".claude/RULES.md", ".claude/commands/mb.md", ".pi/agent/skills/memory-bank/SKILL.md"])
def test_identical_reinstall_retains_original_backup_and_restores_it(
    sandbox: tuple[Path, Path, dict[str, str]], tmp_path: Path, relative: str,
) -> None:
    home, project, env = sandbox
    bundle = copy_bundle(tmp_path / "bundle")
    original = home / relative
    original.parent.mkdir(parents=True)
    original.write_text("Original user content\n")
    install(bundle, project, env)
    first = json.loads((bundle / ".installed-manifest.json").read_text())
    backed_up_path = original.parent if relative.endswith("/SKILL.md") else original
    mapping = next(entry for entry in first["backups"] if entry.startswith(f"{backed_up_path}|"))
    install(bundle, project, env)
    second = json.loads((bundle / ".installed-manifest.json").read_text())
    result = run_script(bundle / "uninstall.sh", project, env, "-y")

    assert result.returncode == 0, result.stdout + result.stderr
    assert mapping in second["backups"], "reinstall orphaned the original backup mapping"
    assert original.read_text() == "Original user content\n"
    assert not Path(mapping.split("|", 1)[1]).exists()


def test_uninstall_from_canonical_bundle_completes_global_and_project_cleanup(
    sandbox: tuple[Path, Path, dict[str, str]],
) -> None:
    home, project, env = sandbox
    bundle = copy_bundle(home / ".claude/skills/skill-memory-bank")
    rules = home / ".claude/RULES.md"
    rules.write_text("Original user rules\n")
    agents = home / ".codex/AGENTS.md"
    agents.parent.mkdir(parents=True)
    agents.write_text("Keep my Codex instructions\n")
    project_agents = project / "AGENTS.md"
    project_agents.write_text("Keep my project instructions\n")
    install(bundle, project, env, clients="codex")
    assert (project / ".codex/.mb-manifest.json").is_file()
    assert "memory-bank-codex:start" in agents.read_text()

    result = run_script(bundle / "uninstall.sh", project, env, "-y")

    assert result.returncode == 0, result.stdout + result.stderr
    assert "memory-bank-codex:start" not in agents.read_text()
    assert "Keep my Codex instructions" in agents.read_text()
    assert "memory-bank:start" not in project_agents.read_text()
    assert "Keep my project instructions" in project_agents.read_text()
    assert not (project / ".codex/.mb-manifest.json").exists()
    assert not (project / ".codex/hooks.json").exists()
    assert not (home / ".cursor/.mb-manifest.json").exists()
    assert rules.read_text() == "Original user rules\n"
    assert not bundle.exists()


@pytest.mark.parametrize("storage", ["local", "global"])
@pytest.mark.parametrize("separate", [False, True], ids=["equals", "separate"])
def test_init_explicit_project_root_selects_target_from_another_cwd(
    sandbox: tuple[Path, Path, dict[str, str]], tmp_path: Path, storage: str, separate: bool,
) -> None:
    home, project, env = sandbox
    cwd = tmp_path / "different cwd"
    cwd.mkdir()
    root_args = ["--project-root", str(project)] if separate else [f"--project-root={project}"]

    result = run_script(
        REPO / "scripts/mb-init-bank.sh", cwd, env,
        f"--storage={storage}", "--agent=pi", *root_args,
    )

    assert result.returncode == 0, result.stdout + result.stderr
    assert not (cwd / ".memory-bank").exists()
    if storage == "local":
        assert (project / ".memory-bank/status.md").is_file()
    else:
        registry = json.loads((home / ".pi/agent/memory-bank/registry.json").read_text())
        assert list(registry["projects"]) == [str(project.resolve())]
        assert Path(registry["projects"][str(project.resolve())]["bank_path"], "status.md").is_file()
        assert not (project / ".memory-bank").exists()


@pytest.mark.parametrize("args", [
    ["--project-root"], ["--project-root", "--force"], ["--project-root="],
    ["--unknown"], ["unexpected-path"], ["--lang"], ["--storage="], ["--agent="],
    ["--project-root", "-h"],
])
def test_init_invalid_arguments_fail_before_filesystem_mutation(
    sandbox: tuple[Path, Path, dict[str, str]], args: list[str],
) -> None:
    home, project, env = sandbox

    result = run_script(REPO / "scripts/mb-init-bank.sh", project, env, *args)

    assert result.returncode == 2, result.stdout + result.stderr
    assert "mb-init-bank" in result.stderr
    assert list(project.iterdir()) == []
    assert list(home.iterdir()) == []
