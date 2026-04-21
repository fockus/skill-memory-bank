"""Tests for settings/merge-hooks.py.

Contract:
    merge_hooks(settings_path, hooks_path) merges skill hooks into an
    existing Claude Code settings.json without overwriting user hooks.
    Must be idempotent — running it N times yields the same result.
"""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
MERGE_SCRIPT = REPO_ROOT / "settings" / "merge-hooks.py"
HOOKS_JSON = REPO_ROOT / "settings" / "hooks.json"


def _load_merge_module():
    """Import merge-hooks.py (dashed filename) as a module for coverage."""
    spec = importlib.util.spec_from_file_location("merge_hooks", MERGE_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="module")
def merge_mod():
    return _load_merge_module()


@pytest.fixture
def tmp_settings(tmp_path: Path) -> Path:
    return tmp_path / "settings.json"


@pytest.fixture
def tmp_hooks_minimal(tmp_path: Path) -> Path:
    """Small synthetic hooks file — keeps tests focused and fast."""
    hooks = {
        "PreToolUse": [
            {
                "matcher": "Bash",
                "hooks": [
                    {
                        "type": "command",
                        "command": "~/.claude/hooks/block-dangerous.sh # [memory-bank-skill]",
                    }
                ],
            }
        ],
        "Stop": [
            {
                "hooks": [
                    {
                        "type": "command",
                        "command": "echo '[MB] done' # [memory-bank-skill]",
                    }
                ]
            }
        ],
    }
    path = tmp_path / "hooks.json"
    path.write_text(json.dumps(hooks))
    return path


def run_merge(settings: Path, hooks: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(MERGE_SCRIPT), str(settings), str(hooks)],
        capture_output=True,
        text=True,
        check=False,
    )


# ═══════════════════════════════════════════════════════════════
# Basic behaviour
# ═══════════════════════════════════════════════════════════════


def test_creates_settings_when_missing(tmp_settings, tmp_hooks_minimal):
    """If settings.json does not exist, it is created with skill hooks."""
    assert not tmp_settings.exists()
    result = run_merge(tmp_settings, tmp_hooks_minimal)
    assert result.returncode == 0, result.stderr
    assert tmp_settings.exists()

    data = json.loads(tmp_settings.read_text())
    assert "hooks" in data
    assert "PreToolUse" in data["hooks"]
    assert "Stop" in data["hooks"]


def test_preserves_existing_unrelated_settings(tmp_settings, tmp_hooks_minimal):
    """Non-hooks fields (model, theme, etc.) survive the merge untouched."""
    tmp_settings.write_text(
        json.dumps(
            {
                "model": "claude-opus-4-7",
                "theme": "dark",
                "hooks": {},
            }
        )
    )
    run_merge(tmp_settings, tmp_hooks_minimal)

    data = json.loads(tmp_settings.read_text())
    assert data["model"] == "claude-opus-4-7"
    assert data["theme"] == "dark"


def test_preserves_existing_user_hooks(tmp_settings, tmp_hooks_minimal):
    """Existing user hooks under the same event MUST NOT be dropped."""
    user_hook = {
        "matcher": "Edit",
        "hooks": [
            {
                "type": "command",
                "command": "echo 'user custom hook'",
            }
        ],
    }
    tmp_settings.write_text(
        json.dumps({"hooks": {"PreToolUse": [user_hook]}})
    )

    run_merge(tmp_settings, tmp_hooks_minimal)

    data = json.loads(tmp_settings.read_text())
    pre = data["hooks"]["PreToolUse"]
    # User hook kept + skill hook appended
    assert len(pre) >= 2
    assert any(
        entry.get("matcher") == "Edit"
        and any("user custom hook" in h["command"] for h in entry["hooks"])
        for entry in pre
    )


# ═══════════════════════════════════════════════════════════════
# Idempotency
# ═══════════════════════════════════════════════════════════════


def test_idempotent_two_runs(tmp_settings, tmp_hooks_minimal):
    """Two consecutive runs produce identical settings.json."""
    run_merge(tmp_settings, tmp_hooks_minimal)
    first = tmp_settings.read_text()

    run_merge(tmp_settings, tmp_hooks_minimal)
    second = tmp_settings.read_text()

    assert first == second


def test_idempotent_many_runs(tmp_settings, tmp_hooks_minimal):
    """5× runs still yield one copy of each hook."""
    for _ in range(5):
        run_merge(tmp_settings, tmp_hooks_minimal)

    data = json.loads(tmp_settings.read_text())
    pre = data["hooks"]["PreToolUse"]
    # Exactly one Bash block-dangerous entry
    cmds = [
        h["command"]
        for entry in pre
        for h in entry.get("hooks", [])
        if "block-dangerous" in h.get("command", "")
    ]
    assert len(cmds) == 1


# ═══════════════════════════════════════════════════════════════
# Deduplication
# ═══════════════════════════════════════════════════════════════


def test_deduplication_same_command(tmp_settings, tmp_hooks_minimal):
    """If the exact same skill hook already exists, it is not duplicated."""
    # Pre-populate with the same command
    tmp_settings.write_text(
        json.dumps(
            {
                "hooks": {
                    "PreToolUse": [
                        {
                            "matcher": "Bash",
                            "hooks": [
                                {
                                    "type": "command",
                                    "command": "~/.claude/hooks/block-dangerous.sh # [memory-bank-skill]",
                                }
                            ],
                        }
                    ]
                }
            }
        )
    )

    run_merge(tmp_settings, tmp_hooks_minimal)

    data = json.loads(tmp_settings.read_text())
    block_cmds = [
        h["command"]
        for entry in data["hooks"]["PreToolUse"]
        for h in entry.get("hooks", [])
        if "block-dangerous" in h.get("command", "")
    ]
    assert len(block_cmds) == 1


