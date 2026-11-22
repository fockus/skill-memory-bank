#!/usr/bin/env python3
"""Args of the mb-team-track Workflow (workflows/mb-team-track.js): `mb-team.sh workflow-args`.

Usage (through mb-team.sh, which adds --mb <bank>):
  mb_team_workflow.py workflow-args --tracks A,B [--start execute|fix|judge] [--topic T]

Prints one JSON object the orchestrator passes verbatim as the Workflow tool's `args`: the bank,
tree, skill and topic paths, the bookkeeping command prefix, and per track the executor agent,
model and effort (the track's resolved pipeline), the verifier, whether the cross-model review
runs, plus the judge, triage and review settings (team.external_review, model_profiles). A
workflow script cannot read files, so everything it needs is resolved here.
Exit: 0 ok · 2 bad input.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mb_team_state as st  # noqa: E402
import mb_work_models as models_mod  # noqa: E402
from mb_team_config import external_review  # noqa: E402
from mb_team_state import TeamError  # noqa: E402

SKILL = st.HERE.parent
NO_REVIEW_SIZES = ("trivial", "small")


def agent_effort(agent: str) -> str:
    path = SKILL / "agents" / f"{agent}.md"
    m = (
        re.search(r"^effort:\s*(\w+)", path.read_text(encoding="utf-8"), re.M)
        if path.is_file()
        else None
    )
    return m.group(1) if m else ""


def _model(value: str | None) -> str:
    return "" if not value or value == "inherit" else value


def build(bank: str, topic: str, ids: list[str], start: str) -> dict:
    team = st.load(bank, topic)
    by_id = {t["id"]: t for t in team["tracks"]}
    unknown = [i for i in ids if i not in by_id]
    if unknown or not ids:
        raise TeamError(f"--tracks: unknown {unknown or 'empty'}; tracks {list(by_id)}")
    project, bundled, cfg = st.configs(bank)
    host = team.get("host") or "claude-code"
    cost = models_mod.resolve_cost(project, bundled, host)
    judge_model = _model(models_mod.resolve_model("judge", project, bundled, host, cost)[0])
    rv = external_review(project, bundled, cfg)
    command = rv["command"]
    for key, value in (("tree", team["tree"]), ("model", rv["model"]), ("effort", rv["effort"])):
        command = command.replace("{" + key + "}", shlex.quote(value))
    tracks = []
    for tid in ids:
        t, pipe = by_id[tid], by_id[tid]["pipeline"] or {}
        models = pipe.get("models") or {}
        verifier = None
        if pipe.get("verifier", "none") != "none":
            verifier = {
                "agent": pipe["verifier"],
                "model": _model(models.get("verifier")),
                "effort": agent_effort(pipe["verifier"]),
            }
        tracks.append(
            {
                "id": tid,
                "start": start,
                "agent": t["agent"],
                "model": _model(models.get("executor")),
                "effort": pipe.get("effort") or agent_effort(t["agent"]),
                "verifier": verifier,
                "review": bool(command and rv["max_rounds"])
                and t.get("size") not in NO_REVIEW_SIZES,
                "prompt": os.path.join(bank, t["prompt"]),
                "report": os.path.join(bank, t["report"]),
                "files": t["files"],
            }
        )
    q = shlex.quote
    return {
        "topic": topic,
        "bank": bank,
        "tree": team["tree"],
        "skill": str(SKILL),
        "team": f"bash {q(str(SKILL / 'scripts' / 'mb-team.sh'))} --mb {q(bank)} --topic {q(topic)}",
        "brief": os.path.join(bank, team["brief"]),
        "review": {
            **rv,
            "command": command,
            "template": str(SKILL / "workflows" / "mb-team-track.review.md"),
        },
        "judge": {"agent": "mb-judge", "model": judge_model, "effort": agent_effort("mb-judge")},
        "triage": {"model": judge_model, "effort": "high"},
        "tracks": tracks,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="mb_team_workflow.py")
    parser.add_argument("cmd", choices=("workflow-args",))
    parser.add_argument("--mb", required=True)
    parser.add_argument("--topic", default="")
    parser.add_argument("--tracks", required=True)
    parser.add_argument("--start", choices=("execute", "fix", "judge"), default="execute")
    args = parser.parse_args(argv)
    bank = os.path.abspath(args.mb)
    try:
        ids = [x.strip() for x in args.tracks.split(",") if x.strip()]
        print(
            json.dumps(
                build(bank, st.find_topic(bank, args.topic, closed_too=True), ids, args.start),
                ensure_ascii=False,
                indent=2,
            )
        )
    except TeamError as exc:
        print(f"[team] {exc}", file=sys.stderr)
        return exc.code
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
