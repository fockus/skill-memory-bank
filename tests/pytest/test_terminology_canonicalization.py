"""Stage 7 — Phase / Sprint / Stage SSoT propagation.

Single source of truth lives in `references/templates.md` § Plan decomposition.
Every surface that mentions plan structure must cross-link to it (one-line
ref) instead of redefining or drifting away. Cyrillic «Этап / Эпик / Спринт /
Фаза» are legacy aliases — allowed only in archived `plans/done/*.md`,
historical notes, the SSoT itself, and a handful of explicitly whitelisted
files (CHANGELOG history, lessons.md, progress.md).
"""

from __future__ import annotations

import re
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
TEMPLATES_REF = "references/templates.md"
HIERARCHY_PHRASE = re.compile(
    r"Plan\s+hierarchy.*?(Phase|references/templates\.md)",
    re.IGNORECASE | re.DOTALL,
)


def _read(rel: str) -> str:
    return (REPO_ROOT / rel).read_text(encoding="utf-8")


def test_rules_md_has_naming_conventions_section() -> None:
    """`rules/RULES.md` must declare the Phase/Sprint/Stage convention."""
    text = _read("rules/RULES.md")
    assert re.search(r"^##\s+Naming conventions\s*$", text, re.MULTILINE), (
        "rules/RULES.md must contain a `## Naming conventions` section pointing "
        "at references/templates.md"
    )
    # The section must reference the SSoT path.
    section_match = re.search(
        r"^##\s+Naming conventions\s*$(.*?)(^##\s+|\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    assert section_match, "could not isolate `## Naming conventions` body"
    body = section_match.group(1)
    assert TEMPLATES_REF in body, (
        f"## Naming conventions must reference `{TEMPLATES_REF}` (the SSoT)"
    )


def test_skill_md_links_to_terminology_reference() -> None:
    text = _read("SKILL.md")
    assert HIERARCHY_PHRASE.search(text), (
        "SKILL.md must mention 'Plan hierarchy' and link to references/templates.md"
    )
    assert TEMPLATES_REF in text


def test_commands_plan_md_has_hierarchy_reminder() -> None:
    text = _read("commands/plan.md")
    assert TEMPLATES_REF in text, (
        "commands/plan.md must cross-link to references/templates.md"
    )
    # The plan command already mentions templates.md in section 1; the
    # hierarchy reminder must appear in section 0 (Validate arguments) — the
    # earliest place a reader sees before scaffolding a plan.
    section_zero = re.search(
        r"^##\s+0\..*?Validate arguments\s*$(.*?)(^##\s+1\.)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    assert section_zero, "could not locate `## 0. Validate arguments` section"
    body_zero = section_zero.group(1)
    assert "Phase" in body_zero and "Sprint" in body_zero and "Stage" in body_zero, (
        "Section 0 must remind the reader of Phase / Sprint / Stage hierarchy"
    )


def test_commands_mb_md_links_to_terminology_reference() -> None:
    text = _read("commands/mb.md")
    assert TEMPLATES_REF in text, (
        "commands/mb.md must cross-link to references/templates.md from the /mb plan section"
    )


def test_planning_and_verification_md_links_to_terminology_reference() -> None:
    text = _read("references/planning-and-verification.md")
    assert TEMPLATES_REF in text or "templates.md" in text, (
        "references/planning-and-verification.md must cross-link to templates.md"
    )


CYRILLIC_PLANNING_RE = re.compile(r"\b(Этап|Эпик|Спринт|Фаза)\b", re.IGNORECASE)


# Files where Cyrillic planning terms are legitimate and must NOT trigger drift.
WHITELIST_PATTERNS = (
    re.compile(r"^plans/done/"),
    re.compile(r"^CHANGELOG\.md$"),
    re.compile(r"^\.memory-bank/progress\.md$"),
    re.compile(r"^\.memory-bank/lessons\.md$"),
    re.compile(r"^\.memory-bank/\.pre-migrate/"),
    re.compile(r"^\.memory-bank/\.pre-migrate-[^/]+/"),
    re.compile(r"^\.memory-bank/\.migration-backup-[^/]+/"),
    re.compile(r"^\.memory-bank/notes/"),
    re.compile(r"^\.memory-bank/plans/done/"),
    re.compile(r"^\.memory-bank/specs/"),
    re.compile(r"^commands/plan\.md$"),
    re.compile(r"^rules/RULES\.md$"),
    re.compile(r"^references/templates\.md$"),  # the SSoT itself can cite legacy term
    re.compile(r"^templates/locales/"),
    re.compile(r"^tests/.*"),  # tests can reference the term they're checking
)


@pytest.mark.skipif(
    not (REPO_ROOT / ".git").exists(), reason="needs git repo to scope the grep"
)
def test_no_cyrillic_planning_terms_outside_whitelist() -> None:
    """Active project surface must not use legacy Cyrillic planning terms."""
    result = subprocess.run(
        [
            "git",
            "grep",
            "-inE",
            r"\b(Этап|Эпик|Спринт|Фаза)\b",
            "--",
            "*.md",
            ":!CHANGELOG.md",
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 1:
        return  # no matches at all → nothing to whitelist

    violations = []
    for line in result.stdout.splitlines():
        path = line.split(":", 1)[0]
        if any(p.search(path) for p in WHITELIST_PATTERNS):
            continue
        violations.append(line)

    assert not violations, (
        "Cyrillic planning terms found outside whitelist:\n"
        + "\n".join(violations[:25])
    )
