"""ADR registry contract (AGR-062, plan 2026-10-06_fix_adr-registry Stage 2).

ADRs live in `<bank>/adr.md`. No agent-facing instruction may still route an
ADR into `backlog.md`, and `/mb adr` must demand a short record.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]

ADR_DOCS = (
    "commands/adr.md",
    "references/templates.md",
    "references/structure.md",
    "rules/RULES.md",
    "agents/mb-manager.md",
    "agents/mb-doctor.md",
    "agents/mb-architect.md",
)

_BACKLOG = re.compile(r"backlog\.md|\bBACKLOG\b")
# Case-sensitive on the token, so the lowercase file name `adr.md` is not a hit.
_ADR = re.compile(r"\bADRs?\b|ADR-NNN|(?i:architectural decision)")
# A bare backlog section heading that would hold ADRs.
_ADR_SECTION = re.compile(r"^## (ADR|Architectural decisions)( \(ADR\))?\s*$", re.IGNORECASE | re.MULTILINE)


def _text(rel: str) -> str:
    return (REPO / rel).read_text(encoding="utf-8")


@pytest.mark.parametrize("rel", ADR_DOCS)
def test_adr_docs_never_place_adrs_in_backlog(rel: str) -> None:
    offenders = [
        f"{rel}:{n}: {line.strip()}"
        for n, line in enumerate(_text(rel).splitlines(), 1)
        # A line that names both files is a redirect (backlog → adr.md), not a placement.
        if _BACKLOG.search(line) and _ADR.search(line) and "adr.md" not in line
    ]
    assert not offenders, "ADRs live in adr.md, not backlog.md:\n" + "\n".join(offenders)


@pytest.mark.parametrize("rel", ADR_DOCS)
def test_adr_docs_have_no_backlog_adr_section(rel: str) -> None:
    hits = _ADR_SECTION.findall(_text(rel))
    assert not hits, f"{rel} still shows a `## ADR` backlog section"


@pytest.mark.parametrize("rel", ADR_DOCS)
def test_adr_docs_name_the_registry(rel: str) -> None:
    assert "adr.md" in _text(rel).replace("commands/adr.md", ""), f"{rel} does not point to adr.md"


def test_adr_command_requires_short_four_field_record() -> None:
    body = _text("commands/adr.md")
    assert "1200 bytes" in body or "1 200 bytes" in body, "size limit for one ADR record is missing"
    for field in ("**Context:**", "**Decision:**", "**Alternatives:**", "**Consequences:**"):
        assert field in body, f"field {field} missing from /mb adr"
    assert "one line" not in body.lower(), "contradicting 'one line' format must be gone"
    assert "mb-adr.sh" in body, "/mb adr must create the record through mb-adr.sh"


def test_adr_command_description_names_registry() -> None:
    head = _text("commands/adr.md").split("---", 2)[1]
    assert "ADR registry (adr.md)" in head
