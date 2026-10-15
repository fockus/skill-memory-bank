"""Real drive start and firewall regression contracts (R05/R10, drive-autopilot Task 5).

The `<!-- mb-drive:start -->` fence of commands/drive.md runs against a temp git project; `next`
runs the real `mb-flow-verify.sh` (no stub), so the documented start and the default firewall are
what is tested.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
Drive = tuple[Path, dict]
PLAN = "plans/result.md"


@pytest.fixture
def drive(tmp_path: Path) -> Drive:
    bank = tmp_path / ".memory-bank"
    (bank / "plans").mkdir(parents=True)
    (bank / "goal.md").write_text(
        "---\nid: G-900\nstatus: active\nmode: static\n"
        "progress_source: checklist\nprogress_target: 100\n---\n"
        "# Goal\n## Description\nProduce a documented result.\n"
        f"## Acceptance criteria\n- [ ] Result file delivered\n  - plan: {PLAN}\n"
    )
    (bank / PLAN).write_text(
        "---\ntopic: result\nqa: off — no QA target\n---\n# Plan: result\n\n"
        "<!-- mb-stage:1 -->\n### Stage 1: Deliver result\n\n**DoD:**\n- [ ] result delivered\n"
        "<!-- /mb-stage:1 -->\n"
    )
    (bank / "checklist.md").write_text("- ⬜ Result file delivered\n")
    (bank / "status.md").write_text("# Status\n")
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith(("MB_", "CLAUDE_CODE_SESSION"))}
    env.update(SKILL_DIR=str(ROOT), BANK=str(bank), MB_GRAPH_AUTOUPDATE="off")
    return bank, env


def drive_sh(drive: Drive, *args: object) -> subprocess.CompletedProcess:
    bank, env = drive
    return subprocess.run(
        ["bash", str(ROOT / "scripts" / "mb-drive.sh"), *map(str, args), "--bank", str(bank)],
        cwd=bank.parent, env=env, capture_output=True, text=True, check=False,
    )


def start(drive: Drive, **flags: str) -> subprocess.CompletedProcess:
    bank, env = drive
    document = (ROOT / "commands/drive.md").read_text()
    snippet = re.search(r"<!-- mb-drive:start -->\s*```bash\n(.*?)\n```", document, re.S)
    assert snippet is not None
    return subprocess.run(
        ["bash", "-c", snippet.group(1)], cwd=bank.parent, env={**env, **flags},
        capture_output=True, text=True, check=False,
    )


def started(drive: Drive, **flags: str) -> str:
    result = start(drive, **flags)
    assert result.returncode == 0, result.stderr
    run_id = result.stdout.strip().rsplit("run_id=", 1)[1]
    assert drive_sh(drive, "phase", "execution", "--run-id", run_id).returncode == 0
    return run_id


def test_start_fence_opens_a_planning_run_and_next_asks_for_the_plan(drive: Drive) -> None:
    bank, _ = drive
    result = start(drive)

    assert result.returncode == 0, result.stderr
    run_id = result.stdout.strip().rsplit("run_id=", 1)[1]
    assert json.loads((bank / ".drive" / f"{run_id}.json").read_text())["phase"] == "planning"
    assert drive_sh(drive, "next", "--run-id", run_id).stdout.strip() == "plan"


def test_pending_plan_with_default_firewall_dispatches_work_on_the_plan(drive: Drive) -> None:
    run_id = started(drive)

    result = drive_sh(drive, "next", "--run-id", run_id)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == f"work {PLAN}"


def test_hand_ticked_goal_without_a_closed_plan_never_stops_success(drive: Drive) -> None:
    bank, _ = drive
    run_id = started(drive)
    goal = bank / "goal.md"
    goal.write_text(goal.read_text().replace("- [ ]", "- [x]"))

    result = drive_sh(drive, "next", "--run-id", run_id)

    assert result.stdout.strip() == f"work {PLAN}", result.stderr


def test_closed_plan_with_default_firewall_stops_success(drive: Drive) -> None:
    bank, _ = drive
    run_id = started(drive)
    plan = bank / PLAN
    plan.write_text(plan.read_text().replace("- [ ]", "- [x]"))

    result = drive_sh(drive, "next", "--run-id", run_id)

    assert result.stdout.strip() == "stop_success", result.stderr


def test_budget_spent_through_returned_stops_the_run(drive: Drive) -> None:
    run_id = started(drive, BUDGET="1000")

    returned = drive_sh(drive, "returned", "--run-id", run_id, "--action", f"work {PLAN}", "--tokens", 1000)

    assert returned.returncode == 0, returned.stderr
    assert drive_sh(drive, "next", "--run-id", run_id).stdout.strip() == "stop_budget"


@pytest.mark.parametrize("corruption", ["{invalid", "[]"])
def test_corrupt_run_file_refuses_without_rewriting_it(drive: Drive, corruption: str) -> None:
    bank, _ = drive
    run_id = started(drive)
    run_file = bank / ".drive" / f"{run_id}.json"
    run_file.write_text(corruption)

    result = drive_sh(drive, "next", "--run-id", run_id)

    assert result.returncode != 0
    assert "[drive]" in result.stderr
    assert run_file.read_text() == corruption


def test_legacy_drive_state_file_is_not_a_live_run(drive: Drive) -> None:
    bank, _ = drive
    (bank / ".drive").mkdir()
    (bank / ".drive" / "old.json").write_text('{"run_id": "old", "status": "driving", "stop_reason": ""}')
    run_id = started(drive)

    result = drive_sh(drive, "resume")

    assert result.returncode == 0, result.stderr
    assert result.stdout.startswith(f"run_id={run_id} ")
