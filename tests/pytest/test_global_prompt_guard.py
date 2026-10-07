from __future__ import annotations

import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_claude_global_rules_define_status_line_before_coding_rules() -> None:
    text = (REPO_ROOT / "rules" / "CLAUDE-GLOBAL.md").read_text(encoding="utf-8")

    guard_pos = text.index("## Memory Bank status line")
    rules_pos = text.index("# Engineering rules")

    assert guard_pos < rules_pos
    guard = text[guard_pos:rules_pos]
    assert "first reply" in guard
    assert "`[MEMORY BANK: ACTIVE]`" in guard
    assert "`[MEMORY BANK: ABSENT]`" in guard
    assert "`[MEMORY BANK: INITIALIZED]`" in guard
    assert "Do not silently initialize Memory Bank for meta/install/debug questions." in guard
    assert "A globally installed skill never means this project has a bank" in guard


def test_status_line_stays_out_of_subagent_and_machine_output() -> None:
    # Written as an "invariant ... MUST ... never omit" rule, models put the marker at the
    # top of subagent reports and of output that scripts parse.
    for rules_file in ("CLAUDE-GLOBAL.md", "RULES.md"):
        text = (REPO_ROOT / "rules" / rules_file).read_text(encoding="utf-8")
        assert "subagent reports" in text, rules_file
        assert "output-format invariant" not in text, rules_file
        assert "Before final answer, verify" not in text, rules_file
        assert "Never omit this status line" not in text, rules_file


def test_detailed_rules_carry_the_same_status_line_rule() -> None:
    text = (REPO_ROOT / "rules" / "RULES.md").read_text(encoding="utf-8")

    assert "## Memory Bank status line" in text
    assert "first reply" in text
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

    # The Key rules block (mb-rules.sh sync --scope=user) is the first section.
    assert agents.startswith("<!-- mb-key-rules:start -->")
    assert agents.index("<!-- mb-key-rules:end -->") < agents.index("<!-- memory-bank-pi:start -->")
    assert "- TDD: new logic" in agents
    claude = (tmp_path / ".claude" / "CLAUDE.md").read_text(encoding="utf-8")
    assert claude.startswith("<!-- mb-key-rules:start -->")
    assert "Details: `~/.claude/RULES.md`." in claude
    assert "Pi loads this file at startup and injects it into the agent prompt." in agents
    assert "## Memory Bank status line" in agents
    assert agents.index("## Memory Bank status line") < agents.index("# Engineering rules")
    assert "`[MEMORY BANK: ABSENT]`" in agents
    assert "Do not silently initialize Memory Bank for meta/install/debug questions." in agents
    assert "**Language** — respond in Russian; technical terms may remain in English." in agents
    assert "~/.pi/agent/skills/memory-bank/rules/RULES.md" in agents


GLOBAL_RULES = REPO_ROOT / "rules" / "CLAUDE-GLOBAL.md"


def test_claude_global_stays_within_the_always_loaded_budget() -> None:
    # Rendered into every session of every project (with or without a bank):
    # Memory Bank procedures belong to the skill, not to this block.
    lines = GLOBAL_RULES.read_text(encoding="utf-8").splitlines()
    assert len(lines) <= 60, f"rules/CLAUDE-GLOBAL.md has {len(lines)} lines > 60"


def test_claude_global_leaves_engineering_rules_to_the_key_rules_block() -> None:
    # One wording in one place: the rules live in rules/key-rules.json and are
    # rendered as the `## Key rules` block above this text at install.
    text = GLOBAL_RULES.read_text(encoding="utf-8")
    for definition in (
        "**TDD** —", "**Testing Trophy** —", "**Coverage** —", "**Contract-First** —",
        "**SOLID thresholds** —", "**Fail Fast** —", "**No placeholders** —",
        "## Testing — Testing Trophy", "## Planning", "tests FIRST",
        "Static analysis", "expand scope",
    ):
        assert definition not in text, definition
    assert "Key rules" in text and "/mb rules" in text
    assert "~/.claude/RULES.md" in text


def test_claude_global_leaves_memory_bank_procedures_to_the_skill() -> None:
    text = GLOBAL_RULES.read_text(encoding="utf-8")
    for procedure in (
        "### Session Pipeline",
        "### Codebase Map & Code Graph",
        "### Personalization, privacy, native memory",
        "### When to read the detailed rules",
    ):
        assert procedure not in text, procedure
    # The invariants that must hold before the skill loads stay, one line each.
    for invariant in ("append-only", "mb-coord.sh active", "mb-agree.sh add", "/mb context"):
        assert invariant in text, invariant
