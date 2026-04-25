"""Phase 4 Sprint 2 — `hooks/mb-context-slim-pre-agent.sh` upgrade tests."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / "hooks" / "mb-context-slim-pre-agent.sh"


def _stage(n: int, heading: str, body: str = "- ✅ DoD\n") -> str:
    return f"<!-- mb-stage:{n} -->\n## Stage {n}: {heading}\n\n{body}\n"


def _plan_text() -> str:
    return ("---\ntype: feature\ntopic: foo\nstatus: in-progress\n---\n\n# Plan\n\n"
            + _stage(1, "first stage", "- ✅ build A\n")
            + _stage(2, "second stage", "- ⬜ build B\n"))


def _run(payload: dict, env: dict | None = None) -> subprocess.CompletedProcess[str]:
    e = os.environ.copy()
    if env:
        e.update(env)
    return subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps(payload),
        capture_output=True, text=True, env=e, check=False,
    )


def _task_payload(prompt: str) -> dict:
    return {"tool_name": "Task", "tool_input": {"description": "x", "prompt": prompt}}


# ──────────────────────────────────────────────────────────────────────────


def test_slim_mode_emits_additional_context(tmp_path: Path) -> None:
    plan = tmp_path / "p.md"
    plan.write_text(_plan_text(), encoding="utf-8")
    prompt = f"Plan: {plan}\nStage: 2\n\nfull prompt body here"
    r = _run(_task_payload(prompt), env={"MB_WORK_MODE": "slim"})
    assert r.returncode == 0, r.stderr
    # JSON output on stdout containing additionalContext
    if r.stdout.strip():
        data = json.loads(r.stdout)
        ac = data.get("hookSpecificOutput", {}).get("additionalContext", "")
        assert "second stage" in ac
        assert "build B" in ac
    else:
        # Acceptable: hook gave up gracefully and stayed advisory
        assert "slim" in r.stderr.lower()


def test_full_mode_no_op() -> None:
    r = _run(_task_payload("anything"), env={"MB_WORK_MODE": "full"})
    assert r.returncode == 0
    assert r.stdout.strip() == ""


def test_missing_prompt_field_no_op() -> None:
    payload = {"tool_name": "Task", "tool_input": {"description": "x"}}
    r = _run(payload, env={"MB_WORK_MODE": "slim"})
    assert r.returncode == 0


def test_stage_marker_not_findable_advisory_only() -> None:
    # No "Plan:" / "Stage:" hints
    r = _run(_task_payload("nothing parseable here"), env={"MB_WORK_MODE": "slim"})
    assert r.returncode == 0
    # Should not crash, may emit advisory
    assert r.stdout.strip() == "" or "additionalContext" not in r.stdout


def test_non_task_tool_ignored() -> None:
    payload = {"tool_name": "Write", "tool_input": {"file_path": "x", "content": "y"}}
    r = _run(payload, env={"MB_WORK_MODE": "slim"})
    assert r.returncode == 0
    assert r.stdout.strip() == ""
