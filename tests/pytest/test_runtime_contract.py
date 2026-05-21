"""Runtime/documentation contract tests for global Claude/Codex install."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

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


# ─────────────────────────────────────────────────────────────────────────────
# Sprint 2 / Stage 4 — Codex global AGENTS.md and docs storage-modes matrix
# ─────────────────────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "rule_token",
    ["TDD", "SOLID", "Clean Architecture", "DRY", "KISS", "YAGNI"],
)
def test_codex_global_agents_md_includes_critical_rules_after_install(
    tmp_path: Path,
    rule_token: str,
) -> None:
    """Run install.sh in a sandboxed HOME and assert the generated
    ~/.codex/AGENTS.md contains the always-on engineering rules.

    Mirrors test_pi_install_embeds_guard_into_global_agents_prompt.
    """
    env = os.environ.copy()
    env["HOME"] = str(tmp_path)

    result = subprocess.run(
        ["bash", str(REPO_ROOT / "install.sh"), "--language", "en"],
        env=env,
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr
    agents_path = tmp_path / ".codex" / "AGENTS.md"
    assert agents_path.is_file(), (
        "install.sh must create ~/.codex/AGENTS.md on a fresh install"
    )
    agents = agents_path.read_text(encoding="utf-8")

    assert "<!-- memory-bank-codex:start -->" in agents
    assert "Codex loads this file at startup" in agents
    assert "~/.codex/skills/memory-bank/rules/RULES.md" in agents
    assert "`[MEMORY BANK: ABSENT]`" in agents
    assert rule_token in agents, (
        f"~/.codex/AGENTS.md must contain {rule_token!r} so the always-on "
        "engineering baseline applies even without a project Memory Bank"
    )


def test_skill_md_documents_storage_modes_matrix() -> None:
    """SKILL.md must mention --storage=local, --storage=global, and rules-only mode."""
    skill = (REPO_ROOT / "SKILL.md").read_text(encoding="utf-8")
    lower = skill.lower()

    assert "--storage=local" in skill or "--storage local" in skill, (
        "SKILL.md must document --storage=local (or --storage local) for local mode"
    )
    assert "--storage=global" in skill or "--storage global" in skill, (
        "SKILL.md must document --storage=global (or --storage global) for global mode"
    )
    assert "rules-only" in lower or (
        "[memory bank: absent]" in lower and "tdd" in lower
    ), (
        "SKILL.md must document rules-only mode "
        "([MEMORY BANK: ABSENT] + TDD still applies)"
    )


def test_readme_documents_three_storage_modes() -> None:
    """README.md must explain local mode, global mode, and rules-only mode."""
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    lower = readme.lower()

    # Local mode
    assert "/mb init" in readme, "README must mention /mb init for local mode"

    # Global mode — must mention --storage=global
    assert "--storage=global" in readme or "--storage global" in readme, (
        "README.md must document global storage mode (--storage=global)"
    )

    # Rules-only mode — must say something about no init / absent / rules still apply
    has_rules_only = (
        "rules-only" in lower
        or "[memory bank: absent]" in lower
        or ("no init" in lower and "rules" in lower)
        or ("without" in lower and "memory bank" in lower and "rules" in lower)
    )
    assert has_rules_only, (
        "README.md must describe rules-only mode: no /mb init required, "
        "engineering rules still apply"
    )


# ─────────────────────────────────────────────────────────────────────────────
# Sprint 3 / Stage 5 — Rule profiles & stack presets docs contract tests
# ─────────────────────────────────────────────────────────────────────────────


def test_commands_mb_md_lists_profile() -> None:
    """commands/mb.md must route to profile subcommand."""
    text = (REPO_ROOT / "commands" / "mb.md").read_text(encoding="utf-8")
    has_profile_route = (
        "### profile" in text
        or "profile.md" in text
        or "| `profile`" in text
        or "| profile" in text
    )
    assert has_profile_route, (
        "commands/mb.md must contain a '### profile' section or route to profile.md"
    )


def test_commands_profile_md_exists_and_references_mb_profile_sh() -> None:
    """commands/profile.md must exist and reference mb-profile.sh."""
    profile_cmd = REPO_ROOT / "commands" / "profile.md"
    assert profile_cmd.is_file(), "commands/profile.md must exist"
    text = profile_cmd.read_text(encoding="utf-8")
    assert "mb-profile.sh" in text, (
        "commands/profile.md must reference mb-profile.sh"
    )


def test_readme_documents_role_and_stack_presets() -> None:
    """README.md must mention backend/frontend/mobile roles AND go/python/typescript/javascript/java stacks."""
    readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
    lower = readme.lower()
    for role in ("backend", "frontend", "mobile"):
        assert role in lower, f"README.md must mention role preset '{role}'"
    for stack in ("go", "python", "typescript", "javascript", "java"):
        assert stack in lower, f"README.md must mention stack preset '{stack}'"


def test_rules_only_mode_docs_mention_user_global_profile() -> None:
    """docs/rule-profiles.md or README must mention user-global profile without Memory Bank."""
    candidates = [
        REPO_ROOT / "docs" / "rule-profiles.md",
        REPO_ROOT / "README.md",
    ]
    found = False
    for path in candidates:
        if not path.is_file():
            continue
        text = path.read_text(encoding="utf-8").lower()
        if "user" in text and "global" in text and (
            "without" in text or "absent" in text or "no memory bank" in text or "rules-only" in text
        ):
            found = True
            break
    assert found, (
        "docs/rule-profiles.md or README.md must document user-global profile "
        "working without a project Memory Bank"
    )


def test_docs_state_immutable_baseline_cannot_be_disabled() -> None:
    """At least one doc surface must state immutable baseline cannot be disabled."""
    candidates = [
        REPO_ROOT / "README.md",
        REPO_ROOT / "SKILL.md",
        REPO_ROOT / "docs" / "rule-profiles.md",
        REPO_ROOT / "commands" / "profile.md",
    ]
    found = False
    for path in candidates:
        if not path.is_file():
            continue
        lower = path.read_text(encoding="utf-8").lower()
        if "immutable" in lower and (
            "cannot be disabled" in lower
            or "cannot be overridden" in lower
            or "cannot be weakened" in lower
            or "non-overridable" in lower
        ):
            found = True
            break
    assert found, (
        "At least one of README/SKILL.md/docs/rule-profiles.md/commands/profile.md "
        "must explicitly state the immutable baseline cannot be disabled"
    )


def test_docs_state_json_canonical_yaml_docs_only() -> None:
    """At least one doc surface must state JSON is canonical and YAML is docs-only."""
    candidates = [
        REPO_ROOT / "README.md",
        REPO_ROOT / "SKILL.md",
        REPO_ROOT / "docs" / "rule-profiles.md",
        REPO_ROOT / "commands" / "profile.md",
    ]
    found = False
    for path in candidates:
        if not path.is_file():
            continue
        lower = path.read_text(encoding="utf-8").lower()
        if "json" in lower and (
            "canonical" in lower
            or "runtime format" in lower
        ) and ("yaml" in lower and ("docs" in lower or "documentation" in lower)):
            found = True
            break
    assert found, (
        "At least one doc surface must state JSON is canonical runtime format "
        "and YAML is for documentation only"
    )


def test_skill_md_links_rules_profile_schema_and_mb_profile_sh() -> None:
    """SKILL.md must link rules-profile.schema.md in References and list mb-profile.sh in Tools."""
    text = (REPO_ROOT / "SKILL.md").read_text(encoding="utf-8")
    assert "rules-profile.schema.md" in text, (
        "SKILL.md ## References must link references/rules-profile.schema.md"
    )
    assert "mb-profile.sh" in text, (
        "SKILL.md ## Tools table must list mb-profile.sh"
    )
