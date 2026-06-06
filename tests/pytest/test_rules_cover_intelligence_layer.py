"""Contract: the rules the installer ships must document the full graph
intelligence layer + session-memory, so a fresh install / upgrade provisions
them. Guards against the rules lagging behind the features (regression: the
intelligence layer existed only in a user's hand-edited ~/.claude/RULES.md and
would have been wiped on the next install, which overwrites it from rules/).

Source-of-truth files (install.sh Step 1):
  rules/RULES.md          → ~/.claude/RULES.md   (full overwrite)
  rules/CLAUDE-GLOBAL.md  → ~/.claude/CLAUDE.md  ([MEMORY-BANK-SKILL] block)
  references/claude-md-template.md → project CLAUDE.md (/mb init --full)
"""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
RULES = REPO_ROOT / "rules" / "RULES.md"
CLAUDE_GLOBAL = REPO_ROOT / "rules" / "CLAUDE-GLOBAL.md"
PROJECT_TEMPLATE = REPO_ROOT / "references" / "claude-md-template.md"


def _text(p: Path) -> str:
    return p.read_text(encoding="utf-8")


# ── rules/RULES.md — the detailed global rules ───────────────────────────

@pytest.mark.parametrize("needle", [
    "Intelligence layer",      # the subsection tying the features together
    "--questions",             # suggested questions flag
    "--cochange",              # git co-change flag
    "mb-semantic-search",      # semantic search CLI
    "/mb wiki",                # opt-in LLM wiki + surprising connections
    "/mb recall",              # session-memory lexical recall
])
def test_rules_md_documents_intelligence_layer(needle: str):
    assert needle in _text(RULES), f"rules/RULES.md is missing '{needle}'"


@pytest.mark.parametrize("edge_kind", ['"co_change"', '"semantic"'])
def test_rules_md_schema_lists_new_edge_kinds(edge_kind: str):
    # the jq Data schema block must describe the opt-in edge kinds
    assert edge_kind in _text(RULES), f"rules/RULES.md jq schema missing kind {edge_kind}"


# ── rules/CLAUDE-GLOBAL.md — the injected CLAUDE.md block ─────────────────

def test_claude_global_mentions_opt_in_layers():
    txt = _text(CLAUDE_GLOBAL)
    assert "mb-semantic-search" in txt or "/mb wiki" in txt, \
        "rules/CLAUDE-GLOBAL.md must mention the opt-in graph layers"
    assert "--questions" in txt and "--cochange" in txt, \
        "rules/CLAUDE-GLOBAL.md must mention --questions and --cochange"


def test_claude_global_mentions_session_memory_recall():
    assert "/mb recall" in _text(CLAUDE_GLOBAL), \
        "rules/CLAUDE-GLOBAL.md must point the agent at /mb recall (session memory)"


# ── references/claude-md-template.md — generated project CLAUDE.md ────────

def test_project_template_mentions_opt_in_layers():
    txt = _text(PROJECT_TEMPLATE)
    assert "mb-semantic-search" in txt or "/mb wiki" in txt, \
        "project CLAUDE.md template must mention the opt-in graph layers"
