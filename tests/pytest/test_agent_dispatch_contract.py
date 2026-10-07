"""Subagents are dispatched by name, and their installed definitions carry model/effort/tools.

Re-typing agent files into a `general-purpose` prompt costs the orchestrator thousands of output
tokens per call and silently ignores the agent's frontmatter; the Agent tool has no `thinking`
parameter; bundled scripts must run through the skill root, not the user's project.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
COMMANDS = sorted((REPO_ROOT / "commands").glob("*.md"))
AGENTS = sorted((REPO_ROOT / "agents").glob("*.md"))
DISPATCH_SURFACES = [*COMMANDS, *AGENTS, REPO_ROOT / "SKILL.md"]
EFFORT_LEVELS = {"low", "medium", "high", "xhigh", "max"}
# Bulk worker deliberately pinned to a small model; everything else inherits or uses pipeline.yaml.
SMALL_MODEL_WORKERS = {"mb-wiki-author": "haiku"}


def _frontmatter(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    assert text.startswith("---\n"), path
    block = text[4:text.index("\n---\n", 4)]
    return {k.strip(): v.strip() for k, _, v in (line.partition(":") for line in block.splitlines()) if _}


def _dispatchable_agents() -> list[Path]:
    return [p for p in AGENTS if _frontmatter(p).get("partial") != "true"]


@pytest.mark.parametrize("path", DISPATCH_SURFACES, ids=lambda p: p.name)
def test_no_dispatch_re_types_an_agent_file_into_a_prompt(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    assert not re.search(r'prompt="<contents of [^>]*agents/', text), path.name
    assert 'subagent_type="general-purpose"' not in text, path.name


@pytest.mark.parametrize("path", DISPATCH_SURFACES, ids=lambda p: p.name)
def test_no_dispatch_passes_a_thinking_parameter(path: Path) -> None:
    assert not re.search(r'^\s*thinking="', path.read_text(encoding="utf-8"), re.M), path.name


@pytest.mark.parametrize("path", _dispatchable_agents(), ids=lambda p: p.stem)
def test_agent_declares_effort_and_no_pinned_model(path: Path) -> None:
    fm = _frontmatter(path)
    assert fm.get("effort") in EFFORT_LEVELS, path.stem
    assert fm.get("model") == SMALL_MODEL_WORKERS.get(path.stem), path.stem


@pytest.mark.parametrize("path", _dispatchable_agents(), ids=lambda p: p.stem)
def test_agent_compose_names_existing_partials(path: Path) -> None:
    for name in _frontmatter(path).get("compose", "").split():
        partial = REPO_ROOT / "agents" / f"{name}.md"
        assert partial.is_file(), (path.stem, name)
        assert _frontmatter(partial).get("partial") == "true", (path.stem, name)


def test_implementer_roles_compose_the_engineering_core() -> None:
    roles = ["mb-developer", "mb-backend", "mb-frontend", "mb-ios", "mb-android",
             "mb-devops", "mb-qa", "mb-analyst", "mb-architect", "mb-debugger"]
    for role in roles:
        assert "mb-engineering-core" in _frontmatter(REPO_ROOT / "agents" / f"{role}.md").get("compose", ""), role


@pytest.mark.parametrize("path", COMMANDS, ids=lambda p: p.name)
def test_command_snippets_run_bundled_scripts_through_the_skill_root(path: Path) -> None:
    in_fence, offenders = False, []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence and re.search(r"\b(bash|python3) scripts/", line):
            offenders.append(line.strip())
    assert not offenders, offenders
