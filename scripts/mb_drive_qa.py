#!/usr/bin/env python3
"""Drive's final QA and its fix cycle (drive-autopilot design C3.6, REQ-032/053/054).

`mb_drive_qa.py selection --bank B [--run-id R]` prints `<final run id> @<topic>…`: the run id of the
next final QA and one `@<topic>` per plan of the run, so one drive's final QA runs only its own cases.
`final_qa_returned` is the one call site of the gate (from `mb-drive.sh returned --action final_qa`):
blocking bugs become ordinary fix plans that `/mb work` executes; drive adds no fix chain and no check.
"""

from __future__ import annotations

import argparse
import datetime
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from mb_drive_state import pipeline, select, sh  # noqa: E402
from mb_work_plan_wrapper import fm_value, frontmatter  # noqa: E402

CASE_RE = re.compile(r"^qa/test_cases/([^/]+)/")
SEVERITY = {"blocker": "critical", "major": "major", "medium": "medium", "minor": "low"}
RULE = ("Regression test first when the defect is reachable from tests; never edit `<bank>/qa/` "
        "(`/mb work` §5c2). The regression test for each bug carries `mb:case reg-<bug id lowercased>` "
        "in a comment.")


def final_run(st: dict) -> str:
    return f"{st['run_id']}-final{st['final_qa_cycle']}"


def topics(st: dict) -> list[str]:
    """`topic:` of each plan of the run (wrapper: its spec topic), in item order, deduplicated."""
    from mb_drive_decide import goal_plans, plan_file

    bank = pathlib.Path(st["bank"])
    out: list[str] = []
    for rel in [*goal_plans(pathlib.Path(st["goal"])), *(p for p, r in st["items"].items() if r.get("fix"))]:
        path = plan_file(bank, rel)
        fm = (frontmatter(str(path)) or "") if path else ""
        spec = fm_value(fm, "linked_spec")
        topic = pathlib.PurePath(str(spec)).name if spec else fm_value(fm, "topic")
        if topic and str(topic) not in out:
            out.append(str(topic))
    return out


def bug_bodies(bank: pathlib.Path) -> dict[str, list[str]]:
    """BUG-NNN → its body lines in `<bank>/qa/bugs.md`."""
    bodies: dict[str, list[str]] = {}
    current: list[str] | None = None
    for line in (bank / "qa" / "bugs.md").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^### (BUG-\d+) — ", line)
        if line.startswith("### "):
            current = bodies.setdefault(m[1], []) if m else None
        elif current is not None and line.strip():
            current.append(line.strip())
    return bodies


def blocking(bank: pathlib.Path, run: str, gate: dict) -> list[dict]:
    """Open bugs of the run at a severity the gate bounds: {id, title, sev, case}."""
    res = sh("mb-qa-bug.sh", "--mb", str(bank), "list", "--json", "--open", "--run", run)
    out = []
    for issue in json.loads(res.stdout)["issues"]:
        sev = SEVERITY[issue["severity"]]
        if sev in gate:
            bid, title = issue["message"].split(" ", 1)
            out.append({"id": bid, "title": title, "sev": sev, "case": issue["file"]})
    return out


def write_plan(st: dict, run: str, topic: str, qa: str, bugs: list[dict], bodies: dict[str, list[str]]) -> str:
    bank, run8, cycle = pathlib.Path(st["bank"]), st["run_id"][:8], st["final_qa_cycle"]
    date = datetime.date.today().isoformat()
    rel = f"plans/{date}_fix_drive-qa-{topic}-{run8}-{cycle}.md"
    quoted = "\n\n".join(f"> **{b['id']} — {b['title']}** ({b['sev']})\n" +
                         "\n".join(f"> {line}" for line in bodies.get(b["id"], [])) for b in bugs)
    dod = "\n".join(f"- [ ] {b['id']} fixed — regression test carries mb:case reg-{b['id'].lower()}; "
                    f"mb-qa-bug.sh set {b['id']} fixed" for b in bugs)
    path = bank / rel
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            f"---\ntopic: {topic}\nqa: {qa}\ndrive_run: {st['run_id']}\n---\n"
            f"# Plan: fix final-QA bugs of {topic} (drive {run8}, cycle {cycle})\n\n"
            f"<!-- mb-stage:1 -->\n### Stage 1: Fix final-QA bugs\n\n"
            f"Final QA run `{run}` found these blocking bugs; their evidence paths are relative to "
            f"`<bank>/qa/runs/{run}/`.\n\n{quoted}\n\n{RULE}\n\n"
            f"**DoD:**\n{dod}\n<!-- /mb-stage:1 -->\n", encoding="utf-8")
    return rel


def final_qa_returned(st: dict, bank: pathlib.Path, outcome: str) -> None:
    """Blocked twice → `blocked:<r>`; gate green → `pass`; red → fix plans as items, or `red` past
    `qa.max_cycles`."""
    if outcome.startswith("qa-blocked:"):
        st["final_qa_blocked"] += 1
        if st["final_qa_blocked"] >= 2:
            st["final_qa"] = "blocked:" + outcome.split(":", 1)[1]
        return
    qa = pipeline(bank).get("qa") or {}
    gate = qa.get("gate") if isinstance(qa.get("gate"), dict) else {"critical": 0, "major": 0}
    run = final_run(st)
    if sh("mb-qa-bug.sh", "--mb", str(bank), "gate", "--run", run, "--gate", json.dumps(gate)).returncode == 0:
        st["final_qa"] = "pass"
        return
    st["final_qa_cycle"] += 1
    max_cycles = qa.get("max_cycles")
    if st["final_qa_cycle"] > (max_cycles if isinstance(max_cycles, int) else 3):
        st["final_qa"] = "red"
        return
    groups: dict[tuple[str, str], list[dict]] = {}
    for b in blocking(bank, run, gate):
        m = CASE_RE.match(b["case"])
        key = (m[1], "on") if m and (bank / b["case"]).is_file() else (f"drive-{st['run_id'][:8]}", "off — no case")
        groups.setdefault(key, []).append(b)
    bodies = bug_bodies(bank) if groups else {}
    for (topic, flag), bugs in groups.items():
        rel = write_plan(st, run, topic, flag, bugs, bodies)
        st["items"][rel] = {**st["items"].get(rel, {}), "fix": True}
    st["final_qa"] = "pending"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="mb_drive_qa.py")
    ap.add_argument("cmd", choices=["selection"])
    ap.add_argument("--bank", required=True)
    ap.add_argument("--run-id")
    a = ap.parse_args(argv)
    st = select(pathlib.Path(a.bank).resolve(), a.run_id)
    print(" ".join([final_run(st), *(f"@{t}" for t in topics(st))]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
