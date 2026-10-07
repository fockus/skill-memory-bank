"""scripts/mb-agent-render.py — build the installed form of an agent file.

An agent that declares `compose: <partial> ...` in its frontmatter is installed with those
partials' bodies placed above its own body, so a dispatch by name gets the full discipline
without the orchestrator re-typing partial files into every prompt.
"""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tomllib
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
RENDER = REPO_ROOT / "scripts" / "mb-agent-render.py"


def _render(src: Path, skill_dir: Path, *extra: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(RENDER), str(src), "--skill-dir", str(skill_dir), *extra],
        capture_output=True, text=True, check=False,
    )


@pytest.fixture
def skill(tmp_path: Path) -> Path:
    agents = tmp_path / "agents"
    agents.mkdir()
    (agents / "core-a.md").write_text(
        "---\nname: core-a\npartial: true\n---\n\n# Core A\n\nRule A.\n", encoding="utf-8")
    (agents / "core-b.md").write_text(
        "---\nname: core-b\npartial: true\n---\n\n# Core B\n\nRule B.\n", encoding="utf-8")
    (agents / "role.md").write_text(
        "---\nname: role\ndescription: A role.\ntools: Bash, Read\ncompose: core-a core-b\n"
        "effort: medium\n---\n\n# Role\n\nRole rule.\n", encoding="utf-8")
    (agents / "plain.md").write_text(
        "---\nname: plain\ndescription: Plain.\n---\n\n# Plain\n", encoding="utf-8")
    return tmp_path


def test_render_places_partials_above_role_body_in_declared_order(skill: Path) -> None:
    r = _render(skill / "agents" / "role.md", skill)
    assert r.returncode == 0, r.stderr
    out = r.stdout
    assert out.startswith("---\nname: role\n")
    assert out.index("# Core A") < out.index("# Core B") < out.index("# Role")
    assert "compose:" not in out
    assert "partial: true" not in out
    assert out.count("\n---\n") == 1  # one frontmatter block; partial frontmatter stripped


def test_render_keeps_other_frontmatter_keys(skill: Path) -> None:
    out = _render(skill / "agents" / "role.md", skill).stdout
    assert "tools: Bash, Read\n" in out
    assert "effort: medium\n" in out


def test_render_for_opencode_drops_claude_only_keys(skill: Path) -> None:
    (skill / "agents" / "pinned.md").write_text(
        "---\nname: pinned\ndescription: P.\nmodel: haiku\neffort: low\n---\n\nBody\n", encoding="utf-8")
    out = _render(skill / "agents" / "pinned.md", skill, "--host", "opencode").stdout
    assert "effort:" not in out
    assert "model:" not in out
    assert "description: P.\n" in out


def test_render_for_pi_maps_effort_to_thinking_and_tools_to_pi_names(skill: Path) -> None:
    (skill / "agents" / "reader.md").write_text(
        "---\nname: reader\ndescription: R.\ntools: Bash, Read, Grep, Glob, WebSearch, SendMessage\n"
        "model: sonnet\neffort: high\n---\n\nBody\n", encoding="utf-8")
    out = _render(skill / "agents" / "reader.md", skill, "--host", "pi").stdout
    assert "thinking: high\n" in out
    assert "tools: bash, read, grep, find\n" in out
    assert "effort:" not in out
    assert "model:" not in out


def test_render_for_codex_emits_a_toml_role_with_composed_instructions(skill: Path) -> None:
    role = tomllib.loads(_render(skill / "agents" / "role.md", skill, "--host", "codex").stdout)
    assert role["name"] == "role"
    assert role["description"] == "A role."
    assert role["model_reasoning_effort"] == "medium"
    assert role["sandbox_mode"] == "read-only"  # tools: Bash, Read — no Write/Edit
    body = role["developer_instructions"]
    assert body.index("# Core A") < body.index("# Core B") < body.index("# Role")


def test_render_for_codex_leaves_sandbox_default_for_writing_agents() -> None:
    out = _render(REPO_ROOT / "agents" / "mb-backend.md", REPO_ROOT, "--host", "codex").stdout
    role = tomllib.loads(out)
    assert "sandbox_mode" not in role
    assert role["name"] == "mb-backend"


def test_render_without_compose_is_byte_identical(skill: Path) -> None:
    src = skill / "agents" / "plain.md"
    assert _render(src, skill).stdout == src.read_text(encoding="utf-8")


def test_render_fails_loudly_on_a_missing_partial(skill: Path) -> None:
    (skill / "agents" / "broken.md").write_text(
        "---\nname: broken\ndescription: B.\ncompose: nope\n---\n\nBody\n", encoding="utf-8")
    r = _render(skill / "agents" / "broken.md", skill)
    assert r.returncode != 0
    assert "nope" in r.stderr


