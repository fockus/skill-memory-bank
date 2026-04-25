"""Phase 3 Sprint 3 — registration tests for review-loop wiring."""

from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def test_review_parse_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-work-review-parse.sh").is_file()


def test_severity_gate_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-work-severity-gate.sh").is_file()


def test_budget_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-work-budget.sh").is_file()


def test_protected_check_script_present() -> None:
    assert (REPO_ROOT / "scripts" / "mb-work-protected-check.sh").is_file()


def test_reviewer_agent_has_json_schema() -> None:
    text = (REPO_ROOT / "agents" / "mb-reviewer.md").read_text(encoding="utf-8")
    # Production-grade prompt must show concrete JSON schema example
    assert '"verdict"' in text
    assert '"counts"' in text
    assert '"issues"' in text
    assert '"severity"' in text


def test_reviewer_agent_documents_severity_decision() -> None:
    text = (REPO_ROOT / "agents" / "mb-reviewer.md").read_text(encoding="utf-8")
    for keyword in ("blocker", "major", "minor"):
        assert keyword in text


def test_reviewer_agent_documents_fix_cycle() -> None:
    text = (REPO_ROOT / "agents" / "mb-reviewer.md").read_text(encoding="utf-8")
    assert "fix" in text.lower()
    assert "cycle" in text.lower() or "iteration" in text.lower()


def test_work_command_references_review_loop_helpers() -> None:
    text = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")
    assert "mb-work-review-parse" in text
    assert "mb-work-severity-gate" in text
    assert "mb-work-budget" in text
    assert "mb-work-protected-check" in text


def test_work_command_documents_hard_stops() -> None:
    text = (REPO_ROOT / "commands" / "work.md").read_text(encoding="utf-8")
    for keyword in ("max_cycles", "verifier", "protected", "budget"):
        assert keyword in text.lower()
