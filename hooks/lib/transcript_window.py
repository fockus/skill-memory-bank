"""Anchor a recall hit back to the raw JSONL transcript: +/-N turns around a uuid.

The one capability memsearch has that recall lacks — given a session's
`transcript:` JSONL path (see session frontmatter) and a `turn_uuid`, return
the ordered window of role-tagged, redacted turns around that uuid so a human
can see the surrounding conversation.
"""

from __future__ import annotations

import contextlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import re

from redact import redact_secrets  # noqa: E402

_PRIVATE_CLOSED_RE = re.compile(r"<private>.*?</private>", re.DOTALL)
_PRIVATE_OPEN_RE = re.compile(r"<private>.*\Z", re.DOTALL)


def _sanitize(text: str) -> str:
    """Strip <private> blocks and redact API keys/tokens (mirrors semantic_chunk._sanitize)."""
    text = _PRIVATE_CLOSED_RE.sub("", text)
    text = _PRIVATE_OPEN_RE.sub("", text)
    return redact_secrets(text)


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


def window(jsonl_text: str, turn_uuid: str, n: int = 2) -> list[dict] | None:
    """Return the +/-n turns around `turn_uuid`, or None if the uuid isn't found.

    Each returned entry is `{"uuid": str, "role": "user"|"assistant", "text": str}`
    with `text` sanitized (private blocks stripped, secrets redacted). Iterates the
    JSONL once; malformed lines are skipped silently.
    """
    turns: list[dict] = []
    target_idx: int | None = None
    for line in jsonl_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        msg = obj.get("message") or {}
        role = msg.get("role") or obj.get("type")
        if role not in ("user", "assistant"):
            continue
        uuid = obj.get("uuid")
        text = _sanitize(_msg_text(msg.get("content")))
        if uuid == turn_uuid:
            target_idx = len(turns)
        turns.append({"uuid": uuid, "role": role, "text": text})

    if target_idx is None:
        return None

    start = max(0, target_idx - n)
    end = target_idx + n + 1
    return turns[start:end]


def _main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("usage: transcript_window.py <jsonl_path> <turn_uuid> [--context N]", file=sys.stderr)
        return 2
    jsonl_path = argv[0]
    turn_uuid = argv[1]
    ctx_n = 2
    rest = argv[2:]
    i = 0
    while i < len(rest):
        if rest[i] == "--context" and i + 1 < len(rest):
            with contextlib.suppress(ValueError):
                ctx_n = int(rest[i + 1])
            i += 2
        else:
            i += 1

    try:
        with open(jsonl_path, encoding="utf-8", errors="replace") as f:
            jsonl_text = f.read()
    except OSError as exc:
        print(f"could not read transcript: {exc}", file=sys.stderr)
        return 3

    result = window(jsonl_text, turn_uuid, n=ctx_n)
    if result is None:
        print(f"turn_uuid not found in transcript: {turn_uuid}", file=sys.stderr)
        return 3

    for turn in result:
        uuid8 = (turn["uuid"] or "")[:8]
        print(f"--- {turn['role']} ({uuid8}) ---")
        print(turn["text"])
        print()
    return 0


if __name__ == "__main__":
    raise SystemExit(_main(sys.argv[1:]))
