#!/usr/bin/env python3
"""Drive's planning gate, next action and status (drive-autopilot design C3.2, C3.3, C3.5).

`mb_drive_decide.py <next|status|phase execution> --bank B [--run-id R] [--approve t1,t2]`
(through scripts/mb-drive.sh). Items are the distinct `plan:` links of the run's goal, then its fix
plans. `decide(facts)` is pure: the fifteen rules of C3.3, first match wins. Rules 1-12 read files and
the work-claim listing only; criterion checks run from rule 13, the firewall
(`mb-flow-verify.sh --skip acceptance`) only at rule 15, and `status` runs neither.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mb_goal_evidence as ev  # noqa: E402
from mb_drive_state import budget_of, die, item_record, save, select, sh  # noqa: E402
from mb_work_items import _work_item_to_dict  # noqa: E402
from mb_work_plan_wrapper import fm_value, frontmatter  # noqa: E402
from mb_work_waves import assign_waves, declared_files  # noqa: E402

STATUS_ITEM_KEYS = ("path", "heading", "closed", "deps", "files", "owned_by", "work_runs", "stalls",
                    "pivoted", "qa_blocked", "deferred", "fix")


def goal_plans(goal: pathlib.Path) -> dict[str, int]:
    """Distinct `plan:` links of the goal in goal order → the first criterion number linking each."""
    plans: dict[str, int] = {}
    for n, crit in enumerate(ev.parse_goal(goal.read_text(encoding="utf-8").splitlines()), 1):
        for kind, value in crit["links"]:
            if kind == "plan":
                plans.setdefault(value, n)
    return plans


def plan_file(bank: pathlib.Path, rel: str) -> pathlib.Path | None:
    for path in (bank / rel, bank / "plans" / "done" / pathlib.Path(rel).name):
        if path.is_file():
            return path
    return None


def deps_of(fm: str, items, bank: pathlib.Path) -> list[str]:
    """`depends_on:` entries as item paths; one that is no item and no closed plan stays (never ready)."""
    deps = []
    for raw in str(fm_value(fm, "depends_on") or "").strip().strip("[]").split(","):
        dep = raw.strip().strip("\"'")
        names = [dep, dep if dep.startswith("plans/") else f"plans/{dep}"]
        names += [f"{n}.md" for n in names if not n.endswith(".md")]
        hit = next((n for n in names if n in items), None)
        if dep and (hit or not any(ev.plan_closed(n, bank)[0] for n in names)):
            deps.append(hit or dep)
    return deps


def planning_gaps(st: dict, bank: pathlib.Path) -> list[str]:
    """One line per reason the run cannot enter execution yet (design C3.2)."""
    lines = pathlib.Path(st["goal"]).read_text(encoding="utf-8").splitlines()
    gaps = [f"`{ln.strip()[2:]}` — link the spec through its wrapper plan (plan: plans/<wrapper>.md)"
            for ln in lines if re.match(r"^\s+-\s+spec:", ln)]
    gaps += [f"criterion {n} '{c['label']}' has no plan: or check: link"
             for n, c in enumerate(ev.parse_goal(lines), 1) if not c["links"]]
    plans = goal_plans(pathlib.Path(st["goal"]))
    for rel in plans:
        path = plan_file(bank, rel)
        if path is None:
            gaps.append(f"plan: {rel} resolves to no file")
            continue
        fm = frontmatter(str(path)) or ""
        if fm_value(fm, "qa") is None:
            gaps.append(f"{rel} declares no qa: line — re-plan it with --tier or add `qa: on|off — <reason>`")
        spec = fm_value(fm, "linked_spec")
        if spec:
            topic = pathlib.PurePath(str(spec)).name
            req = bank / str(spec) / "requirements.md"
            status = fm_value(frontmatter(str(req)) or "", "status") if req.is_file() else None
            if status != "ready" and topic not in st["approved"]:
                gaps.append(f"{rel}: spec {topic} is not status: ready — approve it with --approve {topic}")
        gaps += [f"{rel}: depends_on {dep} names a plan neither linked nor closed"
                 for dep in deps_of(fm, plans, bank) if dep not in plans]
    return gaps


def cmd_phase(st: dict, approve: str | None) -> int:
    if st["phase"] == "stopped":
        die(f"run {st['run_id']} stopped: {st['stop_reason']}")
    st["approved"] = sorted(set(st["approved"]) | {t.strip() for t in (approve or "").split(",") if t.strip()})
    try:
        gaps = planning_gaps(st, pathlib.Path(st["bank"]))
    except OSError as exc:
        gaps = [f"goal unreadable: {exc}"]
    if not gaps:
        st["phase"] = "execution"
    save(st)
    for gap in gaps:
        print(f"[drive] {gap}", file=sys.stderr)
    return 1 if gaps else 0


def item_facts(bank: pathlib.Path, rel: str, crit: int, rec: dict, items: dict) -> dict:
    closed, problem = ev.plan_closed(rel, bank)
    path = plan_file(bank, rel)
    if problem or path is None:
        raise ValueError(problem or rel)
    pending = [w for w in map(_work_item_to_dict, ev._plan_items(path, bank)) if w["status"] != "done"]
    fm = frontmatter(str(path)) or ""
    return {**item_record(), **rec, "path": rel, "crit": crit, "closed": closed, "deps": deps_of(fm, items, bank),
            "heading": pending[0]["heading"] if pending else "", "owned_by": None,
            "files": sorted(set().union(*map(declared_files, pending))), "qa_on": fm_value(fm, "qa") == "on"}


def mark_owned(bank: pathlib.Path, items: list[dict]) -> None:
    """Set `owned_by` from live /mb work claims on an item's plan that this run did not record."""
    res = sh("mb-work-state.sh", "status", "--all", "--mb", str(bank), parallel=True)
    claims = json.loads(res.stdout)
    if res.returncode != 0 or not isinstance(claims, list):
        raise ValueError("claims")
    for claim in claims:
        if claim.get("phase") == "done":
            continue
        sources = [s for s in (str(claim.get("source", "")).split("#")[0], claim.get("source_path")) if s]
        for it in items:
            target = (bank / it["path"]).resolve()
            if not it["owned_by"] and claim.get("run_id") not in it["work_runs"] and \
                    any((bank / s).resolve() == target for s in sources):
                it["owned_by"] = claim.get("run_id")


