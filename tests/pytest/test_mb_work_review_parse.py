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


# ── --require-tests-blocker (reviewer-2.0 Task 5, REQ-100/REQ-103/REQ-105) ──
#
# design.md §5 "Reviewer obligation" safety net: if touched-file tests were
# failing but the reviewer's output lacks a category=="tests"/severity=="blocker"
# issue, the parser rewrites the verdict and restores the finding. Opt-in via
# --require-tests-blocker; REQ-105 requires the no-flag path stay byte-identical.


def test_require_tests_blocker_restores_missing_finding_external() -> None:
    payload = {
        "status": "OK",
        "verdict": "CHANGES_REQUESTED",
        "issues": [
            {"severity": "major", "category": "logic", "file": "x.py", "line": 1, "message": "bad"}
        ],
        "counts": {"blocker": 0, "major": 1, "minor": 0},
    }
    r = _run(json.dumps(payload), "--external", "--require-tests-blocker")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "CHANGES_REQUESTED"
    assert out["counts"]["blocker"] >= 1
    first = out["issues"][0]
    assert first["category"] == "tests"
    assert first["severity"] == "blocker"
    assert "restor" in r.stderr.lower()


def test_require_tests_blocker_idempotent_when_already_present() -> None:
    payload = {
        "status": "OK",
        "verdict": "CHANGES_REQUESTED",
        "issues": [
            {
                "severity": "blocker",
                "category": "tests",
                "file": "y.py",
                "line": 5,
                "message": "2 failing tests",
            }
        ],
        "counts": {"blocker": 1, "major": 0, "minor": 0},
    }
    with_flag = _run(json.dumps(payload), "--external", "--require-tests-blocker")
    without_flag = _run(json.dumps(payload), "--external")
    assert with_flag.returncode == 0, with_flag.stderr
    out = json.loads(with_flag.stdout)
    assert len(out["issues"]) == 1
    assert out["counts"]["blocker"] == 1
    assert with_flag.stdout == without_flag.stdout
    assert with_flag.stderr == ""


def test_require_tests_blocker_absent_flag_byte_identical_to_current_behavior() -> None:
    payload = {
        "status": "OK",
        "verdict": "APPROVED",
        "issues": [],
        "counts": {"blocker": 0, "major": 0, "minor": 0, "info": 0},
    }
    without_flag = _run(json.dumps(payload), "--external")
    also_without_flag = _run(json.dumps(payload), "--external")
    assert without_flag.stdout == also_without_flag.stdout
    assert without_flag.stderr == also_without_flag.stderr == ""
    # A no-restore trigger (already has the mandatory finding) proves the flag
    # is dead code unless it actually needs to act — see the idempotent test
    # above for the with-vs-without-flag comparison on the SAME non-triggering
    # input.


def test_require_tests_blocker_skipped_review_restores_blocker() -> None:
    payload = {"status": "SKIPPED", "reason": "codex CLI 403 auth"}
    r = _run(json.dumps(payload), "--external", "--require-tests-blocker")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "CHANGES_REQUESTED"
    assert out["counts"]["blocker"] == 1
    assert out["issues"][0]["category"] == "tests"
    assert out["issues"][0]["severity"] == "blocker"
    assert "restor" in r.stderr.lower()


def test_require_tests_blocker_absent_skipped_review_stays_skipped() -> None:
    """Without the flag, a SKIPPED review still passes through untouched
    (REQ-105 compatibility) -- documents the deliberate contrast with the
    test above."""
    payload = {"status": "SKIPPED", "reason": "codex CLI 403 auth"}
    r = _run(json.dumps(payload), "--external")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "SKIPPED"
    assert out["issues"] == []


def test_require_tests_blocker_strict_mode_restores_finding() -> None:
    """Strict (non-external) mode also honors the flag: an APPROVED verdict
    can never carry a tests/blocker issue (APPROVED requires issues == []),
    so the flag always forces a restore there."""
    clean = _approved()
    r = _run(json.dumps(clean), "--require-tests-blocker")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "CHANGES_REQUESTED"
    assert out["counts"]["blocker"] == 1
    assert out["issues"][0]["category"] == "tests"
    assert out["issues"][0]["severity"] == "blocker"


def test_require_tests_blocker_strict_mode_no_flag_byte_identical() -> None:
    clean = _approved()
    without_flag = _run(json.dumps(clean))
    also_without_flag = _run(json.dumps(clean))
    assert (
        without_flag.stdout
        == also_without_flag.stdout
        == json.dumps(
            {"verdict": "APPROVED", "counts": {"blocker": 0, "major": 0, "minor": 0}, "issues": []}
        )
        + "\n"
    )


