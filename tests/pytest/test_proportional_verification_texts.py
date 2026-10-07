"""proportional-effort Sprint 2 Stage 2 — targeted tests per item, the full suite once (AGR-071).

The implementer and the per-item verifier run tests for the changed files only; the full suite runs
once — on the final item of a `/mb work` run, in `/mb verify` of the whole plan, and before a commit.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


def _read(rel: str) -> str:
    return (REPO_ROOT / rel).read_text(encoding="utf-8")


def _section(text: str, start: str, end_pattern: str) -> str:
    begin = text.index(start)
    tail = text[begin + len(start):]
    match = re.search(end_pattern, tail)
    return tail[: match.start()] if match else tail


def test_core_drops_full_suite_after_every_change_rule() -> None:
    core = _read("agents/mb-engineering-core.md")
    flat = " ".join(core.split())
    assert "After every significant change" not in flat
    assert "tests (all green)" not in flat


def test_core_runs_targeted_tests_for_changed_files() -> None:
    core = " ".join(_read("agents/mb-engineering-core.md").split())
    assert "mb-test-run.sh --changed-since" in core
    assert "full suite" in core


def test_verifier_uses_changed_since_for_one_item_and_full_for_the_plan() -> None:
    step = _section(_read("agents/plan-verifier.md"), "### Step 3.5", r"\n### ")
    assert "--changed-since" in step
    assert "Verify only item" in step, "the verifier must say how it recognises a per-item run"
    assert "Final item: yes" in step
    assert re.search(r"mb-test-run\.sh\"? --dir \. --out json", step), "full-suite command kept for the plan"


def test_work_verify_dispatch_carries_baseline_and_final_flag() -> None:
    work = _read("commands/work.md")
    verify = _section(work, "### 5c. Verify step", r"\n   ### 5d")
    assert "Baseline ref:" in verify
    assert "Final item:" in verify


def test_work_cost_ladder_reports_targeted_runs_per_item() -> None:
    ladder = _section(_read("commands/work.md"), "## Cost ladder", r"\n## ")
    assert "targeted" in ladder
    assert "~28" not in ladder


def test_commit_runs_full_suite_unless_already_green_on_this_tree() -> None:
    commit = " ".join(_read("commands/commit.md").split())
    assert "mb-test-run.sh" in commit
    assert "same tree" in commit