def first_unmet(crits: list[dict], bank: pathlib.Path) -> int | None:
    root = ev.project_root(bank)
    return next((n for n, c in enumerate(crits, 1) if not ev.evaluate(c, bank, root)[0]["met"]), None)


def firewall(bank: pathlib.Path) -> tuple[int, str]:
    binary = os.environ.get("MB_FLOW_VERIFY_BIN") or str(HERE / "mb-flow-verify.sh")
    res = subprocess.run(["bash", binary, str(bank), "--skip", "acceptance"], capture_output=True,
                         text=True, stdin=subprocess.DEVNULL, check=False)
    try:
        checks = [c for c in json.loads(res.stdout).get("checks") or [] if isinstance(c, dict)]
    except (ValueError, AttributeError):
        checks = []
    if res.returncode == 1:
        return 1, ",".join(c.get("name", "?") for c in checks if c.get("status") == "fail")
    broke = [c.get("name", "?") for c in checks if c.get("status") == "broke"]
    return res.returncode, broke[0] if broke else "mb-flow-verify"


def gather(st: dict, cheap: bool) -> dict:
    """Facts for decide(); `cheap` (status) runs no check and no firewall."""
    f = {k: st[k] for k in ("run_id", "phase", "stop_reason", "steps", "waits", "parallel", "final_qa")}
    f.update(broken=None, budget=None, items=[], crits=[], qa_on=False, unmet=lambda: None,
             firewall=lambda: None)
    if st["phase"] != "execution" and not cheap:  # status still lists the items of a stopped run
        return f
    bank = pathlib.Path(st["bank"])
    try:
        raw = pathlib.Path(st["goal"]).read_bytes()
        f["crits"] = ev.parse_goal(raw.decode("utf-8").splitlines())
        items = goal_plans(pathlib.Path(st["goal"]))
    except OSError:
        return {**f, "broken": "acceptance"}
    items.update({p: 0 for p, rec in st["items"].items() if rec.get("fix") and p not in items})
    try:
        f["items"] = [item_facts(bank, p, n, st["items"].get(p, {}), items) for p, n in items.items()]
    except (OSError, ValueError):
        return {**f, "broken": "items"}
    try:
        mark_owned(bank, f["items"])
    except (ValueError, AttributeError):
        return {**f, "broken": "claims"}
    try:
        f["budget"] = budget_of(st)
    except ValueError:
        return {**f, "broken": "budget"}
    f["qa_on"] = any(i["qa_on"] for i in f["items"]) and (bank / "qa" / "README.md").is_file()
    f["unmet"] = lambda: next((n for n, c in enumerate(f["crits"], 1) if not c["ticked"]), None)
    if not cheap:
        f["firewall"] = lambda: firewall(bank)
        if st.get("ticked_sha") != hashlib.sha256(raw).hexdigest():  # ticks of the last `returned` are stale
            f["unmet"] = lambda: first_unmet(f["crits"], bank)
    return f


def ready_items(items: list[dict]) -> list[dict]:
    closed = {i["path"] for i in items if i["closed"]}
    return [i for i in items if not i["closed"] and not i["deferred"] and not i["owned_by"]
            and all(d in closed for d in i["deps"])]


