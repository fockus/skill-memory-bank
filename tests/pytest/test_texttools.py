"""Tests for shared memory_bank_skill text and IO helpers.

Stage 3 contract:
    - memory_bank_skill._io.atomic_write(path, content) writes atomically
      and leaves no tmp file behind on success or failure.
    - memory_bank_skill._texttools exposes reusable helpers for:
      * stripping text from a marker to EOF
      * stripping text between start/end markers
      * localizing language-rule text with optional after-marker boundary
    - scripts/mb-import.py, scripts/mb-index-json.py, and scripts/mb-codegraph.py
      should no longer define their own `_atomic_write` helper.
"""

from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

_io = importlib.import_module("memory_bank_skill._io")
_texttools = importlib.import_module("memory_bank_skill._texttools")


def test_atomic_write_writes_file_without_leftover_tmp(tmp_path: Path) -> None:
    target = tmp_path / "file.txt"

    _io.atomic_write(target, "hello\n")

    assert target.read_text(encoding="utf-8") == "hello\n"
    assert list(tmp_path.glob(".file.txt.*.tmp")) == []


def test_atomic_write_preserves_original_on_replace_failure(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    target = tmp_path / "file.txt"
    target.write_text("old\n", encoding="utf-8")

    original_replace = os.replace

    def failing_replace(src: str, dst: str) -> None:
        raise OSError("simulated replace failure")

    monkeypatch.setattr(os, "replace", failing_replace)
    with pytest.raises(OSError):
        _io.atomic_write(target, "new\n")

    assert target.read_text(encoding="utf-8") == "old\n"
    assert list(tmp_path.glob(".file.txt.*.tmp")) == []
    monkeypatch.setattr(os, "replace", original_replace)


def test_strip_between_markers_preserves_user_content() -> None:
    text = """# User header

before
<!-- memory-bank:start -->
managed
<!-- memory-bank:end -->
after
"""

    stripped = _texttools.strip_between_markers(
        text,
        "<!-- memory-bank:start -->",
        "<!-- memory-bank:end -->",
    )

    assert "managed" not in stripped
    assert "# User header" in stripped
    assert "after" in stripped


def test_strip_after_marker_removes_tail() -> None:
    text = """# User header
keep this
# [MEMORY-BANK-SKILL]
managed tail
"""

    stripped = _texttools.strip_after_marker(text, "# [MEMORY-BANK-SKILL]")

    assert stripped == "# User header\nkeep this"


def test_localize_language_text_only_after_marker_boundary() -> None:
    text = """# untouched prefix
English should stay here.
# [MEMORY-BANK-SKILL]
1. **Language**: English — responses and code comments. Technical terms may remain in English.
> **Language** — respond in English; technical terms may remain in English.
comments in English
"""

    localized = _texttools.localize_language_text(
        text,
        rule_full="Russian — responses and code comments. Technical terms may remain in English.",
        rule_short="respond in Russian; technical terms may remain in English.",
        comments_language="Russian",
        after_marker="# [MEMORY-BANK-SKILL]",
    )

    assert "English should stay here." in localized
    assert "1. **Language**: Russian" in localized
    assert "> **Language** — respond in Russian" in localized
    assert "comments in Russian" in localized


def test_localize_language_text_does_not_replace_other_critical_rules() -> None:
    text = """# [MEMORY-BANK-SKILL]
> **Contract-First** — Protocol/ABC → contract tests → implementation.
> **TDD** — tests first, then code.
> **Language** — respond in English; technical terms may remain in English.
> **No placeholders** — no TODO, `...`, or pseudocode.
"""

    localized = _texttools.localize_language_text(
        text,
        rule_full="Russian — responses and code comments. Technical terms may remain in English.",
        rule_short="respond in Russian; technical terms may remain in English.",
        comments_language="Russian",
        after_marker="# [MEMORY-BANK-SKILL]",
    )

    assert "> **Contract-First** — Protocol/ABC → contract tests → implementation." in localized
    assert "> **TDD** — tests first, then code." in localized
    assert (
        "> **Language** — respond in Russian; technical terms may remain in English." in localized
    )
    assert "> **No placeholders** — no TODO, `...`, or pseudocode." in localized


@pytest.mark.parametrize(
    "relative_path",
    [
        "scripts/mb-import.py",
        "scripts/mb-index-json.py",
        "scripts/mb-codegraph.py",
    ],
)
def test_scripts_no_longer_define_private_atomic_write(relative_path: str) -> None:
    content = (REPO_ROOT / relative_path).read_text(encoding="utf-8")
    assert "def _atomic_write" not in content


@pytest.mark.parametrize(
    ("code", "name"),
    [("en", "English"), ("ru", "Russian"), ("es", "Spanish"), ("pt", "Portuguese"), ("zh", "Chinese")],
)
def test_supported_languages_resolve_without_fallback(code: str, name: str) -> None:
    result = _texttools.resolve_language_strings(code)
    assert result.used_fallback is False
    assert result.rule_short.startswith(f"respond in {name}")
    assert result.rule_full.startswith(f"{name}")
    assert result.comments_language.startswith(name)


def test_unknown_language_falls_back_to_english_and_says_so() -> None:
    result = _texttools.resolve_language_strings("xx")
    assert result.used_fallback is True
    assert result.rule_short.startswith("respond in English")


def test_comments_language_defaults_to_the_response_language() -> None:
    result = _texttools.resolve_language_strings("ru")
    assert result.rule_full == "Russian — responses and code comments. Technical terms may remain in English."
    assert result.comments_language == "Russian"


def test_comments_language_can_differ_from_the_response_language() -> None:
    result = _texttools.resolve_language_strings("ru", comments_language="en")
    assert result.rule_full == "Russian — responses; English — code comments. Technical terms may remain in English."
    assert result.rule_short == "respond in Russian; write code comments in English; technical terms may remain in English."
    assert result.comments_language == "English"


def test_localize_rewrites_both_language_lines_for_split_languages() -> None:
    result = _texttools.resolve_language_strings("es", comments_language="en")
    text = "1. **Language**: English — responses and code comments.\n> **Language** — respond in English; x\n"
    out = _texttools.localize_language_text(
        text, rule_full=result.rule_full, rule_short=result.rule_short,
        comments_language=result.comments_language,
    )
    assert "1. **Language**: Spanish — responses; English — code comments." in out
    assert "> **Language** — respond in Spanish; write code comments in English;" in out


def test_language_strings_cli_accepts_a_comments_language(capsys: pytest.CaptureFixture[str]) -> None:
    assert _texttools.main(["language-strings", "--language", "pt", "--comments-language", "en"]) == 0
    out = capsys.readouterr().out
    assert "RULE_SHORT=respond in Portuguese; write code comments in English;" in out
    assert "COMMENTS_LANGUAGE=English" in out
