#!/usr/bin/env python3
"""/mb team read side: `next` (design §9) and `status` (REQ-TEAM-053).

Usage (through mb-team.sh, which adds --mb <bank>):
  mb_team_status.py next   [--topic T] [--json]
  mb_team_status.py status [--topic T] [--json]

`next` prints one action per line in priority order and changes nothing:
  stop_human <why> · fix <id> · verify <id> · review <id> · dispatch <id> · collect ·
  team_review <N> · stop_success · wait
`decide(team, facts)` is the pure rule; `gather()` collects the facts: the board
(`mb-coord.sh tracks --json`), report STATUS lines, unfilled brief hints, the budget
(`mb-work-budget.sh check`), light-track acceptance (`mb_work_light.accept`), the team
review config, goal acceptance (`mb-goal-acceptance.sh`) and `mb-flow-verify.sh`; the last
two run only when everything else already allows stop_success.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mb_team_render as render  # noqa: E402
import mb_work_light  # noqa: E402
from mb_team_state import (  # noqa: E402
    FINISHED,
    TERMINAL,
    TeamError,
    configs,
    find_topic,
    globs_overlap,
    load,
    run,
    script,
)

ACTIVE = ("dispatched", "returned", "verifying", "reviewing", "fixing")
SEVERITIES = ("blocker", "major", "medium", "minor")


def _light(track: dict) -> bool:
    p = track["pipeline"]
    return p["mode"] == "work" and p.get("work") == "light"


def post_steps(track: dict, accepted: bool = False) -> bool:
    """True when a returned track still owes the orchestrator a verifier, a review or light acceptance."""
    p = track["pipeline"]
    if p["mode"] == "work" and not _light(track):
        return False  # the /mb work loop ran its own gates
    return (_light(track) and not accepted) or p["verifier"] != "none" or p["review"] != "none"


def collectable(track: dict, report_status: str | None, accepted: bool = False) -> bool:
    if track.get("collected"):
        return False
    if track["status"] in FINISHED:
        return True
    return (track["status"] == "returned" and not post_steps(track, accepted)
            and report_status in ("DONE", "DONE_WITH_CONCERNS"))


def light_acceptance(bank: str, team: dict) -> dict:
    """mb_work_light.accept for every returned light track: {id: {"accepted": bool, ...}}."""
    out = {}
    for t in team["tracks"]:
        if t["status"] == "returned" and _light(t):
            report = Path(bank) / t["report"]
            out[t["id"]] = (mb_work_light.accept(Path(bank) / t["source"], report.read_text(encoding="utf-8"))
                            if report.is_file() else {"accepted": False, "errors": ["no report"]})
    return out


def review_clean(review: dict, clean_when: dict) -> bool:
    """Gate verdict when recorded by `review gate`, else the counts against clean_when."""
    if review.get("verdict") in ("clean", "fixes_needed"):
        return review["verdict"] == "clean"
    counts = review.get("counts") or {}
    return all(counts.get(k, 0) <= clean_when[k] for k in SEVERITIES if k in clean_when)


def review_actions(team: dict, last: dict) -> tuple[list[str], list[str]]:
    """(stop, fix) from the last recorded gate; a fix is pending until its track goes through `fixing`.

    The gate snapshots each track's fix_cycle: second-resolution timestamps cannot order a return
    and a gate that fall in the same second.
    """
    by_id = {t["id"]: t for t in team["tracks"]}
    seen = last.get("fix_cycles") or {}
    stop = [a for a in last.get("actions") or [] if a.startswith("stop_human")]
    fix = [a for a in last.get("actions") or [] if a.startswith("fix ") and a[4:] in by_id
           and by_id[a[4:]]["status"] in FINISHED and by_id[a[4:]].get("fix_cycle", 0) <= seen.get(a[4:], 0)]
    return stop, fix


def decide(team: dict, facts: dict) -> list[str]:
    tracks, reports = team["tracks"], facts["reports"]
    if not tracks:
        return ["stop_human no-tracks"]
    stop, fix, verify, review, dispatch = [], [], [], [], []
    cap = facts["review"]["max_cycles"]

    def route_fix(t: dict) -> None:  # a fix past the cap would loop verify <-> fix forever
        if t.get("fix_cycle", 0) >= cap:
            stop.append(f"stop_human fix-cycles:{t['id']}")
        else:
            fix.append(f"fix {t['id']}")
    accepted = {tid: bool(v.get("accepted")) for tid, v in facts["light"].items()}
    if facts["brief_unfilled"]:
        stop.append("stop_human brief-unfilled")
    if facts["budget_stop"]:
        stop.append("stop_human budget")
    board_blocked = {b["track"] for b in facts["board"].get("open_blocked", [])}
    for t in tracks:
        tid, st = t["id"], t["status"]
        if st in ("blocked", "needs_context"):
            stop.append(f"stop_human {st}:{tid}")
        elif st not in TERMINAL and tid in board_blocked:
            stop.append(f"stop_human blocked:{tid}")
        elif st == "returned" and reports.get(tid) in ("BLOCKED", "NEEDS_CONTEXT"):
            stop.append(f"stop_human {reports[tid].lower()}:{tid}")
        elif st == "returned" and not post_steps(t, accepted.get(tid, False)) and reports.get(tid) is None:
            stop.append(f"stop_human no-report:{tid}")
        elif st == "fixing" and t.get("fix_cycle", 0) > cap:
            stop.append(f"stop_human fix-cycles:{tid}")
        elif st == "returned" and post_steps(t, accepted.get(tid, False)):
            if _light(t) and not accepted.get(tid):
                route_fix(t)
            elif t["pipeline"]["verifier"] != "none":
                verify.append(f"verify {tid}")
            elif t["pipeline"]["review"] != "none":
                review.append(f"review {tid}")
    cfg = facts["review"]
    reviews = team.get("reviews") or []
    last_clean = bool(reviews) and review_clean(reviews[-1], cfg["clean_when"])
    all_done = all(t["status"] in TERMINAL for t in tracks)
    all_collected = all(t.get("collected") or t["status"] == "cancelled" for t in tracks)
    if reviews and not last_clean:
        more_stop, more_fix = review_actions(team, reviews[-1])
        stop += [a for a in more_stop if a not in stop]
        for a in more_fix:
            route_fix(next(t for t in tracks if t["id"] == a[4:]))
    if cfg["enabled"] and all_done and all_collected and not last_clean and len(reviews) >= cfg["max_cycles"]:
        stop += [] if "stop_human review-cycles" in stop else ["stop_human review-cycles"]
    if not (facts["brief_unfilled"] or facts["budget_stop"]):
        running = [t for t in tracks if t["status"] in ACTIVE]
        finished = {t["id"] for t in tracks if t["status"] in FINISHED}
        for t in tracks:
            if len(running) >= team["max_parallel"]:
                break
            if t["status"] != "planned" or not set(t.get("deps") or []) <= finished:
                continue
            if any(globs_overlap(a, b) for r in running for a in t["files"] for b in r["files"]):
                continue
            dispatch.append(f"dispatch {t['id']}")
            running.append(t)
    out = stop + fix + verify + review + dispatch
    if any(collectable(t, reports.get(t["id"]), accepted.get(t["id"], False)) for t in tracks):
        out.append("collect")
    if out:
        return out
    if all_done and all_collected:
        if cfg["enabled"] and not last_clean:
            return [f"team_review {len(reviews) + 1}"]
        if facts["goal_ok"]() and facts["flow_ok"]():
            return ["stop_success"]
    return ["wait"]


def report_status(bank: str, track: dict) -> str | None:
    path = Path(bank) / track["report"]
    if not path.is_file():
        return None
    first = next((ln.strip() for ln in path.read_text(encoding="utf-8").splitlines() if ln.strip()), "")
    m = re.match(r"^STATUS:\s*(\S+)", first)
    return m.group(1) if m else None


def _json(cmd: list[str], **kw) -> dict:
    r = run(cmd, **kw)
    try:
        return json.loads(r.stdout or "{}")
    except ValueError:
        return {}


def gather(bank: str, team: dict) -> dict:
    reports = {t["id"]: report_status(bank, t) for t in team["tracks"]}
    brief = Path(bank) / team["brief"]
    light = light_acceptance(bank, team)
    budget_stop = False
    if team.get("budget_run_id"):
        budget_stop = run(["bash", script("mb-work-budget.sh"), "check", "--run-id", team["budget_run_id"],
                           "--mb", bank], env={**os.environ, "MB_WORK_PARALLEL": "1"}).returncode == 2
    cfg_review = configs(bank)[2]["review"]
    review = {"enabled": bool(cfg_review.get("enabled") or team.get("team_review")),
              "clean_when": cfg_review.get("clean_when") or {"blocker": 0, "major": 0, "medium": 0},
              "max_cycles": int(cfg_review.get("max_cycles") or 5)}
    return {"board": _json(["bash", script("mb-coord.sh"), "tracks", "--json", "--mb", bank]) or
            {"tracks": {}, "open_blocked": [], "open_handover": []},
            "reports": reports, "brief_unfilled": len(render.unfilled(str(brief))) if brief.is_file() else 1,
            "budget_stop": budget_stop, "light": light, "review": review,
            "goal_ok": lambda: not team.get("goal") or goal(bank).get("ok") is True,
            "flow_ok": lambda: run(["bash", script("mb-flow-verify.sh"), bank], cwd=team["tree"]).returncode == 0}


def goal(bank: str) -> dict:
    return _json(["bash", script("mb-goal-acceptance.sh"), os.path.join(bank, "goal.md"), bank])


def words(p: dict) -> str:
    parts = [p["mode"] if p["mode"] == "direct" else f"work:{p.get('work')}"]
    parts += ["tdd"] if p["tdd"] == "required" else []
    parts += ["verify"] if p["verifier"] != "none" else []
    parts += {"single": ["review:1"], "lenses": [f"lenses:{len(p['lenses'])}"]}.get(p["review"], [])
    return "/".join(parts)


def status_json(bank: str, team: dict) -> dict:
    facts = gather(bank, team)
    locks = _json(["bash", script("mb-lock.sh"), "status", "--json", "--mb", bank])
    board = facts["board"]
    return {"topic": team["topic"], "tree": team["tree"], "vcs": team["vcs"], "baseline": team["baseline"],
            "goal": {"id": team.get("goal"), **(goal(bank) if team.get("goal") else {})},
            "budget_run_id": team.get("budget_run_id"),
            "tracks": [{"id": t["id"], "status": t["status"], "pipeline": words(t["pipeline"]),
                        "board": board.get("tracks", {}).get(t["id"]), "report": facts["reports"][t["id"]],
                        "collected": t.get("collected", False)} for t in team["tracks"]],
            "resources": locks.get("resources", []), "open_blocked": board.get("open_blocked", []),
            "open_handover": board.get("open_handover", []),
            "review": (team.get("reviews") or [None])[-1], "next": decide(team, facts)}


def print_status(s: dict) -> None:
    g = s["goal"]
    goal_txt = f"{g['id']} {'ok' if g.get('ok') else 'open'}" if g["id"] else "none"
    print(f"team {s['topic']} · goal {goal_txt} · tree {s['tree']} ({s['vcs']}) · baseline {s['baseline'][:8]}"
          f" · budget {s['budget_run_id'] or 'off'}")
    print(f"{'ID':<6}{'STATUS':<20}{'PIPELINE':<22}{'BOARD (latest)':<40}REPORT")
    for t in s["tracks"]:
        b = t["board"]
        board = f"{b['type']} {b['date'][5:]} {b['title']}"[:38] if b else "-"
        rep = f"STATUS: {t['report']}" if t["report"] else "-"
        print(f"{t['id']:<6}{t['status']:<20}{t['pipeline']:<22}{board:<40}{rep}"
              f"{' (collected)' if t['collected'] else ''}")
    for r in s["resources"]:
        h = r.get("holder") or {}
        held = f"held by {h.get('owner')} ({h.get('age_s')}s) {h.get('cmd') or ''}".strip() if r.get("held") else "free"
        queue = ", ".join(f"{q['owner']} {q['wait_s']}s" for q in r.get("queue") or [])
        print(f"resource {r['name']}: {held}" + (f"; queue {queue}" if queue else ""))
    for b in s["open_blocked"]:
        print(f"BLOCKED {b['track']}: {b['title']} (no ACK)")
    if s["review"]:
        print(f"review: cycle-{s['review'].get('cycle')} {s['review'].get('verdict', '')} {s['review'].get('counts')}")
    print("next: " + " · ".join(s["next"]))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="mb_team_status.py")
    parser.add_argument("command", choices=("next", "status"))
    parser.add_argument("--mb", required=True)
    parser.add_argument("--topic", default="")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    bank = os.path.abspath(args.mb)
    try:
        team = load(bank, find_topic(bank, args.topic))
        if args.command == "next":
            actions = decide(team, gather(bank, team))
            print(json.dumps({"actions": actions}) if args.json else "\n".join(actions))
        else:
            s = status_json(bank, team)
            print(json.dumps(s, ensure_ascii=False)) if args.json else print_status(s)
    except TeamError as exc:
        print(f"[team] {exc}", file=sys.stderr)
        return exc.code
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
