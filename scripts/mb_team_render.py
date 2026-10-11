#!/usr/bin/env python3
"""Render the /mb team brief and track prompts from team.json (C1) + the team config.

Usage:
  mb_team_render.py brief --team <team.json> --mb <bank> [--pipeline F] [--skill-dir D] [--out F]
  mb_team_render.py track <id> --team <team.json> --mb <bank> [--pipeline F] [--skill-dir D] [--out F]
  mb_team_render.py unfilled <file>

Templates: templates/team/{brief,track-prompt}.md with `{{name}}` slots. Every
path is rendered absolute (bank-relative paths of team.json are joined to the
bank, track globs to the tree) and every Memory Bank command carries `--mb`.
The brief keeps `<!-- fill: … -->` hints in the sections only the orchestrator
can write; `unfilled` lists them as `<line>: <hint>` (exit 1 when any remain),
and no track is ready while the brief has one (REQ-TEAM-033).

Exit codes: 0 ok · 1 unfilled hints found · 2 bad input (unknown track, no DoD,
invalid config).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from mb_team_config import ConfigError, load_configs, resource_json  # noqa: E402

TEMPLATES = HERE.parent / "templates" / "team"
HINT_RE = re.compile(r"<!--\s*fill:\s*(.*?)\s*-->")
SLOT_RE = re.compile(r"\{\{(\w+)\}\}")
BUILTIN_RULES = (
    "Failing test first, then code. Put the test command and its output before and after the change into the report.",
    "Minimal diff in the layer that owns the invariant; no general refactors.",
    "Do not commit, push or open PRs: the orchestrator commits. Do not change permissions, settings or CLAUDE.md.",
    "Do not read or print secrets. Protected paths: .env*, CI, Docker/K8s/Terraform.",
    "Report to the orchestrator only; never message other tracks. Findings that affect another track: "
    "HANDOVER on the board.",
    "A safety-filter refusal is reported as BLOCKED, not worked around.",
)


class RenderError(Exception):
    pass


def fill(template: str, slots: dict) -> str:
    def sub(match: re.Match) -> str:
        if match.group(1) not in slots:
            raise RenderError(f"template slot {{{{{match.group(1)}}}}} has no value")
        return str(slots[match.group(1)])

    return SLOT_RE.sub(sub, template)


def unfilled(path: str) -> list[tuple[int, str]]:
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    return [(no, hint) for no, line in enumerate(lines, 1) for hint in HINT_RE.findall(line)]


def _abs(bank: str, rel) -> str:
    return os.path.join(bank, rel) if rel else ""


def pipeline_words(p: dict) -> str:
    """Short form for the tracks table: `direct · TDD · review single`."""
    parts = ["direct" if p["mode"] == "direct" else f"work ({p.get('work') or 'orchestrated'})"]
    parts.append("TDD" if p["tdd"] == "required" else "TDD optional")
    if p["verifier"] != "none":
        parts.append("verifier")
    if p["review"] == "single":
        parts.append("review single")
    elif p["review"] == "lenses":
        parts.append("lenses " + ", ".join(p["lenses"]))
    return " · ".join(parts)


def _post_steps(p: dict) -> str:
    models = p.get("models") or {}
    steps = []
    if p["verifier"] != "none":
        steps.append(f"plan-verifier ({models.get('verifier', 'inherit')}) against the DoD above")
    if p["review"] == "single":
        steps.append(f"one reviewer ({models.get('reviewer', 'inherit')}) on your diff")
    elif p["review"] == "lenses":
        steps.append(f"lens reviewers ({', '.join(p['lenses'])}) on {models.get('lenses', 'inherit')} "
                     f"and a lead ({models.get('lead', 'inherit')}) on your diff")
    if not steps:
        return "the orchestrator runs no verifier and no per-track review."
    tail = "; there is no verifier." if p["verifier"] == "none" else "."
    return "the orchestrator runs " + ", then ".join(steps) + tail


def pipeline_lines(track: dict, bank: str) -> list[str]:
    p = track["pipeline"]
    source = _abs(bank, track.get("source"))
    if p["mode"] == "direct":
        first = "You implement directly. After you return, " + _post_steps(p)
    elif p.get("work") == "light":
        first = (f"You walk the stages of {source} yourself, in order, ticking each DoD box as it is met. "
                 "After you return, " + _post_steps(p))
    else:
        first = (f"This track runs through /mb work on {source}, driven by the orchestrator: you are "
                 "dispatched per stage, and the verifier and review gates run inside that loop.")
    lines = [first]
    if p["tdd"] == "required":
        lines.append("TDD is required: failing test first; paste the command and output before and after into the report.")
    else:
        lines.append("TDD is optional: add tests where behaviour changes; paste the test command and output into the report.")
    for res in track.get("resources") or []:
        lines.append(f"Resource `{res}`: see the brief, section Resources. Run it in the background with "
                     f"`--owner {track['id']}`.")
    return [f"- {line}" for line in lines]


def _resource_block(res: dict, lock: str, bank: str) -> str:
    pre, stop = res["preconditions"], res["stop_threshold"]
    text = (f"- **{res['name']}** — every command that needs it goes through\n"
            f"  `{lock} run {res['name']} --owner <track> --mb {bank} -- <command>`.\n"
            "  Start it in the background and keep writing code and tests while it waits.")
    sentences = []
    if res["maintenance"] and pre["free_disk_gb"] is not None:
        sentences.append(f"It runs `{res['maintenance']}` itself when free disk is below {pre['free_disk_gb']} GiB;")
    if pre["free_disk_gb"] is not None or pre["check"]:
        sentences.append("exit 77 means the start preconditions still fail — report BLOCKED.")
    if stop["free_disk_gb"] is not None:
        sentences.append(f"Exit 76 means free disk fell under {stop['free_disk_gb']} GiB during the run and the "
                         "command was stopped.")
    sentences.append("Never remove a lock; ask the orchestrator.")
    return text + _wrap(" ".join(sentences), first=len(text.splitlines()[-1]))


def _wrap(text: str, first: int, width: int = 118) -> str:
    """Continue a bullet at two-space indent, wrapping at `width` like the examples."""
    out, line, used = [], "", first
    for word in text.split():
        if used + len(line) + len(word) + 1 > width and line:
            out.append(line)
            line, used = word, 2
        else:
            line = f"{line} {word}" if line else word
    out.append(line)
    return " " + "\n  ".join(out)


def render_brief(team: dict, bank: str, skill: str, team_cfg: dict) -> str:
    rows, used = [], []
    for t in team["tracks"]:
        used += [r for r in t.get("resources") or [] if r not in used]
        rows.append(f"| {t['id']} | {t['role']} | {t['pipeline']['models'].get('executor', 'inherit')} | "
                    f"{t['size']} | {pipeline_words(t['pipeline'])} | {t.get('title') or t['task']} | "
                    f"{', '.join(t.get('deps') or []) or '—'} | {', '.join(t.get('resources') or []) or '—'} | "
                    f"{_abs(bank, t['report'])} |")
    tree = f"- Edit only in {team['tree']} ({team['vcs']})."
    if team.get("mirror"):
        tree += f" {team['mirror']} is a clean mirror for bundles: do not touch."
    lock = f"bash {skill}/scripts/mb-lock.sh"
    resources = []
    for name in used:
        if name not in team_cfg["resources"]:
            raise RenderError(f"resource '{name}' is used by a track but not declared in team.resources")
        resources.append(_resource_block(resource_json(team_cfg, name, bank), lock, bank))
    known = [f"- {k['id']} — {k['reason']} (since {k['since']})." for k in team.get("known_red") or []]
    goal = f"{team['goal']} ({bank}/goal.md)." if team.get("goal") else "none (team started with --no-goal)."
    slots = {
        "title": team.get("title") or team["topic"], "date": team["created"][:10], "topic": team["topic"],
        "plan": _abs(bank, team.get("plan")) or "none", "goal": goal, "tracks": "\n".join(rows),
        "working_tree": tree + f"\n- Run Memory Bank commands with `--mb {bank}`, never from inside the bank directory.",
        "rules": "\n".join(f"- {r}" for r in (*BUILTIN_RULES, *team_cfg["rules"])),
        "resources": "\n".join(resources) or "- none",
        "known_red": "\n".join(known) or "- none",
        "coord": f"bash {skill}/scripts/mb-coord.sh", "bank": bank,
        "reports": os.path.dirname(_abs(bank, team["brief"])),
    }
    return fill((TEMPLATES / "brief.md").read_text(encoding="utf-8"), slots)


def render_track(team: dict, track_id: str, bank: str, skill: str) -> str:
    track = next((t for t in team["tracks"] if t["id"] == track_id), None)
    if track is None:
        raise RenderError(f"unknown track '{track_id}'; tracks {[t['id'] for t in team['tracks']]}")
    if not track.get("dod"):
        raise RenderError(f"track {track_id}: no DoD (track.dod) — a track prompt is a one-stage plan")
    reports = {t["id"]: _abs(bank, t["report"]) for t in team["tracks"]}
    deps = [f"{d} (read {reports.get(d, d)} before you rely on its work)" for d in track.get("deps") or []]
    slots = {
        "id": track_id, "title": track.get("title") or track["task"].splitlines()[0],
        "brief": _abs(bank, team["brief"]), "agent": track["agent"],
        "model": track["pipeline"]["models"].get("executor", "inherit"), "size": track["size"],
        "skill": skill, "tree": team["tree"], "bank": bank, "task": track["task"].strip(),
        "role": track["role"],
        "files": ", ".join(f"`{os.path.join(team['tree'], g)}`" for g in track.get("files") or []) or "—",
        "deps": "; ".join(deps) or "—", "dod": "\n".join(f"- [ ] {d}" for d in track["dod"]),
        "pipeline": "\n".join(pipeline_lines(track, bank)), "report": reports[track_id],
    }
    return fill((TEMPLATES / "track-prompt.md").read_text(encoding="utf-8"), slots)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="mb_team_render.py")
    parser.add_argument("command", choices=("brief", "track", "unfilled"))
    parser.add_argument("target", nargs="?")
    parser.add_argument("--team", default="")
    parser.add_argument("--mb", default="")
    parser.add_argument("--pipeline", default="")
    parser.add_argument("--skill-dir", default=str(HERE.parent))
    parser.add_argument("--out", default="")
    args = parser.parse_args(argv)
    if args.command == "unfilled":
        hints = unfilled(args.target or "")
        for no, hint in hints:
            print(f"{no}: {hint}")
        return 1 if hints else 0
    try:
        if not args.team or not args.mb:
            raise RenderError("--team and --mb are required")
        bank = os.path.abspath(args.mb)
        team = json.loads(Path(args.team).read_text(encoding="utf-8"))
        if args.command == "brief":
            _project, _bundled, team_cfg = load_configs(args.pipeline, bank)
            text = render_brief(team, bank, args.skill_dir, team_cfg)
        else:
            text = render_track(team, args.target or "", bank, args.skill_dir)
    except ConfigError as exc:
        sys.stderr.write("".join(f"[team] {m}\n" for m in exc.errors))
        return 2
    except (RenderError, OSError, ValueError, KeyError) as exc:
        sys.stderr.write(f"[team] {exc}\n")
        return 2
    if args.out:
        Path(args.out).write_text(text, encoding="utf-8")
        print(args.out)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
