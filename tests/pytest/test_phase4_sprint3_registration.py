"""Phase 4 Sprint 3 — release-prep registration."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_version_bumped_to_4_0_1() -> None:
    text = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()
    assert text == "4.0.1", f"expected 4.0.1, got {text!r}"


def test_package_version_matches_version_file() -> None:
    version_file = (REPO_ROOT / "VERSION").read_text(encoding="utf-8").strip()
    init_text = (REPO_ROOT / "memory_bank_skill" / "__init__.py").read_text(encoding="utf-8")
    assert f'__version__ = "{version_file}"' in init_text


def test_changelog_has_4_0_1_section() -> None:
    text = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    assert "## [4.0.1]" in text


def test_changelog_has_4_0_0_section() -> None:
    text = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    assert "## [4.0.0]" in text


def test_changelog_4_0_0_mentions_phase3_phase4_and_i033() -> None:
    text = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    # Slice the [4.0.0] section.
    start = text.index("## [4.0.0]")
    end = text.find("\n## [", start + 1)
    section = text[start: end if end != -1 else len(text)]
    assert "Phase 3" in section
    assert "Phase 4" in section
    assert "I-033" in section or "checklist-prune" in section


def test_changelog_unreleased_section_is_empty_or_present_above() -> None:
    text = (REPO_ROOT / "CHANGELOG.md").read_text(encoding="utf-8")
    if "## [Unreleased]" not in text:
        return
    # Unreleased must come above [4.0.0]
    u = text.index("## [Unreleased]")
    r = text.index("## [4.0.0]")
    assert u < r


def test_reviewer_resolve_script_exists_and_executable() -> None:
    p = REPO_ROOT / "scripts" / "mb-reviewer-resolve.sh"
    assert p.exists()
    import os
    assert os.access(p, os.X_OK), "mb-reviewer-resolve.sh must be executable"


def test_commands_work_md_references_resolver() -> None:
    text = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")
    assert "mb-reviewer-resolve.sh" in text


def test_install_sh_probes_superpowers_skill() -> None:
    text = (REPO_ROOT / "install.sh").read_text(encoding="utf-8")
    assert "superpowers" in text.lower()
