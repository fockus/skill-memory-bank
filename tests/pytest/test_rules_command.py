"""`/mb rules` command surface (plan key-rules-onboarding, Stage 4)."""

from __future__ import annotations

from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
RULES_CMD = REPO / "commands" / "rules.md"


def _frontmatter(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8").split("---\n", 2)[1]) or {}


def test_rules_command_frontmatter_states_what_and_when() -> None:
    desc = _frontmatter(RULES_CMD)["description"]
    assert "use when" in desc.lower()
    assert "key rules" in desc.lower()


def test_rules_command_documents_every_subcommand_and_scope() -> None:
    text = RULES_CMD.read_text(encoding="utf-8")
    for sub in ("list", "enable", "disable", "add", "remove", "init", "sync", "--scope=user", "--scope=project"):
        assert f"`{sub}" in text or f" {sub}" in text, sub
    assert "mb-rules.sh" in text
    # Agent onboarding: catalog as a multiSelect question + free-text own rules.
    assert "AskUserQuestion" in text and "multiSelect" in text


def test_mb_router_routes_rules() -> None:
    text = (REPO / "commands" / "mb.md").read_text(encoding="utf-8")
    assert "| `rules <subcommand>`" in text
    assert "commands/rules.md" in text


def test_rules_command_documents_set_keys_and_quality_onboarding() -> None:
    text = RULES_CMD.read_text(encoding="utf-8")
    for key in ("set architecture", "set tdd", "set trophy", "set coverage", "set principle", "set discipline"):
        assert key in text, key
    assert "mb-project-rules" in text
    # init onboarding asks the quality settings too.
    for word in ("Architecture", "TDD", "Trophy", "Coverage"):
        assert word in text.split("## `init`", 1)[1], word
