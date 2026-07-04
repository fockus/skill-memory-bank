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
        capture_output=True,
        text=True,
        check=False,
    )


def _approved(issues: list | None = None) -> dict:
    return {
        "verdict": "APPROVED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": issues or [],
    }


def _changes(issues: list | None = None, counts: dict | None = None) -> dict:
    default_issues = [
        {
            "severity": "blocker",
            "category": "logic",
            "file": "foo.py",
            "line": 10,
            "message": "bad",
            "fix": "fix it",
        }
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
    bad = _changes(
        issues=[
            {"severity": "fatal", "category": "logic", "file": "foo.py", "line": 1, "message": "x"}
        ]
    )
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


# ── --external (cross-model reviewer normalization, Этап 6) ────────────────


def test_external_approved_with_issues_normalizes_to_changes() -> None:
    payload = {
        "status": "OK",
        "verdict": "APPROVED",
        "issues": [
            {"severity": "minor", "file": "foo.py", "line": 3, "message": "nit: rename var"}
        ],
        "counts": {"blocker": 0, "major": 0, "minor": 0, "info": 0},
    }
    r = _run(json.dumps(payload), "--external")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "CHANGES_REQUESTED"
    assert out["counts"]["minor"] == 1


def test_external_maps_codex_schema() -> None:
    payload = {
        "status": "OK",
        "verdict": "CHANGES_REQUESTED",
        "issues": [
            {
                "severity": "info",
                "file": "src/x.py",
                "line": None,
                "description": "should rename",
                "recommendation": "rename to foo",
            }
        ],
        "counts": {"blocker": 0, "major": 0, "minor": 0, "info": 1},
    }
    r = _run(json.dumps(payload), "--external")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    issue = out["issues"][0]
    assert issue["message"] == "should rename"
    assert issue["fix"] == "rename to foo"
    assert issue["line"] == 0
    assert issue["severity"] == "minor"


def test_external_skipped_passthrough() -> None:
    payload = {"status": "SKIPPED", "reason": "codex CLI 403 auth"}
    r = _run(json.dumps(payload), "--external")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "SKIPPED"
    assert out["reason"] == "codex CLI 403 auth"
    assert out["counts"] == {"blocker": 0, "major": 0, "minor": 0}
    assert out["issues"] == []


def test_external_status_ok_approved_clean_stays_approved() -> None:
    payload = {
        "status": "OK",
        "verdict": "APPROVED",
        "issues": [],
        "counts": {"blocker": 0, "major": 0, "minor": 0, "info": 0},
    }
    r = _run(json.dumps(payload), "--external")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "APPROVED"
    assert out["issues"] == []


def test_strict_mode_unchanged_backcompat() -> None:
    bad = _approved(
        issues=[
            {
                "severity": "minor",
                "category": "style",
                "file": "foo.py",
                "line": 1,
                "message": "nit",
            }
        ]
    )
    r = _run(json.dumps(bad))
    assert r.returncode == 1
