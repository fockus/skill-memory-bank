"""Phase 3 Sprint 3 — `scripts/mb-work-review-parse.sh` reviewer output parser."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "mb-work-review-parse.sh"


def _run(stdin: str, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(SCRIPT), *args],
        input=stdin,
        capture_output=True, text=True, check=False,
    )


def _approved(issues: list | None = None) -> dict:
    return {
        "verdict": "APPROVED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": issues or [],
    }


def _changes(issues: list | None = None, counts: dict | None = None) -> dict:
    default_issues = [
        {"severity": "blocker", "category": "logic", "file": "foo.py", "line": 10, "message": "bad", "fix": "fix it"}
    ]
    return {
        "verdict": "CHANGES_REQUESTED",
        "counts": counts if counts is not None else {"blocker": 1, "major": 0, "minor": 0},
        "issues": issues if issues is not None else default_issues,
    }


# ──────────────────────────────────────────────────────────────────────────


def test_valid_approved_passes() -> None:
    r = _run(json.dumps(_approved()))
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "APPROVED"


def test_valid_changes_requested_passes() -> None:
    r = _run(json.dumps(_changes()))
    assert r.returncode == 0, r.stderr


def test_changes_requested_with_zero_issues_fails() -> None:
    bad = _changes(issues=[], counts={"blocker": 1, "major": 0, "minor": 0})
    r = _run(json.dumps(bad))
    assert r.returncode == 1
    assert "issues" in (r.stderr + r.stdout).lower()


def test_missing_verdict_fails() -> None:
    bad = {"counts": {"blocker": 0, "major": 0, "minor": 0}, "issues": []}
    r = _run(json.dumps(bad))
    assert r.returncode == 1


def test_invalid_verdict_value_fails() -> None:
    bad = _approved()
    bad["verdict"] = "MAYBE"
    r = _run(json.dumps(bad))
    assert r.returncode == 1


def test_negative_count_fails() -> None:
    bad = _approved()
    bad["counts"]["minor"] = -1
    r = _run(json.dumps(bad))
    assert r.returncode == 1


def test_issue_missing_severity_fails() -> None:
    bad = _changes(issues=[{"category": "logic", "file": "foo.py", "line": 1, "message": "x"}])
    r = _run(json.dumps(bad))
    assert r.returncode == 1


def test_invalid_severity_fails() -> None:
    bad = _changes(issues=[{"severity": "fatal", "category": "logic", "file": "foo.py", "line": 1, "message": "x"}])
    r = _run(json.dumps(bad))
    assert r.returncode == 1


def test_empty_stdin_usage_error() -> None:
    r = _run("")
    assert r.returncode == 2


def test_malformed_json_fails() -> None:
    r = _run("not valid json {{{")
    assert r.returncode == 1


def test_lenient_markdown_fallback() -> None:
    md = """Looks good!

    verdict: APPROVED
    counts: {blocker: 0, major: 0, minor: 0}
    """
    r = _run(md, "--lenient")
    assert r.returncode == 0, r.stderr
