#!/usr/bin/env python3
"""/mb team commands that change the team definition: init, track add/set, prompt, known-red.

Usage (through mb-team.sh, which adds --mb <bank>):
  mb_team_tracks.py init <topic> (--goal G | --no-goal) [--plan P] [--tree D] [--mirror D]
      [--max-parallel N] [--budget TOK] [--team-review] [--title T] [--host H] [pipeline attrs]
  mb_team_tracks.py track add <id> (--task T | --task-file F) --dod D [--dod D]... [--title T]
      [--role R] [--files g1,g2] [--deps A,B] [--resources r1] [--source P] [pipeline attrs] [--layer attr|prompt]
  mb_team_tracks.py track set <id> [--status S [--summary-file F]] [pipeline attrs] [--layer attr|prompt]
  mb_team_tracks.py prompt <id> · known-red add <test-id> --reason R · known-red list
  mb_team_tracks.py plan [--json]   # table, provenance, waves, effort mismatches, readiness
Pipeline attrs: --size --mode --tdd --verifier --review --effort --model key=value (repeatable).
Every command takes --mb <bank> and --topic T (default: the only open team of the bank).
`--source` defaults to the track prompt (a one-stage plan); `--source` and `--plan` take a bank-relative or absolute path. `track add` resolves the pipeline
through mb_team_pipeline.resolve, stores title and DoD, renders the track prompt and refreshes
the brief tracks table while the brief is untouched. `init` requires a valid goal.md unless
--no-goal, records the VCS root, kind and HEAD of --tree, and posts `FREEZE · contract:<topic>`.

Exit codes: 0 ok · 2 refused (bad input, unknown track, invalid move, missing goal).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mb_team_pipeline as pipeline_mod  # noqa: E402
import mb_team_render as render  # noqa: E402
import mb_team_state as st  # noqa: E402
from mb_team_state import TeamError  # noqa: E402


def split(value: str) -> list[str]:
    return [x.strip() for x in (value or "").split(",") if x.strip()]


def _rel(bank: str, path: str) -> str:
    full = path if os.path.isabs(path) else os.path.join(bank, path)
    if not os.path.exists(full):
        raise TeamError(f"no such file: {full}")
    return os.path.relpath(os.path.abspath(full), bank)


def cmd_init(args) -> int:
    bank, topic = args.mb, args.topic_name
    if not st.TOPIC_RE.match(topic):
        raise TeamError(f"topic '{topic}' must match {st.TOPIC_RE.pattern}")
    validate = ["bash", st.script("mb-goal-validate.sh"), os.path.join(bank, "goal.md"), bank]
    if not args.no_goal and st.run(validate).returncode != 0:
        raise TeamError(f"goal.md in {bank} is missing or invalid (mb-goal-validate.sh); "
                        "write one with /mb goal or pass --no-goal")
    tree = os.path.abspath(args.tree or os.getcwd())
    vcs = {op: st.run(["bash", st.script("mb_vcs.sh"), op, "--tree", tree]) for op in ("kind", "root", "head")}
    bad = next((r for r in vcs.values() if r.returncode != 0), None)
    if bad is not None:
        raise TeamError(f"working tree {tree}: {bad.stderr.strip() or 'no revision'}")
    team_attrs = st.pipeline_attrs(args)
    errors: list[str] = []
    pipeline_mod.parse_kv(team_attrs, "team", errors.append)
    if errors:
        raise TeamError("; ".join(errors))
    budget_id = None
    if args.budget:
        budget_id = f"team-{topic}"
        r = st.run(["bash", st.script("mb-work-budget.sh"), "init", str(args.budget), "--run-id", budget_id, "--mb", bank],
                   env={**os.environ, "MB_WORK_PARALLEL": "1"})
        if r.returncode != 0:
            raise TeamError(f"mb-work-budget.sh init: {r.stderr.strip()}")
    base = f"reports/{topic}"
    data = {"schema": 1, "topic": topic, "title": args.title or topic, "created": st.now(),
            "goal": None if args.no_goal else (args.goal or "goal.md"),
            "plan": _rel(bank, args.plan) if args.plan else None, "tree": vcs["root"].stdout.strip(),
            "mirror": os.path.abspath(args.mirror) if args.mirror else None, "vcs": vcs["kind"].stdout.strip(),
            "baseline": vcs["head"].stdout.strip(), "brief": f"{base}/brief.md",
            "max_parallel": args.max_parallel or st.configs(bank)[2]["max_parallel"], "budget_run_id": budget_id,
            "host": args.host, "team_attrs": team_attrs, "team_review": args.team_review,
            "known_red": [], "known_open": [], "tracks": [], "reviews": [], "checkpoints": [], "commits": []}
    with st.locked(bank, topic, create=data) as team:
        st.refresh_brief(bank, team, force=True)
    r = st.run(["bash", st.script("mb-coord.sh"), "append", "--type", "FREEZE", "--title", f"contract:{topic}", "--mb", bank])
    if r.returncode != 0:
        print(f"warning: contract FREEZE not posted: {r.stderr.strip()}", file=sys.stderr)
    print(st.team_file(bank, topic))
    print(Path(bank) / data["brief"])
    return 0


def cmd_track_add(args) -> int:
    bank, tid = args.mb, args.id
    if not st.ID_RE.match(tid):
        raise TeamError(f"track id '{tid}' must match {st.ID_RE.pattern}")
    task = Path(args.task_file).read_text(encoding="utf-8") if args.task_file else args.task
    if not task or not task.strip():
        raise TeamError("--task or --task-file is required")
    if not args.dod:
        raise TeamError("--dod is required (a track prompt is a one-stage plan with a DoD)")
    if not (st.HERE.parent / "agents" / f"mb-{args.role}.md").is_file():
        raise TeamError(f"role '{args.role}': no agents/mb-{args.role}.md")
    topic = st.find_topic(bank, args.topic)
    with st.locked(bank, topic) as team:
        ids = [t["id"] for t in team["tracks"]]
        if tid in ids:
            raise TeamError(f"track {tid} already exists")
        missing = [d for d in split(args.deps) if d not in ids]
        if missing:
            raise TeamError(f"track {tid}: unknown deps {missing}; add them first")
        undeclared = [r for r in split(args.resources) if r not in st.configs(bank)[2]["resources"]]
        if undeclared:
            raise TeamError(f"track {tid}: resources {undeclared} are not declared in team.resources")
        base = f"reports/{topic}"
        track = {"id": tid, "title": args.title or task.strip().splitlines()[0][:80], "task": task.strip(),
                 "dod": args.dod, "role": args.role, "agent": f"mb-{args.role}", "size": None,
                 "source": _rel(bank, args.source) if args.source else f"{base}/tracks/{tid}.prompt.md", "files": split(args.files),
                 "deps": split(args.deps), "resources": split(args.resources),
                 "layers": {"track": [], "prompt": []}, "pipeline": None, "provenance": None,
                 "prompt": f"{base}/tracks/{tid}.prompt.md", "report": f"{base}/{tid}.md", "status": "planned",
                 "run_id": None, "fix_cycle": 0, "collected": False, "dispatched_at": None, "returned_at": None,
                 "summary": None}
        track["layers"][args.layer] = st.pipeline_attrs(args)
        st.resolve_track(bank, team, track)
        team["tracks"].append(track)
        print(st.render_prompt(bank, team, tid))
        st.refresh_brief(bank, team)
    return 0


def cmd_track_set(args) -> int:
    bank = args.mb
    with st.locked(bank, st.find_topic(bank, args.topic)) as team:
        track = next((t for t in team["tracks"] if t["id"] == args.id), None)
        if track is None:
            raise TeamError(f"unknown track '{args.id}'")
        if args.status:
            if not st.can_move(track["status"], args.status):
                raise TeamError(f"track {args.id}: {track['status']} -> {args.status} is not allowed")
            if args.status == "fixing":
                track["fix_cycle"] += 1
                # A fix reopens the track: its return must be collected again, or a team-review
                # fix on a returned track stays `returned` and `next` waits forever.
                track["collected"] = False
            stamp = {"dispatched": "dispatched_at", "returned": "returned_at"}.get(args.status)
            if stamp:
                track[stamp] = st.now()
            track["status"] = args.status
        if args.summary_file:
            track["summary"] = Path(args.summary_file).read_text(encoding="utf-8").strip()
        attrs = st.pipeline_attrs(args)
        if attrs:
            track["layers"][args.layer] += attrs
            st.resolve_track(bank, team, track)
            st.render_prompt(bank, team, args.id)
            st.refresh_brief(bank, team)
    return 0


def cmd_prompt(args) -> int:
    bank = args.mb
    with st.locked(bank, st.find_topic(bank, args.topic)) as team:
        if args.id not in [t["id"] for t in team["tracks"]]:
            raise TeamError(f"unknown track '{args.id}'")
        print(st.render_prompt(bank, team, args.id))
    return 0


def cmd_known_red(args) -> int:
    bank, topic = args.mb, st.find_topic(args.mb, args.topic)
    if args.action == "list":
        for k in st.load(bank, topic)["known_red"]:
            print(f"{k['id']}\t{k['reason']}\t{k['since']}")
        return 0
    if not args.test_id or not args.reason:
        raise TeamError("known-red add <test-id> --reason R")
    with st.locked(bank, topic) as team:
        team["known_red"].append({"id": args.test_id, "reason": args.reason, "since": st.now()[:10]})
        st.refresh_brief(bank, team)
    return 0


def agent_effort(agent: str) -> str | None:
    path = st.HERE.parent / "agents" / f"{agent}.md"
    m = re.search(r"^effort:\s*(\S+)", path.read_text(encoding="utf-8"), re.M) if path.is_file() else None
    return m.group(1) if m else None


def plan_json(bank: str, team: dict) -> dict:
    waves: dict[str, int] = {}
    for t in team["tracks"]:  # deps are added before their dependants
        waves[t["id"]] = 1 + max((waves.get(d, 0) for d in t.get("deps") or []), default=0)
    warnings, overlaps = [], []
    for t in team["tracks"]:
        have = agent_effort(t["agent"])
        if have and have != t["pipeline"]["effort"]:
            warnings.append(f"{t['id']} effort={t['pipeline']['effort']} but agent {t['agent']} has effort: {have} "
                            "(Claude Code reads effort from the agent) — accept or change")
    for i, a in enumerate(team["tracks"]):
        for b in team["tracks"][i + 1:]:
            if waves[a["id"]] == waves[b["id"]] and any(st.globs_overlap(x, y) for x in a["files"] for y in b["files"]):
                overlaps.append(f"{a['id']}/{b['id']}")
    brief = Path(bank) / team["brief"]
    return {"tracks": [{"id": t["id"], "role": t["role"], "size": t["size"], "pipeline": t["pipeline"],
                        "provenance": t["provenance"], "wave": waves[t["id"]], "deps": t.get("deps") or []}
                       for t in team["tracks"]],
            "warnings": warnings,
            "ready": {"brief_unfilled": len(render.unfilled(str(brief))) if brief.is_file() else 1,
                      "glob_overlaps_in_wave": overlaps}}


def print_plan(p: dict) -> None:
    print(f"{'ID':<6}{'ROLE':<10}{'SIZE':<10}{'MODE':<8}{'TDD':<10}{'VERIFIER':<15}{'REVIEW':<8}"
          f"{'EXECUTOR':<12}{'EFFORT':<8}WAVE")
    for t in p["tracks"]:
        q = t["pipeline"]
        deps = f" (deps {','.join(t['deps'])})" if t["deps"] else ""
        print(f"{t['id']:<6}{t['role']:<10}{t['size']:<10}{q['mode']:<8}{q['tdd']:<10}{q['verifier']:<15}"
              f"{q['review']:<8}{q['models'].get('executor', '-'):<12}{q['effort']:<8}{t['wave']}{deps}")
    for t in p["tracks"]:
        print(f"provenance {t['id']}: " + " ".join(f"{k}={v}" for k, v in t["provenance"].items()))
    for w in p["warnings"]:
        print(f"warning: {w}")
    r = p["ready"]
    print(f"ready: brief unfilled hints {r['brief_unfilled']} · overlaps in a wave {r['glob_overlaps_in_wave'] or 'none'}")


def _parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--mb", required=True)
    common.add_argument("--topic", default="")
    attrs = argparse.ArgumentParser(add_help=False)
    for flag in ("size", "mode", "tdd", "verifier", "review", "effort"):
        attrs.add_argument(f"--{flag}", default="")
    attrs.add_argument("--model", action="append", default=[], help="key=value, e.g. executor=opus")
    attrs.add_argument("--layer", choices=("track", "attr", "prompt"), default="track")
    parser = argparse.ArgumentParser(prog="mb_team_tracks.py")
    sub = parser.add_subparsers(dest="cmd", required=True)
    init = sub.add_parser("init", parents=[common, attrs])
    init.add_argument("topic_name")
    init.add_argument("--goal", default="")
    init.add_argument("--no-goal", action="store_true")
    for flag in ("--plan", "--tree", "--mirror", "--title"):
        init.add_argument(flag, default="")
    init.add_argument("--max-parallel", type=int, default=0)
    init.add_argument("--budget", type=int, default=0)
    init.add_argument("--team-review", action="store_true")
    init.add_argument("--host", default="claude-code")
    track = sub.add_parser("track").add_subparsers(dest="action", required=True)
    add = track.add_parser("add", parents=[common, attrs])
    add.add_argument("id")
    for flag in ("--task", "--task-file", "--title", "--files", "--deps", "--resources", "--source"):
        add.add_argument(flag, default="")
    add.add_argument("--dod", action="append", default=[])
    add.add_argument("--role", default="developer")
    tset = track.add_parser("set", parents=[common, attrs])
    tset.add_argument("id")
    tset.add_argument("--status", default="", choices=("", *st.MOVES, *st.TERMINAL))
    tset.add_argument("--summary-file", default="")
    prompt = sub.add_parser("prompt", parents=[common])
    prompt.add_argument("id")
    known = sub.add_parser("known-red", parents=[common])
    known.add_argument("action", choices=("add", "list"))
    known.add_argument("test_id", nargs="?", default="")
    known.add_argument("--reason", default="")
    sub.add_parser("plan", parents=[common]).add_argument("--json", action="store_true")
    return parser


def main(argv: list[str]) -> int:
    args = _parser().parse_args(argv)
    args.mb = os.path.abspath(args.mb)
    if getattr(args, "layer", "") == "attr":
        args.layer = "track"
    handler = {"init": cmd_init, "prompt": cmd_prompt, "known-red": cmd_known_red}.get(args.cmd)
    if args.cmd == "track":
        handler = cmd_track_add if args.action == "add" else cmd_track_set
    try:
        if args.cmd == "plan":
            p = plan_json(args.mb, st.load(args.mb, st.find_topic(args.mb, args.topic)))
            print(json.dumps(p, ensure_ascii=False)) if args.json else print_plan(p)
            return 0
        return handler(args)
    except TeamError as exc:
        print(f"[team] {exc}", file=sys.stderr)
        return exc.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
