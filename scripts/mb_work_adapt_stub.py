"""Staged-stub gate for ADaPT (svp-adapt-escalation design C4/C5, REQ-009/REQ-004).

``verify-stub`` proves a stub is fenced: marker line -> existing backlog item, the flag token steers
real code, and the ``eval=`` driver prints ``baseline`` without the flag and ``staged`` with it.
``stub-backlog`` (see bottom) sequences the shipped backlog writers; it never edits backlog.md.

Exit: 0 clean · 1 violations / halted chain · 2 usage or broken tooling.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import signal
import subprocess
import sys

MARKER = re.compile(r"MB-ADAPT-STUB\s+backlog=(I-\d+)\s+flag=([A-Z][A-Z0-9_]*)(?:\s+eval=(\S+))?")
MARKER_POS = re.compile(r"^\s*(\"\"\"|'''|///|//|/\*|\*|#|--|;)?\s*MB-ADAPT-STUB\s")
PLACEHOLDER = re.compile(r"raise\s+NotImplementedError|\bTODO\b|\bFIXME\b|^\s*\.\.\.\s*$")
PATH_LINE = "MB-ADAPT-STUB-PATH:"


class ToolingError(Exception):
    """A driver or input is unusable (exit 2), never a silent pass."""


def _timeout() -> float:
    try:
        return float(os.environ.get("MB_ADAPT_STUB_TIMEOUT", "120"))
    except ValueError:
        return 120.0


def _run_driver(repo: pathlib.Path, driver: pathlib.Path, flag: str, on: bool):
    """Run the driver once in its own process group; (rc, stdout) or None on timeout."""
    env = {k: v for k, v in os.environ.items() if k != flag}
    if on:
        env[flag] = "1"
    proc = subprocess.Popen(
        [str(driver)],
        cwd=repo,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        out, _ = proc.communicate(timeout=_timeout())
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        return None
    return proc.returncode, out


def _prove_fencing(repo: pathlib.Path, eval_rel: str, flag: str) -> str:
    """'' when the driver proves the fence, else the violation code."""
    driver = (repo / eval_rel).resolve()
    if (
        repo.resolve() not in driver.parents
        or not driver.is_file()
        or not os.access(driver, os.X_OK)
    ):
        raise ToolingError(f"stub driver missing or not executable: {eval_rel}")
    off = _run_driver(repo, driver, flag, on=False)
    if off is None:
        return "stub_eval_timeout"
    if off[0] != 0:
        return "stub_eval_failed"
    if f"{PATH_LINE} staged" in off[1]:
        return "flag_default_on"
    if f"{PATH_LINE} baseline" not in off[1]:
        return "flag_does_not_gate_stub"
    on = _run_driver(repo, driver, flag, on=True)
    if on is None:
        return "stub_eval_timeout"
    if on[0] != 0:
        return "stub_eval_failed"
    return "" if f"{PATH_LINE} staged" in on[1] else "flag_does_not_gate_stub"


def _check_file(repo: pathlib.Path, rel: str, known: set[str]):
    lines = (repo / rel).read_text(encoding="utf-8", errors="replace").splitlines()
    stubs, bad = [], []
    marked = [(n, ln) for n, ln in enumerate(lines, 1) if "MB-ADAPT-STUB " in ln]
    if not marked:
        bad = [
            {"file": rel, "line": n, "reason": "bare_placeholder"}
            for n, ln in enumerate(lines, 1)
            if PLACEHOLDER.search(ln)
        ]
    for n, ln in marked:
        found = []
        m = MARKER.search(ln)
        if not MARKER_POS.match(ln):
            found.append("marker_not_in_docstring")
        if not m:
            bad += [{"file": rel, "line": n, "reason": r} for r in found or ["missing_stub_eval"]]
            continue
        bid, flag, ev = m.groups()
        if bid not in known:
            found.append("unknown_backlog_id")
        if not any(flag in other for i, other in enumerate(lines, 1) if i != n):
            found.append("flag_token_unused")
        if ev is None:
            found.append("missing_stub_eval")
        elif not found:
            code = _prove_fencing(repo, ev, flag)
            found += [code] if code else []
        bad += [{"file": rel, "line": n, "reason": r} for r in found]
        if not found:
            stubs.append({"file": rel, "backlog_id": bid, "flag": flag, "eval": ev})
    return stubs, bad


def verify_stub(repo: pathlib.Path, diff_file: pathlib.Path, backlog: pathlib.Path) -> dict:
    if not (repo.is_dir() and diff_file.is_file() and backlog.is_file()):
        raise ToolingError("--repo, --diff-file and --backlog must exist")
    known = set(re.findall(r"^###\s+(I-\d+)\b", backlog.read_text(encoding="utf-8"), re.M))
    out: dict = {"stubs": [], "violations": []}
    for rel in dict.fromkeys(ln.strip() for ln in diff_file.read_text().splitlines() if ln.strip()):
        if (repo / rel).is_file():
            stubs, bad = _check_file(repo, rel, known)
            out["stubs"] += stubs
            out["violations"] += bad
    return out


def cli_verify(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="mb_work_adapt.py verify-stub")
    for flag in ("--repo", "--diff-file", "--backlog"):
        ap.add_argument(flag, required=True)
    a = ap.parse_args(argv)
    try:
        out = verify_stub(pathlib.Path(a.repo), pathlib.Path(a.diff_file), pathlib.Path(a.backlog))
    except ToolingError as exc:
        print(f"[adapt] verify-stub: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(out, ensure_ascii=False))
    return 1 if out["violations"] else 0


# ── stub-backlog: thin sequencer over mb-idea.sh / mb-backlog-state.sh (design C5) ──
SCRIPTS = pathlib.Path(__file__).resolve().parent
NEXT_STATE = {"NEW": "NEEDS-INFO", "NEEDS-INFO": "TRIAGED", "TRIAGED": "READY"}
REUSE_STATES = ("READY", "IN-PROGRESS")
_FLAG = re.compile(r"[A-Z][A-Z0-9_]*\Z")
_CAPABILITY = re.compile(r"[A-Za-z0-9 ,-]+\Z")
_SLUG = re.compile(r"[A-Za-z0-9._-]+\Z")
BRIEF = (
    "While {flag} is off, the existing behavior shall remain unchanged; "
    "when {flag} is on, {capability} shall be available."
)


class Halt(Exception):
    """The backlog chain cannot reach READY: stop the stub path before any code (exit 1)."""


def _script(name: str, *args: str) -> str:
    res = subprocess.run(["bash", str(SCRIPTS / name), *args], capture_output=True, text=True)
    if res.returncode != 0:
        raise Halt(f"{name} {args[0]}: {res.stderr.strip() or res.stdout.strip()}")
    return res.stdout


def _state_of(bank: str, item: str) -> str:
    listing = _script("mb-backlog-state.sh", "list", "--mb", bank)
    m = re.search(rf"^item={re.escape(item)} state=(\S+)", listing, re.M)
    if not m:
        raise Halt(f"{item} is not listed in the backlog")
    return m.group(1)


def stub_backlog(
    bank: str, topic: str, task_id: str, reason: str, flag: str, capability: str
) -> str:
    title = f"[ADAPT] {topic}#{task_id}: {reason}"
    item = _script("mb-idea.sh", title, "HIGH", bank).strip().splitlines()[-1]
    state = _state_of(bank, item)
    while state not in REUSE_STATES:
        if state not in NEXT_STATE:
            raise Halt(f"{item} is {state}: not a stub target")
        if NEXT_STATE[state] == "READY":
            _script(
                "mb-backlog-state.sh",
                "annotate",
                item,
                "--brief",
                BRIEF.format(flag=flag, capability=capability.strip()),
                "--mb",
                bank,
            )
        _script("mb-backlog-state.sh", "transition", item, NEXT_STATE[state], "--mb", bank)
        state = NEXT_STATE[state]
    return item


def cli_backlog(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="mb_work_adapt.py stub-backlog")
    for flag in ("--bank", "--spec-topic", "--task-id", "--reason", "--flag", "--capability"):
        ap.add_argument(flag, required=True)
    a = ap.parse_args(argv)
    one_line = a.reason.strip() and "\n" not in a.reason
    if not (
        _FLAG.match(a.flag)
        and _CAPABILITY.match(a.capability)
        and _SLUG.match(a.spec_topic)
        and a.task_id.isdigit()
        and one_line
    ):
        print(
            "[adapt] stub-backlog: invalid --flag/--capability/--spec-topic/--task-id/--reason",
            file=sys.stderr,
        )
        return 2
    try:
        print(stub_backlog(a.bank, a.spec_topic, a.task_id, a.reason.strip(), a.flag, a.capability))
    except Halt as exc:
        print(f"[adapt] stub-backlog halted: {exc}", file=sys.stderr)
        return 1
    return 0