# ═══════════════════════════════════════════════════════════════
# Edge cases
# ═══════════════════════════════════════════════════════════════


def test_empty_settings_json(tmp_settings, tmp_hooks_minimal):
    """settings.json = '{}' is handled and hooks are added."""
    tmp_settings.write_text("{}")

    result = run_merge(tmp_settings, tmp_hooks_minimal)
    assert result.returncode == 0

    data = json.loads(tmp_settings.read_text())
    assert "hooks" in data
    assert "PreToolUse" in data["hooks"]


def test_settings_with_non_ascii(tmp_settings, tmp_hooks_minimal):
    """UTF-8 content in existing settings survives the merge (ensure_ascii=False)."""
    tmp_settings.write_text(
        json.dumps({"note": "Hello from settings", "hooks": {}}, ensure_ascii=False),
        encoding="utf-8",
    )

    run_merge(tmp_settings, tmp_hooks_minimal)

    text = tmp_settings.read_text(encoding="utf-8")
    assert "Hello" in text


def test_corrupted_settings_json_is_rejected(tmp_settings, tmp_hooks_minimal):
    """Corrupted settings.json causes non-zero exit — does NOT silently clobber."""
    tmp_settings.write_text("{not valid json")

    result = run_merge(tmp_settings, tmp_hooks_minimal)
    # Merge must fail loudly, not silently overwrite content.
    assert result.returncode != 0


def test_real_hooks_json_integration(tmp_settings):
    """Integration: merge the actual shipped hooks.json."""
    result = run_merge(tmp_settings, HOOKS_JSON)
    assert result.returncode == 0, result.stderr

    data = json.loads(tmp_settings.read_text())
    hooks = data["hooks"]
    # All top-level events from the real file present
    for event in ("Setup", "PreToolUse", "PostToolUse", "Notification", "PreCompact", "Stop"):
        assert event in hooks, f"Missing event {event}"


def test_atomic_write_leaves_no_temp_files(tmp_settings, tmp_hooks_minimal):
    """After a successful merge, no *.tmp files remain next to settings.json."""
    run_merge(tmp_settings, tmp_hooks_minimal)

    parent = tmp_settings.parent
    leftover = list(parent.glob("*.tmp"))
    assert leftover == []


# ═══════════════════════════════════════════════════════════════
# CLI / usage
# ═══════════════════════════════════════════════════════════════


def test_usage_error_on_missing_args():
    """Calling without args → non-zero exit, usage message."""
    result = subprocess.run(
        [sys.executable, str(MERGE_SCRIPT)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode != 0
    combined = result.stdout + result.stderr
    assert "Usage" in combined or "usage" in combined


# ═══════════════════════════════════════════════════════════════
# Direct function calls — drive coverage through the module itself,
# not only the subprocess CLI path.
# ═══════════════════════════════════════════════════════════════


def test_direct_call_creates_settings(merge_mod, tmp_settings, tmp_hooks_minimal):
    merge_mod.merge_hooks(str(tmp_settings), str(tmp_hooks_minimal))
    data = json.loads(tmp_settings.read_text())
    assert "PreToolUse" in data["hooks"]


def test_direct_call_merges_into_existing_event(
    merge_mod, tmp_settings, tmp_hooks_minimal
):
    """User has a hook under Stop — skill hook is appended, user hook stays."""
    tmp_settings.write_text(
        json.dumps(
            {
                "hooks": {
                    "Stop": [
                        {"hooks": [{"type": "command", "command": "echo user-stop"}]}
                    ]
                }
            }
        )
    )
    merge_mod.merge_hooks(str(tmp_settings), str(tmp_hooks_minimal))

    stop = json.loads(tmp_settings.read_text())["hooks"]["Stop"]
    cmds = [h["command"] for entry in stop for h in entry.get("hooks", [])]
    assert "echo user-stop" in cmds
    assert any("[MB] done" in c for c in cmds)


def test_direct_call_rejects_corrupted(merge_mod, tmp_settings, tmp_hooks_minimal):
    tmp_settings.write_text("{not json")
    with pytest.raises(json.JSONDecodeError):
        merge_mod.merge_hooks(str(tmp_settings), str(tmp_hooks_minimal))


def test_direct_call_string_entries_ignored(merge_mod, tmp_settings, tmp_path):
    """Non-dict entries in hooks array must not crash dedup logic."""
    weird_hooks = {
        "PreToolUse": ["string-entry", {"hooks": [{"type": "command", "command": "ok"}]}]
    }
    tmp_settings.write_text(
        json.dumps(
            {
                "hooks": {
                    "PreToolUse": ["legacy-string", {"hooks": []}]
                }
            }
        )
    )
    hooks_file = tmp_path / "weird.json"
    hooks_file.write_text(json.dumps(weird_hooks))

    merge_mod.merge_hooks(str(tmp_settings), str(hooks_file))
    data = json.loads(tmp_settings.read_text())
    cmds = [
        h.get("command")
        for entry in data["hooks"]["PreToolUse"]
        if isinstance(entry, dict)
        for h in entry.get("hooks", [])
        if isinstance(h, dict)
    ]
    assert "ok" in cmds
