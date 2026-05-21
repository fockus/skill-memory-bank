"""Cursor adapter hooks contract — full 10-hook registration with matchers."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
ADAPTER = REPO_ROOT / "adapters" / "cursor.sh"

EXPECTED_MB_OWNED = 10
PRE_TOOL_USE = 4
POST_TOOL_USE = 2


def _run_adapter(action: str, project: Path | None = None) -> subprocess.CompletedProcess[str]:
    cmd = ["bash", str(ADAPTER), action]
    if project is not None:
        cmd.append(str(project))
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def _install_project(tmp: Path) -> Path:
    r = _run_adapter("install", tmp)
    assert r.returncode == 0, r.stderr
    return tmp / ".cursor" / "hooks.json"


@pytest.fixture()
def project_dir() -> Path:
    with tempfile.TemporaryDirectory() as td:
        yield Path(td)


def test_cursor_hooks_json_has_all_events(project_dir: Path) -> None:
    hjson = _install_project(project_dir)
    data = json.loads(hjson.read_text(encoding="utf-8"))
    hooks = data["hooks"]
    for event in (
        "sessionStart",
        "sessionEnd",
        "preCompact",
        "beforeShellExecution",
        "preToolUse",
        "postToolUse",
    ):
        assert event in hooks, f"missing event {event}"


def test_cursor_pre_tool_use_has_four_entries_with_matchers(project_dir: Path) -> None:
    hjson = _install_project(project_dir)
    entries = json.loads(hjson.read_text(encoding="utf-8"))["hooks"]["preToolUse"]
    owned = [e for e in entries if e.get("_mb_owned")]
    assert len(owned) == PRE_TOOL_USE
    matchers = [e.get("matcher") for e in owned]
    assert "Write|Edit" in matchers
    assert "Write" in matchers
    assert matchers.count("Task") == 2


def test_cursor_post_tool_use_has_two_entries(project_dir: Path) -> None:
    hjson = _install_project(project_dir)
    entries = json.loads(hjson.read_text(encoding="utf-8"))["hooks"]["postToolUse"]
    owned = [e for e in entries if e.get("_mb_owned")]
    assert len(owned) == POST_TOOL_USE


def test_cursor_total_mb_owned_count(project_dir: Path) -> None:
    hjson = _install_project(project_dir)
    data = json.loads(hjson.read_text(encoding="utf-8"))
    owned = [e for ev in data["hooks"].values() for e in ev if e.get("_mb_owned")]
    assert len(owned) == EXPECTED_MB_OWNED


def test_cursor_install_idempotent_no_duplicate_mb_owned(project_dir: Path) -> None:
    _run_adapter("install", project_dir)
    _run_adapter("install", project_dir)
    data = json.loads((project_dir / ".cursor/hooks.json").read_text(encoding="utf-8"))
    owned = [e for ev in data["hooks"].values() for e in ev if e.get("_mb_owned")]
    assert len(owned) == EXPECTED_MB_OWNED


def test_cursor_manifest_lists_all_hook_events(project_dir: Path) -> None:
    _install_project(project_dir)
    manifest = json.loads((project_dir / ".cursor/.mb-manifest.json").read_text(encoding="utf-8"))
    events = set(manifest.get("hooks_events", []))
    assert events >= {
        "sessionStart",
        "sessionEnd",
        "preCompact",
        "beforeShellExecution",
        "preToolUse",
        "postToolUse",
    }


def test_cursor_manifest_tracks_all_hook_scripts(project_dir: Path) -> None:
    _install_project(project_dir)
    manifest = json.loads((project_dir / ".cursor/.mb-manifest.json").read_text(encoding="utf-8"))
    files = "\n".join(manifest.get("files", []))
    for script in (
        "session-end-autosave.sh",
        "mb-compact-reminder.sh",
        "block-dangerous.sh",
        "mb-protected-paths-guard.sh",
        "mb-ears-pre-write.sh",
        "mb-context-slim-pre-agent.sh",
        "mb-sprint-context-guard.sh",
        "file-change-log.sh",
        "mb-plan-sync-post-write.sh",
        "mb-session-start-context.sh",
    ):
        assert script in files


def test_session_start_hook_returns_empty_without_memory_bank() -> None:
    hook = REPO_ROOT / "hooks" / "mb-session-start-context.sh"
    with tempfile.TemporaryDirectory() as td:
        payload = json.dumps({"workspace_roots": [td]})
        r = subprocess.run(
            ["bash", str(hook)],
            input=payload,
            capture_output=True,
            text=True,
            check=False,
        )
    assert r.returncode == 0
    assert json.loads(r.stdout.strip()) == {}


def test_session_start_hook_returns_empty_for_invalid_json() -> None:
    hook = REPO_ROOT / "hooks" / "mb-session-start-context.sh"
    r = subprocess.run(
        ["bash", str(hook)],
        input="not-json",
        capture_output=True,
        text=True,
        check=False,
    )
    assert r.returncode == 0
    assert json.loads(r.stdout.strip()) == {}


def test_session_start_hook_injects_context_with_memory_bank() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        mb = root / ".memory-bank"
        mb.mkdir()
        (mb / "status.md").write_text("# Status\nActive work here\n", encoding="utf-8")
        (mb / "checklist.md").write_text("- [ ] unfinished task\n", encoding="utf-8")
        hook = REPO_ROOT / "hooks" / "mb-session-start-context.sh"
        payload = json.dumps({"workspace_roots": [str(root)]})
        r = subprocess.run(
            ["bash", str(hook)],
            input=payload,
            capture_output=True,
            text=True,
            check=False,
        )
        assert r.returncode == 0
        out = json.loads(r.stdout.strip())
        assert "additional_context" in out
        assert "[MEMORY BANK: ACTIVE]" in out["additional_context"]
        assert "unfinished task" in out["additional_context"]


def test_session_start_hook_caps_context() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        mb = root / ".memory-bank"
        mb.mkdir()
        (mb / "status.md").write_text("# Status\n" + "x" * 5000, encoding="utf-8")
        hook = REPO_ROOT / "hooks" / "mb-session-start-context.sh"
        payload = json.dumps({"workspace_roots": [str(root)]})
        r = subprocess.run(
            ["bash", str(hook)],
            input=payload,
            capture_output=True,
            text=True,
            check=False,
        )
        assert r.returncode == 0
        out = json.loads(r.stdout.strip())
        assert len(out["additional_context"]) <= 2500