def test_shipped_role_agents_render_with_engineering_core() -> None:
    src = REPO_ROOT / "agents" / "mb-backend.md"
    r = _render(src, REPO_ROOT)
    assert r.returncode == 0, r.stderr
    core_heading = next(
        line for line in (REPO_ROOT / "agents" / "mb-engineering-core.md").read_text(
            encoding="utf-8").splitlines() if line.startswith("# "))
    assert core_heading in r.stdout


def test_render_for_cursor_keeps_only_documented_keys_and_composes_partials(skill: Path) -> None:
    (skill / "agents" / "pinned.md").write_text(
        "---\nname: pinned\ndescription: P.\ntools: Bash, Read\nmodel: haiku\neffort: low\n"
        "color: blue\ncompose: core-a\n---\n\nBody\n", encoding="utf-8")
    out = _render(skill / "agents" / "pinned.md", skill, "--host", "cursor").stdout
    # Cursor subagent frontmatter: name/description; no model = inherit (Claude aliases are not Cursor ids)
    assert out.startswith("---\nname: pinned\ndescription: P.\n---\n\n")
    assert out.index("# Core A") < out.index("Body")


# ── Stage 4b (AGR-074): the role's tier model in installed agents ──────────────────────────────
DEFAULT_PIPELINE = REPO_ROOT / "references" / "pipeline.default.yaml"
needs_yaml = pytest.mark.skipif(importlib.util.find_spec("yaml") is None, reason="PyYAML required")


def _agent(name: str) -> Path:
    return REPO_ROOT / "agents" / f"{name}.md"


def _pipeline(tmp_path: Path, body: str) -> Path:
    path = tmp_path / "pipeline.yaml"
    path.write_text(body, encoding="utf-8")
    return path


@needs_yaml
@pytest.mark.parametrize(("agent", "cost", "model"), [
    ("mb-developer", "optimal", "claude-sonnet-5-5"),
    ("mb-reviewer", "optimal", "claude-opus-5-5"),
    ("mb-developer", "premium", "claude-opus-5-5"),
])
def test_render_for_cursor_with_pipeline_writes_tier_model(agent: str, cost: str, model: str) -> None:
    r = _render(_agent(agent), REPO_ROOT, "--host", "cursor", "--pipeline", str(DEFAULT_PIPELINE), "--cost", cost)
    assert r.returncode == 0, r.stderr
    assert r.stdout.startswith(f"---\nname: {agent}\ndescription: ")
    assert f"\nmodel: {model}\n---\n" in r.stdout


@needs_yaml
def test_render_with_pipeline_leaves_agents_without_a_role_unchanged() -> None:
    plain = _render(_agent("mb-doctor"), REPO_ROOT, "--host", "cursor").stdout
    with_pipe = _render(_agent("mb-doctor"), REPO_ROOT, "--host", "cursor", "--pipeline", str(DEFAULT_PIPELINE))
    assert with_pipe.stdout == plain


def test_render_for_opencode_without_a_host_profile_is_unchanged() -> None:
    plain = _render(_agent("mb-developer"), REPO_ROOT, "--host", "opencode").stdout
    with_pipe = _render(_agent("mb-developer"), REPO_ROOT, "--host", "opencode", "--pipeline", str(DEFAULT_PIPELINE))
    assert with_pipe.stdout == plain
    assert "model:" not in plain


@needs_yaml
def test_render_for_opencode_with_profile_writes_provider_model(tmp_path: Path) -> None:
    pipe = _pipeline(tmp_path, "roles:\n  developer: {agent: mb-developer}\n"
                     "model_profiles:\n  opencode: {premium: openai/gpt-6-astra, mid: openai/gpt-6.1-sol}\n")
    out = _render(_agent("mb-developer"), REPO_ROOT, "--host", "opencode", "--pipeline", str(pipe)).stdout
    assert "\nmodel: openai/gpt-6.1-sol\n---\n" in out


@needs_yaml
def test_render_for_opencode_skips_a_role_model_without_provider(tmp_path: Path) -> None:
    pipe = _pipeline(tmp_path, "roles:\n  developer: {agent: mb-developer, model: opus}\n")
    out = _render(_agent("mb-developer"), REPO_ROOT, "--host", "opencode", "--pipeline", str(pipe)).stdout
    assert "model:" not in out


@needs_yaml
def test_render_for_codex_with_pipeline_writes_model_key() -> None:
    out = _render(_agent("mb-developer"), REPO_ROOT, "--host", "codex", "--pipeline", str(DEFAULT_PIPELINE)).stdout
    role = tomllib.loads(out)
    assert role["model"] == "gpt-6.1-sol"
    assert role["name"] == "mb-developer"
