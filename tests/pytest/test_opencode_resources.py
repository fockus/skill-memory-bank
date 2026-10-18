"""OpenCode-specific metadata after the shared composition/model renderer."""

import json
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]


def native_pin(text: str) -> str:
    metadata = yaml.safe_load(text.split("\n---\n", 1)[0].removeprefix("---\n"))
    return metadata.get("model", "") + (f"#{metadata['variant']}" if metadata.get("variant") else "")


def test_native_roles_preserve_shared_composition_and_permissions() -> None:
    adapter = ROOT / "adapters/opencode_resources.py"
    result = subprocess.run(
        [sys.executable, str(adapter), str(ROOT / "agents/mb-backend.md"),
         "--skill-dir", str(ROOT)], text=True, capture_output=True, check=True,
    )
    text = result.stdout
    assert "# MB Engineering Core" in text
    assert "# MB Tooling Core" in text
    assert "# MB Backend" in text
    assert re.search(r'color: "#[0-9a-fA-F]{6}"', text)
    assert "  edit: allow" in text
    assert "  bash: allow" in text
    assert "\nmodel:" not in text
    assert "\ncompose:" not in text
    assert "\neffort:" not in text


def test_readonly_roles_keep_native_edit_denial() -> None:
    result = subprocess.run(
        [sys.executable, str(ROOT / "adapters/opencode_resources.py"),
         str(ROOT / "agents/plan-verifier.md"), "--skill-dir", str(ROOT)],
        text=True, capture_output=True, check=True,
    )
    assert "  edit: deny" in result.stdout


def test_bundle_declares_complete_runtime_and_shared_renderer() -> None:
    cfg = tomllib.loads((ROOT / "pyproject.toml").read_text())
    build = cfg["tool"]["hatch"]["build"]["targets"]
    shared = build["wheel"]["shared-data"]
    for name in ("adapters/opencode_plugin.mjs", "adapters/opencode_resources.py",
                 "adapters/opencode_session.sh", "scripts/mb-agent-render.py",
                 "hooks/lib/session-common.sh"):
        directory = name.split("/")[0]
        assert (ROOT / name).is_file()
        assert shared[directory] == f"share/memory-bank-skill/{directory}"
        assert f"/{directory}" in build["sdist"]["include"]


def test_missing_partial_refuses_to_publish_a_role(tmp_path: Path) -> None:
    src = tmp_path / "broken.md"
    src.write_text("---\nname: broken\ncompose: missing-partial\n---\nRole body\n")
    result = subprocess.run(
        [sys.executable, str(ROOT / "adapters/opencode_resources.py"), str(src),
         "--skill-dir", str(ROOT)], text=True, capture_output=True,
    )
    assert result.returncode == 1
    assert result.stdout == ""
    assert "compose partial not found" in result.stderr


