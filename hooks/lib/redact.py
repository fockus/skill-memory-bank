"""Redact API keys and tokens from text before it is persisted to the Memory Bank.

Used by the session-capture pipeline (semantic_chunk.py) so secrets that appear
in transcripts — error messages quoting an API key, pasted env exports — never
reach .memory-bank/session/*.md chunks or the semantic index.

Keep the pattern set in sync with `sc_redact_secrets` in hooks/lib/session-common.sh
(the shell side used by mb-session-turn.sh / mb-session-end.sh). Patterns are
deliberately high-precision (vendor prefixes, fixed-length token shapes) rather
than entropy-based, to avoid mangling ordinary prose and code.
"""

from __future__ import annotations

import re

REPLACEMENT = "[REDACTED]"

# Full match is replaced.
_PLAIN_PATTERNS = [
    # OpenAI / Anthropic / OpenRouter / project keys: sk-..., sk-ant-..., sk-or-v1-...
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"),
    # GitHub tokens (classic + app) and fine-grained PATs.
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{22,}"),
    # AWS access key IDs.
    re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
    # Slack tokens.
    re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}"),
    # Google API keys.
    re.compile(r"\bAIza[A-Za-z0-9_-]{30,}"),
    # Hugging Face tokens.
    re.compile(r"\bhf_[A-Za-z0-9]{30,}"),
    # npm / PyPI publish tokens.
    re.compile(r"\bnpm_[A-Za-z0-9]{30,}"),
    re.compile(r"\bpypi-[A-Za-z0-9_-]{20,}"),
    # JWTs (three base64url segments; header always decodes from "eyJ").
    re.compile(r"\beyJ[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_=-]{10,}\.[A-Za-z0-9_.+/=-]{5,}"),
]

# Group 1 (the prefix) is kept; the token after it is replaced.
_PREFIXED_PATTERNS = [
    # Authorization: Bearer <token>
    re.compile(r"\b([Bb]earer\s+)[A-Za-z0-9._~+/=-]{20,}"),
    # KEY=value / KEY: value for secret-named (uppercase, env-style) variables.
    re.compile(
        r"\b([A-Z0-9_]*(?:API_?KEY|TOKEN|SECRET|PASSWORD|PASSWD)[A-Z0-9_]*\s*[=:]\s*)['\"]?[^\s'\"]{8,}['\"]?"
    ),
]


def redact_secrets(text: str) -> str:
    """Return *text* with recognizable API keys/tokens replaced by [REDACTED]."""
    if not text:
        return text
    for pat in _PLAIN_PATTERNS:
        text = pat.sub(REPLACEMENT, text)
    for pat in _PREFIXED_PATTERNS:
        text = pat.sub(r"\1" + REPLACEMENT, text)
    return text
