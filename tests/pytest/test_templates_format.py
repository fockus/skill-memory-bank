"""Format invariants for templates/.memory-bank/ core files (v3.1 structure).

Guarantees relied on by `mb-plan-sync.sh`, `mb-plan-done.sh`,
`mb-idea.sh`, `mb-idea-promote.sh`, `mb-adr.sh`, and `mb-compact.sh`:

- plan.md:     exactly one `<!-- mb-active-plans --> ... <!-- /mb-active-plans -->`
               block, plus `## Current focus`, `## Active plans`, `## Deferred`,
               and `## Declined` sections.
- STATUS.md:   `<!-- mb-active-plans -->` and `<!-- mb-recent-done -->` blocks,
               plus `## Metrics`, `## Active plans`, `## Recently done`.
- BACKLOG.md:  `## Ideas` and `## ADR` sections, without a legacy `(none yet)`
               placeholder.
- checklist.md: starts with `# Project — Checklist` (or `# Checklist`) and
               contains at least one ⬜ item (smoke).

These tests fail if someone edits the templates and breaks the script contract.
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent.parent
TEMPLATES = REPO / "templates" / ".memory-bank"


def _read(name: str) -> str:
    path = TEMPLATES / name
    assert path.exists(), f"template missing: {path}"
    return path.read_text(encoding="utf-8")


def _exactly_one(text: str, pattern: str) -> None:
    hits = re.findall(pattern, text)
    assert len(hits) == 1, f"expected exactly one `{pattern}`, found {len(hits)}"


# ── plan.md ──────────────────────────────────────────────────────────────


def test_plan_md_has_plural_active_plans_marker_pair() -> None:
    text = _read("plan.md")
    _exactly_one(text, r"<!--\s*mb-active-plans\s*-->")
    _exactly_one(text, r"<!--\s*/mb-active-plans\s*-->")


def test_plan_md_has_no_legacy_singular_marker() -> None:
    text = _read("plan.md")
    assert "<!-- mb-active-plan -->" not in text
    assert "<!-- /mb-active-plan -->" not in text


def test_plan_md_has_required_sections() -> None:
    text = _read("plan.md")
    for section in (
        "## Current focus",
        "## Active plans",
        "## Deferred",
        "## Declined",
    ):
        assert section in text, f"plan.md missing section: {section}"


# ── STATUS.md ────────────────────────────────────────────────────────────


def test_status_md_has_active_plans_and_recent_done_markers() -> None:
    text = _read("STATUS.md")
    _exactly_one(text, r"<!--\s*mb-active-plans\s*-->")
    _exactly_one(text, r"<!--\s*/mb-active-plans\s*-->")
    _exactly_one(text, r"<!--\s*mb-recent-done\s*-->")
    _exactly_one(text, r"<!--\s*/mb-recent-done\s*-->")


def test_status_md_has_required_sections() -> None:
    text = _read("STATUS.md")
    for section in (
        "## Metrics",
        "## Active plans",
        "## Recently done",
    ):
        assert section in text, f"STATUS.md missing section: {section}"


# ── BACKLOG.md ───────────────────────────────────────────────────────────


def test_backlog_has_ideas_and_adr_sections() -> None:
    text = _read("BACKLOG.md")
    assert re.search(r"^## Ideas\s*$", text, re.MULTILINE), "BACKLOG missing `## Ideas`"
    assert re.search(r"^## ADR\s*$", text, re.MULTILINE), "BACKLOG missing `## ADR`"


def test_backlog_has_no_legacy_placeholder() -> None:
    text = _read("BACKLOG.md")
    assert "none yet" not in text, "legacy '(none yet)' placeholder must be removed"


# ── checklist.md ─────────────────────────────────────────────────────────


def test_checklist_starts_with_title_h1() -> None:
    text = _read("checklist.md")
    first_heading = next(
        (line for line in text.splitlines() if line.startswith("# ")),
        "",
    )
    assert first_heading.startswith("# "), "checklist.md must start with an H1"


def test_checklist_contains_open_item_smoke() -> None:
    text = _read("checklist.md")
    assert re.search(r"^- ⬜ ", text, re.MULTILINE), "checklist.md should contain a ⬜ item"


# ── smoke: all four core files exist ──────────────────────────────────────


@pytest.mark.parametrize("name", ["STATUS.md", "plan.md", "checklist.md", "BACKLOG.md"])
def test_core_file_present(name: str) -> None:
    assert (TEMPLATES / name).exists(), f"template missing: {name}"
