"""Contract tests for the mb-tooling-core shared partial.

`agents/mb-tooling-core.md` is a single prepended injection point that gives
every implementer the graph-first, fail-open code-understanding routing table.
It mirrors `agents/mb-engineering-core.md`'s partial header style and reuses the
SSoT routing vocabulary already present in `adapters/_lib_agents_md.sh` and
`commands/mb.md`. These tests assert the literal contract strings — not "should".
"""

from __future__ import annotations

from pathlib import Path

import pytest

# PyYAML is an optional dependency (the `yaml`/`dev` extras); CI installs only
# `[codegraph]`. Skip — never crash collection — when it is absent, mirroring
# test_pipeline_default_yaml.py and the scripts' fail-open-without-PyYAML stance.
yaml = pytest.importorskip("yaml")

REPO_ROOT = Path(__file__).resolve().parents[2]
TOOLING_CORE = REPO_ROOT / "agents" / "mb-tooling-core.md"

ROUTING_TOKENS = (
    "code_context",
    "graph_neighbors",
    "graph_impact",
    "graph_tests",
    "search_code",
    "recall",
)

CANONICAL_PATHS = (
    "mb-code-context.py",
    "mb-graph-query.py",
    "mb-semantic-search.py",
    "/mb recall",
)


def _read() -> str:
    return TOOLING_CORE.read_text(encoding="utf-8")


def _frontmatter(text: str) -> dict:
    assert text.startswith("---\n"), "missing frontmatter open fence"
    parts = text.split("---\n", 2)
    assert len(parts) >= 3, "malformed frontmatter (no closing fence)"
    data = yaml.safe_load(parts[1])
    assert isinstance(data, dict), "frontmatter did not parse to a mapping"
    return data


def test_tooling_core_file_exists_returns_a_regular_file() -> None:
    assert TOOLING_CORE.is_file(), "missing agents/mb-tooling-core.md"


def test_frontmatter_parses_and_marks_partial_true() -> None:
    fm = _frontmatter(_read())
    assert fm.get("partial") is True, "frontmatter must declare partial: true"
    assert fm.get("name") == "mb-tooling-core", "name must be mb-tooling-core"


def test_all_six_routing_tokens_present_as_exact_substrings() -> None:
    text = _read()
    for token in ROUTING_TOKENS:
        assert token in text, f"missing routing token: {token}"


def test_all_canonical_script_path_fragments_present() -> None:
    text = _read()
    for fragment in CANONICAL_PATHS:
        assert fragment in text, f"missing canonical path fragment: {fragment}"


def test_fail_open_sentence_present() -> None:
    assert "must not block work" in _read(), "missing fail-open sentence"


def test_do_not_dispatch_directly_marker_present() -> None:
    assert "Do not dispatch directly" in _read(), "missing partial dispatch marker"


def test_canonical_section_heading_present() -> None:
    assert "## Code-understanding tools (graph-first, fail-open)" in _read(), (
        "missing exact section heading"
    )
