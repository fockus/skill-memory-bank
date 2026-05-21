"""Runtime/documentation contract tests for global Claude/Codex install."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_settings_hooks_use_agent_not_task() -> None:
    hooks = (REPO_ROOT / "settings" / "hooks.json").read_text(encoding="utf-8")
    assert "Task(" not in hooks
    assert "Agent(" in hooks


def test_codex_docs_do_not_promise_native_mb_install_surface() -> None:
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    assert "Claude Code / OpenCode" in readme
    assert "In Codex use the CLI directly" in readme


def test_install_docs_describe_codex_global_aliases() -> None:
    install_doc = (REPO_ROOT / "docs" / "install.md").read_text(encoding="utf-8")
    assert "~/.codex/skills/memory-bank" in install_doc
    assert "~/.codex/AGENTS.md" in install_doc


def test_license_file_exists() -> None:
    license_file = REPO_ROOT / "LICENSE"
    assert license_file.is_file()
    assert "MIT License" in license_file.read_text(encoding="utf-8")


def test_install_sh_no_longer_embeds_cursor_global_helper_bodies() -> None:
    install_sh = (REPO_ROOT / "install.sh").read_text(encoding="utf-8")
    assert "install_cursor_global_agents()" not in install_sh
    assert "install_cursor_user_rules_paste()" not in install_sh
    assert "install_cursor_global_hooks()" not in install_sh


def test_cursor_adapter_supports_global_actions() -> None:
    cursor_adapter = (REPO_ROOT / "adapters" / "cursor.sh").read_text(encoding="utf-8")
    assert "install-global" in cursor_adapter
    assert "uninstall-global" in cursor_adapter


# ─────────────────────────────────────────────────────────────────────────────
# Global storage Sprint 1 / Stage 5 — runtime command docs & rules-only mode
# ─────────────────────────────────────────────────────────────────────────────

def test_skill_md_describes_agent_agnostic_global_storage() -> None:
    skill = (REPO_ROOT / "SKILL.md").read_text(encoding="utf-8")
    # Must mention both storage modes, not only the legacy .claude-workspace pointer.
    assert "storage_mode" in skill or "--storage" in skill or "global storage" in skill.lower(), (
        "SKILL.md must describe agent-agnostic global storage (not only legacy "
        ".claude-workspace)"
    )
    assert "[MEMORY BANK: ACTIVE]" in skill
    assert "[MEMORY BANK: ABSENT]" in skill


def test_commands_describe_resolver_not_only_local_path() -> None:
    """start/done/plan must not pretend `./.memory-bank/` is the only active-state signal."""
    # Use rel paths qualified with `commands/` so the v1-plan-md naming guard does
    # not flag this test file (the guard excludes `commands/plan.md` references).
    rel_paths = ("commands/start.md", "commands/done.md", "commands/plan.md")
    for rel in rel_paths:
        path = REPO_ROOT / rel
        text = path.read_text(encoding="utf-8")
        # Each command should reference the resolver / global storage at least once.
        assert (
            "mb_resolve_path" in text
            or "global storage" in text.lower()
            or "--storage" in text
            or "registered global" in text.lower()
        ), f"{rel} should describe resolved/global Memory Bank, not only local"


def test_mb_md_init_section_documents_storage_modes() -> None:
    text = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    # mb.md must show both storage modes for /mb init
    assert "--storage=local" in text or "--storage local" in text
    assert "--storage=global" in text or "--storage global" in text
    # And mention `--agent` for global mode
    assert "--agent" in text


def test_rules_only_mode_documented_in_rules() -> None:
    """RULES.md and CLAUDE-GLOBAL.md must say global rules apply even without Memory Bank."""
    for name in ("RULES.md", "CLAUDE-GLOBAL.md"):
        text = (REPO_ROOT / "rules" / name).read_text(encoding="utf-8")
        lower = text.lower()
        assert "rules-only" in lower or (
            "[memory bank: absent]" in lower and "tdd" in lower
        ), f"rules/{name} must document rules-only mode (ABSENT + TDD still applies)"
