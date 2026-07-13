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
    assert TEMPLATES_REF in text, "commands/plan.md must cross-link to references/templates.md"
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
    re.compile(r"^SKILL\.md$"),
    re.compile(r"^commands/(mb|plan)\.md$"),
    re.compile(r"^rules/RULES\.md$"),
    re.compile(r"^CHANGELOG\.md$"),
    re.compile(r"^templates/locales/ru/"),
    re.compile(r"^\.memory-bank/progress\.md$"),
    re.compile(r"^\.memory-bank/lessons\.md$"),
    re.compile(r"^\.memory-bank/notes/"),
    re.compile(r"^\.memory-bank/reports/"),
    re.compile(r"^\.memory-bank/specs/"),
    re.compile(r"^\.memory-bank/plans/done/"),
    re.compile(r"^\.memory-bank/\.migration-backup-"),
    re.compile(r"^\.memory-bank/\.pre-migrate(?:-|/)"),
    re.compile(r"^references/templates\.md$"),  # the SSoT itself can cite legacy term
    re.compile(r"^tests/.*"),  # tests can reference the term they're checking
)


def test_historical_migration_backups_are_legacy_whitelisted() -> None:
    """Tracked migration backups preserve old terminology as historical data."""
    legacy_paths = (
        ".memory-bank/.migration-backup-20260422-174417/roadmap.md",
        ".memory-bank/.pre-migrate-20260421-163107/backlog.md",
        ".memory-bank/.pre-migrate/20260421_091115/checklist.md",
    )

    for path in legacy_paths:
        assert any(pattern.search(path) for pattern in WHITELIST_PATTERNS), path


def test_required_terminology_reference_surfaces_are_whitelisted() -> None:
    """Policy references intentionally cite the Cyrillic legacy aliases."""
    reference_paths = (
        "SKILL.md",
        "commands/mb.md",
        "commands/plan.md",
        "rules/RULES.md",
        "templates/locales/ru/.memory-bank/status.md",
    )

    for path in reference_paths:
        assert any(pattern.search(path) for pattern in WHITELIST_PATTERNS), path


def test_memory_bank_historical_entries_are_whitelisted() -> None:
    """Notes, reports, and specs preserve historical project language."""
    historical_paths = (
        ".memory-bank/notes/2026-05-23_20-32_parallel-pipeline-non-goals.md",
        ".memory-bank/reports/2026-05-24_opencode-integration-audit.md",
        ".memory-bank/specs/mb-skill-v2/design.md",
    )

    for path in historical_paths:
        assert any(pattern.search(path) for pattern in WHITELIST_PATTERNS), path


@pytest.mark.skipif(not (REPO_ROOT / ".git").exists(), reason="needs git repo to scope the grep")
def test_no_cyrillic_planning_terms_outside_whitelist() -> None:
    """Active project surface must not use legacy Cyrillic planning terms.

    Word-boundary detection is done with **Python's** `re` engine (used only
    to enumerate tracked `*.md` files, scoped exactly like the old `git grep`
    pathspec) rather than delegating the actual `\\b(...)\\b` match to the
    host's native regex engine via `git grep -E`.

    Why: `git grep`'s `\\b` is backed by the OS's C regex library, and BSD
    (macOS) and GNU (Linux) classify non-ASCII "word" characters
    differently. Concretely, BSD's default `\\w` class only covers ASCII
    `[A-Za-z0-9_]`, so a Cyrillic letter is treated as a *non-word*
    character; a `\\b` immediately before/after a Cyrillic word therefore
    sits between two non-word characters and never fires. Result: on macOS
    `git grep -inE '\\b(Этап|Эпик|Спринт|Фаза)\\b'` matched **zero** lines
    repo-wide even though the same content substring-matched 369 times —
    the test was passing, but vacuously, hiding every real violation. GNU
    grep (Linux CI) is Unicode-aware in a UTF-8 locale and matched for
    real, which is why CI went red while macOS stayed silently green. This
    is the same class of BSD-vs-GNU platform drift previously hit with
    `stat`.

    Python's `re` module does not have this problem: `\\b`/`\\w` are
    Unicode-aware by default for `str` patterns on every platform Python
    runs on, so `CYRILLIC_PLANNING_RE` (already used elsewhere in this
    file) behaves identically on macOS and Linux. Moving the match into
    Python — while still using `git ls-files` merely to enumerate tracked,
    pathspec-filtered files — removes the platform-dependent regex engine
    from the equation entirely instead of trying to out-guess it.
    """
    result = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.md", ":!CHANGELOG.md"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    rel_paths = [p for p in result.stdout.split("\0") if p]

    violations = []
    for rel_path in rel_paths:
        if any(p.search(rel_path) for p in WHITELIST_PATTERNS):
            continue
        full_path = REPO_ROOT / rel_path
        try:
            text = full_path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, FileNotFoundError):
            continue
        for lineno, line in enumerate(text.splitlines(), start=1):
            if CYRILLIC_PLANNING_RE.search(line):
                violations.append(f"{rel_path}:{lineno}:{line}")

    assert not violations, "Cyrillic planning terms found outside whitelist:\n" + "\n".join(
        violations[:25]
    )
