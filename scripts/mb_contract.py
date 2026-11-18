#!/usr/bin/env python3
"""Executable stage contracts (contract-first): run, and freeze with a red dry run.

Usage:
  mb_contract.py run <contract.md> [--tree D] [--json] [--timeout S]
  mb_contract.py freeze <contract.md> [--tree D] [--amend --reason R]

A contract is written from the plan stage / spec task / team track BEFORE implementation, by someone other
than the executor, in `<bank>/contracts/<id>.md`: `**Covers:** REQ-001, …` (each covered REQ needs a spec item),
`## spec` (`- REQ-001 <what> — <Eval>`, acceptance from the REQ text), `## rules` and `## dod` (`- <what> — <Eval>`).
`<Eval>` is the task Eval syntax `` `<command>` — exit: N; output~: <regex> `` (default `exit: 0`) plus
`output-empty`; or `- <what> — manual: <reason>` for the verifier's judgement. Commands run with `bash -c` in
--tree (default: the project that holds the bank); a timeout kills the whole process group.

freeze: every executable spec item must FAIL now (red anchor); hash + red evidence go to `<contract>.lock.json`.
A changed lock (`drifted`) fails `run` until `freeze --amend --reason R` (recorded); an unreadable one (`corrupt`)
until it is removed and the contract frozen again.
Exit: 0 all executable items pass · 1 a failure, a covered REQ without an item, a bad lock, freeze refused ·
2 malformed contract or usage.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import mb_req_id as rq  # noqa: E402
from mb_work_items import MalformedTaskField, _parse_eval  # noqa: E402

SECTIONS = ("spec", "rules", "dod")
COVERS_RE = re.compile(r"^\*\*Covers:\*\*\s*(.*)$", re.I)
SECTION_RE = re.compile(r"^##\s+(\S+)")
TAIL = 20


class ContractError(Exception):
    pass


def parse(text: str) -> tuple[list[str], list[dict]]:
    covers, items, section = [], [], None
    for no, line in enumerate(text.splitlines(), 1):
        if m := COVERS_RE.match(line.strip()):
            covers = rq.extract_req_ids(m.group(1))
        elif m := SECTION_RE.match(line):
            section = m.group(1).lower()
            if section not in SECTIONS:
                raise ContractError(
                    f"line {no}: unknown section '## {m.group(1)}'; allowed {list(SECTIONS)}"
                )
        elif section and line.startswith("- "):
            items.append(_item(section, line[2:].strip(), no))
    if not items:
        raise ContractError("no items under ## spec / ## rules / ## dod")
    return covers, items


def _item(section: str, body: str, no: int) -> dict:
    label, sep, rest = body.partition(" — ")
    if not sep or not rest.strip():
        raise ContractError(
            f"line {no}: item needs `<what> — <Eval>` or `<what> — manual: <reason>`"
        )
    item = {"section": section, "id": label.strip(), "line": no}
    if section == "spec":
        reqs = rq.extract_req_ids(label)
        if not reqs:
            raise ContractError(f"line {no}: a spec item starts with the REQ id it checks")
        item["id"], item["reqs"] = reqs[0], reqs
    if rest.strip().startswith("manual:"):
        reason = rest.strip()[len("manual:") :].strip()
        if not reason:
            raise ContractError(f"line {no}: manual item needs a reason")
        return {**item, "manual": reason}
    try:
        ev = _parse_eval(rest)
    except MalformedTaskField as exc:
        raise ContractError(f"line {no}: {exc}") from exc
    if ev["cmd"] in ("none", ""):
        raise ContractError(f"line {no}: no command; use `manual: <reason>`")
    return {
        **item,
        "cmd": ev["cmd"],
        "exit": 0 if ev["exit"] is None else ev["exit"],
        "output_re": ev["output_re"],
        "output_empty": "output-empty" in rest.partition(" — ")[2],
    }


def run_shell(cmd: str, cwd: str, timeout: int) -> tuple[int | None, str, str]:
    """(exit code, stdout, stderr) of `bash -c cmd`; on timeout the whole process group is killed → code None."""
    proc = subprocess.Popen(["bash", "-c", cmd], cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, start_new_session=True)
    try:
        stdout, stderr = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        return None, "", ""
    return proc.returncode, stdout, stderr


def run_item(item: dict, tree: str, timeout: int) -> dict:
    out = {k: item[k] for k in ("section", "id", "line")}
    if "manual" in item:
        return {**out, "status": "manual", "reason": item["manual"]}
    code, stdout, stderr = run_shell(item["cmd"], tree, timeout)
    if code is None:
        return {**out, "status": "fail", "reason": f"timeout after {timeout}s", "cmd": item["cmd"]}
    text = stdout + stderr
    reasons = []
    if code != item["exit"]:
        reasons.append(f"exit {code}, expected {item['exit']}")
    if item["output_re"] and not re.search(item["output_re"], text):
        reasons.append(f"output does not match /{item['output_re']}/")
    if item["output_empty"] and stdout.strip():
        reasons.append("output is not empty")
    tail = "\n".join(text.strip().splitlines()[-TAIL:])
    return {
        **out,
        "status": "fail" if reasons else "pass",
        "reason": "; ".join(reasons),
        "cmd": item["cmd"],
        "exit": code,
        "tail": tail,
    }


def _lock_path(contract: Path) -> Path:
    return contract.with_name(contract.name + ".lock.json")


def _sha(contract: Path) -> str:
    return hashlib.sha256(contract.read_bytes()).hexdigest()


def frozen_state(contract: Path) -> str:
    """`yes` (lock matches), `no` (no lock), `drifted` (changed since freeze) or `corrupt` (unreadable lock)."""
    lock = _lock_path(contract)
    if not lock.is_file():
        return "no"
    try:
        sha = json.loads(lock.read_text(encoding="utf-8"))["sha256"]
    except (OSError, ValueError, KeyError, TypeError):
        return "corrupt"
    return (
        "yes"
        if sha == _sha(contract)
        else "drifted"
    )


def run(contract: Path, tree: str, timeout: int) -> dict:
    covers, items = parse(contract.read_text(encoding="utf-8"))
    results = [run_item(i, tree, timeout) for i in items]
    have = {r for i in items if i["section"] == "spec" for r in i["reqs"]}
    results += [
        {
            "section": "spec",
            "id": req,
            "line": 0,
            "status": "fail",
            "reason": "no contract item for covered REQ (CRITICAL)",
        }
        for req in covers
        if req not in have
    ]
    frozen = frozen_state(contract)
    if frozen in ("drifted", "corrupt"):
        results.append(
            {
                "section": "contract",
                "id": "freeze",
                "line": 0,
                "status": "fail",
                "reason": "contract changed since freeze; amend with `freeze --amend --reason R`"
                if frozen == "drifted" else "lock file is unreadable; remove it and freeze again (the red run repeats)",
            }
        )
    summary = {s: sum(1 for r in results if r["status"] == s) for s in ("pass", "fail", "manual")}
    return {"contract": str(contract), "frozen": frozen, "items": results, "summary": summary,
            "amendments": _amendments(contract) if frozen == "yes" else []}


def _amendments(contract: Path) -> list[dict]:
    """Recorded changes after freeze — the verifier checks each one was the orchestrator's decision."""
    lock = json.loads(_lock_path(contract).read_text(encoding="utf-8"))
    return [{"reason": a["reason"], "at": a["at"]} for a in lock.get("amendments", [])]


