#!/usr/bin/env python3
"""Build .memory-bank/index.json — pragmatic frontmatter index.

Usage:
    mb-index-json.py <mb_path>

Scans <mb_path>/notes/ for markdown files with YAML frontmatter
(``type``, ``tags``, ``importance``) plus a summary (first 2 non-empty
body lines after the frontmatter), and parses <mb_path>/lessons.md for
``### L-NNN: Title`` entries. Writes ``<mb_path>/index.json`` atomically
(tmp file + os.replace).

Shape::

    {
      "notes":   [{"path","type","tags","importance","summary"}, ...],
      "lessons": [{"id","title"}, ...],
      "generated_at": "ISO8601 UTC"
    }
"""

from __future__ import annotations

import json
import re
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

try:
    from memory_bank_skill._io import atomic_write
except ModuleNotFoundError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from memory_bank_skill._io import atomic_write

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.DOTALL)
LESSON_RE = re.compile(r"^###\s+(L-\d+)[:\-\s]+(.+?)\s*$", re.MULTILINE)
_KEBAB_RE_1 = re.compile(r"(.)([A-Z][a-z]+)")
_KEBAB_RE_2 = re.compile(r"([a-z0-9])([A-Z])")


def _kebab_case(s: str) -> str:
    """camelCase/PascalCase/UPPER → kebab-case (lowercase with hyphens)."""
    s = str(s).strip().strip('"\'')
    s = _KEBAB_RE_1.sub(r"\1-\2", s)
    s = _KEBAB_RE_2.sub(r"\1-\2", s)
    return s.lower()
# PII markers: `<private>...</private>` — content must not enter the index.
# Closed blocks are fully removed; open blocks without closing tag extend to EOF
# (protects against leaks when `</private>` is forgotten).
PRIVATE_CLOSED_RE = re.compile(r"<private>.*?</private>", re.DOTALL)
PRIVATE_OPEN_RE = re.compile(r"<private>.*\Z", re.DOTALL)


def _strip_private(text: str) -> tuple[str, bool]:
    """Remove <private>...</private> blocks. Return (clean_text, had_private)."""
    new, n_closed = PRIVATE_CLOSED_RE.subn("", text)
    new, n_open = PRIVATE_OPEN_RE.subn("", new)
    return new, (n_closed + n_open) > 0


def _parse_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    """Return (metadata, body). If parse fails → ({}, original text)."""
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    raw, body = m.group(1), m.group(2)
    try:
        import yaml  # noqa: PLC0415
    except ImportError:
        meta = _simple_yaml_parse(raw)
    else:
        try:
            meta = yaml.safe_load(raw) or {}
            if not isinstance(meta, dict):
                meta = {}
        except Exception:  # noqa: BLE001 — malformed frontmatter → defaults
            meta = _simple_yaml_parse(raw)
    return meta, body


def _simple_yaml_parse(raw: str) -> dict[str, Any]:
    """Tiny fallback YAML: handles `key: value` and `key: [a, b]`.

    Not full YAML — good enough for well-formed frontmatter when PyYAML
    is unavailable or full parse fails.
    """
    result: dict[str, Any] = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        key, value = key.strip(), value.strip()
        if not key:
            continue
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            if not inner:
                result[key] = []
            else:
                result[key] = [v.strip().strip("\"'") for v in inner.split(",")]
        elif value:
            result[key] = value.strip("\"'")
    return result


def _summary(body: str, max_lines: int = 2) -> str:
    lines: list[str] = []
    for raw in body.splitlines():
        stripped = raw.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            continue
        lines.append(stripped)
        if len(lines) >= max_lines:
            break
    return " ".join(lines)


def _index_notes(mb_path: Path) -> list[dict[str, Any]]:
    notes_dir = mb_path / "notes"
    if not notes_dir.is_dir():
        return []

    entries: list[dict[str, Any]] = []
    for note in sorted(notes_dir.rglob("*.md")):
        try:
            text = note.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue

        meta, body = _parse_frontmatter(text)
        tags = meta.get("tags") or []
        if isinstance(tags, str):
            tags = [tags]
        # Protection: do not index tags containing PII markers.
        tags = [t for t in tags if "<private>" not in str(t) and "</private>" not in str(t)]
        # Normalize: lowercase + kebab-case (camelCase/PascalCase/UPPER → foo-bar).
        tags = [_kebab_case(t) for t in tags]
        # Dedup preserving order.
        seen: set[str] = set()
        tags = [t for t in tags if not (t in seen or seen.add(t))]

        clean_body, has_private = _strip_private(body)

        rel = note.relative_to(mb_path).as_posix()
        # `notes/archive/...` entries get `archived: True` (opt in through `--include-archived`)
        archived = rel.startswith("notes/archive/")
        entries.append(
            {
                "path": rel,
                "type": meta.get("type") or "note",
                "tags": list(tags),
                "importance": meta.get("importance"),
                "summary": _summary(clean_body),
                "has_private": has_private,
                "archived": archived,
            }
        )
    return entries


def _index_lessons(mb_path: Path) -> list[dict[str, str]]:
    lessons_file = mb_path / "lessons.md"
    if not lessons_file.is_file():
        return []

    text = lessons_file.read_text(encoding="utf-8")
    return [
        {"id": m.group(1), "title": m.group(2).strip()}
        for m in LESSON_RE.finditer(text)
    ]


def build_index(mb_path_str: str) -> dict[str, Any]:
    """Scan mb_path, write index.json atomically, return the index data."""
    mb_path = Path(mb_path_str)
    if not mb_path.is_dir():
        raise FileNotFoundError(f"Memory Bank path not found: {mb_path}")

    data = {
        "notes": _index_notes(mb_path),
        "lessons": _index_lessons(mb_path),
        "generated_at": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }

    target = mb_path / "index.json"
    atomic_write(target, json.dumps(data, indent=2, ensure_ascii=False, sort_keys=False))

    return data


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"Usage: {argv[0]} <mb_path>", file=sys.stderr)
        return 1
    try:
        build_index(argv[1])
    except FileNotFoundError as e:
        print(f"[error] {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
