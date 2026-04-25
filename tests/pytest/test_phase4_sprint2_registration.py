"""Phase 4 Sprint 2 — registration tests."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_context_slim_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-context-slim.py").is_file()


def test_session_spend_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-session-spend.sh").is_file()


def test_sprint_context_guard_hook_present() -> None:
    assert (REPO_ROOT / "hooks" / "mb-sprint-context-guard.sh").is_file()


def test_hooks_md_mentions_sprint_context_guard() -> None:
    text = (REPO_ROOT / "references" / "hooks.md").read_text(encoding="utf-8")
    assert "mb-sprint-context-guard" in text


def test_work_command_propagates_mb_work_mode() -> None:
    text = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")
    assert "MB_WORK_MODE" in text
    assert "slim" in text


def test_context_slim_hook_references_sprint2_or_trimmer() -> None:
    text = (REPO_ROOT / "hooks" / "mb-context-slim-pre-agent.sh").read_text(encoding="utf-8")
    assert "Sprint 2" in text or "mb-context-slim.py" in text or "additionalContext" in text
