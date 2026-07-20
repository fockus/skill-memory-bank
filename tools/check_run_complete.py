#!/usr/bin/env python3
"""Verify that a test run actually finished — and that every file you meant to
run produced a log at all (I-147 follow-up).

    python3 tools/check_run_complete.py run.log [more.log ...]
    python3 tools/check_run_complete.py --expect tests/e2e/a.bats:a.log \\
                                        --expect tests/bats/b.bats:b.log

═══════════════════════════════════════════════════════════════════════════════
WHY THIS EXISTS
═══════════════════════════════════════════════════════════════════════════════

Twice in one hour, two people read a partial bats log as a final result:

    ok=29  not ok=0      <- reads as "green" by every habit either of us had
    plan  1..56          <- the run was simply still going

`not ok = 0` is not evidence of success. It is equally consistent with "nothing
failed" and "nothing else has run yet". A killed, crashed, or still-running
suite produces exactly the same shape as a clean one, and the only thing that
distinguishes them is the count TAP already told you to expect.

That is one level of the failure. The other has no snippet at all: a file that
was never run produces no log, and a report assembled per-file cannot notice a
file missing from its own set. One of us checked each file that was run and
never checked that each intended file HAD been run.

Both are the same mistake at different levels — trusting the members without
checking against a declared total. Hence two modes:

    per-log   : ok == plan, no `not ok`, and a plan line that EXISTS
    set-level : every intended file has a log, and every log is complete

═══════════════════════════════════════════════════════════════════════════════
A MISSING PLAN LINE IS THE LOUDEST FAILURE, NOT THE QUIETEST
═══════════════════════════════════════════════════════════════════════════════

A log with no `1..N` is what a run that died at startup looks like — a bad
`load`, a syntax error, a missing interpreter. It also has zero `not ok` lines,
so every naive check calls it green. Treating "no plan" as "nothing to verify"
would rebuild the exact hole this tool closes, so it is a hard error.

Exit 0 only when every log checked is provably complete.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

PLAN_RE = re.compile(r"^1\.\.(\d+)\s*$")
OK_RE = re.compile(r"^ok\b")
NOT_OK_RE = re.compile(r"^not ok\b")
# bats prints `# skip` on the ok line; skipped tests still count toward the plan.
SKIP_RE = re.compile(r"^ok\b.*# skip")


class Result:
    def __init__(self, log: pathlib.Path) -> None:
        self.log = log
        self.plan: int | None = None
        self.ok = 0
        self.not_ok = 0
        self.skipped = 0
        self.problems: list[str] = []

    @property
    def complete(self) -> bool:
        return not self.problems

    def summary(self) -> str:
        plan = "MISSING" if self.plan is None else str(self.plan)
        return f"plan={plan} ok={self.ok} not_ok={self.not_ok} skipped={self.skipped}"


def check_log(log: pathlib.Path) -> Result:
    r = Result(log)
    if not log.exists():
        r.problems.append("log does not exist")
        return r

    text = log.read_text(errors="replace")
    for line in text.splitlines():
        m = PLAN_RE.match(line.strip())
        if m:
            # A second plan line means two runs were concatenated into one file,
            # which makes every count below ambiguous.
            if r.plan is not None:
                r.problems.append(
                    f"two plan lines ({r.plan} then {m.group(1)}) — "
                    "logs from separate runs are concatenated"
                )
            r.plan = int(m.group(1))
            continue
        if NOT_OK_RE.match(line):
            r.not_ok += 1
        elif OK_RE.match(line):
            r.ok += 1
            if SKIP_RE.match(line):
                r.skipped += 1

    if r.plan is None:
        r.problems.append(
            "NO PLAN LINE — the run died before reporting one (bad load, syntax "
            "error, missing interpreter). Zero failures here means nothing."
        )
        return r
    if r.plan == 0 and (r.ok or r.not_ok):
        r.problems.append(f"plan is 1..0 but {r.ok + r.not_ok} results present")
    total = r.ok + r.not_ok
    if total < r.plan:
        r.problems.append(
            f"TRUNCATED: {total} of {r.plan} tests reported — the run was "
            "killed, crashed, or is still writing to this file"
        )
    elif total > r.plan:
        r.problems.append(f"OVER-REPORTED: {total} results for a plan of {r.plan}")
    if r.not_ok:
        r.problems.append(f"{r.not_ok} failing test(s)")
    return r


def parse_expect(spec: str) -> tuple[str, pathlib.Path]:
    """`<intended-file>:<log>` — split on the LAST colon so paths may contain one."""
    if ":" not in spec:
        raise SystemExit(f"--expect needs '<test-file>:<log>', got {spec!r}")
    src, _, log = spec.rpartition(":")
    return src, pathlib.Path(log)


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Fail unless every test run provably finished.",
    )
    ap.add_argument("logs", nargs="*", help="TAP/bats log files to check")
    ap.add_argument(
        "--expect",
        action="append",
        default=[],
        metavar="FILE:LOG",
        help="a test file you INTENDED to run, and the log it should have produced",
    )
    args = ap.parse_args()

    if not args.logs and not args.expect:
        ap.error("give at least one log, or one --expect FILE:LOG")

    failures = 0
    entries = 0          # every thing we were asked to account for
    checked: list[Result] = []

    # ── set level: did every intended file even produce a log? ──────────────
    for spec in args.expect:
        entries += 1
        src, log = parse_expect(spec)
        if not pathlib.Path(src).exists():
            print(f"MISSING SOURCE  {src} — intended file does not exist")
            failures += 1
            continue
        if not log.exists():
            print(f"NEVER RAN       {src} — no log at {log}")
            failures += 1
            continue
        r = check_log(log)
        checked.append(r)
        label = "COMPLETE" if r.complete else "INCOMPLETE"
        print(f"{label:<15} {src} [{r.summary()}]")
        for p in r.problems:
            print(f"                  ! {p}")
        failures += 0 if r.complete else 1

    # ── per-log level ──────────────────────────────────────────────────────
    for raw in args.logs:
        entries += 1
        r = check_log(pathlib.Path(raw))
        checked.append(r)
        label = "COMPLETE" if r.complete else "INCOMPLETE"
        print(f"{label:<15} {raw} [{r.summary()}]")
        for p in r.problems:
            print(f"                  ! {p}")
        failures += 0 if r.complete else 1

    total_tests = sum(r.ok + r.not_ok for r in checked if r.plan is not None)
    # Count against everything ASKED FOR, not just what produced a Result — a
    # file that never ran has no Result, and omitting it from the denominator
    # would hide exactly the set-level gap this mode exists to catch.
    print(
        f"\n{entries - failures}/{entries} run(s) provably complete; "
        f"{total_tests} test result(s) accounted for"
    )
    if failures:
        print(
            "REFUSING to call this green: an unfinished run and a clean run are "
            "the same shape until you compare against the plan."
        )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
