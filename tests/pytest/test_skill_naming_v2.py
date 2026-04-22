"""Guard: skill source code must use v2 lowercase filenames.

Exclusions:
- scripts/mb-migrate-v2.sh (migration logic references both names by design)
- scripts/mb-migrate-structure.sh (historical v3.0 → v3.1 migrator)
- CHANGELOG.md (release history)
- docs/MIGRATION-*.md (migration documentation)
- tests/pytest/fixtures/** (test fixtures intentionally use v1 names)
- tests/pytest/test_migrate_v2.py (tests migration logic on v1 fixture)
- tests/pytest/test_migrate_v2_e2e.py (e2e contract test; references v1 names by design)
- .memory-bank/** (may contain user data during dogfood migration)
- .pre-migrate*/** (pre-migration backups)
- dist/, site/, .git/, .pytest_cache/, .ruff_cache/, __pycache__/
- SECURITY_AUDIT_REPORT.md (historical)
- commands/start.md (contains v1 detection patterns for Pre-flight check)
- commands/mb.md (delegates to v1 detection; may reference legacy names)
- agents/mb-doctor.md (contains v1 detection patterns in "Check: v2 naming migration")
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

EXCLUDED_PATHS = (
    "scripts/mb-migrate-v2.sh",
    "scripts/mb-migrate-structure.sh",
    "CHANGELOG.md",
    "docs/MIGRATION-v3-v3.1.md",
    "docs/MIGRATION-v1-v2.md",
    "docs/MIGRATION-install-v1-v2.md",
    "tests/pytest/fixtures/",
    "tests/pytest/test_migrate_v2.py",
    "tests/pytest/test_migrate_v2_e2e.py",
    "tests/pytest/test_skill_naming_v2.py",
    ".memory-bank/",
    ".pre-migrate",
    "SECURITY_AUDIT_REPORT.md",
    "dist/",
    "site/",
    ".git/",
    ".pytest_cache/",
    ".ruff_cache/",
    "__pycache__/",
    # v1-layout autodetection docs: contain legacy names as detection patterns
    "commands/start.md",
    "commands/mb.md",
    "agents/mb-doctor.md",
)

OLD_NAMES = re.compile(r"\b(STATUS|BACKLOG|RESEARCH)\.md\b")
# plan.md (file-ref) — but NOT `commands/plan.md` (that's the filename of the
# /plan slash command definition, which we keep; renaming would break the
# user-facing slash command).
OLD_PLAN = re.compile(r"(?<![A-Za-z0-9_\-])(?<!commands/)plan\.md\b")


def _is_excluded(path: Path) -> bool:
    rel = path.relative_to(REPO_ROOT).as_posix()
    return any(rel.startswith(p) for p in EXCLUDED_PATHS)


@pytest.mark.parametrize("suffix", ["*.md", "*.sh", "*.py"])
def test_no_v1_uppercase_names(suffix: str) -> None:
    offenders: list[str] = []
    for f in REPO_ROOT.rglob(suffix):
        if _is_excluded(f):
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, PermissionError):
            continue
        if OLD_NAMES.search(text):
            offenders.append(f.relative_to(REPO_ROOT).as_posix())
    assert not offenders, (
        "Files still reference STATUS.md/BACKLOG.md/RESEARCH.md:\n  "
        + "\n  ".join(offenders)
    )


@pytest.mark.parametrize("suffix", ["*.md", "*.sh", "*.py"])
def test_no_v1_plan_md(suffix: str) -> None:
    offenders: list[str] = []
    for f in REPO_ROOT.rglob(suffix):
        if _is_excluded(f):
            continue
        try:
            text = f.read_text(encoding="utf-8")
        except (UnicodeDecodeError, PermissionError):
            continue
        if OLD_PLAN.search(text):
            offenders.append(f.relative_to(REPO_ROOT).as_posix())
    assert not offenders, (
        "Files still reference plan.md (expected roadmap.md):\n  "
        + "\n  ".join(offenders)
    )
