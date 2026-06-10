"""Contract tests for the portable `mb-research` research subagent.

`agents/mb-research.md` is a de-FaberlicApp'd, generalized port of the
standalone `mb-research` skill into a dispatchable Memory Bank agent. It
researches code, project memory, library docs, prior art and the open web —
graph-first, multi-source, file:line-grounded — and it NEVER writes code.

These tests assert the literal contract strings (not "should"):
- valid frontmatter, `name: mb-research`;
- the research-not-write tool contract (Bash/Read/Grep/Glob present,
  Write/Edit absent);
- the routing vocabulary / canonical script fragments are referenced;
- ZERO `FaberlicApp` occurrences (the orphan-agent guard, lesson L40);
- portability clause (must work with no Memory Bank — fail-open to Grep);
- anti-hallucination discipline (`file:line` grounding).

Conventions mirror `tests/pytest/test_tooling_core.py` (frontmatter parsing +
repo-root resolution).
"""

from __future__ import annotations

from pathlib import Path

import pytest

# PyYAML is an optional dependency (the `yaml`/`dev` extras); CI installs only
# `[codegraph]`. Skip — never crash collection — when it is absent, mirroring
# test_pipeline_default_yaml.py and the scripts' fail-open-without-PyYAML stance.
yaml = pytest.importorskip("yaml")

REPO_ROOT = Path(__file__).resolve().parents[2]
RESEARCH = REPO_ROOT / "agents" / "mb-research.md"

# Routing vocabulary / script fragments the body must reference so it stays
# consistent with mb-tooling-core's tool model and the source SKILL.
ROUTING_FRAGMENTS = (
    "graph_impact",
    "search_code",
    "recall",
    "mb-graph-query.py",
    "mb-semantic-search.py",
)


def _read() -> str:
    return RESEARCH.read_text(encoding="utf-8")


def _frontmatter(text: str) -> dict:
    assert text.startswith("---\n"), "missing frontmatter open fence"
    parts = text.split("---\n", 2)
    assert len(parts) >= 3, "malformed frontmatter (no closing fence)"
    data = yaml.safe_load(parts[1])
    assert isinstance(data, dict), "frontmatter did not parse to a mapping"
    return data


def _tools(fm: dict) -> set[str]:
    raw = fm.get("tools", "")
    if isinstance(raw, list):
        return {str(t).strip() for t in raw}
    return {t.strip() for t in str(raw).split(",") if t.strip()}


def test_mb_research_file_exists_returns_a_regular_file() -> None:
    assert RESEARCH.is_file(), "missing agents/mb-research.md"


def test_frontmatter_parses_and_name_is_mb_research() -> None:
    fm = _frontmatter(_read())
    assert fm.get("name") == "mb-research", "name must be mb-research"


def test_tools_include_read_only_research_toolset() -> None:
    tools = _tools(_frontmatter(_read()))
    for required in ("Bash", "Read", "Grep", "Glob"):
        assert required in tools, f"tools must include {required}; got {sorted(tools)}"


def test_tools_exclude_write_and_edit_research_not_write_contract() -> None:
    tools = _tools(_frontmatter(_read()))
    assert "Write" not in tools, "mb-research must NOT have Write (researches, never writes code)"
    assert "Edit" not in tools, "mb-research must NOT have Edit (researches, never writes code)"


def test_routing_vocabulary_and_script_fragments_present() -> None:
    text = _read()
    for fragment in ROUTING_FRAGMENTS:
        assert fragment in text, f"missing routing fragment: {fragment}"


def test_zero_faberlic_references_orphan_agent_guard() -> None:
    # Lesson L40 — a ported agent must carry no client-specific identifiers.
    assert "faberlic" not in _read().lower(), "FaberlicApp reference leaked into the portable agent"


def test_portability_clause_no_memory_bank_fail_open() -> None:
    text = _read()
    assert "no Memory Bank" in text, (
        "missing the 'works in a repo with no Memory Bank' portability clause"
    )
    # Fail-open degradation to plain text search must be stated.
    assert "Grep" in text, "missing the Grep/Glob/Read fallback for stale/absent indexes"


def test_anti_hallucination_file_line_discipline_present() -> None:
    assert "file:line" in _read(), "missing the file:line grounding (anti-hallucination) discipline"
