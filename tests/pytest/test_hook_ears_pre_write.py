"""Phase 4 Sprint 1 — `hooks/mb-ears-pre-write.sh` PreToolUse Write hook."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HOOK = REPO_ROOT / "hooks" / "mb-ears-pre-write.sh"


VALID_EARS = """\
# Requirements (EARS)

- **REQ-001** (ubiquitous): The system shall persist user sessions.
- **REQ-002** (event-driven): When a user logs out, the system shall purge tokens.
"""

INVALID_EARS = """\
# Requirements (EARS)

- **REQ-001** something something — no trigger, no shall.
"""


def _run(payload: dict) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(HOOK)],
        input=json.dumps(payload),
        capture_output=True, text=True, check=False,
    )


def _payload(file_path: str, content: str, tool: str = "Write") -> dict:
    return {"tool_name": tool, "tool_input": {"file_path": file_path, "content": content}}


# ──────────────────────────────────────────────────────────────────────────


def test_valid_ears_in_requirements_passes() -> None:
    r = _run(_payload(".memory-bank/specs/foo/requirements.md", VALID_EARS))
    assert r.returncode == 0, r.stderr


def test_invalid_ears_in_requirements_blocked() -> None:
    r = _run(_payload(".memory-bank/specs/foo/requirements.md", INVALID_EARS))
    assert r.returncode == 2
    assert "ears" in (r.stderr + r.stdout).lower()


def test_valid_ears_in_context_passes() -> None:
    r = _run(_payload(".memory-bank/context/foo.md", VALID_EARS))
    assert r.returncode == 0


def test_unrelated_path_no_validation() -> None:
    r = _run(_payload("src/foo.py", VALID_EARS))
    assert r.returncode == 0


def test_non_write_tool_ignored() -> None:
    r = _run(_payload(".memory-bank/specs/foo/requirements.md", INVALID_EARS, tool="Bash"))
    assert r.returncode == 0


def test_missing_content_field_no_op() -> None:
    payload = {"tool_name": "Write", "tool_input": {"file_path": ".memory-bank/specs/foo/requirements.md"}}
    r = _run(payload)
    assert r.returncode == 0
