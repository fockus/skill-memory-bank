"""Drive brain (drive-autopilot Task 2): run files, run selection, planning gate, next, returned.

The decision table is checked row by row on fact dicts; everything else runs through
`scripts/mb-drive.sh` on a temp bank. The only mock is `mb-flow-verify.sh`
(`MB_FLOW_VERIFY_BIN`), the firewall that rule 15 calls.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
FIREWALL_STUB = """#!/usr/bin/env bash
echo "$*" >> "$FV_LOG"
case "${FV_RC:-0}" in
  1) echo '{"checks":[{"name":"tests","status":"fail"},{"name":"lint","status":"fail"},{"name":"rules","status":"pass"}]}' ;;
  2) echo '{"checks":[{"name":"qa","status":"broke"}]}' ;;
  *) echo '{"checks":[]}' ;;
esac
exit "${FV_RC:-0}"
"""


def decide(facts: dict):
    sys.path.insert(0, str(SCRIPTS))
    import mb_drive_decide

    return mb_drive_decide.decide(facts)


def item(path: str, **kw) -> dict:
    base = {"path": path, "closed": False, "deps": [], "files": [f"src/{path}.py"], "owned_by": None,
            "stalls": 0, "pivoted": False, "deferred": False, "qa_retried": False, "qa_reason": "", "crit": 1}
    return {**base, **kw}


def all_triggered() -> dict:
    return {
        "run_id": "R1", "phase": "planning", "stop_reason": "budget", "broken": "items",
        "budget": {"exceeded": True, "total": 100, "spent": 10}, "steps": 1, "parallel": True,
        "waits": 3, "final_qa": "pending", "qa_on": True,
        "items": [item("X", stalls=2), item("Y"), item("W", owned_by="w1"),
                  item("Q", deferred=True, qa_retried=False, qa_reason="no-browser")],
        "unmet": lambda: 2, "firewall": lambda: (0, ""),
    }


def test_decide_table_each_rule_wins_over_the_next() -> None:
    f = all_triggered()
    by = {i["path"]: i for i in f["items"]}
    steps = [
        (lambda: None, ("plan", 0)),
        (lambda: f.update(phase="stopped"), ("[drive] run R1 stopped: budget", 1)),
        (lambda: f.update(phase="execution"), ("stop_human check-broke:items", 0)),
        (lambda: f.update(broken=None), ("stop_budget", 0)),
        (lambda: f.update(budget={"exceeded": False, "total": 100, "spent": 60}), ("stop_budget", 0)),
        (lambda: f.update(budget=None), ("stop_human stall", 0)),
        (lambda: by["X"].update(stalls=1), ("pivot X", 0)),
        (lambda: by["X"].update(pivoted=True), ("team X Y", 0)),
        (lambda: f.update(parallel=False), ("work X", 0)),
        (lambda: (by["X"].update(closed=True), by["Y"].update(closed=True)), ("stop_human owned-elsewhere:w1", 0)),
        (lambda: f.update(waits=2), ("wait W", 0)),
        (lambda: by["W"].update(closed=True), ("qa Q", 0)),
        (lambda: by["Q"].update(qa_retried=True), ("stop_human qa-blocked:no-browser", 0)),
        (lambda: by["Q"].update(closed=True), ("stop_human acceptance-red:2", 0)),
        (lambda: f.update(unmet=lambda: None), ("final_qa", 0)),
        (lambda: f.update(final_qa="blocked:env"), ("stop_human qa-blocked:env", 0)),
        (lambda: f.update(final_qa="red"), ("stop_human qa-red", 0)),
        (lambda: f.update(final_qa="pass"), ("stop_success", 0)),
        (lambda: f.update(firewall=lambda: (1, "tests,lint")), ("stop_human flow-red:tests,lint", 0)),
        (lambda: f.update(firewall=lambda: (2, "qa")), ("stop_human check-broke:qa", 0)),
        (lambda: f.update(firewall=lambda: None), ("firewall", 0)),
    ]
    for mutate, expected in steps:
        mutate()
        assert decide(f) == expected


def test_decide_open_unready_item_is_acceptance_red_and_qa_off_skips_final_qa() -> None:
    f = {**all_triggered(), "phase": "execution", "broken": None, "budget": None, "waits": 0,
         "items": [item("V", deps=["plans/gone.md"], crit=3)], "unmet": lambda: None}
    assert decide(f) == ("stop_human acceptance-red:3", 0)
    f.update(items=[item("V", closed=True)], qa_on=False)
    assert decide(f) == ("stop_success", 0)
    f.update(items=[item("A", files=[]), item("B")])
    assert decide(f) == ("work A", 0)  # an item without declared files never joins a team


# ── CLI on a temp bank ──────────────────────────────────────────────────


@pytest.fixture
def bank(tmp_path: Path) -> Path:
    b = tmp_path / ".memory-bank"
    (b / "plans").mkdir(parents=True)
    (b / "checklist.md").write_text("- ⬜ x\n")
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    stub = tmp_path / "flow-verify-stub.sh"
    stub.write_text(FIREWALL_STUB)
    stub.chmod(0o755)
    return b


def env_for(bank: Path, **extra: str) -> dict:
    env = {k: v for k, v in os.environ.items() if not k.startswith(("MB_", "CLAUDE_CODE_SESSION"))}
    env.update(MB_FLOW_VERIFY_BIN=str(bank.parent / "flow-verify-stub.sh"), FV_LOG=str(bank.parent / "fv.log"),
               MB_GRAPH_AUTOUPDATE="off", **extra)
    return env


def drive(bank: Path, *args: str, **extra: str) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(SCRIPTS / "mb-drive.sh"), *args, "--bank", str(bank)],
                          cwd=bank.parent, env=env_for(bank, **extra), capture_output=True, text=True, check=False)


def plan(bank: Path, name: str, files: str = "", qa: str = "off — no QA target", deps: str = "",
         done: bool = False) -> str:
    fm = f"---\ntopic: {name}\n" + (f"qa: {qa}\n" if qa else "") + (f"depends_on: [{deps}]\n" if deps else "")
    stage = f"### Stage 1: Build {name}\n" + (f"**Files:** {files}\n" if files else "")
    box = "x" if done else " "
    (bank / "plans" / f"{name}.md").write_text(
        f"{fm}---\n# Plan: {name}\n\n<!-- mb-stage:1 -->\n{stage}\n**DoD:**\n- [{box}] {name} works\n<!-- /mb-stage:1 -->\n")
    return f"plans/{name}.md"


def close(bank: Path, rel: str) -> None:
    p = bank / rel
    p.write_text(p.read_text().replace("- [ ]", "- [x]"))


def goal(bank: Path, *crits: tuple[str, list[str]], name: str = "goal.md") -> Path:
    body = "".join(f"- [ ] {label}\n" + "".join(f"  - {link}\n" for link in links) for label, links in crits)
    path = bank / name
    path.write_text("---\nid: G-001\nstatus: active\nmode: static\nprogress_source: checklist\n"
                    f"progress_target: 100\n---\n# Goal: g\n\n## Acceptance criteria\n\n{body}")
    return path


def started(bank: Path, *flags: str) -> str:
    res = drive(bank, "start", *flags)
    assert res.returncode == 0, res.stderr
    rid = res.stdout.strip().splitlines()[-1]
    assert drive(bank, "phase", "execution", "--run-id", rid).returncode == 0
    return rid


def nxt(bank: Path, rid: str, **extra: str) -> str:
    res = drive(bank, "next", "--run-id", rid, **extra)
    assert res.returncode == 0, res.stderr
    return res.stdout.strip()


def ret(bank: Path, rid: str, action: str, *flags: str) -> None:
    res = drive(bank, "returned", "--run-id", rid, "--action", action, *flags)
    assert res.returncode == 0, res.stderr


def test_cli_help_unknown_and_fail_closed(bank: Path) -> None:
    help_out = drive(bank, "--help")
    assert help_out.returncode == 0 and "returned" in help_out.stdout
    assert drive(bank, "decide").returncode == 2
    assert drive(bank, "start", "--route", "x").returncode == 2
    goal(bank, ("A", [f"plan: {plan(bank, 'a', 'src/a.py')}"]))
    rid = started(bank)
    (bank / "goal.md").unlink()
    assert nxt(bank, rid) == "stop_human check-broke:acceptance"


def test_start_scaffolds_default_goal_and_run_file_sits_at_drive_slot(bank: Path) -> None:
    res = drive(bank, "start")
    assert res.returncode == 1 and (bank / "goal.md").is_file()
    assert drive(bank, "start", "--goal", "other.md").returncode == 1 and not (bank / "other.md").exists()
    goal(bank, ("A", [f"plan: {plan(bank, 'a', 'src/a.py')}"]))
    rid = drive(bank, "start", "--session", "S9").stdout.strip()
    slot = subprocess.run(["bash", "-c", f'. "{SCRIPTS}/mb-work-slots.sh"; mbw_drive_slot "$0" "$1"', str(bank), rid],
                          capture_output=True, text=True, check=True).stdout.strip()
    state = json.loads(Path(slot).read_text())
    assert Path(slot) == bank / ".drive" / f"{rid}.json"
    assert (state["phase"], state["session"], state["goal"], state["parallel"]) == (
        "planning", "S9", str((bank / "goal.md").resolve()), True)
    assert nxt(bank, rid) == "plan"
    assert drive(bank, "returned", "--run-id", rid, "--action", "work plans/a.md").returncode == 2


def test_planning_gate_names_every_gap_then_approve_opens_execution(bank: Path) -> None:
    spec = bank / "specs" / "big"
    spec.mkdir(parents=True)
    (spec / "requirements.md").write_text("---\nstatus: draft\n---\n# R\n")
    (spec / "tasks.md").write_text("<!-- mb-task:1 -->\n## Task 1: T\n\n- [ ] t\n<!-- /mb-task:1 -->\n")
    (bank / "plans" / "w.md").write_text("---\ntopic: big\nqa: on\nlinked_spec: specs/big\n---\n# W\n")
    goal(bank, ("no link", []), ("missing", ["plan: plans/nope.md"]), ("no qa", [f"plan: {plan(bank, 'n', qa='')}"]),
         ("wrapper", ["plan: plans/w.md"]), ("dep", [f"plan: {plan(bank, 'd', deps='plans/ghost.md')}"]),
         ("spec", ["spec: specs/big"]))
    rid = drive(bank, "start").stdout.strip()
    res = drive(bank, "phase", "execution", "--run-id", rid)
    assert res.returncode == 1
    for needle in ("no link", "plans/nope.md", "plans/n.md", "big", "plans/ghost.md", "spec: specs/big"):
        assert needle in res.stderr
    assert "phase=planning" in drive(bank, "resume", "--run-id", rid).stdout
    goal(bank, ("wrapper", ["plan: plans/w.md"]))
    assert drive(bank, "phase", "execution", "--run-id", rid).returncode == 1
    assert drive(bank, "phase", "execution", "--run-id", rid, "--approve", "big").returncode == 0
    assert nxt(bank, rid) == "work plans/w.md"


def test_team_for_disjoint_independent_plans_then_work_for_the_dependent(bank: Path) -> None:
    a, b = plan(bank, "a", "src/a.py"), plan(bank, "b", "src/b.py")
    c = plan(bank, "c", "src/c.py", deps="plans/a.md")
    goal(bank, ("A", [f"plan: {a}"]), ("B", [f"plan: {b}"]), ("C", [f"plan: {c}"]))
    rid = started(bank)
    assert nxt(bank, rid) == f"team {a} {b}"
    close(bank, a)
    close(bank, b)
    ret(bank, rid, f"team {a} {b}", "--tokens", "10")
    assert "- [x] A" in (bank / "goal.md").read_text()
    assert nxt(bank, rid) == f"work {c}"


@pytest.mark.parametrize("how", ["serial", "pipeline", "host"])
def test_serial_modes_dispatch_only_work(bank: Path, how: str) -> None:
    a, b = plan(bank, "a", "src/a.py"), plan(bank, "b", "src/b.py")
    goal(bank, ("A", [f"plan: {a}"]), ("B", [f"plan: {b}"]))
    if how == "pipeline":
        (bank / "pipeline.yaml").write_text("drive:\n  parallel: false\n")
    flags = {"serial": ["--serial"], "pipeline": [], "host": ["--host-serial"]}[how]
    res = drive(bank, "start", *flags)
    assert ("one dispatch at a time" in res.stderr) == (how == "host")
    rid = res.stdout.strip()
    drive(bank, "phase", "execution", "--run-id", rid)
    assert nxt(bank, rid) == f"work {a}"
    status = json.loads(drive(bank, "status", "--run-id", rid).stdout)
    assert (status["parallel"], status["parallel_reason"]) == (False, {"serial": "serial-flag"}.get(how, how))


def test_stall_pivot_then_stop_and_owned_elsewhere_is_no_stall(bank: Path) -> None:
    a = plan(bank, "a", "src/a.py")
    goal(bank, ("A", [f"plan: {a}"]))
    rid = started(bank)
    ret(bank, rid, f"work {a}", "--outcome", "owned-elsewhere")
    assert nxt(bank, rid) == f"work {a}"
    ret(bank, rid, f"work {a}", "--outcome", "stop_human:claim")
    assert nxt(bank, rid) == f"pivot {a}"
    ret(bank, rid, f"pivot {a}")
    assert nxt(bank, rid) == f"work {a}"
    ret(bank, rid, f"work {a}")
    assert nxt(bank, rid) == "stop_human stall"


def test_foreign_claim_waits_three_times_then_stops_and_own_claim_is_not_foreign(bank: Path) -> None:
    p = plan(bank, "p", "src/p.py")
    goal(bank, ("P", [f"plan: {p}"]))
    rid = started(bank)
    claim = subprocess.run(["bash", str(SCRIPTS / "mb-work-state.sh"), "init", p, "1", "--mb", str(bank),
                            "--run-id", "foreign1"], env=env_for(bank, MB_WORK_PARALLEL="1"),
                           capture_output=True, text=True, check=False)
    assert claim.returncode == 0, claim.stderr
    for _ in range(3):
        assert nxt(bank, rid) == f"wait {p}"
        ret(bank, rid, f"wait {p}")
    assert nxt(bank, rid) == "stop_human owned-elsewhere:foreign1"
    other = started(bank, "--goal", str(goal(bank, ("P", [f"plan: {p}"]), name="g2.md")))
    ret(bank, other, f"work {p}", "--outcome", "owned-elsewhere", "--work-run", "foreign1")
    assert nxt(bank, other) == f"work {p}"


def test_budget_average_cost_stops_and_spend_is_under_the_run_id(bank: Path) -> None:
    a = plan(bank, "a", "src/a.py")
    goal(bank, ("A", [f"plan: {a}"]))
    rid = started(bank, "--budget", "100000")
    for _ in range(2):
        ret(bank, rid, f"work {a}", "--tokens", "40000", "--outcome", "owned-elsewhere")
    assert nxt(bank, rid) == "stop_budget"
    status = subprocess.run(["bash", str(SCRIPTS / "mb-work-budget.sh"), "status", "--run-id", rid, "--mb", str(bank)],
                            env=env_for(bank, MB_WORK_PARALLEL="1"), capture_output=True, text=True, check=False)
    assert "spent=80000" in status.stdout


def test_qa_blocked_twice_defers_then_retries_once_after_the_rest_closes(bank: Path) -> None:
    a, b = plan(bank, "a", "src/a.py"), plan(bank, "b", "src/b.py")
    goal(bank, ("A", [f"plan: {a}"]), ("B", [f"plan: {b}"]))
    rid = started(bank, "--serial")
    for _ in range(2):
        assert nxt(bank, rid) == f"work {a}"
        ret(bank, rid, f"work {a}", "--outcome", "qa-blocked:no-browser")
    assert nxt(bank, rid) == f"work {b}"
    close(bank, b)
    ret(bank, rid, f"work {b}")
    assert nxt(bank, rid) == f"qa {a}"
    status = json.loads(drive(bank, "status", "--run-id", rid).stdout)
    assert [c["waiting_qa"] for c in status["criteria"]] == [True, False]
    ret(bank, rid, f"qa {a}", "--outcome", "qa-blocked:no-browser")
    assert nxt(bank, rid) == "stop_human qa-blocked:no-browser"


@pytest.mark.parametrize(("rc", "action"), [("0", "stop_success"), ("1", "stop_human flow-red:tests,lint"),
                                            ("2", "stop_human check-broke:qa")])
def test_final_qa_then_firewall_without_acceptance(bank: Path, rc: str, action: str) -> None:
    (bank / "qa").mkdir()
    (bank / "qa" / "README.md").write_text("# QA target\n")
    a = plan(bank, "a", "src/a.py", qa="on", done=True)
    goal(bank, ("A", [f"plan: {a}", "check: true"]))
    rid = started(bank)
    assert nxt(bank, rid, FV_RC=rc) == "final_qa"
    ret(bank, rid, "final_qa")
    assert nxt(bank, rid, FV_RC=rc) == action
    assert (bank.parent / "fv.log").read_text().split() == [str(bank), "--skip", "acceptance"]


def test_two_runs_coexist_and_same_goal_by_another_spelling_is_refused(bank: Path) -> None:
    a = plan(bank, "a", "src/a.py")
    goal(bank, ("A", [f"plan: {a}"]))
    goal(bank, ("A", [f"plan: {a}"]), name="second.md")
    first = started(bank)
    second = started(bank, "--goal", "second.md")
    assert first != second and (bank / ".drive" / f"{second}.json").is_file()
    again = drive(bank, "start", "--goal", str(bank / "plans" / ".." / "goal.md"))
    assert again.returncode == 1 and first in again.stderr and "--resume" in again.stderr
    listing = drive(bank, "resume")
    assert listing.returncode == 2 and first in listing.stdout and second in listing.stdout
    assert drive(bank, "next").returncode == 2


def test_resume_picks_the_only_live_run_without_a_run_id(bank: Path) -> None:
    goal(bank, ("A", [f"plan: {plan(bank, 'a', 'src/a.py')}"]))
    rid = started(bank)
    res = drive(bank, "resume")
    assert res.returncode == 0
    assert res.stdout.strip() == f"run_id={rid} goal={(bank / 'goal.md').resolve()} phase=execution"


def test_status_names_items_by_path_and_first_pending_heading(bank: Path) -> None:
    a = plan(bank, "a", "src/a.py")
    goal(bank, ("A", [f"plan: {a}"]))
    rid = started(bank)
    status = json.loads(drive(bank, "status", "--run-id", rid).stdout)
    assert status["items"][0]["path"] == a
    assert status["items"][0]["heading"] == "Stage 1: Build a"
    assert status["items"][0]["files"] == ["src/a.py"]
    assert status["action"] == f"work {a}"
    assert not (bank.parent / "fv.log").exists()