# ── Fix-cycle 1 (governed review NO_GO on Task 5) ───────────────────────────
#
# BLOCKER #1: strict mode trusted self-reported `counts` and never recomputed
# them from `issues`, so a reviewer emitting a genuine tests/blocker issue
# while self-reporting counts.blocker=0 sailed through `mb-work-severity-gate.sh`
# (which reads ONLY counts, never issues) with a `blocker_max:0` gate. Strict
# mode must recompute counts from issues under the flag, exactly like
# --external already always does.
#
# MAJOR #2: the pre-existing "CHANGES_REQUESTED requires non-empty issues"
# fail() ran BEFORE the restore logic, so a fully-omitted mandatory finding
# was rejected (exit 1) instead of silently restored (exit 0) -- burning the
# review-loop's one bounded retry on exactly the failure mode the flag exists
# to recover from.


def _gate_run(stdin: str, *args: str) -> subprocess.CompletedProcess[str]:
    gate_script = REPO_ROOT / "scripts" / "mb-work-severity-gate.sh"
    return subprocess.run(
        ["bash", str(gate_script), "--counts-stdin", *args],
        input=stdin,
        capture_output=True,
        text=True,
        check=False,
    )


def test_require_tests_blocker_strict_mode_recomputes_counts_from_issues() -> None:
    """BLOCKER #1 repro: a real tests/blocker issue is present (so the
    has_tests_blocker() safety net correctly stays silent) but the reviewer
    self-reports counts.blocker=0. Under the flag, strict mode must not trust
    that self-reported count."""
    payload = {
        "verdict": "CHANGES_REQUESTED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": [
            {
                "severity": "blocker",
                "category": "tests",
                "file": "t.py",
                "line": 1,
                "message": "x",
            }
        ],
    }
    r = _run(json.dumps(payload), "--require-tests-blocker")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["counts"]["blocker"] >= 1
    # No restore-warning should fire -- the finding was already present, honest.
    assert "restor" not in r.stderr.lower()


def test_require_tests_blocker_strict_mode_count_lie_fails_severity_gate_end_to_end() -> None:
    """End-to-end: the recomputed counts must actually fail a blocker_max:0
    gate -- the whole point of REQ-103's "cannot drop" guarantee."""
    payload = {
        "verdict": "CHANGES_REQUESTED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": [
            {
                "severity": "blocker",
                "category": "tests",
                "file": "t.py",
                "line": 1,
                "message": "x",
            }
        ],
    }
    parsed = _run(json.dumps(payload), "--require-tests-blocker")
    assert parsed.returncode == 0, parsed.stderr
    gated = _gate_run(parsed.stdout, "--gate", '{"blocker":0,"major":0,"minor":0}')
    assert gated.returncode != 0, gated.stdout + gated.stderr


def test_require_tests_blocker_strict_mode_no_flag_still_trusts_self_reported_counts() -> None:
    """Without the flag, strict mode's self-reported counts.blocker=0 (even
    with a real tests/blocker issue present) stay authoritative -- REQ-105."""
    payload = {
        "verdict": "CHANGES_REQUESTED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": [
            {
                "severity": "blocker",
                "category": "tests",
                "file": "t.py",
                "line": 1,
                "message": "x",
            }
        ],
    }
    r = _run(json.dumps(payload))
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["counts"]["blocker"] == 0


def test_require_tests_blocker_strict_mode_fully_omitted_finding_is_restored_not_rejected() -> None:
    """MAJOR #2 repro: CHANGES_REQUESTED with issues == [] must be silently
    restored (exit 0) under the flag, not rejected (exit 1)."""
    payload = {
        "verdict": "CHANGES_REQUESTED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": [],
    }
    r = _run(json.dumps(payload), "--require-tests-blocker")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "CHANGES_REQUESTED"
    assert out["counts"]["blocker"] == 1
    assert out["issues"][0]["category"] == "tests"
    assert out["issues"][0]["severity"] == "blocker"


def test_require_tests_blocker_external_fully_omitted_finding_is_restored_not_rejected() -> None:
    """Same as above, --external mode."""
    payload = {
        "status": "OK",
        "verdict": "CHANGES_REQUESTED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": [],
    }
    r = _run(json.dumps(payload), "--external", "--require-tests-blocker")
    assert r.returncode == 0, r.stderr
    out = json.loads(r.stdout)
    assert out["verdict"] == "CHANGES_REQUESTED"
    assert out["counts"]["blocker"] == 1
    assert out["issues"][0]["category"] == "tests"
    assert out["issues"][0]["severity"] == "blocker"


def test_require_tests_blocker_absent_fully_omitted_finding_still_rejected() -> None:
    """Regression guard: without the flag, both modes still reject a
    CHANGES_REQUESTED verdict carrying an empty issues list (unchanged,
    pre-existing behavior -- REQ-105)."""
    payload = {
        "verdict": "CHANGES_REQUESTED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": [],
    }
    r = _run(json.dumps(payload))
    assert r.returncode == 1

    payload_ext = {
        "status": "OK",
        "verdict": "CHANGES_REQUESTED",
        "counts": {"blocker": 0, "major": 0, "minor": 0},
        "issues": [],
    }
    r_ext = _run(json.dumps(payload_ext), "--external")
    assert r_ext.returncode == 1
