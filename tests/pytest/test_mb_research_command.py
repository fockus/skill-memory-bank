"""Stage 4 — `/mb research` entrypoint wiring in `commands/mb.md`.

Stage 3 ported the `mb-research` agent (`agents/mb-research.md`). This stage
registers a user-facing entrypoint so `/mb research <query>` dispatches that
agent. The wiring lives entirely in `commands/mb.md`:

  - a `research <query>` row in the `## Subcommands` routing table, consistent
    with sibling rows (`recall`, `verify`, ...);
  - a `### research <query>` dispatch section that mirrors `### verify`'s
    Task/Agent convention, references `agents/mb-research.md`, explains the
    narrow→single / broad→fan-out execution model, and carries a fail-open note.

These tests assert the LITERAL contract strings (per lesson "assert real
strings, not 'should'") and scope section-level assertions to the `### research`
region using the same extraction pattern as `test_tooling_core_wiring.py`.
"""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MB_MD = REPO_ROOT / "commands" / "mb.md"

RESEARCH_AGENT_REF = "mb-research.md"


def _read() -> str:
    return MB_MD.read_text(encoding="utf-8")


def _research_section(text: str) -> str:
    """Return the `### research` region (header → next top-level `### `)."""
    start = text.find("### research")
    assert start != -1, "### research section not found in mb.md"
    nxt = text.find("\n### ", start + len("### research"))
    return text[start : nxt if nxt != -1 else len(text)]


def test_router_table_lists_research_row() -> None:
    """The `## Subcommands` table must carry a `research` row."""
    assert "| `research" in _read(), (
        "commands/mb.md router table missing a `research` row "
        "(expected a `| `research ...` table line)"
    )


def test_mb_md_has_research_section() -> None:
    assert "### research" in _read(), "### research section header missing in mb.md"


def test_research_section_dispatches_mb_research_agent_via_task() -> None:
    """The section must reference the dispatched agent and the dispatch mechanism."""
    region = _research_section(_read())
    assert RESEARCH_AGENT_REF in region, (
        "the `### research` section must reference agents/mb-research.md (the dispatched agent)"
    )
    assert "Task" in region, (
        "the `### research` section must reference Task (the dispatch mechanism)"
    )


def test_research_section_documents_fan_out_for_broad_sweeps() -> None:
    """Broad/multi-area questions fan out to parallel subagents."""
    region = _research_section(_read())
    assert ("fan-out" in region) or ("parallel" in region), (
        "the `### research` section must document fan-out / parallel subagents for broad sweeps"
    )


def test_research_section_has_fail_open_note() -> None:
    """Graph/index optional — degrade to Grep/Read, never block."""
    region = _research_section(_read())
    assert ("fail-open" in region.lower()) or ("Grep" in region), (
        "the `### research` section must carry a fail-open note "
        "(graph/index optional; degrade to Grep/Read)"
    )
