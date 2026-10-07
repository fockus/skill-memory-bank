"""i18n locale layout invariants (v3.1.1+).

Each supported locale must ship a full `.memory-bank/` skeleton with the same
marker/section contract as the English source of truth, so that `mb init
--lang=XX` produces a bank compatible with every `mb-*` script regardless of
the chosen locale.

Supported locales:
    - en  — reference (full English content)
    - ru, es, pt, zh — full translations (prose translated; script anchors stay English)

Invariants that MUST hold for every locale:
    1. All 7 core files present: status.md, roadmap.md, checklist.md, backlog.md,
       research.md, progress.md, lessons.md.
    2. roadmap.md has exactly one `<!-- mb-active-plans -->` marker pair.
    3. status.md has both `<!-- mb-active-plans -->` and `<!-- mb-recent-done -->`
       marker pairs.
    4. backlog.md has the `## Ideas` heading (strict EN — scripts use it as the
       canonical anchor across all locales) and no `## ADR` section (AGR-062).
    5. No locale carries a `TODO(i18n-<lang>)` scaffold banner.
    6. Every translated locale differs from English in its prose (not an EN copy).
"""

from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parent.parent.parent
LOCALES_DIR = REPO / "templates" / "locales"

SUPPORTED_LOCALES = ("en", "ru", "es", "pt", "zh")
FULL_LOCALES = SUPPORTED_LOCALES
TRANSLATED_LOCALES = ("ru", "es", "pt", "zh")

CORE_FILES = (
    "status.md",
    "roadmap.md",
    "checklist.md",
    "backlog.md",
    "research.md",
    "progress.md",
    "lessons.md",
)


def _bank(locale: str) -> Path:
    return LOCALES_DIR / locale / ".memory-bank"


def _read(locale: str, name: str) -> str:
    path = _bank(locale) / name
    assert path.exists(), f"missing template: {path}"
    return path.read_text(encoding="utf-8")


def _exactly_one(text: str, pattern: str, ctx: str) -> None:
    hits = re.findall(pattern, text)
    assert len(hits) == 1, f"{ctx}: expected exactly one `{pattern}`, found {len(hits)}"


@pytest.mark.parametrize("locale", SUPPORTED_LOCALES)
def test_locale_directory_exists(locale: str) -> None:
    assert _bank(locale).is_dir(), f"missing locale bank directory: {_bank(locale)}"


@pytest.mark.parametrize("locale", SUPPORTED_LOCALES)
@pytest.mark.parametrize("name", CORE_FILES)
def test_core_file_present_in_every_locale(locale: str, name: str) -> None:
    path = _bank(locale) / name
    assert path.exists(), f"missing template in locale '{locale}': {name}"


@pytest.mark.parametrize("locale", SUPPORTED_LOCALES)
def test_plan_md_has_plural_active_plans_marker_pair(locale: str) -> None:
    text = _read(locale, "roadmap.md")
    ctx = f"{locale}/roadmap.md"
    _exactly_one(text, r"<!--\s*mb-active-plans\s*-->", ctx)
    _exactly_one(text, r"<!--\s*/mb-active-plans\s*-->", ctx)


@pytest.mark.parametrize("locale", SUPPORTED_LOCALES)
def test_status_md_has_both_marker_pairs(locale: str) -> None:
    text = _read(locale, "status.md")
    ctx = f"{locale}/status.md"
    _exactly_one(text, r"<!--\s*mb-active-plans\s*-->", ctx)
    _exactly_one(text, r"<!--\s*/mb-active-plans\s*-->", ctx)
    _exactly_one(text, r"<!--\s*mb-recent-done\s*-->", ctx)
    _exactly_one(text, r"<!--\s*/mb-recent-done\s*-->", ctx)


@pytest.mark.parametrize("locale", SUPPORTED_LOCALES)
def test_backlog_has_canonical_english_anchors(locale: str) -> None:
    """Anchors stay English across all locales — scripts key off them."""
    text = _read(locale, "backlog.md")
    assert re.search(r"^## Ideas\s*$", text, re.MULTILINE), (
        f"{locale}/backlog.md must keep canonical `## Ideas` heading"
    )
    assert not re.search(r"^## ADR", text, re.MULTILINE), (
        f"{locale}/backlog.md must not carry an ADR section — ADRs live in adr.md"
    )


@pytest.mark.parametrize("locale", TRANSLATED_LOCALES)
@pytest.mark.parametrize("name", ("status.md", "roadmap.md", "checklist.md", "research.md", "progress.md", "lessons.md"))
def test_translated_locale_is_not_an_english_copy(locale: str, name: str) -> None:
    assert _read(locale, name) != _read("en", name), f"{locale}/{name} is still the English text"


@pytest.mark.parametrize("locale", FULL_LOCALES)
@pytest.mark.parametrize("name", CORE_FILES)
def test_full_locale_has_no_todo_banner(locale: str, name: str) -> None:
    text = _read(locale, name)
    assert "TODO(i18n-" not in text, (
        f"fully-translated locale '{locale}/{name}' must not carry a "
        "`TODO(i18n-*)` banner (that marker is only for scaffolds)"
    )
