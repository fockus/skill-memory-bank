"""Contract: the Homebrew formula must track the current VERSION.

Regression guard (H-1): `packaging/homebrew/memory-bank.rb` was pinned to an old
release (3.1.2) while VERSION had moved on (5.2.0), so `brew install` shipped a
stale build with no CI check catching the drift. This test fails on any
version drift between the formula `url` and the VERSION file.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
VERSION_FILE = REPO_ROOT / "VERSION"
FORMULA = REPO_ROOT / "packaging" / "homebrew" / "memory-bank.rb"

# Tolerant of dotted / pre-release-ish version strings inside the sdist filename.
_URL_VERSION = re.compile(r"memory_bank_skill-(?P<v>[0-9][0-9A-Za-z.+-]*)\.tar\.gz")


def _version() -> str:
    return VERSION_FILE.read_text(encoding="utf-8").strip()


_SHA256 = re.compile(r'sha256 "(?P<sha>[0-9a-f]{64})"')


def _formula_url_version() -> str:
    text = FORMULA.read_text(encoding="utf-8")
    match = _URL_VERSION.search(text)
    assert match, "formula url must reference memory_bank_skill-<version>.tar.gz"
    return match.group("v")


def _formula_sha256() -> str:
    text = FORMULA.read_text(encoding="utf-8")
    match = _SHA256.search(text)
    assert match, "formula must carry a 64-hex sha256 for the pinned sdist"
    return match.group("sha")


def test_homebrew_formula_url_matches_version() -> None:
    assert _formula_url_version() == _version(), (
        "Homebrew formula url version drifted from VERSION; "
        f"formula={_formula_url_version()!r} VERSION={_version()!r}. "
        "Bump packaging/homebrew/memory-bank.rb (url + sha256) on release."
    )


def test_homebrew_formula_has_sha256() -> None:
    assert _formula_sha256(), "formula must carry a 64-hex sha256 for the pinned sdist"


def test_homebrew_formula_sha256_not_placeholder() -> None:
    """Regression guard: a `0`-repeated (or any single-char-repeated) sha256 is a
    placeholder, never a real digest — `brew install` would fail checksum
    verification against the actual downloaded sdist. Catches the C-2/H-1
    tail where the formula was bumped to the right `url` but sha256 was left
    as `"0" * 64`.
    """
    sha = _formula_sha256()
    assert len(set(sha)) > 1, (
        f"sha256 looks like a placeholder (single repeated char): {sha!r}. "
        "Compute the real digest of the pinned sdist "
        "(curl -L <url> | shasum -a 256) and update the formula."
    )
