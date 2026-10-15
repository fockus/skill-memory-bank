#!/usr/bin/env python3
"""Shared state of the team review (mb_team_review.py): config, paths, cycle masters, issue routing."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import mb_pipeline_validate_team as schema  # noqa: E402
import mb_team_state as st  # noqa: E402
from mb_team_config import load_configs  # noqa: E402

SEVERITIES = schema.SEVERITIES
CLOSED = ("resolved", "superseded", "closed")
PREV_STATUSES = (*CLOSED, "unresolved", "open", "partial")
EXT_STATUSES = ("closed", "open", "partial")
LENS_SCOPE = {
    "logic": "correctness, edge cases, contracts between components",
    "tests": "behaviour coverage, failing-first evidence, flaky or vacuous tests",
    "code_rules": "SRP/DRY, layering, naming, no placeholders",
    "security": "input validation at boundaries, secrets, authorization, injection",
    "scalability": "N+1, blocking IO, unbounded growth, lock contention",
}
LENS_FORMAT = ('{"reviewer", "focus", "cycle", "verdict": "APPROVED|CHANGES_REQUESTED", '
               '"counts": {"blocker", "major", "medium", "minor"}, '
               '"issues": [{"id", "severity", "category", "file", "line", "message", "fix"}], '
               '"previous_issues": [{"id", "status": "resolved|unresolved|superseded", "evidence"}]}')


class ReviewError(Exception):
    pass


def load_json(path: Path, what: str):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ReviewError(f"{what}: {path} not found") from exc
    except ValueError as exc:
        raise ReviewError(f"{what}: {path}: invalid JSON: {exc}") from exc


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


class Ctx:
    def __init__(self, args):
        self.bank = os.path.abspath(args.mb)
        self.team = load_json(Path(args.team), "team.json")
        self.review_dir = Path(os.path.abspath(args.team)).parent / "review"
        _project, _bundled, team_cfg = load_configs(args.pipeline, self.bank)
        self.cfg = team_cfg["review"]
        self.clean_when = self.cfg.get("clean_when") or {"blocker": 0, "major": 0, "medium": 0}
        self.enabled = bool(self.cfg.get("enabled")) or bool(self.team.get("team_review"))

    def cycle_dir(self, n: int) -> Path:
        return self.review_dir / f"cycle-{n}"

    def master(self, n: int) -> dict | None:
        path = self.cycle_dir(n) / "master.json"
        return load_json(path, f"cycle {n} master") if path.exists() else None

    def owner(self, issue: dict) -> str | None:
        ids = [t["id"] for t in self.team.get("tracks") or []]
        if issue.get("owner") in ids:
            return issue["owner"]
        path = str(issue.get("file") or "")
        for root in (self.team.get("tree"), self.team.get("mirror")):
            prefix = (root or "").rstrip("/") + "/"
            if root and path.startswith(prefix):
                path = path[len(prefix):]
                break
        for track in self.team.get("tracks") or []:
            if st.owns(track, path):
                return track["id"]
        return None

    def routed(self, issue: dict) -> bool:
        return issue.get("severity") in self.clean_when


def to_close(ctx: Ctx, master: dict | None) -> list[dict]:
    """Issues a later cycle must give a status for: routed issues plus still-open previous ones."""
    if not master:
        return []
    out = [i for i in master.get("issues") or [] if ctx.routed(i)]
    seen = {i.get("id") for i in out}
    out += [p for p in master.get("previous_issues") or []
            if p.get("status") not in CLOSED and p.get("id") not in seen]
    return out


def issue_line(issue: dict) -> str:
    sev = issue.get("severity", issue.get("status", "?"))
    return f"- {issue.get('id')} ({sev}): {issue.get('message') or issue.get('evidence') or ''}".rstrip()


def lenses_for(ctx: Ctx, csv: str) -> list[str]:
    names = [n.strip() for n in csv.split(",") if n.strip()] if csv else list(ctx.cfg.get("lenses") or [])
    out = []
    for name in names:
        lens = schema.normalize_lens(name)
        if lens is None:
            raise ReviewError(f"unknown lens '{name}'; allowed {list(LENS_SCOPE)} (+ alias quality)")
        if lens not in out:
            out.append(lens)
    if not out:
        raise ReviewError("no lenses: set team.review.lenses or pass --lenses")
    return out


def known_open(ctx: Ctx) -> str:
    return "\n".join(f"- {k}" for k in ctx.team.get("known_open") or []) or "- none"
