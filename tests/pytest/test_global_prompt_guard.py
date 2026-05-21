from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_claude_global_rules_define_first_response_guard_before_coding_rules() -> None:
    text = (REPO_ROOT / "rules" / "CLAUDE-GLOBAL.md").read_text(encoding="utf-8")

    guard_pos = text.index("## Mandatory first response guard")
    critical_pos = text.index("# CRITICAL RULES")

    assert guard_pos < critical_pos
    assert "This is an output-format invariant, not optional workflow advice." in text
    assert "Before any substantive response in a project directory:" in text
    assert "`[MEMORY BANK: ACTIVE]`" in text
    assert "`[MEMORY BANK: ABSENT]`" in text
    assert "`[MEMORY BANK: INITIALIZED]`" in text
    assert "Do not silently initialize Memory Bank for meta/install/debug questions." in text
    # Sprint 1 / Stage 5: wording updated to be storage-mode-agnostic. Accept either
    # the historical `./.memory-bank/` phrasing or the new "project Memory Bank" wording.
    assert (
        "Did I distinguish global skill installation from project `./.memory-bank/` activation?"
        in text
        or "Did I distinguish global skill installation from project Memory Bank activation?"
        in text
    )


def test_detailed_rules_repeat_first_response_guard() -> None:
    text = (REPO_ROOT / "rules" / "RULES.md").read_text(encoding="utf-8")

    assert "## Mandatory first response guard" in text
    assert "Before any substantive response in a project directory" in text
    assert "[MEMORY BANK: ACTIVE]" in text
    assert "[MEMORY BANK: ABSENT]" in text
    assert "Do not silently initialize Memory Bank for meta/install/debug questions." in text


def test_absent_state_does_not_disable_engineering_rules() -> None:
    """Sprint 1 / Stage 5 rules-only mode contract.

    When Memory Bank is intentionally absent in a project, the global engineering
    baseline (TDD, SOLID, Clean Architecture/FSD, DRY/KISS/YAGNI, Testing Trophy,
    protected files, no placeholders) must still apply. The guard must say so
    explicitly so agents do not skip discipline because of `ABSENT`.
    """
    for rules_file in ("CLAUDE-GLOBAL.md", "RULES.md"):
        text = (REPO_ROOT / "rules" / rules_file).read_text(encoding="utf-8")
        lower = text.lower()
        # The "rules-only" wording or an explicit ABSENT-keeps-rules clause must exist.
        assert "rules-only" in lower or "still apply" in lower or (
            "[memory bank: absent]" in lower and "tdd" in lower
        ), (
            f"rules/{rules_file} must declare that ABSENT state does not disable "
            "TDD/SOLID/Clean Architecture/DRY/KISS/YAGNI/Testing Trophy rules"
        )


def test_global_storage_wording_mentions_agent_agnostic_resolver() -> None:
    """Rules must point at agent-agnostic global storage, not only legacy .claude-workspace."""
    for rules_file in ("CLAUDE-GLOBAL.md", "RULES.md"):
        text = (REPO_ROOT / "rules" / rules_file).read_text(encoding="utf-8")
        assert (
            "--storage" in text
            or "global storage" in text.lower()
            or "agent-agnostic" in text.lower()
        ), f"rules/{rules_file} must describe agent-agnostic global storage"


def test_pi_install_embeds_guard_into_global_agents_prompt(tmp_path: Path) -> None:
    env = os.environ.copy()
    env["HOME"] = str(tmp_path)

    result = subprocess.run(
        ["bash", str(REPO_ROOT / "install.sh"), "--language", "ru"],
        env=env,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    agents = (tmp_path / ".pi" / "agent" / "AGENTS.md").read_text(encoding="utf-8")

    assert agents.startswith("<!-- memory-bank-pi:start -->")
    assert "Pi loads this file at startup and injects it into the agent prompt." in agents
    assert "## Mandatory first response guard" in agents
    assert agents.index("## Mandatory first response guard") < agents.index("# CRITICAL RULES")
    assert "`[MEMORY BANK: ABSENT]`" in agents
    assert "Do not silently initialize Memory Bank for meta/install/debug questions." in agents
    assert "**Language** — respond in Russian; technical terms may remain in English." in agents
    assert "~/.pi/agent/skills/memory-bank/rules/RULES.md" in agents
