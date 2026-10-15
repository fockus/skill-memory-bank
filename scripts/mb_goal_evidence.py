#!/usr/bin/env python3
"""Evidence acceptance for goal files with linked criteria (drive-autopilot C1).

Usage: mb_goal_evidence.py <goal-path> <bank> [--tick]

A criterion under `## Acceptance criteria` may carry indented link sub-bullets:
`  - plan: <bank-relative path>` and `  - check: <command>`. When no criterion
carries a link, nothing is printed (the caller keeps plain checkbox counting).
Otherwise one JSON line is printed:
  {"name":"acceptance","ok":..,"findings":[..],"unbacked":[..],"criteria":[..]}
A criterion is met when it has >= 1 link, every plan is closed (all of its work
items are done) and every check exits 0; checks run only once the plans are
closed. `--tick` rewrites each linked criterion's box to its result. Exit 0.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from mb_work_items import parse_work_items  # noqa: E402
from mb_work_plan_wrapper import fm_value  # noqa: E402

_FENCE_RE = re.compile(r"^\s*(```+|~~~+)")
_SECTION_RE = re.compile(r"^##\s+[Aa]cceptance\s+criteria\s*$")
_CRIT_RE = re.compile(r"^(\s*-\s+\[)([ xX])(\]\s*)(.*)$")
_LINK_RE = re.compile(r"^\s+-\s+(plan|check):\s*(.*?)\s*$")
_RANGE_RE = re.compile(r"^(\d+)(?:-(\d*))?$")




def parse_goal(lines: list[str]) -> list[dict]:
    """Criteria of the acceptance section, fence-aware like mb-goal-acceptance.sh."""
    crits: list[dict] = []
    in_acc = False
    fence = ""
    for idx, line in enumerate(lines):
        m = _FENCE_RE.match(line)
        if m and (not fence or line.strip().startswith(fence)):
            fence = "" if fence else m.group(1)
            continue
        if fence:
            continue
        if _SECTION_RE.match(line):
            in_acc = True
            continue
        if in_acc and line.startswith("#"):
            in_acc = False
        if not in_acc:
            continue
        cm = _CRIT_RE.match(line)
        if cm:
            crits.append(
                {
                    "idx": idx,
                    "ticked": cm.group(2) != " ",
                    "label": cm.group(4),
                    "links": [],
                    "bad": [],
                }
            )
            continue
        lm = _LINK_RE.match(line)
        if lm and crits:
            kind, value = lm.groups()
            if kind == "plan":
                value = re.split(r"\s+#", value)[0].strip()
            if value:
                crits[-1]["links"].append((kind, value))
            else:
                crits[-1]["bad"].append(line.strip())
    return crits


def _frontmatter(text: str) -> str | None:
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return m.group(1) if m else None


def _inside(root: pathlib.Path, path: pathlib.Path) -> bool:
    real = root.resolve()
    return os.path.commonpath([real, path.resolve()]) == str(real)


def _plan_items(plan: pathlib.Path, bank: pathlib.Path):
    """Work items a plan resolves to: its stages, or a wrapper's spec tasks in range."""
    fm = _frontmatter(plan.read_text(encoding="utf-8")) or ""
    spec = fm_value(fm, "linked_spec")
    if spec is None:
        return parse_work_items(plan)
    tasks = bank / spec / "tasks.md"
    if not _inside(bank, tasks) or not tasks.is_file():
        raise ValueError(f"linked_spec tasks not found: {spec}")
    items = parse_work_items(tasks)
    rng = fm_value(fm, "tasks")
    if not rng:
        return items
    m = _RANGE_RE.match(str(rng))
    if not m:
        raise ValueError(f"bad tasks range: {rng}")
    start = int(m.group(1))
    end = start if m.group(2) is None else int(m.group(2) or len(items))
    return items[start - 1 : end]


