"""Execute the documented command paths from a project outside the skill bundle."""

import json
import os
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def _block(command: str, section: str, index: int = 0) -> str:
    text = (ROOT / "commands" / command).read_text()
    tail = text.split(section, 1)[1]
    return re.findall(r"```bash\n(.*?)\n```", tail, re.S)[index]


def _run(tmp_path: Path, block: str, *, setup: str = "", **extra):
    project = tmp_path / "project with spaces"
    bank = tmp_path / "personal bank" / ".memory-bank"
    project.mkdir(exist_ok=True)
    bank.mkdir(parents=True, exist_ok=True)
    env = {key: value for key, value in os.environ.items() if not key.startswith("MB_")}
    env.update(SKILL_DIR=str(ROOT), MB_PATH=str(bank), BANK=str(bank))
    env.update(extra)
    return subprocess.run(
        ["bash", "-eu", "-c", setup + "\n" + block],
        cwd=project, env=env, capture_output=True, text=True,
    )


def test_start_global_bank_is_active_without_repo_local_bank(tmp_path):
    result = _run(tmp_path, _block("start.md", "## 1. Check whether Memory Bank is active"))
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "[MEMORY BANK: ACTIVE]"
    assert not (tmp_path / "project with spaces" / ".memory-bank").exists()


def test_done_global_bank_supplies_gate_configuration(tmp_path):
    bank = tmp_path / "personal bank" / ".memory-bank"
    bank.mkdir(parents=True)
    (bank / "pipeline.yaml").write_text("done_gates:\n  enabled: false\n")
    result = _run(tmp_path, _block("done.md", "## 0. Mandatory done-gates"))
    assert result.returncode == 0, result.stderr
    assert "disabled" in result.stdout + result.stderr
    assert not (tmp_path / "project with spaces" / ".memory-bank").exists()


@pytest.mark.parametrize("command", ["start.md", "done.md", "mb.md"])
def test_command_setup_resolves_global_bank_and_absence_without_mutation(tmp_path, command):
    setup = _block(command, "<!-- mb-runtime:setup -->")
    result = _run(tmp_path, 'printf "%s\\n" "$BANK"', setup=setup)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == str(tmp_path / "personal bank" / ".memory-bank")
    missing = tmp_path / "missing bank"
    result = _run(tmp_path, 'echo SHOULD_NOT_RUN', setup=setup, MB_PATH=str(missing))
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == "[MEMORY BANK: ABSENT]"
    assert not missing.exists()


def test_start_uses_registered_global_bank_and_reads_its_context(tmp_path):
    project = tmp_path / "project with spaces"
    project.mkdir()
    bank = tmp_path / "personal bank" / ".memory-bank"
    bank.mkdir(parents=True)
    (bank / "status.md").write_text("# Status\n## Current Phase\nGLOBAL_CONTEXT_EVIDENCE\n")
    user_dir = tmp_path / "isolated home"
    registry = user_dir / ".codex" / "memory-bank" / "registry.json"
    registry.parent.mkdir(parents=True)
    registry.write_text(json.dumps({"projects": {str(project.resolve()): {"bank_path": str(bank)}}}))
    result = _run(
        tmp_path, _block("start.md", "## 2. Collect context"),
        setup=_block("start.md", "<!-- mb-runtime:setup -->"),
        HOME=str(user_dir), MB_PATH="", MB_AGENT="codex",
    )
    assert result.returncode == 0, result.stderr
    assert "GLOBAL_CONTEXT_EVIDENCE" in result.stdout
    assert not (project / ".memory-bank").exists()


@pytest.mark.parametrize("section,args_name", [
    ("**Rebuild `_recent.md`**", None),
    ("### recap <sid>", "ARGS_AFTER_RECAP"),
    ("### conflicts [", "ARGS_AFTER_CONFLICTS"),
    ("### consolidate [", "ARGS_AFTER_CONSOLIDATE"),
])
def test_memory_tool_snippet_runs_from_project_cwd(tmp_path, section, args_name):
    setup = f"{args_name}=(--help)" if args_name else ""
    if args_name == "ARGS_AFTER_RECAP":
        session = tmp_path / "personal bank" / ".memory-bank" / "session" / "abcd1234.md"
        session.parent.mkdir(parents=True)
        session.write_text("---\nrecapped: true\n---\n## Summary\nAlready captured.\n")
        setup = "ARGS_AFTER_RECAP=(abcd1234)"
    result = _run(tmp_path, _block("mb.md", section), setup=setup)
    assert result.returncode == 0, result.stderr
    assert "No such file" not in result.stderr


@pytest.mark.parametrize("explicit", [True, False])
@pytest.mark.parametrize("unrelated_plan", [True, False])
def test_verify_selects_spec_source_even_with_unrelated_newer_plan(tmp_path, explicit, unrelated_plan):
    bank = tmp_path / "personal bank" / ".memory-bank"
    spec = bank / "specs" / "orders" / "tasks.md"
    spec.parent.mkdir(parents=True)
    spec.write_text("# Tasks\n<!-- mb-task:1 -->\n### Task 1: Verify order\n"
                    "**Covers:** REQ-001\n**DoD:** correct order\n**Testing:** contract\n")
    if unrelated_plan:
        plan = bank / "plans" / "unrelated.md"
        plan.parent.mkdir()
        plan.write_text("# Unrelated\n<!-- mb-stage:1 -->\n### Stage 1: Unrelated\n")
    (bank / ".work-state.json").write_text(json.dumps({
        "source": "spec", "source_path": str(spec), "source_topic": "orders",
        "item_no": 1, "phase": "done", "run_id": "test",
    }))
    result = _run(tmp_path, _block("mb.md", "<!-- mb-verify:resolve -->"),
                  VERIFY_TARGET=str(spec) if explicit else "")
    assert result.returncode == 0, result.stderr
    items = [json.loads(line) for line in result.stdout.splitlines()]
    assert items and all(item["source_path"] == str(spec) for item in items)
    assert all(item["kind"] == "task" for item in items)


def test_verify_missing_current_source_does_not_guess_latest_plan(tmp_path):
    bank = tmp_path / "personal bank" / ".memory-bank"
    plans = bank / "plans"
    plans.mkdir(parents=True)
    (plans / "unrelated.md").write_text("# Unrelated\n")
    result = _run(tmp_path, _block("mb.md", "<!-- mb-verify:resolve -->"))
    assert result.returncode != 0
    assert "target" in result.stderr.lower()


def test_verify_dispatch_prompts_resolve_from_loaded_skill_without_claude_install():
    text = (ROOT / "commands" / "mb.md").read_text().split("### verify", 1)[1].split("### map", 1)[0]
    verifier = (ROOT / "agents" / "plan-verifier.md").read_text()
    paths = re.findall(r"<contents of ([^>]+)>", text + verifier)
    assert len(paths) == 3
    for path in paths:
        resolved = Path(path.replace("${SKILL_DIR}", str(ROOT)))
        assert resolved.is_file(), f"Prompt does not resolve from the loaded skill: {path}"
