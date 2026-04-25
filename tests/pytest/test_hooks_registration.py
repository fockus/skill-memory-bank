"""Phase 4 Sprint 3 — settings/hooks.json contains 5 v2 hooks for auto-install."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOKS_JSON = REPO_ROOT / "settings" / "hooks.json"
MERGE_PY = REPO_ROOT / "settings" / "merge-hooks.py"


def _load_hooks() -> dict:
    return json.loads(HOOKS_JSON.read_text(encoding="utf-8"))


def _all_commands(data: dict) -> list[str]:
    cmds = []
    for event_entries in data.get("hooks", data).values() if isinstance(data, dict) else []:
        if not isinstance(event_entries, list):
            continue
        for entry in event_entries:
            for hook in entry.get("hooks", []):
                cmds.append(hook.get("command", ""))
    return cmds


def test_hooks_json_contains_protected_paths_guard() -> None:
    data = _load_hooks()
    cmds = _all_commands(data)
    assert any("mb-protected-paths-guard.sh" in c for c in cmds), cmds


def test_hooks_json_contains_plan_sync_post_write() -> None:
    cmds = _all_commands(_load_hooks())
    assert any("mb-plan-sync-post-write.sh" in c for c in cmds), cmds


def test_hooks_json_contains_ears_pre_write() -> None:
    cmds = _all_commands(_load_hooks())
    assert any("mb-ears-pre-write.sh" in c for c in cmds), cmds


def test_hooks_json_contains_context_slim_pre_agent() -> None:
    cmds = _all_commands(_load_hooks())
    assert any("mb-context-slim-pre-agent.sh" in c for c in cmds), cmds


def test_hooks_json_contains_sprint_context_guard() -> None:
    cmds = _all_commands(_load_hooks())
    assert any("mb-sprint-context-guard.sh" in c for c in cmds), cmds


def test_all_v2_hooks_have_marker() -> None:
    cmds = _all_commands(_load_hooks())
    v2 = [c for c in cmds if "/hooks/mb-" in c and ".sh" in c]
    # Every v2 hook command must carry the `[memory-bank-skill]` marker so
    # `merge-hooks.py` can strip it on uninstall.
    assert len(v2) >= 5, f"expected ≥5 v2 hook commands, got {v2}"
    for c in v2:
        assert "[memory-bank-skill]" in c, f"missing marker: {c}"


def test_merge_hooks_idempotent_with_v2_entries() -> None:
    """Running merge-hooks.py twice produces an identical settings.json."""
    with tempfile.TemporaryDirectory() as td:
        settings = Path(td) / "settings.json"
        settings.write_text("{}", encoding="utf-8")

        for _ in range(2):
            r = subprocess.run(
                ["python3", str(MERGE_PY), str(settings), str(HOOKS_JSON)],
                capture_output=True, text=True, check=False,
            )
            assert r.returncode == 0, r.stderr

        final = json.loads(settings.read_text(encoding="utf-8"))
        cmds_after = _all_commands(final)
        v2_after = [c for c in cmds_after if "/hooks/mb-" in c and ".sh" in c]
        # Each v2 hook present exactly once after the second merge.
        for marker in [
            "mb-protected-paths-guard.sh",
            "mb-plan-sync-post-write.sh",
            "mb-ears-pre-write.sh",
            "mb-context-slim-pre-agent.sh",
            "mb-sprint-context-guard.sh",
        ]:
            count = sum(marker in c for c in v2_after)
            assert count == 1, f"{marker} appeared {count}× after idempotent merge"
