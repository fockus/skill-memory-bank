"""Transcript cost mining — `memory_bank_skill/cost_report.py` + `scripts/mb-cost-report.py`.

Baseline measurement for the mb-work-cost-diet phase: the numbers asserted here
are the ones Sprint 2/3 gates compare against, so the schema keys and the
counting rules (which turns belong to a work item, what counts as a test run)
are contract, not incidental.

Fixtures under `tests/fixtures/cost-report/` are synthetic transcripts in the
real `~/.claude/projects/<slug>/` layout: `<session>.jsonl` plus
`<session>/subagents/*.jsonl`.
"""

from __future__ import annotations

import json
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))
from memory_bank_skill import cost_report  # noqa: E402

FIXTURES = REPO_ROOT / "tests" / "fixtures" / "cost-report"
MAIN = FIXTURES / "sess-main.jsonl"
IMPL = FIXTURES / "sess-main" / "subagents" / "impl.jsonl"
VERIFY = FIXTURES / "sess-main" / "subagents" / "verify.jsonl"
SCRIPT = REPO_ROOT / "scripts" / "mb-cost-report.py"

NOW = datetime(2026, 9, 6, 12, 0, 0, tzinfo=UTC)


# ── session_stats ────────────────────────────────────────────────────


def test_session_stats_counts_tokens_tools_and_tasks() -> None:
    stats = cost_report.session_stats(MAIN)

    assert stats["session"] == "sess-main"
    assert stats["turns"] == 6
    assert stats["tool_calls"] == 5
    assert stats["tasks"] == 2
    assert stats["output_tokens"] == 667
    assert stats["cache_creation_tokens"] == 2661
    assert stats["cache_read_tokens"] == 18122
    # peak = max(cache_creation + cache_read + input) over assistant records
    assert stats["peak_context"] == 9110
    assert stats["compactions"] == 1


# ── subagent_stats ───────────────────────────────────────────────────


def test_subagent_role_detected_from_prompt_markers() -> None:
    assert cost_report.subagent_stats(IMPL)["role"] == "implementer"
    assert cost_report.subagent_stats(VERIFY)["role"] == "verifier"


@pytest.mark.parametrize(
    "prompt,expected",
    [
        ("You are MB Judge. Emit decision GO_WITH_BACKLOG.", "judge"),
        ("You are plan-verifier — Plan execution auditor", "verifier"),
        ("# MB Engineering Core\nPlan: p.md\nStage: 1", "implementer"),
        ("mb-reviewer: emit CHANGES_REQUESTED for this ## Diff", "reviewer"),
        # An implementer prompt quotes `review_rubric` in its self-review section;
        # that must not steal it into the reviewer bucket.
        ("# MB Engineering Core\nIf a pipeline.yaml:review_rubric is provided", "implementer"),
        # `mb-tooling-core` is prepended to reviewer/manager/research prompts too,
        # so it must never decide a role ahead of the agent's own identity.
        (
            "# MB Reviewer — Subagent Prompt\n"
            "Code-understanding routing (`agents/mb-tooling-core.md`) is prepended.\n## Diff",
            "reviewer",
        ),
        (
            "# MB Manager\nThe mb-tooling-core routing table is prepended.\n"
            "You are the Memory Bank manager.",
            "manager",
        ),
        (
            "# mb-research\nThe mb-tooling-core routing table is prepended.\n"
            "Return file:line-grounded findings.",
            "research",
        ),
        # A fix-cycle implementer carries the judge's blocking_issues, which quote
        # reviewer vocabulary verbatim. The dispatch heading, not the body, decides.
        (
            "# MB Engineering Core — shared discipline\nYou implement one work item.\n"
            "Blocking issue from mb-reviewer: CHANGES_REQUESTED on ROLE_MARKERS order.",
            "implementer",
        ),
        (
            "# MB Manager\nActualize the core files.\n"
            "Do not dispatch MB Reviewer for this mechanical pass.",
            "manager",
        ),
        ("Summarize the release notes for me.", "other"),
    ],
)
def test_role_for_prompt_matches_marker_table(prompt: str, expected: str) -> None:
    assert cost_report.role_for_prompt(prompt) == expected


def test_subagent_test_runs_counted_by_command_regex() -> None:
    impl = cost_report.subagent_stats(IMPL)
    verify = cost_report.subagent_stats(VERIFY)

    # pytest + bats in impl; Read/Grep are not test runs.
    assert impl["test_runs"] == 2
    assert impl["turns"] == 2
    assert impl["tool_calls"] == 3
    assert impl["output_tokens"] == 900
    assert impl["peak_context"] == 4015
    assert verify["test_runs"] == 0
    assert verify["tool_calls"] == 1


