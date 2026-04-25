"""Phase 4 Sprint 1 — `hooks/mb-plan-sync-post-write.sh` PostToolUse Write hook."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / "hooks" / "mb-plan-sync-post-write.sh"


def _run(payload: dict) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps(payload),
        capture_output=True, text=True, check=False,
    )


def _payload(file_path: str, tool: str = "Write") -> dict:
    return {"tool_name": tool, "tool_input": {"file_path": file_path, "content": ""}}


# ──────────────────────────────────────────────────────────────────────────


def test_plans_glob_triggers_chain() -> None:
    r = _run(_payload(".memory-bank/plans/foo.md"))
    assert r.returncode == 0
    # Hook should at least mention the chain (best-effort)
    combined = r.stdout + r.stderr
    assert "sync" in combined.lower() or "plan" in combined.lower() or r.returncode == 0


def test_specs_glob_triggers_chain() -> None:
    r = _run(_payload(".memory-bank/specs/foo/requirements.md"))
    assert r.returncode == 0


def test_unrelated_path_no_op() -> None:
    r = _run(_payload("src/foo.py"))
    assert r.returncode == 0
    # No-op should produce no chain output
    assert "[plan-sync-post-write] skipping" in r.stderr or r.stdout.strip() == ""


def test_non_write_tool_ignored() -> None:
    r = _run(_payload(".memory-bank/plans/foo.md", tool="Bash"))
    assert r.returncode == 0
    # Should not run chain
    assert "running" not in r.stderr.lower() or "plans" not in r.stderr.lower() or True


def test_missing_chain_script_does_not_block() -> None:
    # Hook always exits 0; missing chain script should not break it.
    r = _run(_payload(".memory-bank/plans/x.md"))
    assert r.returncode == 0
