#!/usr/bin/env python3
"""Team review cycles (design §8): cycle brief, gate over clean_when, external reviewer.

Usage (all paths absolute or relative to cwd; `--pipeline` overrides the bank pipeline):
  mb_team_review.py start    --team <team.json> --mb <bank> --cycle N [--lenses a,b] [--range <base>..<rev>]
  mb_team_review.py gate     --team <team.json> --mb <bank> --cycle N
  mb_team_review.py external --team <team.json> --mb <bank> --cycle N --name X [--rev R]
  mb_team_review.py ingest   --team <team.json> --mb <bank> --cycle N --name X

Files live under `<dir of team.json>/review/`: `cycle-N/{brief.md,<lens>.json,master.json}`,
`external-<name>-cycle-N/{prompt.md,meta.json,findings.json,prior-closure.json}` and the
ingested aspect report `cycle-N/external-<name>.json`.

`gate` validates master.json through mb-work-review-parse.sh, applies `team.review.clean_when`
through mb-work-severity-gate.sh, requires a `previous_issues` status for every routed issue of
the previous cycle, and prints JSON with fixes grouped by owner track and the `next` actions.

Exit codes: 0 ok / clean · 1 fixes needed · 2 broken input or usage · 3 team review disabled.
"""

from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import mb_pipeline_validate_team as schema  # noqa: E402
from mb_team_config import ConfigError  # noqa: E402
from mb_team_render import RenderError  # noqa: E402
from mb_team_review_core import (  # noqa: E402
    CLOSED,
    LENS_FORMAT,
    LENS_SCOPE,
    PREV_STATUSES,
    SEVERITIES,
    Ctx,
    ReviewError,
    issue_line,
    known_open,
    lenses_for,
    load_json,
    to_close,
    write_atomic,
)
from mb_team_review_external import cmd_external, cmd_ingest  # noqa: E402


def _diff_cmd(ctx: Ctx, rng: str) -> str:
    vcs, tree = ctx.team.get("vcs") or "git", ctx.team.get("tree") or "."
    if rng:
        base, sep, rev = rng.partition("..")
        if not (sep and base and rev):
            raise ReviewError(f"--range must be <base>..<rev>, got '{rng}'")
        return f"cd {shlex.quote(tree)} && {vcs} diff {base} {rev}"
    return f"cd {shlex.quote(tree)} && {vcs} diff {ctx.team['baseline']}"


def cmd_start(ctx: Ctx, args) -> int:
    lenses, n = lenses_for(ctx, args.lenses), args.cycle
    out = ctx.cycle_dir(n)
    prev = to_close(ctx, ctx.master(n - 1)) if n > 1 else []
    tracks = [f"- {t['id']}: {', '.join(t.get('files') or []) or '—'}" for t in ctx.team.get("tracks") or []]
    lines = [
        f"# Team review: {ctx.team.get('title') or ctx.team['topic']} (cycle {n})", "",
        f"**Object:** `{_diff_cmd(ctx, args.range)}`", "",
        "## Read first",
        f"- Team brief: {os.path.join(ctx.bank, ctx.team['brief'])}" if ctx.team.get("brief") else None,
        f"- Plan: {os.path.join(ctx.bank, ctx.team['plan'])}" if ctx.team.get("plan") else None,
        f"- Decisions to check the change against: {os.path.join(ctx.bank, 'agreements.md')}",
        f"- Previous master: {ctx.cycle_dir(n - 1) / 'master.json'}" if prev else None,
        f"- External reports in {out} (`external-*.json`), when present: input for the lead.", "",
        "## Lenses (one reviewer each, in parallel)",
        *[f"- {lens} — {LENS_SCOPE[lens]} → write {out / (lens + '.json')}" for lens in lenses], "",
        "## Tracks (owner = track id, by file globs)", *tracks, "",
        "## Known open items — do not reopen without new facts", known_open(ctx), "",
        "## Previous issues to close (status required in `previous_issues`)",
        *([issue_line(i) for i in prev] or ["- none (first cycle)"]), "",
        "## Format",
        f"- Lens report: `{LENS_FORMAT}`.",
        f"- Lead (mb-reviewer-lead): closure check of previous issues first, then merge the lens reports into "
        f"{out / 'master.json'} (same shape, plus `owner` per issue) and {out / 'master.md'}.",
        f"- Severities: {', '.join(SEVERITIES)}; clean when {json.dumps(ctx.clean_when)}.",
    ]
    path = out / "brief.md"
    write_atomic(path, "\n".join(line for line in lines if line is not None) + "\n")
    print(path)
    return 0


