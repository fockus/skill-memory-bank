import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from semantic_chunk import CHUNK_CHARS, chunk_markdown, chunk_transcript


def test_markdown_splits_into_nonempty_chunks_carrying_source():
    text = "# Title\n\n" + ("para one. " * 200) + "\n\n" + ("para two. " * 200)
    chunks = chunk_markdown(text, source="session/x.md", kind="session")
    assert len(chunks) >= 2
    assert all(c["text"].strip() for c in chunks)
    assert all(c["source"] == "session/x.md" and c["kind"] == "session" for c in chunks)


def test_markdown_respects_chunk_size():
    text = "word " * 5000
    chunks = chunk_markdown(text, source="notes/n.md", kind="note")
    assert all(len(c["text"]) <= CHUNK_CHARS + 600 for c in chunks)  # +overlap slack


def test_transcript_extracts_user_assistant_text_skips_tool_noise():
    import json
    lines = [
        json.dumps({"type": "user", "message": {"role": "user", "content": "как починить деплой"}}),
        json.dumps({"type": "assistant", "message": {"role": "assistant",
            "content": [{"type": "text", "text": "проверь kamal proxy host"},
                        {"type": "tool_use", "name": "Bash", "input": {"command": "ls"}}]}}),
        "not json at all",
    ]
    chunks = chunk_transcript("\n".join(lines), source="t.jsonl")
    blob = " ".join(c["text"] for c in chunks)
    assert "починить деплой" in blob
    assert "kamal proxy host" in blob
    assert "tool_use" not in blob and "ls" not in blob


def test_empty_inputs_yield_no_chunks():
    assert chunk_markdown("   \n\n  ", source="a.md", kind="note") == []
    assert chunk_transcript("", source="t.jsonl") == []
