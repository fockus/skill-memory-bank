"""transcript_window() anchors a recall hit back to raw JSONL turns.

memsearch's one capability we lack: show +/-N turns around a `turn_uuid`
(the session frontmatter already carries a `transcript:` path — see
`hooks/mb-recall.sh --transcript`). These tests exercise the pure helper
in isolation (no shell, no Memory Bank on disk).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "hooks" / "lib"))

from transcript_window import window  # noqa: E402


def _turn(uuid: str, role: str, text: str) -> str:
    return json.dumps({"type": role, "uuid": uuid, "message": {"role": role, "content": text}})


def _build_transcript(n: int = 8) -> tuple[str, list[str]]:
    """Build n alternating user/assistant turns; return (jsonl_text, uuid_list)."""
    uuids = [f"uuid-{i:02d}" for i in range(n)]
    lines = []
    for i, uid in enumerate(uuids):
        role = "user" if i % 2 == 0 else "assistant"
        lines.append(_turn(uid, role, f"turn number {i}"))
    return "\n".join(lines), uuids


def test_transcript_window_returns_pm_n_turns() -> None:
    jsonl_text, uuids = _build_transcript(n=7)
    middle = uuids[3]

    result = window(jsonl_text, middle, n=2)

    assert result is not None
    assert len(result) == 5
    assert [t["uuid"] for t in result] == uuids[1:6]
    # centered on the target uuid
    assert result[2]["uuid"] == middle
    for turn in result:
        assert turn["role"] in ("user", "assistant")
        assert "text" in turn


def test_transcript_window_clamps_at_file_edges() -> None:
    jsonl_text, uuids = _build_transcript(n=7)
    first = uuids[0]

    result = window(jsonl_text, first, n=2)

    assert result is not None
    # clamped at start: only [0:3] available (no turns before index 0)
    assert [t["uuid"] for t in result] == uuids[0:3]


def test_transcript_window_unknown_uuid_errors() -> None:
    jsonl_text, _uuids = _build_transcript(n=7)

    result = window(jsonl_text, "no-such-uuid", n=2)

    assert result is None


def test_transcript_window_skips_malformed_lines() -> None:
    jsonl_text, uuids = _build_transcript(n=5)
    jsonl_with_junk = jsonl_text + "\nnot valid json at all {{{\n"

    result = window(jsonl_text=jsonl_with_junk, turn_uuid=uuids[2], n=1)

    assert result is not None
    assert len(result) == 3


def test_transcript_window_redacts_secrets() -> None:
    secret = "sk-ant-" + ("a" * 40)
    lines = [
        _turn("u0", "user", "hello there"),
        _turn(
            "u1",
            "assistant",
            f"here is my key {secret} and <private>super secret plan</private> ok",
        ),
        _turn("u2", "user", "thanks"),
        _turn("u3", "assistant", "no problem"),
        _turn("u4", "user", "bye"),
    ]
    jsonl_text = "\n".join(lines)

    result = window(jsonl_text, "u1", n=2)

    assert result is not None
    full_text = " ".join(t["text"] for t in result)
    assert secret not in full_text
    assert "super secret plan" not in full_text
