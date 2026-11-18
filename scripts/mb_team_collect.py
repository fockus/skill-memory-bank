"""`/mb team collect`: progress entries for newly finished tracks, goal criteria, report questions and
follow-ups, and cross-track duplication candidates of the wave (mb_dup_scan).

Called by mb_team_ops.py (`collect [--dry-run] [--json]`); one progress entry per newly returned track
(mb-work-progress-append.sh), marks it collected; with a goal, lists the goal criteria next to the collected
reports; prints report questions and follow-ups as mb-agree.sh / mb-idea.sh commands for the orchestrator,
and `duplicate:` lines for code two finished tracks both added since the baseline.
"""

from __future__ import annotations

import json
import re
import shlex
import sys
from pathlib import Path

import mb_dup_scan as dup
import mb_team_state as st
from mb_team_status import collectable, report_status

STATUS_OF = {"DONE": "done", "DONE_WITH_CONCERNS": "done_with_concerns"}


def _sections(text: str, word: str) -> list[str]:
    out, inside = [], False
    for line in text.splitlines():
        if line.startswith("#"):
            inside = word in line.lower()
        elif inside and re.match(r"^\s*-\s+\S", line):
            out.append(re.sub(r"^\s*-\s+", "", line).strip())
    return out


def goal_criteria(bank: str) -> list[dict]:
    path = Path(bank) / "goal.md"
    out, inside, fence = [], False, False
    for line in path.read_text(encoding="utf-8").splitlines() if path.is_file() else []:
        if line.lstrip().startswith(("```", "~~~")):
            fence = not fence
        elif not fence and line.startswith("## "):
            inside = line[3:].strip().lower() == "acceptance criteria"
        elif inside and not fence and (m := re.match(r"^\s*-\s+\[([ xX])\]\s+(.*)$", line)):
            out.append({"criterion": m.group(2).strip(), "checked": m.group(1) != " "})
    return out


def _collect(args) -> int:
    bank = args.mb
    result = {"collected": [], "goal": [], "evidence": [], "questions": [], "followups": [], "duplicates": [],
              "errors": []}
    with st.locked(bank, st.find_topic(bank, args.topic)) as team:
        for t in team["tracks"]:
            rs = report_status(bank, t)
            if not collectable(t, rs):
                continue
            report = Path(bank) / t["report"]
            text = report.read_text(encoding="utf-8") if report.is_file() else ""
            if not args.dry_run:
                entry = (f"## {st.now()[:10]} — team {team['topic']} · track {t['id']} ({rs or t['status']})\n"
                         f"{t['title']}\nReport: {report}\n" + (f"{t['summary']}\n" if t.get("summary") else ""))
                r = st.run(["bash", st.script("mb-work-progress-append.sh"), "--text", entry, "--mb", bank])
                if r.returncode != 0 or "skipping append" in r.stderr:
                    result["errors"].append(f"{t['id']}: progress append failed: {r.stderr.strip()}")
                    break
                if t["status"] == "returned":
                    t["status"] = STATUS_OF[rs]
                t["collected"] = True
            result["collected"].append(t["id"])
            result["evidence"].append(str(report))
            result["questions"] += _sections(text, "question")
            result["followups"] += _sections(text, "follow")
        if args.dry_run:
            raise _DryRun(result)
        if team.get("goal"):
            result["goal"] = goal_criteria(bank)
        snapshot = json.loads(json.dumps(team))
    try:  # advisory: a failing scan must not undo the collect that already appended progress
        result["duplicates"] = _wave_duplicates(snapshot)
    except st.TeamError as exc:
        print(f"warning: duplicate scan skipped: {exc}", file=sys.stderr)
    _print_collect(result, args.json)
    return 1 if result["errors"] else 0


def cmd_collect(args) -> int:
    try:
        return _collect(args)
    except _DryRun as dry:
        _print_collect(dry.result, args.json)
        return 0


def _wave_duplicates(team: dict) -> list[dict]:
    finished = {t["id"] for t in team["tracks"] if t["status"] in st.FINISHED}
    if len(finished) < 2:
        return []
    untracked = [p for p in st.vcs(team, "untracked").split("\0") if p]
    return dup.wave_duplicates(team, team["tree"], st.vcs(team, "diff", team["baseline"]), untracked, finished)


class _DryRun(Exception):
    """Leaves locked() without writing team.json."""

    def __init__(self, result: dict):
        super().__init__("dry run")
        self.result = result


def _print_collect(result: dict, as_json: bool) -> None:
    if as_json:
        print(json.dumps(result, ensure_ascii=False))
        return
    print("collected: " + (", ".join(result["collected"]) or "none"))
    for g in result["goal"]:
        print(f"goal [{'x' if g['checked'] else ' '}] {g['criterion']}")
    for path in result["evidence"] if result["goal"] else []:
        print(f"  evidence: {path}")
    skill = st.HERE
    for q in result["questions"]:
        print(f"question: bash {shlex.quote(f'{skill}/mb-agree.sh')} question {shlex.quote(q)}")
    for f in result["followups"]:
        print(f"follow-up: bash {shlex.quote(f'{skill}/mb-idea.sh')} {shlex.quote(f)}")
    for d in result["duplicates"]:
        a, b = d["a"], d["b"]
        print(f"duplicate: {a['track']} {a['path']}:{a['line']} ~ {b['track']} {b['path']}:{b['line']} ({d['lines']} lines)")
    for e in result["errors"]:
        print(f"error: {e}", file=sys.stderr)
