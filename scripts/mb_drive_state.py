#!/usr/bin/env python3
"""Drive run files and the subcommands that change them (drive-autopilot design C2, C3.1, C3.4).

`mb_drive_state.py <start|resume|returned|stop> --bank B [flags]` — flags as in scripts/mb-drive.sh;
`stop --reason WHY` is called by scripts/mb-drive-stop.sh. One JSON file per run at
<bank>/.drive/<run_id>.json (`mbw_drive_slot`), written only by its run (temp file + os.replace).
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
from typing import NoReturn

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from mb_goal_evidence import plan_closed  # noqa: E402
from mb_pipeline_minimal_yaml import minimal_pipeline_load, parse_nested_block  # noqa: E402

DISPATCH = {"work", "team", "qa", "pivot", "wait", "final_qa"}
HOST_NOTICE = "[drive] this host runs one dispatch at a time — items run serially through /mb work"


def item_record() -> dict:
    return {"stalls": 0, "pivoted": False, "qa_blocked": 0, "deferred": False, "qa_retried": False,
            "qa_reason": "", "work_runs": [], "fix": False}


def die(msg: str, code: int = 1) -> NoReturn:
    print(f"[drive] {msg}", file=sys.stderr)
    sys.exit(code)


def sh(script: str, *args: str, parallel: bool = False) -> subprocess.CompletedProcess:
    env = {**os.environ, "MB_WORK_PARALLEL": "1"} if parallel else None
    return subprocess.run(["bash", str(HERE / script), *args], capture_output=True, text=True,
                          stdin=subprocess.DEVNULL, env=env, check=False)



def run_file(bank: pathlib.Path, run_id: str) -> pathlib.Path:
    """Same path as `mbw_drive_slot <bank> <run_id>` (scripts/mb-work-slots.sh)."""
    return bank / ".drive" / f"{run_id}.json"


def save(st: dict) -> None:
    path = run_file(pathlib.Path(st["bank"]), st["run_id"])
    path.parent.mkdir(parents=True, exist_ok=True)
    st["updated"] = datetime.datetime.now(datetime.UTC).isoformat()
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{st['run_id']}.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(st, indent=1) + "\n")
    os.replace(tmp, path)


def live_runs(bank: pathlib.Path) -> list[dict]:
    runs = []
    for path in sorted((bank / ".drive").glob("*.json")):
        try:
            st = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        # A file without a live phase (stopped, or a pre-autopilot drive-state slot) is not a run.
        if isinstance(st, dict) and st.get("phase") in ("planning", "execution"):
            runs.append(st)
    return runs


def select(bank: pathlib.Path, run_id: str | None) -> dict:
    if run_id:
        try:
            st = json.loads(run_file(bank, run_id).read_text(encoding="utf-8"))
        except OSError:
            die(f"no drive run {run_id} in {bank}")
        except ValueError:
            st = None
        if not isinstance(st, dict) or "phase" not in st:
            die(f"drive run file of {run_id} is unreadable")
        return st
    runs = live_runs(bank)
    if len(runs) == 1:
        return runs[0]
    if not runs:
        die("no live drive run — start one with /mb drive")
    for st in runs:
        print(f"{st['run_id']} {st['goal']} {st['phase']}")
    die("several live drive runs — pass --run-id (or /mb drive --resume <run_id>)", 2)



def pipeline(bank: pathlib.Path) -> dict:
    """The `drive` and `qa` blocks of the bank's effective pipeline.yaml (inline or block form)."""
    path = sh("mb-pipeline.sh", "path", str(bank)).stdout.strip()
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
        cfg = minimal_pipeline_load(text)
    except (OSError, ValueError):
        return {}
    blocks = {b: cfg.get(b) if isinstance(cfg.get(b), dict) else parse_nested_block(text.splitlines(), b)
              for b in ("drive", "qa")}
    return {b: v for b, v in blocks.items() if isinstance(v, dict)}


def budget_of(st: dict) -> dict | None:
    """{total, spent, exceeded} of the run's budget slot; None without one; ValueError when unreadable."""
    args = ("--run-id", st["run_id"], "--mb", st["bank"])
    res = sh("mb-work-budget.sh", "status", *args, parallel=True)
    if res.returncode == 1 and "no active budget" in res.stderr:
        return None
    m = re.search(r"total=(\d+) spent=(\d+)", res.stdout)
    if res.returncode != 0 or not m:
        raise ValueError("budget status")
    check = sh("mb-work-budget.sh", "check", *args, parallel=True).returncode
    if check not in (0, 1, 2):
        raise ValueError("budget check")
    return {"total": int(m[1]), "spent": int(m[2]), "exceeded": check == 2}


