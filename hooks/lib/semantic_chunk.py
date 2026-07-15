"""Split markdown and JSONL transcripts into embedding-sized text chunks."""

from __future__ import annotations

import json
import re
from collections.abc import Iterable

from redact import redact_secrets

CHUNK_CHARS = 1600  # ~400-512 tokens
OVERLAP_CHARS = 200

# <private>…</private> blocks never reach the index (mirrors mb-index-json.py).
_PRIVATE_CLOSED_RE = re.compile(r"<private>.*?</private>", re.DOTALL)
_PRIVATE_OPEN_RE = re.compile(r"<private>.*\Z", re.DOTALL)


def _sanitize(text: str) -> str:
    """Strip <private> blocks and redact API keys/tokens before chunking."""
    text = _PRIVATE_CLOSED_RE.sub("", text)
    text = _PRIVATE_OPEN_RE.sub("", text)
    return redact_secrets(text)


def _split_oversized_word(word: str, limit: int) -> tuple[list[str], str]:
    """Break a single overlong whitespace-free token into <=limit pieces.

    A `files:` list is comma-joined with NO spaces (`/a,/b,/c`), so it arrives
    here as one giant "word". Prefer comma boundaries so a piece never starts
    mid-path; fall back to a hard char slice only when a single comma segment
    is itself still longer than limit. Returns (full_pieces, remainder) where
    remainder (<=limit) is left for the caller's normal buf-packing.
    """
    if "," not in word:
        pieces: list[str] = []
        remainder = word
        while len(remainder) > limit:
            pieces.append(remainder[:limit])
            remainder = remainder[limit:]
        return pieces, remainder

    pieces = []
    buf = ""
    segments = word.split(",")
    for idx, segment in enumerate(segments):
        piece = segment + ("," if idx < len(segments) - 1 else "")
        while len(piece) > limit:  # a single path segment longer than limit
            if buf:
                pieces.append(buf)
                buf = ""
            pieces.append(piece[:limit])
            piece = piece[limit:]
        if buf and len(buf) + len(piece) > limit:
            pieces.append(buf)
            buf = piece
        else:
            buf += piece
    return pieces, buf


def _split_long(text: str, limit: int) -> list[str]:
    """Break a single oversized paragraph into <=limit pieces on word, then char, boundaries."""
    if len(text) <= limit:
        return [text]
    out: list[str] = []
    buf = ""
    for word in text.split(" "):
        if len(word) > limit:  # a single word longer than limit → comma-safe split
            if buf:
                out.append(buf)
                buf = ""
            full_pieces, word = _split_oversized_word(word, limit)
            out.extend(full_pieces)
        if buf and len(buf) + len(word) + 1 > limit:
            out.append(buf)
            buf = word
        else:
            buf = (buf + " " + word) if buf else word
    if buf:
        out.append(buf)
    return out


def _pack(paragraphs: Iterable[str], *, bullet_aware: bool = False) -> list[str]:
    """Pack paragraphs/bullets into <=CHUNK_CHARS chunks with a small overlap tail.

    `bullet_aware=True` drops the raw char-slice overlap: for bullet-structured
    content (see `_split_bullets`), a char-slice tail can start mid-bullet or
    mid-path, so a new chunk simply starts clean on the next piece instead.
    """
    chunks: list[str] = []
    buf = ""
    for para in paragraphs:
        para = para.strip("\n") if bullet_aware else para.strip()
        if not para:
            continue
        for piece in _split_long(para, CHUNK_CHARS):
            if buf and len(buf) + len(piece) + 1 > CHUNK_CHARS:
                chunks.append(buf)
                if bullet_aware:
                    buf = piece
                else:
                    tail = buf[-OVERLAP_CHARS:] if len(buf) > OVERLAP_CHARS else buf
                    buf = tail + "\n" + piece
            else:
                buf = (buf + "\n" + piece) if buf else piece
    if buf.strip():
        chunks.append(buf)
    return chunks


# A Live-log bullet starts a NEW line with `- HH:MM` (e.g. `- 20:30 — User: ...`).
_BULLET_START_RE = re.compile(r"^- \d{2}:\d{2}", re.MULTILINE)


def _is_bullet_structured(body: str) -> bool:
    return _BULLET_START_RE.search(body) is not None


def _split_bullets(body: str) -> list[str]:
    """Cut a bullet-structured body into atomic bullet units on `^- HH:MM` boundaries.

    Any content before the first bullet (e.g. a `## Live log` heading) is kept
    as its own leading unit so nothing is dropped.
    """
    starts = [m.start() for m in _BULLET_START_RE.finditer(body)]
    if not starts:
        return [body]
    units: list[str] = []
    if starts[0] > 0:
        units.append(body[: starts[0]])
    for idx, start in enumerate(starts):
        end = starts[idx + 1] if idx + 1 < len(starts) else len(body)
        units.append(body[start:end])
    return units


def _strip_frontmatter(text: str) -> str:
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[end + 4 :]
    return text


def chunk_markdown(text: str, source: str, kind: str) -> list[dict]:
    body = _sanitize(_strip_frontmatter(text))
    if _is_bullet_structured(body):
        packed = _pack(_split_bullets(body), bullet_aware=True)
    else:
        packed = _pack(body.split("\n\n"))
    out = []
    for i, ck in enumerate(packed):
        out.append({"text": ck.strip(), "source": source, "kind": kind, "anchor": f"p{i}"})
    return [c for c in out if c["text"]]


def _msg_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(str(block.get("text", "")))
        return "\n".join(parts)
    return ""


def chunk_transcript(jsonl_text: str, source: str) -> list[dict]:
    turns: list[str] = []
    for line in jsonl_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except (ValueError, TypeError):
            continue
        msg = obj.get("message") or {}
        role = msg.get("role") or obj.get("type")
        if role not in ("user", "assistant"):
            continue
        txt = _sanitize(_msg_text(msg.get("content")))
        if txt.strip():
            turns.append(f"{role}: {txt.strip()}")
    out = []
    for i, ck in enumerate(_pack(turns)):
        out.append({"text": ck.strip(), "source": source, "kind": "transcript", "anchor": f"c{i}"})
    return [c for c in out if c["text"]]
