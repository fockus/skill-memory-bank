"""Phase 4 Sprint 1 — `hooks/mb-protected-paths-guard.sh` PreToolUse Write/Edit guard."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / "hooks" / "mb-protected-paths-guard.sh"


def _run(payload: dict, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    e = os.environ.copy()
    if env:
        e.update(env)
    return subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps(payload),
        capture_output=True, text=True, env=e, check=False,
    )


def _write_payload(file_path: str, tool: str = "Write") -> dict:
    return {"tool_name": tool, "tool_input": {"file_path": file_path, "content": ""}}


# ──────────────────────────────────────────────────────────────────────────


def test_unprotected_file_passes() -> None:
    r = _run(_write_payload("src/foo.py"))
    assert r.returncode == 0


def test_dotenv_blocked() -> None:
    r = _run(_write_payload(".env.production"))
    assert r.returncode == 2
    assert ".env" in r.stderr or "protected" in r.stderr.lower()


def test_ci_glob_blocked() -> None:
    r = _run(_write_payload("ci/build.yaml"))
    assert r.returncode == 2


def test_allow_protected_env_bypass() -> None:
    r = _run(_write_payload(".env.production"), env={"MB_ALLOW_PROTECTED": "1"})
    assert r.returncode == 0


def test_missing_file_path_passes() -> None:
    r = _run({"tool_name": "Write", "tool_input": {"content": "hi"}})
    assert r.returncode == 0


def test_other_tool_ignored() -> None:
    r = _run(_write_payload(".env", tool="Bash"))
    assert r.returncode == 0