def decide(f: dict) -> tuple[str, int]:
    """The next action line and the exit code (design C3.3, first match wins)."""
    if f["phase"] == "planning":
        return "plan", 0
    if f["phase"] == "stopped":
        return f"[drive] run {f['run_id']} stopped: {f['stop_reason']}", 1
    if f["broken"]:
        return f"stop_human check-broke:{f['broken']}", 0
    b = f["budget"]
    if b and (b["exceeded"] or (f["steps"] > 0 and b["spent"] / f["steps"] > b["total"] - b["spent"])):
        return "stop_budget", 0
    items = f["items"]
    if any(i["stalls"] >= 2 for i in items):
        return "stop_human stall", 0
    stalled = [i for i in items if i["stalls"] == 1 and not i["pivoted"]]
    if stalled:
        return f"pivot {stalled[0]['path']}", 0
    ready = ready_items(items)
    if ready and f["parallel"]:
        waves = assign_waves([{"item_no": n, "source": "plan", "body": "**Files:** " + ", ".join(i["files"])}
                              for n, i in enumerate(ready, 1)])
        first = [i["path"] for i, wave in zip(ready, waves, strict=True) if wave == 1]
        if len(first) >= 2:
            return "team " + " ".join(first), 0
    if ready:
        return f"work {ready[0]['path']}", 0
    still_open = [i for i in items if not i["closed"]]
    owned = [i for i in still_open if i["owned_by"]]
    if owned:
        if f["waits"] < 3:
            return "wait " + " ".join(i["path"] for i in owned), 0
        return f"stop_human owned-elsewhere:{owned[0]['owned_by']}", 0
    deferred = [i for i in still_open if i["deferred"]]
    retry = [i for i in deferred if not i["qa_retried"]]
    if retry:
        return f"qa {retry[0]['path']}", 0
    if deferred:
        return f"stop_human qa-blocked:{deferred[0]['qa_reason']}", 0
    unmet = still_open[0]["crit"] if still_open else f["unmet"]()
    if unmet is not None:
        return f"stop_human acceptance-red:{unmet}", 0
    if f["final_qa"] == "pending" and f["qa_on"]:
        return "final_qa", 0
    if f["final_qa"].startswith("blocked:"):
        return f"stop_human qa-blocked:{f['final_qa'].split(':', 1)[1]}", 0
    if f["final_qa"] == "red":
        return "stop_human qa-red", 0
    gate = f["firewall"]()
    if gate is None:
        return "firewall", 0
    rc, names = gate
    if rc == 0:
        return "stop_success", 0
    return (f"stop_human flow-red:{names}" if rc == 1 else f"stop_human check-broke:{names}"), 0


def status(st: dict) -> dict:
    f = gather(st, cheap=True)
    closed = {i["path"]: i["closed"] for i in f["items"]}
    deferred = {i["path"] for i in f["items"] if i["deferred"] and not i["closed"]}
    ready = {i["path"] for i in ready_items(f["items"])}

    def plans(crit: dict) -> list[str]:
        return [v for k, v in crit["links"] if k == "plan"]

    out = {k: st.get(k) for k in ("run_id", "goal", "session", "phase", "parallel", "parallel_reason",
                                   "steps", "waits", "final_qa", "final_qa_cycle")}
    out["budget"] = {k: f["budget"][k] for k in ("total", "spent")} if f["budget"] else None
    out["items"] = [{**{k: i[k] for k in STATUS_ITEM_KEYS}, "ready": i["path"] in ready} for i in f["items"]]
    out["criteria"] = [{"n": n, "label": c["label"], "met": c["ticked"],
                        "waiting_qa": any(p in deferred for p in plans(c))} for n, c in enumerate(f["crits"], 1)]
    out["unbacked"] = [c["label"] for c in f["crits"] if c["ticked"] and not all(closed.get(p, True) for p in plans(c))]
    out["action"] = decide(f)[0]
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="mb-drive.sh")
    ap.add_argument("cmd", choices=["next", "status", "phase"])
    ap.add_argument("target", nargs="?")
    ap.add_argument("--bank", required=True)
    ap.add_argument("--run-id")
    ap.add_argument("--approve")
    a = ap.parse_args(argv)
    if (a.cmd == "phase") != (a.target == "execution") or (a.approve and a.cmd != "phase"):
        die("usage: mb-drive.sh phase execution [--approve t1,t2] | next | status", 2)
    st = select(pathlib.Path(a.bank).resolve(), a.run_id)
    if a.cmd == "phase":
        return cmd_phase(st, a.approve)
    if a.cmd == "status":
        print(json.dumps(status(st), ensure_ascii=False))
        return 0
    line, rc = decide(gather(st, cheap=False))
    print(line, file=sys.stderr if rc else sys.stdout)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
