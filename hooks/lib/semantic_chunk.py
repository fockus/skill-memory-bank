"""Split markdown and JSONL transcripts into embedding-sized text chunks."""
from __future__ import annotations

import json
from collections.abc import Iterable

CHUNK_CHARS = 1600          # ~400-512 tokens
OVERLAP_CHARS = 200


def _split_long(text: str, limit: int) -> list[str]:
    """Break a single oversized paragraph into <=limit pieces on word, then char, boundaries."""
    if len(text) <= limit:
        return [text]
    out: list[str] = []
    buf = ""
    for word in text.split(" "):
        while len(word) > limit:                # a single word longer than limit → hard char split
            if buf:
                out.append(buf)
                buf = ""
            out.append(word[:limit])
            word = word[limit:]
        if buf and len(buf) + len(word) + 1 > limit:
            out.append(buf)
            buf = word
        else:
            buf = (buf + " " + word) if buf else word
    if buf:
        out.append(buf)
    return out


def _pack(paragraphs: Iterable[str]) -> list[str]:
    chunks: list[str] = []
    buf = ""
    for para in paragraphs:
        para = para.strip()
        if not para:
            continue
        for piece in _split_long(para, CHUNK_CHARS):
            if buf and len(buf) + len(piece) + 1 > CHUNK_CHARS:
                chunks.append(buf)
                tail = buf[-OVERLAP_CHARS:] if len(buf) > OVERLAP_CHARS else buf
                buf = tail + "\n" + piece
            else:
                buf = (buf + "\n" + piece) if buf else piece
    if buf.strip():
        chunks.append(buf)
    return chunks


def _strip_frontmatter(text: str) -> str:
    if text.startswith("---"):
        end = text.find("\n---", 3)
        if end != -1:
            return text[end + 4:]
    return text


def chunk_markdown(text: str, source: str, kind: str) -> list[dict]:
    body = _strip_frontmatter(text)
    paras = body.split("\n\n")
    out = []
    for i, ck in enumerate(_pack(paras)):
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
        txt = _msg_text(msg.get("content"))
        if txt.strip():
            turns.append(f"{role}: {txt.strip()}")
    out = []
    for i, ck in enumerate(_pack(turns)):
        out.append({"text": ck.strip(), "source": source, "kind": "transcript", "anchor": f"c{i}"})
    return [c for c in out if c["text"]]