@pytest.mark.parametrize("configuration, expected", [
    ("roles:\n  developer: {agent: mb-developer, model: local/team/coder#deep}\n",
     "local/team/coder#deep"),
    ("roles:\n  developer: {agent: mb-developer, model: local/team/coder, thinking: deep}\n",
     "local/team/coder#deep"),
    ("roles:\n  developer: {agent: mb-developer}\nmodel_profiles:\n"
     "  opencode: {premium: local/premium, mid: local/team/coder#deep}\n",
     "local/team/coder#deep"),
])
def test_native_render_uses_canonical_model_precedence_and_variant(
    tmp_path: Path, configuration: str, expected: str,
) -> None:
    pipeline = tmp_path / "pipeline.yaml"
    pipeline.write_text(configuration)
    result = subprocess.run(
        [sys.executable, str(ROOT / "adapters/opencode_resources.py"),
         str(ROOT / "agents/mb-developer.md"), "--skill-dir", str(ROOT),
         "--pipeline", str(pipeline)], text=True, capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert native_pin(result.stdout) == expected


@pytest.mark.parametrize("configuration, reason", [
    ("roles: [", "YAML"),
    ("roles:\n  developer: {agent: mb-developer, model: opus}\n", "provider/model"),
    ("roles:\n  developer: {agent: mb-developer, thinking: high}\n", "thinking"),
    ("roles:\n  developer: {agent: mb-developer, model: local/coder#deep, thinking: low}\n",
     "conflict"),
    ("roles:\n  developer: {agent: mb-developer, model: local/coder#}\n", "variant"),
])
def test_invalid_native_assignment_refuses_publication(
    tmp_path: Path, configuration: str, reason: str,
) -> None:
    pipeline = tmp_path / "pipeline.yaml"
    pipeline.write_text(configuration)
    result = subprocess.run(
        [sys.executable, str(ROOT / "adapters/opencode_resources.py"),
         str(ROOT / "agents/mb-developer.md"), "--skill-dir", str(ROOT),
         "--pipeline", str(pipeline)], text=True, capture_output=True,
    )
    assert result.returncode == 1
    assert result.stdout == ""
    assert reason in result.stderr


def test_config_host_detection_accepts_native_object_model_without_losing_variant(tmp_path: Path) -> None:
    (tmp_path / "opencode.json").write_text(json.dumps({
        "model": {"providerID": "local", "model": "team/coder", "variant": "deep"},
        "small_model": "local/cheap",
    }))
    env = {k: v for k, v in os.environ.items() if not k.startswith("OPENCODE_")}
    env.update(HOME=str(tmp_path), XDG_CONFIG_HOME=str(tmp_path / "config"))
    result = subprocess.run([
        sys.executable, "-c", "import runpy,sys; print(runpy.run_path(sys.argv[1])['opencode_current'](sys.argv[2]))",
        str(ROOT / "scripts/mb_config_hosts.py"), str(tmp_path),
    ], env=env, capture_output=True, text=True, check=True)
    assert result.stdout.strip() == "local/team/coder#deep"


@pytest.mark.parametrize("selection", ["local", "mb-path", "global", "explicit", "host", "config", "default", "bundled"])
def test_adapter_renders_the_pipeline_selected_by_the_shared_ladder(tmp_path: Path, selection: str) -> None:
    project, home = tmp_path / "project", tmp_path / "home"
    project.mkdir()
    home.mkdir()
    env = {k: v for k, v in os.environ.items() if not k.startswith(("MB_", "XDG_"))}
    env.update(HOME=str(home))
    bank = tmp_path / "bank" if selection in ("mb-path", "global") else project / ".memory-bank"
    bank.mkdir()
    (bank / "status.md").write_text("# Task\n")
    if selection == "mb-path":
        env["MB_PATH"] = str(bank)
        (project / ".memory-bank").mkdir()
        (project / ".memory-bank/pipeline.yaml").write_text("roles: {developer: {agent: mb-developer, model: wrong/model}}\n")
    if selection == "global":
        registry = home / ".config/opencode/memory-bank/registry.json"
        registry.parent.mkdir(parents=True)
        registry.write_text(json.dumps({"projects": {str(project.resolve()): {"bank_path": str(bank)}}}))
    if selection != "bundled":
        text = f"roles:\n  developer: {{agent: mb-developer, model: local/{selection}#deep}}\n"
        selected = bank / "pipeline.yaml"
        if selection in ("explicit", "host", "config", "default"):
            (bank / "pipelines").mkdir()
            selected = bank / "pipelines/selected.yaml"
            (bank / "pipeline.yaml").write_text("roles: {developer: {agent: mb-developer, model: wrong/model}}\n")
            if selection == "explicit":
                env["MB_PIPELINE"] = "selected"
                (bank / "pipelines/host.yaml").write_text("agents: [opencode]\nroles: {}\n")
            if selection == "host":
                text = "agents: [opencode]\n" + text
                (bank / ".mb-config").write_text("pipeline=missing-lower-priority\n")
            if selection == "config":
                (bank / ".mb-config").write_text("pipeline=selected\n")
                (bank / "pipelines/default.yaml").write_text("default: true\nroles: {}\n")
            if selection == "default":
                text = "default: true\n" + text
        selected.write_text(text)
    result = subprocess.run(["bash", str(ROOT / "adapters/opencode.sh"), "install", str(project)],
                            env=env, cwd=project, text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr
    rendered = (project / ".opencode/agent/mb-developer.md").read_text()
    assert native_pin(rendered) == ("" if selection == "bundled" else f"local/{selection}#deep")
    assert not (bank / "pipelines/opencode.yaml").exists()


def test_config_rerender_respects_a_higher_priority_host_binding(tmp_path: Path) -> None:
    project, home = tmp_path / "project", tmp_path / "home"
    (project / ".memory-bank/pipelines").mkdir(parents=True)
    home.mkdir()
    selected = project / ".memory-bank/pipelines/native.yaml"
    selected.write_text("agents: [opencode]\nroles: {developer: {agent: mb-developer, model: local/selected#deep}}\n")
    legacy = project / ".memory-bank/pipeline.yaml"
    legacy.write_text("roles: {developer: {agent: mb-developer, model: local/legacy}}\n")
    env = {k: v for k, v in os.environ.items() if not k.startswith(("MB_", "XDG_"))}
    env["HOME"] = str(home)
    subprocess.run(["bash", str(ROOT / "adapters/opencode.sh"), "install", str(project)],
                   env=env, cwd=project, check=True, capture_output=True, timeout=30)
    result = subprocess.run([
        sys.executable, "-c",
        "import runpy,sys; sys.exit(runpy.run_path(sys.argv[1])['render_installed_agents']('opencode', sys.argv[2], sys.argv[3]))",
        str(ROOT / "scripts/mb_config_hosts.py"), str(project), str(legacy),
    ], env=env, cwd=project, text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr
    assert native_pin((project / ".opencode/agent/mb-developer.md").read_text()) == "local/selected#deep"


def test_work_dispatch_reuses_the_canonical_item_override_even_for_a_planner(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    source = bank / "specs/demo/tasks.md"
    source.parent.mkdir(parents=True)
    source.write_text("# Tasks\n<!-- mb-task:1 -->\n## Task 1\n**Role:** planner\n**DoD:**\n- [ ] Works\n")
    (bank / "pipeline.yaml").write_text(
        "roles:\n  planner: {agent: mb-architect, model: local/planner#deep}\n"
        "workflow: {default: check}\nworkflows:\n  check: {steps: [implement, done]}\nqa: {enabled: false}\n")
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    result = subprocess.run([sys.executable, str(ROOT / "adapters/opencode_work.py"), str(bank)],
                            input="demo --model inherit", env=env, cwd=tmp_path,
                            text=True, capture_output=True, check=True, timeout=30)
    data = json.loads(result.stdout)
    assert data["items"][0]["model"] == "inherit"
    assert {r["native"] for r in data["roles"].values() if r["agent"] == "mb-architect"} == {""}


def test_rendered_specialist_keeps_the_shared_developer_thinking_fallback(tmp_path: Path) -> None:
    pipeline = tmp_path / "pipeline.yaml"
    pipeline.write_text("roles:\n  developer: {agent: mb-developer, model: local/coder, thinking: deep}\n"
                        "  backend: {agent: mb-backend}\n")
    result = subprocess.run([sys.executable, str(ROOT / "adapters/opencode_resources.py"),
                             str(ROOT / "agents/mb-backend.md"), "--skill-dir", str(ROOT),
                             "--pipeline", str(pipeline)], text=True, capture_output=True, check=True)
    assert native_pin(result.stdout) == "local/coder#deep"


@pytest.mark.parametrize("workflow", ["full-cycle", "requirements-plan"])
def test_s4_entry_new_planning_topic_does_not_need_a_preexisting_task(tmp_path: Path, workflow: str) -> None:
    bank = tmp_path / ".memory-bank"
    bank.mkdir()
    (bank / "pipeline.yaml").write_text((ROOT / "references/pipeline.default.yaml").read_text())
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    result = subprocess.run([sys.executable, str(ROOT / "adapters/opencode_work.py"), str(bank)],
                            input=f"brand-new-topic --workflow {workflow}", env=env, cwd=tmp_path,
                            text=True, capture_output=True, timeout=30)
    assert result.returncode == 0, f"S4-ENTRY-1: {result.stderr}"
    data = json.loads(result.stdout)
    assert data["workflow"]["entrypoint"] == "freeform_or_topic"
    assert data["items"] == []
    assert not (bank / "specs").exists() and not (bank / "plans").exists()


def test_s4_entry_existing_execution_ambiguity_still_refuses(tmp_path: Path) -> None:
    bank = tmp_path / ".memory-bank"
    (bank / "plans").mkdir(parents=True)
    (bank / "pipeline.yaml").write_text((ROOT / "references/pipeline.default.yaml").read_text())
    for name in ("first-widget.md", "second-widget.md"):
        (bank / "plans" / name).write_text("<!-- mb-stage:1 -->\n### Stage 1\n- [ ] Work\n")
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    result = subprocess.run([sys.executable, str(ROOT / "adapters/opencode_work.py"), str(bank)],
                            input="widget --workflow medium", env=env, cwd=tmp_path,
                            text=True, capture_output=True, timeout=30)
    assert result.returncode != 0 and "ambiguous" in result.stderr


@pytest.mark.parametrize("cli, logic, generic, expected", [
    ("", "local/logic#deep", "opus", "local/logic#deep"),
    ("--step-model reviewer=local/override#deep", "local/logic#deep", "opus", "local/override#deep"),
    ("--step-model reviewer=inherit", "local/logic#deep", "opus", ""),
    ("", "", "local/review#deep", "local/review#deep"),
    ("", "opus", "external/unused", "ERROR"),
])
def test_s4_roles_preflight_selects_ensemble_lenses_lead_and_cli_priority(
    tmp_path: Path, cli: str, logic: str, generic: str, expected: str,
) -> None:
    bank = tmp_path / ".memory-bank"
    source = bank / "specs/demo/tasks.md"
    source.parent.mkdir(parents=True)
    source.write_text("<!-- mb-task:1 -->\n## Task 1\n**Role:** developer\n**DoD:**\n- [ ] Works\n")
    cfg = {"roles": {"reviewer": {"agent": "codex-cli", "model": generic},
                     "reviewer_logic": {"agent": "mb-reviewer-logic", "model": logic},
                     "reviewer_security": {"agent": "mb-reviewer-security", "model": "opus"},
                     "reviewer_lead": {"agent": "mb-reviewer-lead", "model": "local/lead#deep"}},
           "workflows": {"ensemble": {"steps": ["review", "done"], "review_profile": "ensemble"}},
           "review_ensemble": {"reviewers": [{"role": "reviewer_logic", "focus": "logic"},
                                              {"role": "reviewer_security", "focus": "security"}], "lead_role": "reviewer_lead"},
           "qa": {"enabled": False}}
    (bank / "pipeline.yaml").write_text(json.dumps(cfg))
    env = {k: v for k, v in os.environ.items() if not k.startswith("MB_")}
    result = subprocess.run([sys.executable, str(ROOT / "adapters/opencode_work.py"), str(bank)],
                            input=f"demo --workflow ensemble --lenses logic {cli}", env=env, cwd=tmp_path,
                            text=True, capture_output=True, timeout=30)
    if expected == "ERROR":
        assert result.returncode != 0 and "provider/model" in result.stderr
    else:
        assert result.returncode == 0, f"S4-ROLES-2: {result.stderr}"
        roles = json.loads(result.stdout)["roles"]
        assert "reviewer" not in roles and "reviewer_security" not in roles
        assert roles["reviewer_logic"]["native"] == expected
        assert roles["reviewer_lead"]["native"] == (expected if cli else "local/lead#deep")
