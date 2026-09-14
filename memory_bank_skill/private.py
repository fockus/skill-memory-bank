"""Pure private-span handling shared by Memory Bank search and indexing."""

from __future__ import annotations

import re

_MARKER_RE = re.compile(r"<(/?)private>")


def _private_spans(text: str) -> list[tuple[int, int]]:
    """Return disjoint original-text spans; an unfinished outer block ends at EOF."""
    spans: list[tuple[int, int]] = []
    depth = 0
    start = 0
    for marker in _MARKER_RE.finditer(text):
        if not marker.group(1):
            if depth == 0:
                start = marker.start()
            depth += 1
        elif depth:
            depth -= 1
            if depth == 0:
                spans.append((start, marker.end()))
    if depth:
        spans.append((start, len(text)))
    return spans


def strip_private(text: str) -> tuple[str, bool]:
    """Remove complete private spans and return (public_text, had_private)."""
    spans = _private_spans(text)
    parts: list[str] = []
    cursor = 0
    for start, end in spans:
        parts.append(text[cursor:start])
        cursor = end
    parts.append(text[cursor:])
    return "".join(parts), bool(spans)


def redact_private_lines(text: str) -> list[str]:
    """Redact each span's overlap with a line, preserving public text and line numbers."""
    spans = _private_spans(text)
    result: list[str] = []
    offset = span_index = 0
    for raw_line in text.splitlines(keepends=True):
        line = raw_line.splitlines()[0]
        line_end = offset + len(line)
        while span_index < len(spans) and spans[span_index][1] <= offset:
            span_index += 1
        cursor = 0
        parts: list[str] = []
        current = span_index
        while current < len(spans) and spans[current][0] < line_end:
            start, end = spans[current]
            parts.extend((line[cursor:max(0, start - offset)], "[REDACTED]"))
            cursor = min(len(line), end - offset)
            current += 1
        parts.append(line[cursor:])
        result.append("".join(parts))
        offset += len(raw_line)
    return result
