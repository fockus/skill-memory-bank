"""/mb work QA step (AGR-098): work.md §5c2 drives the QA loop over the Stage 1 contract."""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
WORK = (REPO / "commands" / "work.md").read_text(encoding="utf-8")
RUNNER = (REPO / "agents" / "mb-qa-runner.md").read_text(encoding="utf-8")


def _section(text: str, start: str, end: str) -> str:
    match = re.search(rf"^\s*{re.escape(start)}.*?(?=^\s*{re.escape(end)})", text, re.M | re.S)
    assert match, f"section {start!r} not found"
    return match.group(0)


def test_work_qa_step_names_the_loop_contract():
    qa = _section(WORK, "### 5c2.", "### 5d.")
    for token in ("qa.prepare", "mb-qa-runner", "mb-qa-bug.sh", " gate --run", "qa-cycle",
                  "before_review", "after_review", "on_max_cycles", "BLOCKED", "qa/test_cases/",
                  "expected_build", "qa.md` § run"):
        assert token in qa, token


def test_work_summary_reports_qa():
    summary = _section(WORK, "6. **End-of-run summary.**", "## Concurrent core-file writes")
    assert "QA" in summary and "cycles" in summary


def test_work_threads_the_qa_flag_to_both_resolvers():
    assert re.search(r"mb-workflow\.sh [^\n]*\[--qa\]", WORK)
    assert re.search(r"mb-work-plan\.sh [^\n]*\[--qa\]", WORK)


def test_runner_checks_expected_build_and_tags_bugs_with_the_run():
    assert "expected_build" in RUNNER and "stale stand" in RUNNER
    assert "- Run: <run_id>" in RUNNER


def test_work_qa_halts_on_any_unrun_scenario():
    # A dead stand gives BLOCKED + "stand down" SKIP; any of them means QA did not finish and must halt,
    # otherwise a run with no executed scenario reaches the gate with zero bugs and passes.
    qa = _section(WORK, "### 5c2.", "### 5d.")
    assert "Any scenario BLOCKED or SKIP" in qa
    assert "Every scenario BLOCKED" not in qa
    assert "any scenario BLOCKED or SKIP" in WORK  # the --auto hard-stop table row