def cmd_start(a: argparse.Namespace, bank: pathlib.Path) -> None:
    if a.goal:
        goal = pathlib.Path(a.goal) if os.path.isabs(a.goal) else bank / a.goal
        if not goal.is_file():
            die(f"goal file not found: {a.goal}")
    else:
        goal = bank / "goal.md"
        if not goal.is_file():
            shutil.copy(HERE.parent / "templates" / "goal.md", goal)
            die(f"scaffolded {goal} — write its acceptance criteria, then start /mb drive again")
    goal = goal.resolve()
    valid = sh("mb-goal-validate.sh", str(goal), str(bank))
    if valid.returncode != 0:
        sys.stderr.write(valid.stdout + valid.stderr)
        die(f"goal {goal} is not valid")
    for st in live_runs(bank):
        if pathlib.Path(st.get("goal", "")).resolve() == goal:
            die(f"goal {goal} is already driven by run {st['run_id']} — resume it with /mb drive --resume "
                f"{st['run_id']}, or start on another goal file with --goal <path>")
    run_id = sh("mb-work-state.sh", "new-run-id").stdout.strip()
    if not run_id:
        die("mb-work-state.sh new-run-id printed no id")
    drive_cfg = pipeline(bank).get("drive")
    parallel, reason = True, "default"
    if a.serial:
        parallel, reason = False, "serial-flag"
    elif isinstance(drive_cfg, dict) and drive_cfg.get("parallel") is False:
        parallel, reason = False, "pipeline"
    elif a.host_serial:
        parallel, reason = False, "host"
        print(HOST_NOTICE, file=sys.stderr)
    if a.budget:
        res = sh("mb-work-budget.sh", "init", str(a.budget), "--run-id", run_id, "--mb", str(bank), parallel=True)
        if res.returncode != 0:
            die(f"budget init failed: {res.stderr.strip()}")
    now = datetime.datetime.now(datetime.UTC).isoformat()
    session = a.session or os.environ.get("CLAUDE_CODE_SESSION_ID") or os.environ.get("MB_SESSION_ID") or None
    save({"run_id": run_id, "bank": str(bank), "goal": str(goal), "session": session, "phase": "planning",
          "parallel": parallel, "parallel_reason": reason, "approved": [], "steps": 0, "waits": 0, "items": {},
          "final_qa": "pending", "final_qa_blocked": 0, "final_qa_cycle": 0, "stop_reason": "",
          "started": now})
    print(run_id)


def account(rec: dict, outcome: str, kind: str, closed: bool) -> None:
    """Per-item stall and QA accounting of a returned work/team/qa run (design C3.4 step 3)."""
    if closed:
        rec["stalls"] = 0
    elif outcome == "owned-elsewhere":
        return
    elif outcome.startswith("qa-blocked:"):
        rec["qa_blocked"] += 1
        rec["qa_reason"] = outcome.split(":", 1)[1]
        rec["deferred"] = rec["qa_blocked"] >= 2
        if kind == "qa":
            rec["qa_retried"] = True
    else:
        rec["stalls"] += 1


def cmd_returned(a: argparse.Namespace, bank: pathlib.Path) -> None:
    st = select(bank, a.run_id)
    if st["phase"] != "execution":
        die(f"run {st['run_id']} is in phase {st['phase']} — nothing was dispatched", 2)
    kind, *paths = a.action.split()
    if kind not in DISPATCH:
        die(f"returned takes a dispatch action, not '{a.action}'", 2)
    outcomes = {}
    for pair in a.item_outcome:
        plan, sep, outcome = pair.partition("=")
        if not sep:
            die(f"--item-outcome takes <plan>=<outcome>, not '{pair}'", 2)
        outcomes[plan] = outcome
    if a.tokens is None:
        print("[drive] returned without --tokens — the drive budget cannot count this step", file=sys.stderr)
    else:
        res = sh("mb-work-budget.sh", "add", str(a.tokens), "--run-id", st["run_id"], "--mb", str(bank),
                 parallel=True)
        if res.returncode != 0 and "no active budget" not in res.stderr:
            print(f"[drive] budget add failed: {res.stderr.strip()}", file=sys.stderr)
    st["steps"] += 1
    st["waits"] = st["waits"] + 1 if kind == "wait" else 0
    for path in paths:
        rec = {**item_record(), **st["items"].get(path, {})}
        rec["work_runs"] = rec["work_runs"] + [w for w in a.work_run if w not in rec["work_runs"]]
        if kind in ("work", "team", "qa"):
            account(rec, outcomes.get(path, a.outcome), kind, plan_closed(path, bank)[0])
        elif kind == "pivot":
            rec["pivoted"] = True
        st["items"][path] = rec
    if kind == "final_qa":
        from mb_drive_qa import final_qa_returned  # C3.6; lazy: mb_drive_qa imports this module

        final_qa_returned(st, bank, a.outcome)
    save(st)
    sh("mb-goal-acceptance.sh", st["goal"], str(bank), "--tick")


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="mb-drive.sh")
    sub = ap.add_subparsers(dest="cmd", required=True)
    start = sub.add_parser("start")
    start.add_argument("--goal")
    start.add_argument("--budget", type=int)
    start.add_argument("--serial", action="store_true")
    start.add_argument("--host-serial", action="store_true")
    start.add_argument("--session")
    ret = sub.add_parser("returned")
    ret.add_argument("--action", required=True)
    ret.add_argument("--tokens", type=int)
    ret.add_argument("--outcome", default="ok")
    ret.add_argument("--item-outcome", action="append", default=[])
    ret.add_argument("--work-run", action="append", default=[])
    stop = sub.add_parser("stop")
    stop.add_argument("--reason", required=True)
    resume = sub.add_parser("resume")
    for p in (start, ret, stop, resume):
        p.add_argument("--bank", required=True)
        if p is not start:
            p.add_argument("--run-id")
    a = ap.parse_args(argv)
    bank = pathlib.Path(a.bank).resolve()
    if not bank.is_dir():
        die(f"no Memory Bank at {a.bank}")
    if a.cmd == "start":
        cmd_start(a, bank)
    elif a.cmd == "returned":
        cmd_returned(a, bank)
    else:
        st = select(bank, a.run_id)
        if a.cmd == "stop":
            st["phase"], st["stop_reason"] = "stopped", a.reason
            save(st)
            print(run_file(bank, st["run_id"]))
        else:
            print(f"run_id={st['run_id']} goal={st['goal']} phase={st['phase']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
