"""Native command contracts, exercised through the installed Pi loader."""

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / "tests/fixtures/pi_native_host.mjs"


def host(tmp_path, cwd, **kwargs):
    home = tmp_path / "home"
    home.mkdir(exist_ok=True)
    env = {**os.environ, "HOME": str(home), "MB_AGENT": "pi"}
    env.pop("MB_PATH", None)
    proc = subprocess.run(
        ["node", str(HOST)],
        cwd=ROOT,
        env=env,
        input=json.dumps({"home": str(home), "cwd": str(cwd), **kwargs}),
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert proc.returncode == 0, proc.stderr
    return json.loads(proc.stdout.strip().splitlines()[-1])


def bank(path, marker="PROJECT_A"):
    path.mkdir(parents=True, exist_ok=True)
    for name in ["status", "checklist", "roadmap", "research"]:
        (path / f"{name}.md").write_text(f"# {name}\n{marker}\n")
    return path


@pytest.mark.parametrize("subdir", [False, True], ids=["root", "subfolder"])
@pytest.mark.parametrize("layout", ["local", "legacy", "global"])
def test_context_restores_resolved_bank_without_llm(tmp_path, layout, subdir):
    cwd = tmp_path / "project"
    cwd.mkdir()
    home = tmp_path / "home"
    home.mkdir()
    if layout == "local":
        mb = bank(cwd / ".memory-bank")
    elif layout == "legacy":
        mb = bank(home / ".claude/workspaces/sample/.memory-bank")
        (cwd / ".claude-workspace").write_text("storage: external\nproject_id: sample\n")
    else:
        # Use the public initializer to establish a real host registry entry.
        # Registry is rooted in cwd, so initialize via absolute script from project.
        proc = subprocess.run(
            ["bash", str(ROOT / "scripts/mb-init-bank.sh"), "--storage=global", "--agent=pi"],
            cwd=cwd,
            env={**os.environ, "HOME": str(home)},
            text=True,
            capture_output=True,
        )
        assert proc.returncode == 0, proc.stderr
        resolved = subprocess.check_output(
            [
                "bash",
                "-c",
                'source "$1"; MB_AGENT=pi mb_resolve_path',
                "_",
                str(ROOT / "scripts/_lib.sh"),
            ],
            cwd=cwd,
            env={**os.environ, "HOME": str(home)},
            text=True,
        ).strip()
        mb = bank(Path(resolved))
    # Pi started in a project subfolder walks up to the project's bank.
    start = cwd / "src" / "deep" if subdir else cwd
    start.mkdir(parents=True, exist_ok=True)
    result = host(tmp_path, start, args="context")
    assert not result.get("error"), result
    assert any("PROJECT_A" in m.get("content", "") for m in result["messages"]), result
    assert not any(m["kind"] == "user" for m in result["messages"])
    assert not result["launches"]
    assert mb.exists()


def test_start_alias_uses_same_native_restore(tmp_path):
    bank(tmp_path / ".memory-bank", "START_RESTORED")
    result = host(tmp_path, tmp_path, command="start")
    assert any("START_RESTORED" in m.get("content", "") for m in result["messages"]), result


def test_no_bank_fails_without_initializing(tmp_path):
    result = host(tmp_path, tmp_path, args="work sample --range 1")
    assert result.get("error") and "bank" in result["error"].lower(), result
    assert not (tmp_path / ".memory-bank").exists()
    assert not result["launches"]


def test_goal_collision_and_all_template_aliases(tmp_path):
    bank(tmp_path / ".memory-bank")
    result = host(tmp_path, tmp_path, args="goal quoted; value")
    assert "goal" not in result["commands"]
    expected = {"mb-" + p.stem for p in (ROOT / "commands").glob("*.md") if p.stem != "mb"}
    assert expected <= set(result["commands"]), result
    assert any(
        "quoted; value" in m.get("text", "") and "# /mb goal" in m.get("text", "")
        for m in result["messages"]
    ), result


def test_quotes_and_semicolon_are_not_executable(tmp_path):
    bank(tmp_path / ".memory-bank")
    result = host(tmp_path, tmp_path, args='context " ; touch OWNED ; "')
    assert result.get("error"), result
    assert not (tmp_path / "OWNED").exists()
