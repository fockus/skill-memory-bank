"""`memory-bank` CLI locale flag wiring (v3.1.1+).

Covers the Python CLI surface for locale selection:

- `memory-bank install --language XX` accepts the four supported locales
  (en, ru, es, zh) via argparse `choices` — sticking an unsupported code
  must exit with code 2 and a clear error.
- `memory-bank init --lang XX` advertises the locale in the hint payload
  so agents (Claude Code / Cursor / Codex) can pick up the right templates.

These tests drive Stage 8; they fail until `cli.py` exposes `--lang` on
`init` and broadens `VALID_LANGUAGES` to include es/zh.
"""

from __future__ import annotations

import pytest

from memory_bank_skill import cli


@pytest.mark.parametrize("locale", ["en", "ru", "es", "zh"])
def test_install_accepts_supported_locale(locale: str) -> None:
    parser = cli.build_parser()
    args = parser.parse_args(["install", "--language", locale, "--non-interactive"])
    assert args.language == locale


def test_install_rejects_unsupported_locale() -> None:
    parser = cli.build_parser()
    with pytest.raises(SystemExit) as excinfo:
        parser.parse_args(["install", "--language", "fr"])
    assert excinfo.value.code == 2


@pytest.mark.parametrize("locale", ["en", "ru", "es", "zh"])
def test_init_accepts_lang_flag(locale: str) -> None:
    parser = cli.build_parser()
    args = parser.parse_args(["init", "--lang", locale])
    assert args.lang == locale


def test_init_rejects_unsupported_lang() -> None:
    parser = cli.build_parser()
    with pytest.raises(SystemExit) as excinfo:
        parser.parse_args(["init", "--lang", "fr"])
    assert excinfo.value.code == 2


def test_init_hint_mentions_selected_locale(capsys: pytest.CaptureFixture[str]) -> None:
    """When `--lang ru` is passed, the printed hint must surface the locale."""
    rc = cli.main(["init", "--lang", "ru"])
    assert rc == 0
    out = capsys.readouterr().out
    assert "lang=ru" in out or "--lang ru" in out, (
        "init hint must advertise the requested locale so /mb init can copy "
        "the matching templates"
    )


def test_valid_languages_covers_supported_locales() -> None:
    assert set(cli.VALID_LANGUAGES) >= {"en", "ru", "es", "zh"}
