"""Always-loaded instruction files of this repo stay inside their host limits.

Codex reads project AGENTS.md up to `project_doc_max_bytes` and silently drops the
rest; the repo's `.codex/config.toml` raises it to 65536, but the file must fit the
default so a user without that override still sees the whole thing.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

# Codex default `project_doc_max_bytes = 32768` (32 KiB):
# https://github.com/openai/codex/blob/main/codex-rs/config/defaults.toml
# https://developers.openai.com/codex/guides/agents-md ("32 KiB by default")
CODEX_PROJECT_DOC_MAX_BYTES = 32 * 1024
CLAUDE_MD_MAX_LINES = 200
CLAUDE_MD_MAX_BYTES = 10 * 1024


def test_agents_md_fits_codex_default_project_doc_limit() -> None:
    agents = REPO_ROOT / "AGENTS.md"
    if not agents.is_file():  # gitignored, rendered by the adapters
        pytest.skip("AGENTS.md is not rendered in this checkout")
    assert agents.stat().st_size <= CODEX_PROJECT_DOC_MAX_BYTES


def test_claude_md_stays_within_line_and_byte_budget() -> None:
    claude = REPO_ROOT / "CLAUDE.md"
    assert len(claude.read_text(encoding="utf-8").splitlines()) <= CLAUDE_MD_MAX_LINES
    assert claude.stat().st_size <= CLAUDE_MD_MAX_BYTES
