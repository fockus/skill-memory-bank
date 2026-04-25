"""Phase 4 Sprint 1 — `hooks/mb-context-slim-pre-agent.sh` PreToolUse Task hook."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / "hooks" / "mb-context-slim-pre-agent.sh"


def _run(payload: dict, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    e = os.environ.copy()
    if env:
        e.update(env)
    return subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps(payload),
        capture_output=True, text=True, env=e, check=False,
    )


def _task_payload(prompt: str = "do thing") -> dict:
    return {"tool_name": "Task", "tool_input": {"description": "x", "prompt": prompt}}


# ──────────────────────────────────────────────────────────────────────────


def test_slim_mode_emits_advisory() -> None:
    r = _run(_task_payload(), env={"MB_WORK_MODE": "slim"})
    assert r.returncode == 0
    combined = r.stdout + r.stderr
    assert "slim" in combined.lower()


def test_full_mode_no_op() -> None:
    r = _run(_task_payload(), env={"MB_WORK_MODE": "full"})
    assert r.returncode == 0
    assert r.stdout.strip() == ""
    assert r.stderr.strip() == ""


def test_unset_mode_no_op() -> None:
    e = {k: v for k, v in os.environ.items() if k != "MB_WORK_MODE"}
    r = subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps(_task_payload()),
        capture_output=True, text=True, env=e, check=False,
    )
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_non_task_tool_ignored() -> None:
    payload = {"tool_name": "Write", "tool_input": {"file_path": "x", "content": "y"}}
    r = _run(payload, env={"MB_WORK_MODE": "slim"})
    assert r.returncode == 0
    assert r.stdout.strip() == ""
