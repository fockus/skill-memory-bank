"""Contract tests for GraphRAG-lite routing guidance.

The guidance must be agent-neutral: exact structural questions use graph tools,
ambiguous code-understanding questions use code_context, and explicit semantic
search requests use search_code directly.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]

GUIDANCE_FILES = [
    REPO_ROOT / "rules" / "RULES.md",
    REPO_ROOT / "SKILL.md",
    REPO_ROOT / "commands" / "mb.md",
]

AGENT_SURFACE_FILES = [
    REPO_ROOT / "rules" / "RULES.md",
    REPO_ROOT / "SKILL.md",
    REPO_ROOT / "adapters" / "_lib_agents_md.sh",
    REPO_ROOT / "adapters" / "pi.sh",
    REPO_ROOT / "adapters" / "opencode.sh",
]


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_guidance_declares_code_context_default_for_ambiguous_code_questions() -> None:
    combined = "\n".join(_read(path) for path in GUIDANCE_FILES)

    assert "GraphRAG-lite retrieval routing" in combined
    assert "code_context is the default" in combined
    assert "where is the logic for X" in combined
    assert "find similar implementation" in combined


def test_guidance_routes_exact_structural_questions_to_graph_not_search_code() -> None:
    combined = "\n".join(_read(path) for path in GUIDANCE_FILES)

    structural_examples = [
        r"who calls/imports/defines X.*graph_neighbors",
        r"reverse deps.*graph_impact",
        r"what tests cover this file/symbol.*graph_tests",
    ]
    for pattern in structural_examples:
        assert re.search(pattern, combined, flags=re.DOTALL), pattern

    forbidden = re.compile(
        r"who calls/imports/defines X[^\n|]*\|[^\n|]*search_code",
        flags=re.IGNORECASE,
    )
    assert not forbidden.search(combined)


def test_guidance_keeps_explicit_semantic_requests_on_search_code() -> None:
    combined = "\n".join(_read(path) for path in GUIDANCE_FILES)

    assert 'User explicitly asks "semantic search"' in combined
    assert "search_code" in combined
    assert "Respect explicit tool intent" in combined


def test_guidance_documents_fail_open_modes() -> None:
    combined = "\n".join(_read(path) for path in GUIDANCE_FILES)

    for phrase in [
        "missing graph",
        "stale graph",
        "missing semantic provider",
        "unavailable native extension",
        "fail open",
    ]:
        assert phrase in combined


def test_agent_surfaces_cover_pi_claude_codex_opencode_and_generic_agents() -> None:
    combined = "\n".join(_read(path) for path in AGENT_SURFACE_FILES)

    for agent in ["Pi", "Claude Code", "Codex", "OpenCode", "generic AGENTS.md"]:
        assert agent in combined

    for tool_name in ["graph_neighbors", "graph_impact", "graph_tests", "code_context"]:
        assert tool_name in combined


def test_agent_surfaces_explain_cli_fallback_for_agents_without_native_tools() -> None:
    combined = "\n".join(_read(path) for path in AGENT_SURFACE_FILES)

    assert "scripts/mb-graph-query.py" in combined
    assert "scripts/mb-code-context.py" in combined
    assert "native tool" in combined
    assert "CLI fallback" in combined
