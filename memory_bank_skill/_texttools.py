"""Reusable text transforms for installer and maintenance scripts."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path

from memory_bank_skill._io import atomic_write

# ═══ Single source of truth for the language-rule strings install.sh, the adapters, and
# uninstall.sh write into RULES.md / CLAUDE.md / AGENTS.md. Response and code-comment
# languages are named in English inside the rules text, so a new locale needs only its
# display name here (plus the install.sh / mb-upgrade.sh / cli.py lists). Unknown codes fall
# back to English (never an empty rule) and report it via `used_fallback`.
LANGUAGE_NAMES: dict[str, str] = {
    "en": "English",
    "ru": "Russian",
    "es": "Spanish",
    "pt": "Portuguese",
    "zh": "Chinese (Simplified)",
}
FALLBACK_LANGUAGE = "en"


@dataclass(frozen=True)
class LanguageStrings:
    rule_full: str
    rule_short: str
    comments_language: str
    used_fallback: bool


def resolve_language_strings(language: str, comments_language: str | None = None) -> LanguageStrings:
    """Build the language-rule strings for a response language and a code-comment language.

    `comments_language` defaults to the response language. Unknown codes fall back to English
    and set `used_fallback=True`, so callers can warn instead of shipping an empty rule.
    """
    comments_code = comments_language or language
    used_fallback = language not in LANGUAGE_NAMES or comments_code not in LANGUAGE_NAMES
    response = LANGUAGE_NAMES.get(language, LANGUAGE_NAMES[FALLBACK_LANGUAGE])
    comments = LANGUAGE_NAMES.get(comments_code, response)
    if comments == response:
        full = f"{response} — responses and code comments. Technical terms may remain in English."
        short = f"respond in {response}; technical terms may remain in English."
    else:
        full = f"{response} — responses; {comments} — code comments. Technical terms may remain in English."
        short = (f"respond in {response}; write code comments in {comments}; "
                 "technical terms may remain in English.")
    return LanguageStrings(full, short, comments, used_fallback)


_COMMENTS_IN = re.compile(r"comments in (?:" + "|".join(re.escape(n) for n in LANGUAGE_NAMES.values()) + r")")


def strip_between_markers(text: str, start_marker: str, end_marker: str) -> str:
    """Remove all lines between marker lines, preserving surrounding content."""
    inside = False
    kept: list[str] = []
    for line in text.splitlines():
        if start_marker in line:
            inside = True
            continue
        if inside and end_marker in line:
            inside = False
            continue
        if not inside:
            kept.append(line)
    return "\n".join(kept).strip()


def strip_after_marker(text: str, marker: str) -> str:
    """Remove marker and everything after it."""
    if marker not in text:
        return text.rstrip()
    return text[: text.index(marker)].rstrip()


def localize_language_text(
    text: str,
    *,
    rule_full: str,
    rule_short: str,
    comments_language: str,
    after_marker: str = "",
) -> str:
    """Rewrite only the managed language statements inside the target text."""
    prefix = ""
    target = text
    if after_marker and after_marker in text:
        prefix, rest = text.split(after_marker, 1)
        prefix = prefix + after_marker
        target = rest

    target = re.sub(
        r"1\. \*\*Language\*\*: .+",
        f"1. **Language**: {rule_full}",
        target,
    )
    target = re.sub(
        r"> \*\*Language\*\* — .+",
        f"> **Language** — {rule_short}",
        target,
    )
    target = _COMMENTS_IN.sub(f"comments in {comments_language}", target)
    return prefix + target


def localize_file(
    path: str | Path,
    *,
    rule_full: str,
    rule_short: str,
    comments_language: str,
    after_marker: str = "",
) -> bool:
    target = Path(path)
    if not target.exists():
        return False
    updated = localize_language_text(
        target.read_text(encoding="utf-8"),
        rule_full=rule_full,
        rule_short=rule_short,
        comments_language=comments_language,
        after_marker=after_marker,
    )
    atomic_write(target, updated, encoding="utf-8")
    return True


def _write_or_delete(path: Path, text: str, *, delete_if_empty: bool) -> bool:
    normalized = text.strip()
    if normalized:
        atomic_write(path, normalized + "\n", encoding="utf-8")
        return True
    if delete_if_empty and path.exists():
        path.unlink()
        return False
    atomic_write(path, "", encoding="utf-8")
    return False


def strip_between_markers_file(
    path: str | Path,
    *,
    start_marker: str,
    end_marker: str,
    delete_if_empty: bool = True,
) -> bool:
    target = Path(path)
    if not target.exists():
        return False
    stripped = strip_between_markers(target.read_text(encoding="utf-8"), start_marker, end_marker)
    return _write_or_delete(target, stripped, delete_if_empty=delete_if_empty)


def strip_after_marker_file(
    path: str | Path,
    *,
    marker: str,
    delete_if_empty: bool = True,
) -> bool:
    target = Path(path)
    if not target.exists():
        return False
    stripped = strip_after_marker(target.read_text(encoding="utf-8"), marker)
    return _write_or_delete(target, stripped, delete_if_empty=delete_if_empty)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Shared text tools for memory-bank-skill")
    sub = parser.add_subparsers(dest="command", required=True)

    localize = sub.add_parser("localize-file")
    localize.add_argument("--path", required=True)
    localize.add_argument("--rule-full", required=True)
    localize.add_argument("--rule-short", required=True)
    localize.add_argument("--comments-language", required=True)
    localize.add_argument("--after-marker", default="")

    strip_after = sub.add_parser("strip-after-marker")
    strip_after.add_argument("--path", required=True)
    strip_after.add_argument("--marker", required=True)
    strip_after.add_argument("--keep-empty", action="store_true")

    strip_between = sub.add_parser("strip-between-markers")
    strip_between.add_argument("--path", required=True)
    strip_between.add_argument("--start-marker", required=True)
    strip_between.add_argument("--end-marker", required=True)
    strip_between.add_argument("--keep-empty", action="store_true")

    # A18: install.sh/uninstall.sh resolve their language-rule strings through
    # this subcommand instead of hardcoded bash case statements — a plain
    # `KEY=value`-per-line stdout format that's trivial to parse in bash
    # without a JSON dependency.
    lang_strings = sub.add_parser("language-strings")
    lang_strings.add_argument("--language", required=True)
    lang_strings.add_argument("--comments-language", default=None)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.command == "localize-file":
        localize_file(
            args.path,
            rule_full=args.rule_full,
            rule_short=args.rule_short,
            comments_language=args.comments_language,
            after_marker=args.after_marker,
        )
        return 0
    if args.command == "strip-after-marker":
        strip_after_marker_file(
            args.path,
            marker=args.marker,
            delete_if_empty=not args.keep_empty,
        )
        return 0
    if args.command == "strip-between-markers":
        strip_between_markers_file(
            args.path,
            start_marker=args.start_marker,
            end_marker=args.end_marker,
            delete_if_empty=not args.keep_empty,
        )
        return 0
    if args.command == "language-strings":
        result = resolve_language_strings(args.language, args.comments_language)
        print(f"RULE_FULL={result.rule_full}")
        print(f"RULE_SHORT={result.rule_short}")
        print(f"COMMENTS_LANGUAGE={result.comments_language}")
        print(f"USED_FALLBACK={'1' if result.used_fallback else '0'}")
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
