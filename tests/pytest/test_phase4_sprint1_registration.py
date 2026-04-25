"""Phase 4 Sprint 1 — registration tests for 4 critical hooks."""

from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]


HOOKS = (
    "mb-protected-paths-guard.sh",
    "mb-plan-sync-post-write.sh",
    "mb-ears-pre-write.sh",
    "mb-context-slim-pre-agent.sh",
)


@pytest.mark.parametrize("hook", HOOKS)
def test_hook_file_exists(hook: str) -> None:
    p = REPO_ROOT / "hooks" / hook
    assert p.is_file(), f"missing hooks/{hook}"


@pytest.mark.parametrize("hook", HOOKS)
def test_hook_executable_shebang(hook: str) -> None:
    text = (REPO_ROOT / "hooks" / hook).read_text(encoding="utf-8")
    assert text.startswith("#!"), f"{hook}: missing shebang"


def test_hooks_doc_exists() -> None:
    assert (REPO_ROOT / "references" / "hooks.md").is_file()


@pytest.mark.parametrize("hook", HOOKS)
def test_hooks_doc_mentions_each_hook(hook: str) -> None:
    text = (REPO_ROOT / "references" / "hooks.md").read_text(encoding="utf-8")
    assert hook in text, f"references/hooks.md must mention {hook}"


def test_hooks_doc_has_settings_json_example() -> None:
    text = (REPO_ROOT / "references" / "hooks.md").read_text(encoding="utf-8")
    assert "settings.json" in text or "PreToolUse" in text