@pytest.mark.parametrize(
    "command,is_test_run",
    [
        (".venv/bin/pytest -q tests/pytest", True),
        ("bats tests/bats/foo.bats", True),
        ("go test ./...", True),
        ("ya make -t path/to/pkg", True),
        ("git status", False),
        ("cat pytest.ini", True),  # regex is substring-based — documented behavior
    ],
)
def test_test_command_regex_classification(command: str, is_test_run: bool) -> None:
    assert bool(cost_report.TEST_CMD_RE.search(command)) is is_test_run


# ── item_segments ────────────────────────────────────────────────────


def test_item_segment_bounded_by_init_and_flip() -> None:
    segments = cost_report.item_segments(MAIN)

    assert len(segments) == 1
    seg = segments[0]
    assert seg["session"] == "sess-main"
    assert seg["dispatches"] == 2
    # Usage is accrued from the turn AFTER the one that opened the segment,
    # up to and including the flip turn: 200 + 300 + 50 + 10.
    assert seg["output_tokens"] == 560
    assert seg["turns"] == 4
    assert seg["bash_calls"] == 3
    assert seg["test_runs"] == 1
    assert seg["duration_min"] == pytest.approx(44.83, abs=0.02)


def test_item_segment_absent_without_flip(tmp_path: Path) -> None:
    """An item opened but never flipped is not reported as a closed item."""
    src = MAIN.read_text(encoding="utf-8").splitlines()
    kept = [ln for ln in src if "mb-work-checkbox.sh flip" not in ln]
    unclosed = tmp_path / "sess-unclosed.jsonl"
    unclosed.write_text("\n".join(kept) + "\n", encoding="utf-8")

    assert cost_report.item_segments(unclosed) == []


# ── robustness ───────────────────────────────────────────────────────


def test_malformed_line_skipped_without_crash() -> None:
    records = list(cost_report.iter_records(MAIN))

    # 14 physical lines, one of which is a truncated JSON object.
    assert len(MAIN.read_text(encoding="utf-8").strip().splitlines()) == 14
    assert len(records) == 13
    assert all(isinstance(r, dict) for r in records)


# ── build_report ─────────────────────────────────────────────────────


def test_since_filter_excludes_old_sessions() -> None:
    unfiltered = cost_report.build_report(FIXTURES, now=NOW)
    filtered = cost_report.build_report(FIXTURES, since_days=30, now=NOW)

    assert {s["session"] for s in unfiltered["sessions"]} == {"sess-main", "sess-old"}
    assert {s["session"] for s in filtered["sessions"]} == {"sess-main"}


def test_build_report_aggregates_roles_across_subagents() -> None:
    report = cost_report.build_report(FIXTURES, now=NOW)

    assert set(report["roles"]) == {"implementer", "verifier"}
    impl = report["roles"]["implementer"]
    assert impl["n"] == 1
    assert impl["avg_turns"] == pytest.approx(2.0)
    assert impl["avg_test_runs"] == pytest.approx(2.0)
    assert impl["avg_output_tokens"] == pytest.approx(900.0)
    assert impl["avg_peak_context"] == pytest.approx(4015.0)
    assert impl["avg_duration_min"] == pytest.approx(18.92, abs=0.02)
    assert report["roles"]["verifier"]["n"] == 1


def test_json_output_schema_has_sessions_roles_items() -> None:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--project", str(FIXTURES), "--json"],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )

    assert proc.returncode == 0, proc.stderr
    payload = json.loads(proc.stdout)
    assert set(payload) >= {"generated_at", "project", "sessions", "roles", "items"}
    assert {s["session"] for s in payload["sessions"]} == {"sess-main", "sess-old"}
    assert set(payload["roles"]) == {"implementer", "verifier"}
    assert len(payload["items"]) == 1
    assert payload["items"][0]["dispatches"] == 2


def test_table_output_lists_sessions_roles_and_items() -> None:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--project", str(FIXTURES)],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )

    assert proc.returncode == 0, proc.stderr
    assert "sess-main" in proc.stdout
    assert "implementer" in proc.stdout
    assert "verifier" in proc.stdout


def test_missing_project_dir_exits_nonzero_with_message(tmp_path: Path) -> None:
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--project", str(tmp_path / "nope"), "--json"],
        capture_output=True,
        text=True,
        check=False,
        cwd=REPO_ROOT,
    )

    assert proc.returncode != 0
    assert "nope" in proc.stderr
