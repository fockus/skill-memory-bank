"""Phase 4 Sprint 2 — `hooks/mb-sprint-context-guard.sh` runtime token watcher."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / "hooks" / "mb-sprint-context-guard.sh"
SPEND_SH = REPO_ROOT / "scripts" / "mb-session-spend.sh"


def _init_mb(tmp_path: Path) -> Path:
    mb = tmp_path / ".memory-bank"
    mb.mkdir()
    return mb


def _spend(*args: str, mb: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SPEND_SH), *args, "--mb", str(mb)],
        capture_output=True, text=True, check=False,
    )


def _run(payload: dict, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    e = os.environ.copy()
    if env:
        e.update(env)
    return subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps(payload),
        capture_output=True, text=True, env=e, check=False,
    )


def _task(prompt: str = "do thing") -> dict:
    return {"tool_name": "Task", "tool_input": {"description": "x", "prompt": prompt}}


# ──────────────────────────────────────────────────────────────────────────


def test_below_threshold_passes(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _spend("init", "--soft", "1000000", "--hard", "2000000", mb=mb)
    r = _run(_task(prompt="small"), env={"MB_SESSION_BANK": str(mb)})
    assert r.returncode == 0


def test_hard_threshold_blocks(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _spend("init", "--soft", "100", "--hard", "200", mb=mb)
    # 1000 chars * 1 invocation == 250 tokens, above 200 hard
    r = _run(_task(prompt="x" * 1000), env={"MB_SESSION_BANK": str(mb)})
    assert r.returncode == 2


def test_soft_threshold_warns(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _spend("init", "--soft", "100", "--hard", "10000", mb=mb)
    # 1000 chars => 250 tokens, above 100 soft, below 10000 hard
    r = _run(_task(prompt="x" * 1000), env={"MB_SESSION_BANK": str(mb)})
    assert r.returncode == 0
    assert "warn" in r.stderr.lower() or "soft" in r.stderr.lower()


def test_non_task_tool_ignored(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    _spend("init", "--soft", "100", "--hard", "200", mb=mb)
    payload = {"tool_name": "Write", "tool_input": {"file_path": "x", "content": "y" * 10000}}
    r = _run(payload, env={"MB_SESSION_BANK": str(mb)})
    assert r.returncode == 0


def test_no_state_file_lazy_inits(tmp_path: Path) -> None:
    mb = _init_mb(tmp_path)
    # Don't init — hook should lazy-init or fail open
    r = _run(_task(prompt="small"), env={"MB_SESSION_BANK": str(mb)})
    assert r.returncode == 0
