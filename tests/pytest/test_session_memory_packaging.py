"""Contract: the session-memory subsystem must actually ship + auto-register on
install, so a fresh clone/install gets cross-chat memory out of the box.

Regression guard: the four session hooks + their lib/ helpers were untracked WIP,
install.sh copied hooks/*.sh by a flat glob (no lib/), and hooks.json had no
SessionStart event nor session entries — so a fresh install got nothing.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOKS_JSON = REPO_ROOT / "settings" / "hooks.json"
INSTALL_SH = REPO_ROOT / "install.sh"

SESSION_HOOKS = [
    "hooks/mb-session-turn.sh",
    "hooks/mb-session-end.sh",
    "hooks/mb-session-start.sh",
    "hooks/mb-recall.sh",
    "hooks/lib/session-common.sh",
    "hooks/lib/extract-tools-files.sh",
]


def _tracked_files() -> set[str]:
    out = subprocess.run(
        ["git", "-C", str(REPO_ROOT), "ls-files"],
        capture_output=True, text=True, check=True,
    ).stdout
    return set(out.splitlines())


@pytest.mark.parametrize("path", SESSION_HOOKS)
def test_session_hook_is_git_tracked(path: str) -> None:
    assert path in _tracked_files(), f"{path} must be git-tracked (a clone needs it)"


def _all_commands() -> list[str]:
    data = json.loads(HOOKS_JSON.read_text(encoding="utf-8"))
    cmds: list[str] = []
    for entries in data.values():
        for entry in entries:
            for hook in entry.get("hooks", []):
                cmds.append(hook.get("command", ""))
    return cmds


@pytest.mark.parametrize("hook", [
    "mb-session-turn.sh",
    "mb-session-end.sh",
    "mb-session-start.sh",
])
def test_hooks_json_registers_session_hook(hook: str) -> None:
    cmds = _all_commands()
    matching = [c for c in cmds if hook in c]
    assert matching, f"settings/hooks.json must register {hook}"
    for c in matching:
        assert "[memory-bank-skill]" in c, f"{hook} missing marker: {c}"


def test_hooks_json_has_session_start_event() -> None:
    data = json.loads(HOOKS_JSON.read_text(encoding="utf-8"))
    assert "SessionStart" in data, "hooks.json must define a SessionStart event"


def test_install_sh_installs_hook_lib_dir() -> None:
    # install.sh must copy hooks/lib/ so $HOOK_DIR/lib/session-common.sh resolves
    # for the copied-path hooks (e.g. ~/.claude/hooks/mb-recall.sh).
    assert "hooks/lib" in INSTALL_SH.read_text(encoding="utf-8"), \
        "install.sh must install hooks/lib/ alongside the hooks"
