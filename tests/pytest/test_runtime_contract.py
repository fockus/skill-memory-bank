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
