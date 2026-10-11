#!/usr/bin/env python3
"""External reviewer of a team review cycle: prompt rendering and ingestion (design §8, examples §7)."""

from __future__ import annotations

import json
import os
import shlex
import subprocess
from pathlib import Path

from mb_team_render import TEMPLATES, fill
from mb_team_review_core import (
    EXT_STATUSES,
    HERE,
    LENS_SCOPE,
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


def _earlier_routed(ctx: Ctx, n: int) -> list[dict]:
    out, seen = [], set()
    for k in range(1, n):
        for issue in to_close(ctx, ctx.master(k)):
            if issue.get("id") not in seen:
                seen.add(issue.get("id"))
                out.append(issue)
    return out


def _ext_dir(ctx: Ctx, name: str, n: int) -> Path:
    return ctx.review_dir / f"external-{name}-cycle-{n}"


def cmd_external(ctx: Ctx, args) -> int:
    n, name, team = args.cycle, args.name, ctx.team
    tree, vcs = team.get("tree") or ".", team.get("vcs") or "git"
    rev = args.rev or subprocess.run(["bash", str(HERE / "mb_vcs.sh"), "head", "--tree", team.get("mirror") or tree],
                                     capture_output=True, text=True, check=True).stdout.strip()
    prev_rev = next((load_json(_ext_dir(ctx, name, k) / "meta.json", "meta")["rev"] for k in range(n - 1, 0, -1)
                     if (_ext_dir(ctx, name, k) / "meta.json").exists()), None)
    delta = (f"- Earlier cycles: the delta since your last cycle is `{vcs} diff {prev_rev} {rev}`." if prev_rev
             else "- First cycle for this reviewer: review the whole diff.")
    read = [f"- {os.path.join(ctx.bank, 'agreements.md')} — decisions in force; check the change against them."]
    read += [f"- {os.path.join(ctx.bank, team[k])}" for k in ("brief", "plan") if team.get(k)]
    read += [f"- {p}" for k in range(1, n) for p in sorted(ctx.cycle_dir(k).glob("master.*"))]
    lenses = lenses_for(ctx, "")
    out = _ext_dir(ctx, name, n)
    text = fill((TEMPLATES / "external-review.md").read_text(encoding="utf-8"), {
        "name": name, "title": team.get("title") or team["topic"], "cycle": n, "rev": rev,
        "base": team["baseline"], "tree": shlex.quote(team.get("mirror") or tree), "vcs": vcs, "delta": delta, "read_first": "\n".join(read),
        "lenses": "\n".join(f"- {lens} — {LENS_SCOPE[lens]}" for lens in lenses),
        "known_open": known_open(ctx), "out_dir": out,
        "prior": "\n".join(issue_line(i) for i in _earlier_routed(ctx, n)) or "- none",
    })
    write_atomic(out / "meta.json", json.dumps({"rev": rev, "base": team["baseline"]}) + "\n")
    write_atomic(out / "prompt.md", text)
    print(out / "prompt.md")
    return 0


def _validate_findings(data) -> list[str]:
    if not isinstance(data, list):
        return ["findings.json: top level must be an array"]
    errors = []
    for n, f in enumerate(data):
        if not isinstance(f, dict):
            errors.append(f"findings[{n}]: must be an object")
            continue
        for key in ("id", "lens", "file", "scenario"):
            if not isinstance(f.get(key), str) or not f[key].strip():
                errors.append(f"findings[{n}].{key}: required non-empty string")
        if f.get("severity") not in SEVERITIES:
            errors.append(f"findings[{n}].severity: required, one of {list(SEVERITIES)}")
        if not isinstance(f.get("line"), int) or isinstance(f.get("line"), bool) or f["line"] < 0:
            errors.append(f"findings[{n}].line: required int >= 0")
    return errors


def _validate_closure(data, required: list[dict]) -> list[str]:
    if not isinstance(data, list) or not all(isinstance(p, dict) for p in data):
        return ["prior-closure.json: top level must be an array of objects"]
    errors = [f"prior-closure[{n}]: needs id, status in {list(EXT_STATUSES)} and evidence"
              for n, p in enumerate(data) if not isinstance(p.get("id"), str)
              or p.get("status") not in EXT_STATUSES or not isinstance(p.get("evidence"), str)]
    lacking = [i["id"] for i in required if i.get("id") not in {p.get("id") for p in data}]
    if lacking:
        errors.append(f"prior-closure.json: no entry for earlier findings {lacking}")
    return errors


def _merge(master: dict, issues: list[dict], name: str) -> None:
    have = {i.get("id") for i in master.get("issues") or []}
    master.setdefault("issues", []).extend(i for i in issues if i["id"] not in have)
    counts = {s: 0 for s in SEVERITIES}
    for issue in master["issues"]:
        counts[issue["severity"]] += 1
    master["counts"] = counts
    if master["issues"]:
        master["verdict"] = "CHANGES_REQUESTED"
    master["external"] = sorted({*master.get("external", []), name})


def cmd_ingest(ctx: Ctx, args) -> int:
    n, name = args.cycle, args.name
    src = _ext_dir(ctx, name, n)
    findings = load_json(src / "findings.json", "findings.json")
    closure = load_json(src / "prior-closure.json", "prior-closure.json")
    errors = _validate_findings(findings) + _validate_closure(closure, _earlier_routed(ctx, n))
    if errors:
        raise ReviewError("; ".join(errors))
    issues = [{"id": f["id"], "severity": f["severity"], "category": f["lens"], "file": f["file"],
               "line": f["line"], "message": f["scenario"], "fix": f.get("fix", ""), "source": f"external:{name}"}
              for f in findings]
    aspect = {"reviewer": f"external:{name}", "cycle": n, "issues": issues, "previous_issues": closure,
              "verdict": "CHANGES_REQUESTED" if issues else "APPROVED",
              "counts": {s: sum(i["severity"] == s for i in issues) for s in SEVERITIES}}
    write_atomic(ctx.cycle_dir(n) / f"external-{name}.json", json.dumps(aspect, ensure_ascii=False, indent=2) + "\n")
    master = ctx.master(n)
    if master is not None:
        _merge(master, issues, name)
        write_atomic(ctx.cycle_dir(n) / "master.json", json.dumps(master, ensure_ascii=False, indent=2) + "\n")
    print(ctx.cycle_dir(n) / f"external-{name}.json")
    return 0
