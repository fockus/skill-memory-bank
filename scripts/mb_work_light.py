#!/usr/bin/env python3
"""Acceptance of a `light` work-mode track result (AGR-097, mb-team design §4).

A `light` track agent walks the stages of its source (plan or one-stage track
prompt) itself; the orchestrator, not the agent, then runs the verifier and the
review. Before spending them, the orchestrator checks the agent's report:

    python3 mb_work_light.py accept --source <plan-file> --report <report.md> [--json]

Report contract (first non-empty line, then a `## Stages` section):

    STATUS: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
    ...
    ## Stages
    - <N>: done|blocked|skipped[ — evidence]

Accepted when STATUS is DONE or DONE_WITH_CONCERNS, every stage still pending
in the source is reported `done`, the report names no stage the source lacks,
and no pending stage declares a non-waived `**Eval:**` (its red→green proof
exists only in the orchestrated engine loop — run such a track `orchestrated`).
The agent never ticks the source: after verify/review pass, the orchestrator
closes each item through `mb-work-state.sh done` + `mb-work-checkbox.sh flip`.

Exit codes: 0 accepted · 1 rejected (reasons in `errors`) · 2 usage / unreadable.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mb_work_items  # noqa: E402

STATUSES = ("DONE", "DONE_WITH_CONCERNS", "BLOCKED", "NEEDS_CONTEXT")
_STATUS_RE = re.compile(r"^STATUS:\s*(\S+)\s*$")
_STAGE_LINE_RE = re.compile(r"^\s*-\s+(\d+)\s*:\s*(done|blocked|skipped)\b", re.I)
_BOX_RE = re.compile(r"^\s*-\s+(?:([⬜✅])|\[([ xX])\])", re.M)


def _done_in_source(body: str) -> bool:
    """Every DoD checkbox ticked (emoji or Markdown, as mb-work-plan.sh reads plans)."""
    states = [e == "✅" if e else m.lower() == "x" for e, m in _BOX_RE.findall(body)]
    return bool(states) and all(states)


def _gated(item) -> bool:
    return bool(item.eval) and item.eval.get("cmd") != "none"


def parse_report(text: str) -> tuple[str | None, dict[int, str]]:
    lines = [ln for ln in text.splitlines() if ln.strip()]
    m = _STATUS_RE.match(lines[0].strip()) if lines else None
    stages: dict[int, str] = {}
    in_stages = False
    for ln in lines:
        if ln.startswith("#"):
            in_stages = ln.lstrip("#").strip().lower() == "stages"
            continue
        sm = _STAGE_LINE_RE.match(ln) if in_stages else None
        if sm:
            stages[int(sm.group(1))] = sm.group(2).lower()
    return (m.group(1) if m else None), stages


def accept(source: pathlib.Path, report_text: str) -> dict:
    items = mb_work_items.parse_work_items(source)
    pending = [i for i in items if not _done_in_source(i.body)]
    status, stages = parse_report(report_text)
    errors = [] if items else [f"source: no mb-stage/mb-task items in {source}"]
    if status is None:
        errors.append("report: first line must be 'STATUS: <DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT>'")
    elif status not in STATUSES:
        errors.append(f"report: unknown STATUS '{status}'")
    elif status not in ("DONE", "DONE_WITH_CONCERNS"):
        errors.append(f"track status {status}: needs the orchestrator (stop_human)")
    known = {i.item_no for i in items}
    errors += [f"report: stage {n} is not in the source" for n in sorted(set(stages) - known)]
    open_items = [i.item_no for i in pending if stages.get(i.item_no) != "done"]
    errors += [f"stage {n}: not reported done" for n in open_items]
    errors += [f"stage {i.item_no}: declares Eval — run the track orchestrated" for i in pending if _gated(i)]
    return {"accepted": not errors, "status": status, "items": [i.item_no for i in pending],
            "pending": open_items, "errors": errors}


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="mb_work_light.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    acc = sub.add_parser("accept")
    acc.add_argument("--source", required=True, type=pathlib.Path)
    acc.add_argument("--report", required=True, type=pathlib.Path)
    acc.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    try:
        report_text = args.report.read_text(encoding="utf-8")
        result = accept(args.source, report_text)
    except (OSError, mb_work_items.MalformedTaskField) as exc:
        sys.stderr.write(f"[work-light] {exc}\n")
        return 2
    if args.json:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print("ACCEPTED" if result["accepted"] else "REJECTED")
        for err in result["errors"]:
            print(f"- {err}")
    return 0 if result["accepted"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
