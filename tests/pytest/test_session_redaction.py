"""Secret redaction in session capture — hooks/lib/redact.py + semantic_chunk integration.

Regression for the real-world leak: a session transcript contained an OpenRouter
API key in an error message; the Haiku summary stored it verbatim in
.memory-bank/session/*.md and the semantic index chunked it. Session capture
must redact API keys/tokens by default before anything reaches disk.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "hooks" / "lib"))

from redact import redact_secrets  # noqa: E402
from semantic_chunk import chunk_markdown, chunk_transcript  # noqa: E402

OPENROUTER_KEY = "sk-or-v1-" + "a1b2c3d4" * 8
ANTHROPIC_KEY = "sk-ant-api03-" + "x" * 40
OPENAI_KEY = "sk-proj-" + "Z9" * 24
GITHUB_PAT = "ghp_" + "A" * 36
GITHUB_FINE_PAT = "github_pat_" + "B" * 22 + "_" + "c" * 30
AWS_KEY = "AKIAIOSFODNN7EXAMPLE"
SLACK_TOKEN = "xoxb-1234567890-abcdefghijklm"
GOOGLE_KEY = "AIza" + "S" * 35
HF_TOKEN = "hf_" + "k" * 34
JWT = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.SflKxwRJSMeKKF2QT4fwpM"


@pytest.mark.parametrize(
    "secret",
    [
        OPENROUTER_KEY,
        ANTHROPIC_KEY,
        OPENAI_KEY,
        GITHUB_PAT,
        GITHUB_FINE_PAT,
        AWS_KEY,
        SLACK_TOKEN,
        GOOGLE_KEY,
        HF_TOKEN,
        JWT,
    ],
    ids=[
        "openrouter",
        "anthropic",
        "openai",
        "github-pat",
        "github-fine-pat",
        "aws-akia",
        "slack-xoxb",
        "google-aiza",
        "huggingface",
        "jwt",
    ],
)
def test_redact_secrets_removes_known_token_shapes(secret: str) -> None:
    text = f"Authentication failed for key {secret} — check your account."
    out = redact_secrets(text)
    assert secret not in out
    assert "[REDACTED]" in out
    # Surrounding prose survives.
    assert "Authentication failed" in out and "check your account." in out


def test_redact_secrets_keeps_bearer_prefix_but_hides_token() -> None:
    out = redact_secrets("curl -H 'Authorization: Bearer abcdef1234567890abcdef1234567890'")
    assert "Bearer [REDACTED]" in out
    assert "abcdef1234567890" not in out


def test_redact_secrets_keeps_env_var_name_but_hides_value() -> None:
    out = redact_secrets("export OPENROUTER_API_KEY=sk-or-v1-deadbeefdeadbeefdeadbeef")
    assert "OPENROUTER_API_KEY=" in out
    assert "deadbeef" not in out
    out2 = redact_secrets("MY_SECRET: supersecretvalue123")
    assert "MY_SECRET" in out2
    assert "supersecretvalue123" not in out2


@pytest.mark.parametrize(
    "benign",
    [
        "the skill-memory-bank repo uses tasks-and-plans",  # sk- inside words, short
        "run /mb work my-feature --review",
        "see docs/first-feature.md and roadmap.md for details",
        "PASSWORD policy requires 12 chars",  # var name without assignment
        "the token economy of the graph is great",  # word 'token' in prose
        "git push origin main",
    ],
)
def test_redact_secrets_leaves_benign_text_untouched(benign: str) -> None:
    assert redact_secrets(benign) == benign


def test_redact_secrets_handles_empty_and_multiline() -> None:
    assert redact_secrets("") == ""
    text = f"line one\nkey: {OPENROUTER_KEY}\nline three"
    out = redact_secrets(text)
    assert OPENROUTER_KEY not in out
    assert out.splitlines()[0] == "line one"
    assert out.splitlines()[2] == "line three"


# ── semantic_chunk integration ───────────────────────────────────────────────


def test_chunk_markdown_redacts_secrets_in_body() -> None:
    md = f"---\nsession_id: abc\n---\n\n## Summary\nThe agent hit an auth error: {OPENROUTER_KEY} was rejected.\n"
    chunks = chunk_markdown(md, source="session/x.md", kind="session")
    joined = "\n".join(c["text"] for c in chunks)
    assert OPENROUTER_KEY not in joined
    assert "[REDACTED]" in joined


def test_chunk_markdown_strips_private_blocks() -> None:
    md = (
        "intro paragraph\n\n<private>my plaintext password hunter2-hunter2</private>\n\npublic tail"
    )
    chunks = chunk_markdown(md, source="notes/x.md", kind="note")
    joined = "\n".join(c["text"] for c in chunks)
    assert "hunter2" not in joined
    assert "intro paragraph" in joined and "public tail" in joined


def test_chunk_markdown_strips_unclosed_private_block_to_eof() -> None:
    md = "public head\n\n<private>secret tail without closing tag"
    chunks = chunk_markdown(md, source="notes/y.md", kind="note")
    joined = "\n".join(c["text"] for c in chunks)
    assert "secret tail" not in joined
    assert "public head" in joined


def test_chunk_transcript_redacts_secrets() -> None:
    import json

    lines = [
        json.dumps(
            {"type": "user", "message": {"role": "user", "content": f"my key is {GITHUB_PAT}"}}
        ),
        json.dumps(
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": f"Error: {ANTHROPIC_KEY} is invalid"}],
                },
            }
        ),
    ]
    chunks = chunk_transcript("\n".join(lines), source="t.jsonl")
    joined = "\n".join(c["text"] for c in chunks)
    assert GITHUB_PAT not in joined
    assert ANTHROPIC_KEY not in joined
    assert "[REDACTED]" in joined