def plan_closed(rel: str, bank: pathlib.Path) -> tuple[bool, str | None]:
    """(closed, problem) for a bank-relative plan path with the plans/done fallback."""
    path = bank / rel
    if not _inside(bank, path):
        return False, f"plan escapes the bank: {rel}"
    if not path.is_file():
        path = bank / "plans" / "done" / pathlib.Path(rel).name
    if not path.is_file():
        return False, f"plan not found: {rel}"
    try:
        items = _plan_items(path, bank)
    except (ValueError, OSError) as exc:
        return False, f"plan unreadable: {rel}: {exc}"
    if not items:
        return False, f"plan has no work items: {rel}"
    return all(i.status == "done" for i in items), None


def run_check(cmd: str, root: pathlib.Path) -> int:
    timeout = int(os.environ.get("MB_GOAL_CHECK_TIMEOUT", "900"))
    try:
        return subprocess.run(
            ["bash", "-c", cmd],
            cwd=root,
            timeout=timeout,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode
    except subprocess.TimeoutExpired:
        return 124


def project_root(bank: pathlib.Path) -> pathlib.Path:
    res = subprocess.run(
        ["git", "-C", str(bank), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    top = res.stdout.strip()
    return pathlib.Path(top) if res.returncode == 0 and top else bank.resolve().parent


def evaluate(crit: dict, bank: pathlib.Path, root: pathlib.Path) -> tuple[dict, list[str]]:
    label = crit["label"]
    problems = [f"{label}: malformed link: {b}" for b in crit["bad"]]
    plans, checks = [], []
    for kind, value in crit["links"]:
        if kind == "plan":
            closed, problem = plan_closed(value, bank)
            plans.append({"path": value, "closed": closed})
            if problem:
                problems.append(f"{label}: {problem}")
    closed_all = all(p["closed"] for p in plans)
    for kind, value in crit["links"]:
        if kind == "check":
            checks.append({"cmd": value, "exit": run_check(value, root) if closed_all else None})
    met = (
        bool(crit["links"])
        and not crit["bad"]
        and closed_all
        and all(c["exit"] == 0 for c in checks)
    )
    if not crit["links"] and not crit["bad"]:
        problems.append(f"{label} — no evidence link")
    elif not met and not problems:
        problems.append(label)
    return {"label": label, "met": met, "plans": plans, "checks": checks}, problems


def tick(goal: pathlib.Path, lines: list[str], crits: list[dict], results: list[dict]) -> None:
    for crit, res in zip(crits, results, strict=True):
        if crit["links"]:
            m = _CRIT_RE.match(lines[crit["idx"]])
            lines[crit["idx"]] = f"{m.group(1)}{'x' if res['met'] else ' '}{m.group(3)}{m.group(4)}"
    fd, tmp = tempfile.mkstemp(dir=goal.parent, prefix=f".{goal.name}.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write("".join(f"{ln}\n" for ln in lines))
    os.chmod(tmp, goal.stat().st_mode & 0o7777)  # mkstemp creates 0600
    os.replace(tmp, goal)


def main(argv: list[str]) -> int:
    goal, bank = pathlib.Path(argv[0]), pathlib.Path(argv[1])
    lines = goal.read_text(encoding="utf-8").splitlines()
    crits = parse_goal(lines)
    if not any(c["links"] or c["bad"] for c in crits):
        return 0
    root = project_root(bank)
    results, findings = [], []
    for n, crit in enumerate(crits, 1):
        res, problems = evaluate(crit, bank, root)
        results.append({"n": n, **res})
        findings.extend(problems)
    unbacked = [
        c["label"] for c, r in zip(crits, results, strict=True) if c["ticked"] and not r["met"]
    ]
    if "--tick" in argv[2:]:
        tick(goal, lines, crits, results)
    out = {
        "name": "acceptance",
        "ok": all(r["met"] for r in results),
        "findings": findings,
        "unbacked": unbacked,
        "criteria": results,
    }
    print(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