def freeze(contract: Path, tree: str, timeout: int, amend: bool, reason: str) -> int:
    lock_path, sha = _lock_path(contract), _sha(contract)
    _covers, items = parse(contract.read_text(encoding="utf-8"))
    if frozen_state(contract) == "corrupt":
        print(f"{lock_path} is unreadable: remove it and freeze again (the red run repeats)", file=sys.stderr)
        return 1
    lock = json.loads(lock_path.read_text(encoding="utf-8")) if lock_path.is_file() else None
    now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    if amend:
        if lock is None or not reason:
            print("freeze --amend needs an existing lock and --reason", file=sys.stderr)
            return 2
        lock["amendments"].append({"at": now, "reason": reason, "from": lock["sha256"], "to": sha})
        lock["sha256"] = sha
    else:
        if lock is not None and lock["sha256"] != sha:
            print(
                "contract changed since freeze: amend it with --amend --reason R", file=sys.stderr
            )
            return 1
        red = [
            run_item(i, tree, timeout)
            for i in items
            if i["section"] == "spec" and "manual" not in i
        ]
        weak = [i["id"] for i in items if i["section"] == "spec" and "cmd" in i
                and not i["output_re"] and not i["output_empty"]]
        if weak:
            print(f"warning: exit-only anchor on {', '.join(weak)} — `go test -run X` exits 0 with no matching "
                  "test; add `output~:` naming the test (e.g. `--- PASS: TestX`)", file=sys.stderr)
        if not red:
            print("warning: no executable spec item — the freeze has no red evidence that the checks target "
                  "missing behaviour", file=sys.stderr)
        green = [r["id"] for r in red if r["status"] == "pass"]
        if green:
            print(
                f"red anchor not proven — already passing: {', '.join(green)}; a spec item must fail before "
                "the implementation exists",
                file=sys.stderr,
            )
            return 1
        lock = {
            "sha256": sha,
            "frozen_at": now,
            "amendments": [],
            "red": [
                {
                    "id": r["id"],
                    "exit": r.get("exit"),
                    "reason": r["reason"],
                    "tail": r.get("tail", ""),
                }
                for r in red
            ],
        }
    lock_path.write_text(json.dumps(lock, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(lock_path)
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="mb_contract.py")
    parser.add_argument("command", choices=("run", "freeze"))
    parser.add_argument("contract")
    parser.add_argument("--tree", default="")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--amend", action="store_true")
    parser.add_argument("--reason", default="")
    args = parser.parse_args(argv)
    contract = Path(args.contract).resolve()
    # <project>/.memory-bank/contracts/<id>.md → <project>
    tree = args.tree or str(contract.parents[2] if len(contract.parents) > 2 else contract.parent)
    try:
        if args.command == "freeze":
            return freeze(contract, tree, args.timeout, args.amend, args.reason)
        result = run(contract, tree, args.timeout)
    except (ContractError, OSError, ValueError) as exc:
        print(f"mb_contract: {contract}: {exc}", file=sys.stderr)
        return 2
    if args.json:
        print(json.dumps(result, ensure_ascii=False))
    else:
        for r in result["items"]:
            print(
                f"{r['status']:<6} {r['section']:<8} {r['id']}"
                + (f" — {r['reason']}" if r.get("reason") else "")
            )
        s = result["summary"]
        print(
            f"pass {s['pass']} · fail {s['fail']} · manual {s['manual']} · frozen {result['frozen']}"
        )
    return 1 if result["summary"]["fail"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
