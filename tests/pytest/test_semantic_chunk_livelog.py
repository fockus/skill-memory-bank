"""Live-log bullet chunking must never decapitate a file path.

Regression: `## Live log` blocks are a run of bullets
`- HH:MM — User: ... · tools: ... · files: /a,/b,/c` on consecutive lines
(no blank line between them), so the old `\\n\\n`-paragraph splitter treated
the whole block as ONE paragraph. When a single bullet's `files:` list (a
comma-joined path list with NO spaces) exceeded CHUNK_CHARS, the old
`_split_long` fell back to a raw char-slice at exactly `limit` characters
(since the whole list is one "word" with no space to break on), and
`_pack`'s overlap (`buf[-OVERLAP_CHARS:]`) compounded it with another raw
char slice — both cut mid-path, e.g. producing a chunk that starts with
`rs/fockus/Apps/...` instead of `/Users/fockus/Apps/...`.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "hooks" / "lib"))

from semantic_chunk import chunk_markdown  # noqa: E402

# A path fragment missing its leading slash, e.g. "rs/fockus/Apps/foo.py" —
# the telltale sign of a hard char-slice landing mid-path.
_DECAPITATED_PATH_RE = re.compile(r"^[a-z]{2,}/")


def _bullet(hhmm: str, files: list[str]) -> str:
    return f'- {hhmm} — User: "did stuff" · tools: Bash,Edit,Read · files: ' + ",".join(files)


def _build_livelog_fixture() -> str:
    small_files = [
        "/Users/fockus/Apps/skill-memory-bank/hooks/lib/semantic_chunk.py",
        "/Users/fockus/Apps/skill-memory-bank/hooks/lib/redact.py",
    ]
    # Pad well past CHUNK_CHARS (1600) with many absolute paths, comma-joined
    # with NO spaces — mirrors the real Live-log bullet shape exactly.
    huge_files = [
        f"/Users/fockus/Apps/skill-memory-bank/hooks/lib/file{i:03d}_module_name.py"
        for i in range(60)
    ]
    bullets = [
        _bullet("20:30", small_files),
        _bullet("21:39", huge_files),
        _bullet("22:07", small_files),
    ]
    return "## Live log\n" + "\n".join(bullets) + "\n"


def _first_nonempty_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line
    return ""


def test_chunk_livelog_files_heavy_first_line_is_clean_field() -> None:
    md = _build_livelog_fixture()
    chunks = chunk_markdown(md, source="session/x.md", kind="session")

    assert len(chunks) > 1, "fixture must be large enough to force multiple chunks"

    for chunk in chunks:
        first_line = _first_nonempty_line(chunk["text"])
        assert not _DECAPITATED_PATH_RE.match(first_line), (
            f"chunk starts with a decapitated path fragment: {first_line!r}"
        )
        is_bullet_start = bool(re.match(r"^- \d{2}:\d{2}", first_line))
        is_clean_field_or_path = bool(re.match(r"^(tools:|files:|/|## Live log)", first_line))
        assert is_bullet_start or is_clean_field_or_path, (
            f"chunk's first line is neither a bullet start nor a clean field/path token: "
            f"{first_line!r}"
        )


def test_chunk_livelog_overlap_never_crosses_bullet() -> None:
    md = _build_livelog_fixture()
    chunks = chunk_markdown(md, source="session/x.md", kind="session")

    assert len(chunks) > 1

    # Every chunk AFTER the first must begin cleanly too — i.e. the overlap
    # never smuggles in a raw char-slice tail from the previous bullet.
    for chunk in chunks[1:]:
        first_line = _first_nonempty_line(chunk["text"])
        assert re.match(r"^(- \d{2}:\d{2}|tools:|files:|/)", first_line), (
            f"overlap crossed into a bullet mid-way: {first_line!r}"
        )

    # The full path list must survive intact somewhere across the chunks —
    # no path was silently dropped or fused with its neighbor.
    joined = "\n".join(c["text"] for c in chunks)
    assert "/Users/fockus/Apps/skill-memory-bank/hooks/lib/file000_module_name.py" in joined
    assert "/Users/fockus/Apps/skill-memory-bank/hooks/lib/file059_module_name.py" in joined


def test_chunk_markdown_plain_paragraph_unchanged() -> None:
    md = "a\n\nb\n\nc"
    chunks = chunk_markdown(md, source="notes/plain.md", kind="note")

    # Old paragraph-packing behavior: three short paragraphs comfortably fit
    # CHUNK_CHARS together and are newline-joined into a single chunk.
    assert chunks == [
        {"text": "a\nb\nc", "source": "notes/plain.md", "kind": "note", "anchor": "p0"}
    ]
