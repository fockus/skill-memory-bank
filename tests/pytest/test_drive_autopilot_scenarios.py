"""drive-autopilot scenarios 1-11 end to end (Task 6, `requirements.md` `<!-- mb-scenario:N -->`).

One test per scenario, over the real CLI chain on a temp git project: `mb-drive.sh start → phase →
next → returned …`, `mb-goal-acceptance.sh`, `mb-drive-stop.sh`, the Stop-hook resume gate,
`mb-work-state.sh` claims, `mb-work-budget.sh` and `mb-qa-bug.sh`. The only mock is the firewall
`mb-flow-verify.sh` (`MB_FLOW_VERIFY_BIN`, the brain fixture's stub). Decision-table units live in
`test_mb_drive_brain.py`; these tests do not repeat them.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_mb_drive_brain  # noqa: E402
import test_s2_file_size_contract  # noqa: E402
from test_mb_drive_brain import (  # noqa: E402
    ROOT,
    SCRIPTS,
    close,
    drive,
    env_for,
    goal,
    nxt,
    plan,
    ret,
    started,
)
from test_mb_drive_final_qa import bug, fix_plans, qa_bank  # noqa: E402

bank = test_mb_drive_brain.bank  # the brain's temp-bank fixture (git project + firewall stub)

DISPATCH = {"work", "team", "pivot", "qa", "wait", "final_qa", "plan"}


def run_id_of(res: subprocess.CompletedProcess) -> str:
    assert res.returncode == 0, res.stderr
    return res.stdout.strip().splitlines()[-1]


def sh(script: str, *args: str, bank: Path, stdin: str | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(["bash", str(ROOT / script), *args], cwd=bank.parent, input=stdin,
                          env=env_for(bank, MB_WORK_PARALLEL="1"), capture_output=True, text=True, check=False)


def status(bank: Path, rid: str) -> dict:
    return json.loads(drive(bank, "status", "--run-id", rid).stdout)


def stop_event(bank: Path, session: str) -> subprocess.CompletedProcess:
    payload = json.dumps({"stop_hook_active": False, "session_id": session, "cwd": str(bank.parent)})
    return sh("hooks/mb-drive-resume-gate.sh", bank=bank, stdin=payload)


def wrapper(bank: Path, topic: str) -> str:
    spec = bank / "specs" / topic
    spec.mkdir(parents=True)
    (spec / "requirements.md").write_text("---\nstatus: draft\n---\n# R\n")
    (spec / "tasks.md").write_text("<!-- mb-task:1 -->\n## Task 1: T\n\n- [ ] t\n<!-- /mb-task:1 -->\n")
    (bank / "plans" / f"{topic}.md").write_text(f"---\ntopic: {topic}\nqa: on\nlinked_spec: specs/{topic}\n---\n# W\n")
    return f"plans/{topic}.md"


# ── Scenario 1 ──────────────────────────────────────────────────────────


def test_REQ_019__planning_gate_refuses_an_unlinked_goal(bank: Path) -> None:
    a, w = plan(bank, "a", "src/a.py", qa="on"), wrapper(bank, "big")
    goal(bank, ("Alpha ships", [f"plan: {a}"]), ("Big feature", [f"plan: {w}"]), ("Gamma unlinked", []))
    rid = run_id_of(drive(bank, "start"))

    gate = drive(bank, "phase", "execution", "--run-id", rid)
    assert gate.returncode == 1 and "Gamma unlinked" in gate.stderr
    assert "phase=planning" in drive(bank, "resume", "--run-id", rid).stdout

    n = plan(bank, "n", "src/n.py", qa="")
    goal(bank, ("Alpha ships", [f"plan: {a}"]), ("Big feature", [f"plan: {w}"]), ("Gamma unlinked", [f"plan: {n}"]))
    no_qa = drive(bank, "phase", "execution", "--run-id", rid, "--approve", "big")
    assert no_qa.returncode == 1 and n in no_qa.stderr and "Gamma unlinked" not in no_qa.stderr
    assert "phase=planning" in drive(bank, "resume", "--run-id", rid).stdout

    plan(bank, "n", "src/n.py", qa="on")
    opened = drive(bank, "phase", "execution", "--run-id", rid, "--approve", "big")
    assert opened.returncode == 0, opened.stderr
    assert "phase=execution" in drive(bank, "resume", "--run-id", rid).stdout


# ── Scenario 2 ──────────────────────────────────────────────────────────


def test_REQ_021__independent_items_go_to_team_and_dependent_ones_to_work(bank: Path) -> None:
    a, b = plan(bank, "a", "src/a.py"), plan(bank, "b", "src/b.py")
    c = plan(bank, "c", "src/c.py", deps=a)
    crits = (("A", [f"plan: {a}"]), ("B", [f"plan: {b}"]), ("C", [f"plan: {c}"]))
    goal(bank, *crits)
    rid = started(bank)
    printed = [nxt(bank, rid)]
    assert printed[0] == f"team {a} {b}"

    # Serial modes, each on its own goal file in the same bank; the host notice comes before
    # pipeline.yaml exists because `drive.parallel: false` outranks --host-serial.
    for name, flags in (("serial.md", ["--serial"]), ("host.md", ["--host-serial"]), ("pipe.md", [])):
        if name == "pipe.md":
            (bank / "pipeline.yaml").write_text("drive:\n  parallel: false\n")
        res = drive(bank, "start", "--goal", str(goal(bank, *crits, name=name)), *flags)
        notices = [line for line in res.stderr.splitlines() if "one dispatch at a time" in line]
        assert len(notices) == (1 if name == "host.md" else 0), res.stderr
        serial = run_id_of(res)
        assert drive(bank, "phase", "execution", "--run-id", serial).returncode == 0
        printed.append(nxt(bank, serial))
        assert printed[-1] == f"work {a}"
        assert status(bank, serial)["parallel"] is False

    close(bank, a)
    close(bank, b)
    ret(bank, rid, f"team {a} {b}", "--tokens", "10")
    printed.append(nxt(bank, rid))
    assert printed[-1] == f"work {c}"
    assert {line.split()[0] for line in printed} <= DISPATCH  # never implement / repair / review / judge


# ── Scenario 3 ──────────────────────────────────────────────────────────


def test_REQ_023__acceptance_counts_evidence_and_reports_unbacked_ticks(bank: Path) -> None:
    a = plan(bank, "a", "src/a.py")
    marker = bank.parent / "check-ran"
    path = goal(bank, ("Hand ticked", [f"plan: {a}"]), ("Check passes", ["check: true"]),
                ("Check runs", [f"check: touch {marker}"]))
    path.write_text(path.read_text().replace("- [ ] Hand ticked", "- [x] Hand ticked"))

    def accept(*flags: str) -> dict:
        res = sh("scripts/mb-goal-acceptance.sh", str(path), str(bank), *flags, bank=bank)
        assert res.returncode == 0, res.stderr
        return json.loads(res.stdout)

    out = accept()
    assert out["ok"] is False
    assert any("Hand ticked" in u for u in out["unbacked"]) and not any("Check" in u for u in out["unbacked"])
    assert [c.get("met") for c in out["criteria"]] == [False, True, True]

    accept("--tick")
    text = path.read_text()
    assert "- [ ] Hand ticked" in text and "- [x] Check passes" in text and "- [x] Check runs" in text

    marker.unlink()
    accept("--ticks-only")
    assert not marker.exists()

    plain = bank / "plain.md"
    plain.write_text("---\nid: G-1\n---\n# Goal\n\n## Acceptance criteria\n\n- [x] One\n- [ ] Two\n")
    res = sh("scripts/mb-goal-acceptance.sh", str(plain), str(bank), bank=bank)
    assert res.stdout == '{"name":"acceptance","ok":false,"findings":["Two"]}\n'


# ── Scenario 4 ──────────────────────────────────────────────────────────


def test_REQ_025__stalled_item_pivots_once_then_stops(bank: Path) -> None:
    a = plan(bank, "a", "src/a.py")
    goal(bank, ("A", [f"plan: {a}"]))
    rid = started(bank)
    assert nxt(bank, rid) == f"work {a}"
    ret(bank, rid, f"work {a}", "--tokens", "1", "--outcome", "stop_human:claim:1")
    assert nxt(bank, rid) == f"pivot {a}"
    ret(bank, rid, f"pivot {a}", "--tokens", "1")
    assert nxt(bank, rid) == f"work {a}"
    ret(bank, rid, f"work {a}", "--tokens", "1")
    assert nxt(bank, rid) == "stop_human stall"


# ── Scenario 5 ──────────────────────────────────────────────────────────


def test_REQ_026__token_usage_is_recorded_and_stops_the_run_early(bank: Path) -> None:
    a = plan(bank, "a", "src/a.py")
    goal(bank, ("A", [f"plan: {a}"]))
    rid = started(bank, "--budget", "100000")
    ret(bank, rid, f"work {a}", "--tokens", "40000")
    assert nxt(bank, rid) == f"pivot {a}"  # 40000 average < 60000 left: the stall rule decides
    ret(bank, rid, f"pivot {a}", "--tokens", "40000")
    spent = sh("scripts/mb-work-budget.sh", "status", "--run-id", rid, "--mb", str(bank), bank=bank)
    assert "spent=80000" in spent.stdout, spent.stdout + spent.stderr
    assert nxt(bank, rid) == "stop_budget"


# ── Scenario 6 ──────────────────────────────────────────────────────────


def test_REQ_028__resume_and_the_stop_gate_read_the_drive_file(bank: Path) -> None:
    a = plan(bank, "a", "src/a.py")
    goal(bank, ("A", [f"plan: {a}"]))
    r1 = started(bank, "--session", "S1")
    assert json.loads((bank / ".drive" / f"{r1}.json").read_text())["session"] == "S1"

    resumed = drive(bank, "resume")
    assert resumed.returncode == 0 and f"run_id={r1} " in resumed.stdout and "phase=execution" in resumed.stdout
    assert '"decision":"block"' in stop_event(bank, "S1").stdout.replace(" ", "")

    (bank / "goals").mkdir()
    r2 = started(bank, "--goal", str(goal(bank, ("B", [f"plan: {a}"]), name="goals/second.md")), "--session", "S2")
    listing = drive(bank, "resume")
    # REQ-029 and commands/drive.md: several live runs without an id → list and exit 2.
    assert listing.returncode == 2 and r1 in listing.stdout and r2 in listing.stdout
    anonymous = stop_event(bank, "")
    assert "decision" not in anonymous.stdout
    assert r1 in anonymous.stderr and r2 in anonymous.stderr, "no-session Stop with two live runs must warn"

    rec = sh("scripts/mb-drive-stop.sh", "record", "--bank", str(bank), "--run-id", r1,
             "--action", "stop_human stall", bank=bank)
    assert rec.returncode == 0, rec.stderr
    assert "decision" not in stop_event(bank, "S1").stdout

    items = status(bank, r1)["items"]
    assert [(i["path"], i["heading"]) for i in items] == [(a, "Stage 1: Build a")]


# ── Scenario 7 ──────────────────────────────────────────────────────────


def test_REQ_030__blocked_qa_is_retried_deferred_and_reported(bank: Path) -> None:
    a, b = plan(bank, "a", "src/a.py"), plan(bank, "b", "src/b.py")
    goal(bank, ("A", [f"plan: {a}"]), ("B", [f"plan: {b}"]))
    rid = started(bank, "--serial")
    assert nxt(bank, rid) == f"work {a}"
    ret(bank, rid, f"work {a}", "--tokens", "1", "--outcome", "qa-blocked:no-browser")
    assert nxt(bank, rid) == f"work {a}"
    ret(bank, rid, f"work {a}", "--tokens", "1", "--outcome", "qa-blocked:no-browser")
    assert nxt(bank, rid) == f"work {b}"
    close(bank, b)
    ret(bank, rid, f"work {b}", "--tokens", "1")
    assert nxt(bank, rid) == f"qa {a}"
    ret(bank, rid, f"qa {a}", "--tokens", "1", "--outcome", "qa-blocked:no-browser")
    assert nxt(bank, rid) == "stop_human qa-blocked:no-browser"
    assert [c["waiting_qa"] for c in status(bank, rid)["criteria"]] == [True, False]
    assert "- [x] B" in (bank / "goal.md").read_text()  # the closed item stays counted


# ── Scenario 8 ──────────────────────────────────────────────────────────


def test_REQ_032__final_qa_and_the_firewall_gate_success(bank: Path) -> None:
    (bank / "qa").mkdir()
    (bank / "qa" / "README.md").write_text("# QA target\n")
    (bank.parent / "flow-verify-stub.sh").write_text(
        '#!/usr/bin/env bash\necho "$*" >> "$FV_LOG"\n'
        'case "$FV_RC" in\n'
        '  1) echo \'{"checks":[{"name":"tests","status":"fail"},{"name":"lint","status":"pass"}]}\' ;;\n'
        '  2) echo \'{"checks":[{"name":"rules","status":"broke"}]}\' ;;\n'
        "  *) echo '{\"checks\":[]}' ;;\nesac\nexit \"$FV_RC\"\n")
    a = plan(bank, "a", "src/a.py", qa="on", done=True)
    log = bank.parent / "fv.log"
    expected = {"0": "stop_success", "1": "stop_human flow-red:tests", "2": "stop_human check-broke:rules"}
    for n, (rc, action) in enumerate(expected.items()):
        rid = started(bank, "--goal", str(goal(bank, ("A", [f"plan: {a}"]), name=f"g{n}.md")))
        assert nxt(bank, rid, FV_RC=rc) == "final_qa"
        assert not log.exists() or len(log.read_text().splitlines()) == n  # no firewall before the final QA
        ret(bank, rid, "final_qa", "--tokens", "1")
        assert nxt(bank, rid, FV_RC=rc) == action
        assert log.read_text().splitlines()[n].split() == [str(bank), "--skip", "acceptance"]
    assert len(log.read_text().splitlines()) == 3


# ── Scenario 9 ──────────────────────────────────────────────────────────


def fences(text: str) -> list[str]:
    return [m.replace("\\\n", " ") for m in re.findall(r"```(?:bash|text|sh)?\n(.*?)```", text, re.S)]


def test_REQ_046__drive_commands_resolve_paths_and_match_the_scripts() -> None:
    drive_md = (ROOT / "commands/drive.md").read_text()
    mb_md = (ROOT / "commands/mb.md").read_text()
    drive_section = mb_md.split("### drive", 1)[1].split("\n### ", 1)[0]
    agents_line = next(line for line in (ROOT / "adapters/_lib_agents_md.sh").read_text().splitlines()
                       if "`/mb drive`" in line)
    blocks = fences(drive_md) + fences((ROOT / "commands/goal.md").read_text()) + fences(drive_section)
    for text in [*blocks, agents_line]:
        assert '$(dirname "$0")' not in text
        assert not re.search(r"\bBANK=\.memory-bank\b", text)

    usage = subprocess.run(["bash", str(SCRIPTS / "mb-drive.sh"), "--help"], capture_output=True, text=True,
                           check=True).stdout
    subs = set(re.findall(r"mb-drive\.sh (\w+)", usage))
    script_flags = set(re.findall(r"--[a-z][a-z-]+", usage))
    for text in [*blocks, agents_line]:
        for line in text.splitlines():
            m = re.search(r"mb-drive\.sh[\"`]? (\w+)(.*)", line)
            if m:
                assert m[1] in subs, line
                assert set(re.findall(r"--[a-z][a-z-]+", m[2])) <= script_flags, line
    for synopsis in re.findall(r"/mb drive (\[--.*)", drive_md + mb_md):
        for flag in re.findall(r"--[a-z][a-z-]+", synopsis):
            assert flag in script_flags or flag.lstrip("-") in subs, flag

    printed = {seg.split()[0] for seg in usage.split("Actions printed by `next`:")[1].split("Drive never")[0]
               .replace("\n", " ").strip(" .").split("·")}
    table = re.findall(r"^\| `([a-z_]+)[^`]*` \|", drive_md, re.M)
    row = re.search(r"prints ONE action \(([^)]*)\)", mb_md)
    assert row is not None and table
    documented = set(table) | {t.rstrip("*") for t in re.findall(r"`([a-z_*]+)`", row[1])}
    assert {d for d in documented if not d.endswith("_")} <= printed, documented - printed
    stop_vocab = (SCRIPTS / "mb-drive-stop.sh").read_text().split("Stop-reason vocabulary", 1)[1].split("--action", 1)[0]
    why = re.search(r"`stop_human <why>` \| [^|]*?: (.*?) \(§6\)", drive_md)
    assert why is not None
    for reason in re.findall(r"`([a-z-]+)", why[1]):
        assert f"human:{reason}" in stop_vocab, reason
    for action in re.findall(r"stop_\w+", agents_line):
        assert action in printed, action

    drive_files = sorted(str(p.relative_to(ROOT)) for p in [*SCRIPTS.glob("*drive*"), *(ROOT / "hooks").glob("*drive*")])
    for rel in drive_files:
        assert len((ROOT / rel).read_text().splitlines()) < 400, rel
    assert set(drive_files) <= set(test_s2_file_size_contract.ZONE_FILES), \
        set(drive_files) - set(test_s2_file_size_contract.ZONE_FILES)


# ── Scenario 10 ─────────────────────────────────────────────────────────


def test_REQ_053__final_qa_bugs_go_through_a_fix_plan(bank: Path) -> None:
    qa_bank(bank, max_cycles=2)
    goal(bank, ("Checkout", [f"plan: {plan(bank, 'checkout', 'src/a.py', qa='on', done=True)}"]))
    rid = started(bank)
    case = "qa/test_cases/checkout/pay.md"

    def final_qa_leaves_a_bug(cycle: int) -> str:
        assert nxt(bank, rid) == "final_qa"
        selection = subprocess.run([sys.executable, str(SCRIPTS / "mb_drive_qa.py"), "selection", "--bank",
                                    str(bank), "--run-id", rid], capture_output=True, text=True, check=True)
        qa_run = selection.stdout.split()[0]
        assert qa_run == f"{rid}-final{cycle}"
        bid = bug(bank, "major", f"Pay returns 500 (cycle {cycle})", qa_run, case)
        ret(bank, rid, "final_qa", "--tokens", "1")
        return bid

    bid = final_qa_leaves_a_bug(0)
    [fix] = fix_plans(bank)
    text = fix.read_text()
    assert "topic: checkout" in text and "qa: on" in text and bid in text
    rel = f"plans/{fix.name}"
    assert nxt(bank, rid) == f"work {rel}"
    close(bank, rel)
    ret(bank, rid, f"work {rel}", "--tokens", "1")

    # REQ-053/054: the final QA re-runs at most qa.max_cycles (2) times; red after the 2nd fix cycle.
    final_qa_leaves_a_bug(1)
    second = f"plans/{fix_plans(bank)[1].name}"
    assert nxt(bank, rid) == f"work {second}"
    close(bank, second)
    ret(bank, rid, f"work {second}", "--tokens", "1")
    final_qa_leaves_a_bug(2)
    assert len(fix_plans(bank)) == 2
    assert nxt(bank, rid) == "stop_human qa-red"


# ── Scenario 11 ─────────────────────────────────────────────────────────


def test_REQ_051__two_drives_in_one_bank_stay_apart(bank: Path) -> None:
    p = plan(bank, "p", "src/p.py")
    goal(bank, ("P", [f"plan: {p}"]))
    r1 = started(bank)

    again = drive(bank, "start")
    assert again.returncode == 1 and r1 in again.stderr
    assert "--resume" in again.stderr and "--goal" in again.stderr

    claim = sh("scripts/mb-work-state.sh", "init", p, "1", "--mb", str(bank), "--run-id", "foreign1", bank=bank)
    assert claim.returncode == 0, claim.stderr
    (bank / "goals").mkdir()
    r2 = started(bank, "--goal", str(goal(bank, ("P too", [f"plan: {p}"]), name="goals/second.md")))
    assert r2 != r1

    for _ in range(3):
        assert nxt(bank, r2) == f"wait {p}"
        ret(bank, r2, f"wait {p}", "--tokens", "1")
        assert status(bank, r2)["items"][0]["stalls"] == 0
    assert nxt(bank, r2) == "stop_human owned-elsewhere:foreign1"
