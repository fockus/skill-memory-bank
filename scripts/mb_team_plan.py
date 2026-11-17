"""`/mb team plan`: track table, provenance, waves, effort mismatches and readiness.

Readiness: unfilled brief hints, glob overlaps inside a wave, and shared foundations (mb_team_shared) — a
signal ≥2 tracks share with no foundation dependency between them is a blocking warning with a suggested
foundation track. `--accept-shared <signal>` (repeatable) records the orchestrator's decision that the
signal needs no foundation track in team.json `accepted_shared`.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import mb_team_render as render
import mb_team_shared as shared
import mb_team_state as st

CONTRACT_SIZES = ("standard", "large", "extra")


def agent_effort(agent: str) -> str | None:
    path = st.HERE.parent / "agents" / f"{agent}.md"
    m = (
        re.search(r"^effort:\s*(\S+)", path.read_text(encoding="utf-8"), re.M)
        if path.is_file()
        else None
    )
    return m.group(1) if m else None


def plan_json(bank: str, team: dict) -> dict:
    waves: dict[str, int] = {}
    for t in team["tracks"]:  # deps are added before their dependants
        waves[t["id"]] = 1 + max((waves.get(d, 0) for d in t.get("deps") or []), default=0)
    warnings, overlaps = [], []
    for t in team["tracks"]:
        have = agent_effort(t["agent"])
        if have and have != t["pipeline"]["effort"]:
            warnings.append(
                f"{t['id']} effort={t['pipeline']['effort']} but agent {t['agent']} has effort: {have} "
                "(Claude Code reads effort from the agent) — accept or change"
            )
        if t["size"] in CONTRACT_SIZES and not t.get("contract"):
            warnings.append(f"{t['id']} (size {t['size']}) has no contract: write <bank>/contracts/<id>.md from the "
                            "task, DoD and REQ text, freeze it (mb_contract.py freeze), then track add/set --contract")
    for i, a in enumerate(team["tracks"]):
        for b in team["tracks"][i + 1 :]:
            if waves[a["id"]] == waves[b["id"]] and any(
                st.globs_overlap(x, y) for x in a["files"] for y in b["files"]
            ):
                overlaps.append(f"{a['id']}/{b['id']}")
    brief = Path(bank) / team["brief"]
    return {
        "tracks": [
            {
                "id": t["id"],
                "role": t["role"],
                "size": t["size"],
                "pipeline": t["pipeline"],
                "provenance": t["provenance"],
                "wave": waves[t["id"]],
                "deps": t.get("deps") or [],
            }
            for t in team["tracks"]
        ],
        "warnings": warnings,
        "ready": {
            "brief_unfilled": len(render.unfilled(str(brief))) if brief.is_file() else 1,
            "glob_overlaps_in_wave": overlaps,
            "shared_foundation": shared.foundation_groups(team, shared.load_registry(bank)),
        },
    }


def print_plan(p: dict) -> None:
    print(
        f"{'ID':<6}{'ROLE':<10}{'SIZE':<10}{'MODE':<8}{'TDD':<10}{'VERIFIER':<15}{'REVIEW':<8}"
        f"{'EXECUTOR':<12}{'EFFORT':<8}WAVE"
    )
    for t in p["tracks"]:
        q = t["pipeline"]
        deps = f" (deps {','.join(t['deps'])})" if t["deps"] else ""
        print(
            f"{t['id']:<6}{t['role']:<10}{t['size']:<10}{q['mode']:<8}{q['tdd']:<10}{q['verifier']:<15}"
            f"{q['review']:<8}{q['models'].get('executor', '-'):<12}{q['effort']:<8}{t['wave']}{deps}"
        )
    for t in p["tracks"]:
        print(f"provenance {t['id']}: " + " ".join(f"{k}={v}" for k, v in t["provenance"].items()))
    for w in p["warnings"]:
        print(f"warning: {w}")
    r = p["ready"]
    for g in r["shared_foundation"]:
        print(
            f"BLOCKING shared foundation {g['signal']} named by {','.join(g['tracks'])}: {g['suggest']}"
        )
    print(
        f"ready: brief unfilled hints {r['brief_unfilled']} · overlaps in a wave {r['glob_overlaps_in_wave'] or 'none'}"
        f" · shared foundations {len(r['shared_foundation']) or 'none'}"
    )


def cmd_plan(args) -> int:
    topic = st.find_topic(args.mb, args.topic)
    if args.accept_shared:
        with st.locked(args.mb, topic) as team:
            accepted = team.setdefault("accepted_shared", [])
            accepted += [s for s in args.accept_shared if s not in accepted]
    p = plan_json(args.mb, st.load(args.mb, topic))
    print(json.dumps(p, ensure_ascii=False)) if args.json else print_plan(p)
    return 0
