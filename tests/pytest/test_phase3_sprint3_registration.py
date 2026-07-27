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
    # The command contract spans work.md plus its companion references, split
    # for the 400-line limit (S2 review [26]).
    text = "\n".join(
        (REPO_ROOT / rel).read_text(encoding="utf-8")
        for rel in (
            "commands/work.md",
            "references/work-reference.md",
            "references/work-loop-v2.md",
        )
    )
    assert "mb-work-review-parse" in text
    assert "mb-work-severity-gate" in text
    assert "mb-work-budget" in text
    assert "mb-work-protected-check" in text


def test_work_command_documents_hard_stops() -> None:
    # The command contract spans work.md plus its companion references, split
    # for the 400-line limit (S2 review [26]).
    text = "\n".join(
        (REPO_ROOT / rel).read_text(encoding="utf-8")
        for rel in (
            "commands/work.md",
            "references/work-reference.md",
            "references/work-loop-v2.md",
        )
    )
    for keyword in ("max_cycles", "verifier", "protected", "budget"):
        assert keyword in text.lower()
