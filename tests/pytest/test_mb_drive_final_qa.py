"""Final QA fix cycle (drive-autopilot Task 4, design C3.6, REQ-032/053/054).

Bugs go into a real `qa/bugs.md` through `mb-qa-bug.sh add`; `returned --action final_qa` runs the real
gate. Blocking bugs become fix plans that join the run's items, so `next` dispatches them through `/mb work`.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_mb_drive_brain  # noqa: E402
from test_mb_drive_brain import SCRIPTS, close, goal, nxt, plan, ret, started  # noqa: E402

bank = test_mb_drive_brain.bank  # the brain's temp-bank fixture


def qa_bank(bank: Path, max_cycles: int = 3) -> None:
    (bank / "qa" / "test_cases" / "checkout").mkdir(parents=True)
    (bank / "qa" / "test_cases" / "profile").mkdir(parents=True)
    (bank / "qa" / "README.md").write_text("# QA target\n")
    for case in ("checkout/pay.md", "profile/edit.md"):
        (bank / "qa" / "test_cases" / case).write_text("---\nid: c\ntags: [x]\n---\n# Case\n")
    (bank / "pipeline.yaml").write_text(
        f"qa:\n  gate: {{critical: 0, major: 0}}\n  max_cycles: {max_cycles}\n")


def bug(bank: Path, sev: str, title: str, run: str, scenario: str | None) -> str:
    body = (f"- Scenario: {scenario}, step 2\n" if scenario else "") + \
        f"- Run: {run}\n- Steps: open the page\n- Expected: ok\n- Actual: 500\n- Evidence: logs/{title}.txt\n"
    res = subprocess.run(["bash", str(SCRIPTS / "mb-qa-bug.sh"), "--mb", str(bank), "add", sev, title, "--run", run],
                         input=body, capture_output=True, text=True, check=True)
    return res.stdout.strip()


def run_state(bank: Path, rid: str) -> dict:
    return json.loads((bank / ".drive" / f"{rid}.json").read_text())


def fix_plans(bank: Path) -> list[Path]:
    return sorted((bank / "plans").glob("*_fix_drive-qa-*.md"))


def at_final_qa(bank: Path, max_cycles: int = 3) -> str:
    qa_bank(bank, max_cycles)
    a = plan(bank, "checkout", "src/a.py", qa="on", done=True)
    goal(bank, ("A", [f"plan: {a}"]))
    rid = started(bank)
    assert nxt(bank, rid) == "final_qa"
    return rid


def test_major_bug_becomes_one_fix_plan_that_next_dispatches_to_work(bank: Path) -> None:
    rid = at_final_qa(bank)
    bid = bug(bank, "major", "Pay returns 500", f"{rid}-final0", "qa/test_cases/checkout/pay.md")
    ret(bank, rid, "final_qa")
    [fix] = fix_plans(bank)
    text = fix.read_text()
    assert fix.name.endswith(f"_fix_drive-qa-checkout-{rid[:8]}-1.md")
    assert "topic: checkout" in text and "qa: on" in text and f"drive_run: {rid}" in text
    assert "Pay returns 500" in text and "open the page" in text and "Regression test first" in text
    assert f"- [ ] {bid} fixed — regression test carries mb:case reg-{bid.lower()}; " \
           f"mb-qa-bug.sh set {bid} fixed" in text
    st = run_state(bank, rid)
    rel = f"plans/{fix.name}"
    assert (st["final_qa"], st["final_qa_cycle"], st["items"][rel]["fix"]) == ("pending", 1, True)
    assert nxt(bank, rid) == f"work {rel}"


def test_bugs_on_two_topics_give_two_plans_and_a_caseless_bug_a_qa_off_plan(bank: Path) -> None:
    rid = at_final_qa(bank)
    run = f"{rid}-final0"
    bug(bank, "critical", "Pay crashes", run, "qa/test_cases/checkout/pay.md")
    bug(bank, "major", "Edit loses name", run, "qa/test_cases/profile/edit.md")
    bug(bank, "major", "Login hangs", run, None)
    ret(bank, rid, "final_qa")
    plans = {p.name.split("_fix_drive-qa-")[1]: p.read_text() for p in fix_plans(bank)}
    assert set(plans) == {f"{t}-{rid[:8]}-1.md" for t in ("checkout", "profile", f"drive-{rid[:8]}")}
    caseless = plans[f"drive-{rid[:8]}-{rid[:8]}-1.md"]
    assert "qa: off — no case" in caseless and "Login hangs" in caseless and "Pay crashes" not in caseless


def test_medium_bug_alone_passes_the_final_qa(bank: Path) -> None:
    rid = at_final_qa(bank)
    bug(bank, "medium", "Typo on pay page", f"{rid}-final0", "qa/test_cases/checkout/pay.md")
    ret(bank, rid, "final_qa")
    assert run_state(bank, rid)["final_qa"] == "pass" and fix_plans(bank) == []


def test_closed_fix_plan_brings_final_qa_back_and_the_bound_stops_qa_red(bank: Path) -> None:
    rid = at_final_qa(bank, max_cycles=1)
    bug(bank, "major", "Pay returns 500", f"{rid}-final0", "qa/test_cases/checkout/pay.md")
    ret(bank, rid, "final_qa")
    rel = f"plans/{fix_plans(bank)[0].name}"
    close(bank, rel)
    ret(bank, rid, f"work {rel}")
    assert nxt(bank, rid) == "final_qa"
    bug(bank, "major", "Pay returns 500", f"{rid}-final1", "qa/test_cases/checkout/pay.md")
    ret(bank, rid, "final_qa")
    assert len(fix_plans(bank)) == 1 and run_state(bank, rid)["final_qa"] == "red"
    assert nxt(bank, rid) == "stop_human qa-red"


def test_selection_lists_only_the_run_topics(bank: Path) -> None:
    rid = at_final_qa(bank)
    plan(bank, "other", "src/o.py", qa="on")
    res = subprocess.run([sys.executable, str(SCRIPTS / "mb_drive_qa.py"), "selection", "--bank", str(bank),
                          "--run-id", rid], capture_output=True, text=True, check=False)
    assert res.returncode == 0, res.stderr
    assert res.stdout.split() == [f"{rid}-final0", "@checkout"]