def _gate_counts(counts: dict, clean_when: dict) -> int:
    """mb-work-severity-gate.sh exit code; severities absent from clean_when are unlimited."""
    gate = {s: clean_when.get(s, counts.get(s, 0)) for s in SEVERITIES}
    run = subprocess.run(["bash", str(HERE / "mb-work-severity-gate.sh"), "--counts", json.dumps(counts),
                          "--gate", json.dumps(gate), "--ignore-approval"],
                         capture_output=True, text=True, check=False)
    if run.returncode == 2:
        raise ReviewError(f"severity gate: {run.stderr.strip()}")
    return run.returncode


def _check_master(text: str, master) -> dict:
    run = subprocess.run(["bash", str(HERE / "mb-work-review-parse.sh")], input=text,
                         capture_output=True, text=True, check=False)
    if run.returncode != 0:
        raise ReviewError(f"master.json: {run.stderr.strip()}")
    missing = [n for n, i in enumerate(master.get("issues") or []) if not isinstance(i.get("id"), str)]
    if missing:
        raise ReviewError(f"master.json: issues {missing} have no string id")
    return json.loads(run.stdout)


def cmd_gate(ctx: Ctx, args) -> int:
    n = args.cycle
    path = ctx.cycle_dir(n) / "master.json"
    master = load_json(path, f"cycle {n} master")
    if not isinstance(master, dict):
        raise ReviewError("master.json: top level must be an object")
    parsed = _check_master(path.read_text(encoding="utf-8"), master)
    prev_master = ctx.master(n - 1) if n > 1 else None
    statuses = {p.get("id"): p for p in master.get("previous_issues") or [] if isinstance(p, dict)}
    bad = [p for p in statuses.values() if p.get("status") not in PREV_STATUSES]
    if bad:
        raise ReviewError(f"previous_issues: status must be one of {list(PREV_STATUSES)}: {bad}")
    required = to_close(ctx, prev_master)
    lacking = [i["id"] for i in required if i.get("id") not in statuses]
    if lacking:
        raise ReviewError(f"previous_issues: no status for {lacking} from cycle {n - 1}")
    prev_by_id = {i.get("id"): i for i in (prev_master or {}).get("issues") or []}
    reopened = [prev_by_id.get(p["id"], p) for p in statuses.values()
                if p["status"] not in CLOSED and p["id"] not in {i["id"] for i in master.get("issues") or []}]
    counts_ok = _gate_counts(parsed["counts"], ctx.clean_when) == 0
    fixes: dict[str, list[str]] = {}
    unowned: list[str] = []
    for issue in [i for i in master.get("issues") or [] if ctx.routed(i)] + reopened:
        owner = ctx.owner(issue)
        (fixes.setdefault(owner, []) if owner else unowned).append(issue["id"])
    clean = counts_ok and not reopened
    actions: list[str] = []
    if not clean and n >= int(ctx.cfg.get("max_cycles") or 5):
        actions = ["stop_human review-cycles"]
    elif not clean:
        order = [t["id"] for t in ctx.team.get("tracks") or []]
        actions = [f"fix {t}" for t in sorted(fixes, key=order.index)]
        actions += ["stop_human review-unowned"] if unowned else []
    print(json.dumps({"cycle": n, "verdict": "clean" if clean else "fixes_needed", "counts": parsed["counts"],
                      "clean_when": ctx.clean_when, "fixes": {} if clean else fixes,
                      "unowned": [] if clean else unowned, "previous_open": [p["id"] for p in reopened],
                      "actions": actions}, ensure_ascii=False))
    return 0 if clean else 1


COMMANDS = {"start": cmd_start, "gate": cmd_gate, "external": cmd_external, "ingest": cmd_ingest}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="mb-team-review.sh")
    parser.add_argument("command", choices=tuple(COMMANDS))
    parser.add_argument("--team", required=True)
    parser.add_argument("--mb", required=True)
    parser.add_argument("--cycle", type=int, required=True)
    parser.add_argument("--pipeline", default="")
    parser.add_argument("--lenses", default="")
    parser.add_argument("--range", default="")
    parser.add_argument("--name", default="")
    parser.add_argument("--rev", default="")
    args = parser.parse_args(argv)
    try:
        if args.cycle < 1:
            raise ReviewError("--cycle must be >= 1")
        if args.command in ("external", "ingest") and not schema.NAME_RE.match(args.name or ""):
            raise ReviewError("--name required: letters, digits, '_' and '-'")
        ctx = Ctx(args)
        if not ctx.enabled:
            sys.stderr.write("[team-review] team review is off: set team.review.enabled or init --team-review\n")
            return 3
        return COMMANDS[args.command](ctx, args)
    except ConfigError as exc:
        sys.stderr.write("".join(f"[team-review] {m}\n" for m in exc.errors))
    except (ReviewError, RenderError, KeyError, AttributeError, TypeError, subprocess.CalledProcessError) as exc:
        sys.stderr.write(f"[team-review] {exc}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
