#!/usr/bin/env python3
"""Is known work running in this bank right now? (I-288)

The Stop-hook closure gate asks this before blocking a red flow: an orchestrator
waiting on background tracks has nothing to repair yet, so a block on every reply
is noise. Two deterministic signals, both bounded by freshness so a crashed run
cannot silence the gate forever:

  * an open /mb team (reports/<topic>/team.json without `closed`) with a track in
    dispatched / verifying / reviewing / fixing, the file touched within max-age;
  * a /mb work run (.work-state.json or .work-state/*.json) in phase
    `in-progress` whose `updated` stamp is within max-age.

Usage: mb_flow_busy.py <bank> [--max-age-min N]   (N=0 disables detection)
Exit 0 busy (one summary line on stdout), 1 idle. Unreadable files count as idle,
so any doubt hands the decision back to the gate.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import time
from pathlib import Path

WORKING = ("dispatched", "verifying", "reviewing", "fixing")


def _json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def team_tracks(bank: Path, cutoff: float) -> list[str]:
    out = []
    for path in sorted(bank.glob("reports/*/team.json")):
        try:
            if path.stat().st_mtime < cutoff:
                continue
        except OSError:
            continue
        team = _json(path)
        if team.get("closed"):
            continue
        tracks = team.get("tracks") or {}
        items = tracks.items() if isinstance(tracks, dict) else enumerate(tracks)
        out += [f"{path.parent.name}/{tid}" for tid, t in items
                if isinstance(t, dict) and t.get("status") in WORKING]
    return out


def work_runs(bank: Path, cutoff: float) -> list[str]:
    out = []
    for path in [bank / ".work-state.json", *sorted(bank.glob(".work-state/*.json"))]:
        state = _json(path)
        if state.get("phase") != "in-progress":
            continue
        try:
            updated = dt.datetime.fromisoformat(str(state.get("updated"))).timestamp()
        except ValueError:
            continue
        if updated >= cutoff:
            out.append(str(state.get("run_id") or state.get("heading") or path.stem))
    return out


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("bank")
    ap.add_argument("--max-age-min", type=float, default=120)
    args = ap.parse_args(argv)
    if args.max_age_min <= 0:
        return 1
    bank = Path(args.bank)
    cutoff = time.time() - args.max_age_min * 60
    tracks, runs = team_tracks(bank, cutoff), work_runs(bank, cutoff)
    if not (tracks or runs):
        return 1
    parts = ([f"team tracks: {', '.join(tracks)}"] if tracks else []) + \
            ([f"work runs: {', '.join(runs)}"] if runs else [])
    print("; ".join(parts))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
